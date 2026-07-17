"""
智能断路器服务层

【功能】
1. 断路器状态管理（内存缓存 + 数据库）
2. 控制命令发送
3. 操作事件记录
4. 状态变化检测（边沿检测）
"""

from datetime import datetime, timedelta
from typing import Optional, Dict, Any, Callable
from loguru import logger

from database.repository import DatabaseRepository
from protocol.modbus_rtu import ModbusRTUParser, CircuitBreakerData


class CircuitBreakerService:
    """
    智能断路器服务
    
    【设计说明】
    1. 维护断路器实时状态（内存缓存）
    2. 状态变化时记录到数据库
    3. 提供控制命令构建
    4. 支持回调通知
    """
    
    # 默认断路器 Modbus 地址
    DEFAULT_ADDRESS = 0x02
    
    # 在线判断阈值（秒）
    ONLINE_TIMEOUT = 300  # 5分钟无数据视为离线
    
    def __init__(self, db: DatabaseRepository):
        self.db = db
        
        # 断路器状态缓存: {modbus_address: {...}}
        self._status_cache: Dict[int, Dict[str, Any]] = {}
        
        # 控制命令发送回调（由外部设置，用于通过 MQTT 发送命令）
        self._send_command_callback: Optional[Callable[[bytes], bool]] = None
        
        logger.info("断路器服务初始化完成")
    
    def set_send_command_callback(self, callback: Callable[[bytes], bool]):
        """设置命令发送回调"""
        self._send_command_callback = callback
    
    def process_status_data(
        self, 
        data: CircuitBreakerData,
        source: str = 'unknown'
    ) -> bool:
        """
        处理断路器状态数据
        
        Args:
            data: 断路器数据
            source: 数据来源
            
        Returns:
            是否是状态变化
        """
        address = data.device_address
        current_time = datetime.now()
        
        # 获取上次状态
        last_status = self._status_cache.get(address, {}).get('is_closed')
        
        # 更新缓存
        self._status_cache[address] = {
            'is_closed': data.is_closed,
            'raw_value': data.raw_value,
            'update_time': current_time,
            'raw_frame': data.raw_frame
        }
        
        # 更新传感器最后数据时间
        self.db.update_sensor_last_data(address)
        
        # 检测状态变化（边沿检测）
        status_changed = last_status is not None and last_status != data.is_closed
        
        # 首次数据或状态变化时记录事件
        if last_status is None or status_changed:
            self._record_event(
                address=address,
                is_closed=data.is_closed,
                source=source if status_changed else 'init',
                success=True
            )
            
            if status_changed:
                action = "合闸(通电)" if data.is_closed else "分闸(断电)"
                logger.info(f"断路器状态变化 [地址:0x{address:02X}]: {action}")
        
        return status_changed
    
    def _record_event(
        self,
        address: int,
        is_closed: bool,
        source: str = 'unknown',
        operator: str = None,
        remark: str = None,
        success: bool = True,
        error_msg: str = None
    ):
        """记录断路器事件到数据库"""
        try:
            # 确保传感器存在
            sensor = self.db.get_or_create_sensor(
                modbus_address=address,
                sensor_type='circuit_breaker',
                name=f"智能断路器 {address}"
            )
            
            # 创建事件
            self.db.create_circuit_breaker_event(
                sensor_id=sensor.id,
                event_type='on' if is_closed else 'off',
                event_time=datetime.now(),
                source=source,
                operator=operator,
                remark=remark,
                success=success,
                error_msg=error_msg
            )
        except Exception as e:
            logger.error(f"记录断路器事件失败: {e}")
    
    def get_status(self, modbus_address: int = None) -> Dict[str, Any]:
        """
        获取断路器状态
        
        Args:
            modbus_address: Modbus 地址（默认使用 DEFAULT_ADDRESS）
        """
        address = modbus_address or self.DEFAULT_ADDRESS
        
        cached = self._status_cache.get(address)
        if cached:
            # 计算在线状态
            is_online = (datetime.now() - cached['update_time']).total_seconds() < self.ONLINE_TIMEOUT
            
            return {
                'modbus_address': address,
                'is_closed': cached['is_closed'],
                'is_online': is_online,
                'status_text': '合闸(通电)' if cached['is_closed'] else '分闸(断电)',
                'last_update': cached['update_time'].isoformat(),
                'raw_value': cached['raw_value']
            }
        
        # 无缓存数据，尝试从数据库获取
        sensor = self.db.get_sensor_by_modbus_address(address)
        if sensor:
            last_status = self.db.get_last_circuit_breaker_status(sensor.id)
            is_online = False
            if sensor.last_data_at:
                is_online = (datetime.now() - sensor.last_data_at).total_seconds() < self.ONLINE_TIMEOUT
            
            return {
                'modbus_address': address,
                'is_closed': last_status if last_status is not None else False,
                'is_online': is_online,
                'status_text': '合闸(通电)' if last_status else '分闸(断电)',
                'last_update': sensor.last_data_at.isoformat() if sensor.last_data_at else None,
                'raw_value': None
            }
        
        # 无任何数据
        return {
            'modbus_address': address,
            'is_closed': False,
            'is_online': False,
            'status_text': '未知',
            'last_update': None,
            'raw_value': None
        }
    
    def is_online(self, modbus_address: int = None) -> bool:
        """判断断路器是否在线"""
        address = modbus_address or self.DEFAULT_ADDRESS
        status = self.get_status(address)
        return status.get('is_online', False)
    
    def control(
        self,
        close: bool,
        modbus_address: int = None,
        operator: str = None,
        remark: str = None
    ) -> Dict[str, Any]:
        """
        控制断路器开关
        
        Args:
            close: True=合闸(通电), False=分闸(断电)
            modbus_address: Modbus 地址
            operator: 操作者
            remark: 备注
            
        Returns:
            操作结果
        """
        address = modbus_address or self.DEFAULT_ADDRESS
        action = "合闸" if close else "分闸"
        
        # 构建控制命令
        cmd = ModbusRTUParser.build_circuit_breaker_control_command(
            device_address=address,
            close=close
        )
        
        logger.info(f"断路器控制 [地址:0x{address:02X}]: {action}, 命令: {cmd.hex().upper()}")
        
        # 发送命令
        success = False
        error_msg = None
        
        if self._send_command_callback:
            try:
                success = self._send_command_callback(cmd)
                if not success:
                    error_msg = "命令发送失败"
            except Exception as e:
                error_msg = str(e)
                logger.error(f"发送断路器控制命令异常: {e}")
        else:
            error_msg = "未配置命令发送回调"
            logger.warning("断路器控制: 未配置命令发送回调，无法发送命令")
        
        # 记录操作事件（不管是否成功）
        self._record_event(
            address=address,
            is_closed=close,
            source='manual',
            operator=operator,
            remark=remark,
            success=success,
            error_msg=error_msg
        )
        
        return {
            'success': success,
            'modbus_address': address,
            'action': action,
            'command_hex': cmd.hex().upper(),
            'error': error_msg
        }
    
    def build_query_command(self, modbus_address: int = None) -> bytes:
        """构建状态查询命令"""
        address = modbus_address or self.DEFAULT_ADDRESS
        return ModbusRTUParser.build_circuit_breaker_query_command(address)
    
    def get_events(
        self,
        modbus_address: int = None,
        limit: int = 50
    ) -> list:
        """获取断路器操作事件历史"""
        address = modbus_address or self.DEFAULT_ADDRESS
        sensor = self.db.get_sensor_by_modbus_address(address)
        
        if not sensor:
            return []
        
        return self.db.get_circuit_breaker_events(
            sensor_id=sensor.id,
            limit=limit
        )
    
    def get_today_switch_count(self, modbus_address: int = None) -> int:
        """获取今日开关次数"""
        address = modbus_address or self.DEFAULT_ADDRESS
        sensor = self.db.get_sensor_by_modbus_address(address)
        
        if not sensor:
            return 0
        
        return self.db.get_today_circuit_breaker_switch_count(sensor.id)

