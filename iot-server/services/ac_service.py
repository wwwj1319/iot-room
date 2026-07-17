"""
红外空调控制服务

【功能】
1. 空调开关控制（制冷/制热/关机）
2. 温度调节（升温/降温）
3. 状态管理（本地维护，因红外是单向通信）
4. 操作事件记录

【注意】
红外遥控是单向通信，无法获取空调真实状态。
设定温度和开关状态都是本地维护的"期望值"。
"""

from datetime import datetime, timedelta
from typing import Optional, Dict, Any, Callable
from loguru import logger

from database.repository import DatabaseRepository
from protocol.modbus_rtu import ModbusRTUParser, ACAction


class ACService:
    """
    红外空调控制服务
    
    【设计说明】
    1. 维护空调期望状态（开关、模式、设定温度）
    2. 发送红外控制命令
    3. 记录操作事件
    """
    
    # 默认空调控制器 Modbus 地址
    DEFAULT_ADDRESS = 0x03
    
    # 温度范围
    MIN_TEMP = 16
    MAX_TEMP = 30
    DEFAULT_TEMP = 26
    
    # 在线判断阈值（秒）- 如果有读取环境温湿度的话
    ONLINE_TIMEOUT = 300
    
    def __init__(self, db: DatabaseRepository):
        self.db = db
        
        # 空调状态缓存: {modbus_address: {...}}
        self._status_cache: Dict[int, Dict[str, Any]] = {}
        
        # 初始化默认状态
        self._init_default_status(self.DEFAULT_ADDRESS)
        
        # 命令发送回调
        self._send_command_callback: Optional[Callable[[bytes], bool]] = None
        
        logger.info("空调控制服务初始化完成")
    
    def _init_default_status(self, address: int):
        """初始化默认状态"""
        # 尝试从数据库恢复状态
        sensor = self.db.get_sensor_by_modbus_address(address)
        if sensor:
            last_state = self.db.get_last_ac_state(sensor.id)
            if last_state:
                self._status_cache[address] = {
                    'is_on': last_state.get('is_on', False),
                    'mode': last_state.get('mode', 'cool'),
                    'target_temp': last_state.get('target_temp', self.DEFAULT_TEMP),
                    'update_time': datetime.now(),
                    'is_online': False  # 默认离线，等待数据更新
                }
                logger.info(f"从数据库恢复空调状态: {self._status_cache[address]}")
                return
        
        # 默认状态
        self._status_cache[address] = {
            'is_on': False,
            'mode': 'cool',
            'target_temp': self.DEFAULT_TEMP,
            'update_time': datetime.now(),
            'is_online': False
        }
    
    def set_send_command_callback(self, callback: Callable[[bytes], bool]):
        """设置命令发送回调"""
        self._send_command_callback = callback
    
    def get_status(self, modbus_address: int = None) -> Dict[str, Any]:
        """获取空调状态（本地维护的期望值）"""
        address = modbus_address or self.DEFAULT_ADDRESS
        
        if address not in self._status_cache:
            self._init_default_status(address)
        
        status = self._status_cache[address]
        
        return {
            'modbus_address': address,
            'is_on': status['is_on'],
            'mode': status['mode'],
            'mode_text': '制冷' if status['mode'] == 'cool' else '制热',
            'target_temp': status['target_temp'],
            'is_online': status.get('is_online', False),
            'last_update': status['update_time'].isoformat() if status.get('update_time') else None
        }
    
    def power_on(
        self,
        mode: str = 'cool',
        modbus_address: int = None,
        operator: str = None
    ) -> Dict[str, Any]:
        """
        空调开机
        
        Args:
            mode: 模式 'cool'=制冷, 'heat'=制热
            modbus_address: 设备地址
            operator: 操作者
        """
        address = modbus_address or self.DEFAULT_ADDRESS
        
        # 构建命令
        if mode == 'heat':
            cmd = ModbusRTUParser.build_ac_power_on_heat(address)
            action = 'power_on_heat'
        else:
            cmd = ModbusRTUParser.build_ac_power_on_cool(address)
            action = 'power_on_cool'
        
        # 发送命令
        success, error_msg = self._send_command(cmd)
        
        # 更新本地状态
        if success:
            if address not in self._status_cache:
                self._init_default_status(address)
            self._status_cache[address]['is_on'] = True
            self._status_cache[address]['mode'] = mode
            self._status_cache[address]['update_time'] = datetime.now()
        
        # 记录事件
        self._record_event(
            address=address,
            action=action,
            is_on=True,
            mode=mode,
            target_temp=self._status_cache.get(address, {}).get('target_temp', self.DEFAULT_TEMP),
            operator=operator,
            success=success,
            error_msg=error_msg
        )
        
        mode_text = '制热' if mode == 'heat' else '制冷'
        logger.info(f"空调开机 [地址:0x{address:02X}]: {mode_text}")
        
        return {
            'success': success,
            'action': action,
            'mode': mode,
            'command_hex': cmd.hex().upper(),
            'error': error_msg
        }
    
    def power_off(
        self,
        modbus_address: int = None,
        operator: str = None
    ) -> Dict[str, Any]:
        """空调关机"""
        address = modbus_address or self.DEFAULT_ADDRESS
        
        cmd = ModbusRTUParser.build_ac_power_off(address)
        success, error_msg = self._send_command(cmd)
        
        if success:
            if address not in self._status_cache:
                self._init_default_status(address)
            self._status_cache[address]['is_on'] = False
            self._status_cache[address]['update_time'] = datetime.now()
        
        self._record_event(
            address=address,
            action='power_off',
            is_on=False,
            mode=self._status_cache.get(address, {}).get('mode', 'cool'),
            target_temp=self._status_cache.get(address, {}).get('target_temp', self.DEFAULT_TEMP),
            operator=operator,
            success=success,
            error_msg=error_msg
        )
        
        logger.info(f"空调关机 [地址:0x{address:02X}]")
        
        return {
            'success': success,
            'action': 'power_off',
            'command_hex': cmd.hex().upper(),
            'error': error_msg
        }
    
    def temp_up(
        self,
        modbus_address: int = None,
        operator: str = None
    ) -> Dict[str, Any]:
        """升温（+1°C）"""
        address = modbus_address or self.DEFAULT_ADDRESS
        
        if address not in self._status_cache:
            self._init_default_status(address)
        
        current_temp = self._status_cache[address].get('target_temp', self.DEFAULT_TEMP)
        new_temp = min(current_temp + 1, self.MAX_TEMP)
        
        if new_temp == current_temp:
            return {
                'success': False,
                'action': 'temp_up',
                'target_temp': current_temp,
                'error': f'已达到最高温度 {self.MAX_TEMP}°C'
            }
        
        cmd = ModbusRTUParser.build_ac_temp_up(address)
        success, error_msg = self._send_command(cmd)
        
        if success:
            self._status_cache[address]['target_temp'] = new_temp
            self._status_cache[address]['update_time'] = datetime.now()
        
        self._record_event(
            address=address,
            action='temp_up',
            is_on=self._status_cache[address].get('is_on', False),
            mode=self._status_cache[address].get('mode', 'cool'),
            target_temp=new_temp if success else current_temp,
            operator=operator,
            success=success,
            error_msg=error_msg
        )
        
        logger.info(f"空调升温 [地址:0x{address:02X}]: {current_temp}→{new_temp}°C")
        
        return {
            'success': success,
            'action': 'temp_up',
            'target_temp': new_temp if success else current_temp,
            'command_hex': cmd.hex().upper(),
            'error': error_msg
        }
    
    def temp_down(
        self,
        modbus_address: int = None,
        operator: str = None
    ) -> Dict[str, Any]:
        """降温（-1°C）"""
        address = modbus_address or self.DEFAULT_ADDRESS
        
        if address not in self._status_cache:
            self._init_default_status(address)
        
        current_temp = self._status_cache[address].get('target_temp', self.DEFAULT_TEMP)
        new_temp = max(current_temp - 1, self.MIN_TEMP)
        
        if new_temp == current_temp:
            return {
                'success': False,
                'action': 'temp_down',
                'target_temp': current_temp,
                'error': f'已达到最低温度 {self.MIN_TEMP}°C'
            }
        
        cmd = ModbusRTUParser.build_ac_temp_down(address)
        success, error_msg = self._send_command(cmd)
        
        if success:
            self._status_cache[address]['target_temp'] = new_temp
            self._status_cache[address]['update_time'] = datetime.now()
        
        self._record_event(
            address=address,
            action='temp_down',
            is_on=self._status_cache[address].get('is_on', False),
            mode=self._status_cache[address].get('mode', 'cool'),
            target_temp=new_temp if success else current_temp,
            operator=operator,
            success=success,
            error_msg=error_msg
        )
        
        logger.info(f"空调降温 [地址:0x{address:02X}]: {current_temp}→{new_temp}°C")
        
        return {
            'success': success,
            'action': 'temp_down',
            'target_temp': new_temp if success else current_temp,
            'command_hex': cmd.hex().upper(),
            'error': error_msg
        }
    
    def set_temp(
        self,
        target_temp: int,
        modbus_address: int = None,
        operator: str = None
    ) -> Dict[str, Any]:
        """
        设置目标温度
        
        通过多次发送升温/降温命令达到目标温度
        """
        address = modbus_address or self.DEFAULT_ADDRESS
        
        if not self.MIN_TEMP <= target_temp <= self.MAX_TEMP:
            return {
                'success': False,
                'error': f'温度必须在 {self.MIN_TEMP}~{self.MAX_TEMP}°C 之间'
            }
        
        if address not in self._status_cache:
            self._init_default_status(address)
        
        current_temp = self._status_cache[address].get('target_temp', self.DEFAULT_TEMP)
        diff = target_temp - current_temp
        
        if diff == 0:
            return {
                'success': True,
                'action': 'set_temp',
                'target_temp': target_temp,
                'steps': 0
            }
        
        # 逐步调节
        steps = abs(diff)
        for i in range(steps):
            if diff > 0:
                result = self.temp_up(address, operator)
            else:
                result = self.temp_down(address, operator)
            
            if not result['success']:
                return {
                    'success': False,
                    'action': 'set_temp',
                    'target_temp': self._status_cache[address].get('target_temp', current_temp),
                    'steps': i,
                    'error': result.get('error')
                }
        
        return {
            'success': True,
            'action': 'set_temp',
            'target_temp': target_temp,
            'steps': steps
        }
    
    def _send_command(self, cmd: bytes) -> tuple:
        """发送命令"""
        if self._send_command_callback:
            try:
                success = self._send_command_callback(cmd)
                return success, None if success else "命令发送失败"
            except Exception as e:
                return False, str(e)
        else:
            logger.warning("空调控制: 未配置命令发送回调")
            return False, "未配置命令发送回调"
    
    def _record_event(
        self,
        address: int,
        action: str,
        is_on: bool,
        mode: str,
        target_temp: int,
        operator: str = None,
        success: bool = True,
        error_msg: str = None
    ):
        """记录操作事件"""
        try:
            sensor = self.db.get_or_create_sensor(
                modbus_address=address,
                sensor_type='ac',
                name=f"空调控制器 {address}"
            )
            
            self.db.create_ac_control_event(
                sensor_id=sensor.id,
                action=action,
                is_on=is_on,
                mode=mode,
                target_temp=target_temp,
                event_time=datetime.now(),
                source='manual',
                operator=operator,
                success=success,
                error_msg=error_msg
            )
        except Exception as e:
            logger.error(f"记录空调事件失败: {e}")
    
    def get_events(self, modbus_address: int = None, limit: int = 50) -> list:
        """获取操作历史"""
        address = modbus_address or self.DEFAULT_ADDRESS
        sensor = self.db.get_sensor_by_modbus_address(address)
        
        if not sensor:
            return []
        
        return self.db.get_ac_control_events(sensor_id=sensor.id, limit=limit)
    
    def get_today_operation_count(self, modbus_address: int = None) -> int:
        """获取今日操作次数"""
        address = modbus_address or self.DEFAULT_ADDRESS
        sensor = self.db.get_sensor_by_modbus_address(address)
        
        if not sensor:
            return 0
        
        return self.db.get_today_ac_operation_count(sensor.id)

