"""
温湿度传感器数据处理服务

【功能】
1. 处理 Modbus 温湿度数据
2. 数据存储（支持采样间隔控制）
3. 更新传感器在线状态
"""

from datetime import datetime, timedelta
from typing import Optional, Dict, Any
from loguru import logger

from database.repository import DatabaseRepository
from protocol.modbus_rtu import TempHumidityData


class TempHumidityService:
    """温湿度数据处理服务"""
    
    # 最小存储间隔（秒）- 防止数据过多
    MIN_SAVE_INTERVAL = 60  # 1分钟存储一次
    
    def __init__(self, repository: DatabaseRepository):
        self.repository = repository
        # 缓存：记录每个传感器最后存储时间
        self._last_save_time: Dict[int, datetime] = {}
        # 缓存：记录每个传感器最新数据（用于实时查询）
        self._latest_data: Dict[int, Dict[str, Any]] = {}
        
        logger.info("温湿度服务初始化完成")
    
    async def process_temp_humidity_data(self, data: TempHumidityData):
        """
        处理温湿度数据
        
        Args:
            data: 解析后的温湿度数据
        """
        try:
            modbus_address = data.device_address
            
            # 获取或创建传感器
            sensor = self.repository.get_or_create_sensor(
                modbus_address=modbus_address,
                sensor_type='temp_humidity'
            )
            
            # 更新传感器在线状态
            self.repository.update_sensor_last_data(modbus_address)
            
            # 更新内存缓存（实时数据）
            self._latest_data[modbus_address] = {
                'sensor_id': sensor.id,
                'modbus_address': modbus_address,
                'temperature': data.temperature,
                'humidity': data.humidity,
                'raw_temp': data.raw_temp,
                'raw_humidity': data.raw_humidity,
                'update_time': datetime.now()
            }
            
            logger.debug(
                f"温湿度数据: 地址={modbus_address}, "
                f"温度={data.temperature}°C, 湿度={data.humidity}%"
            )
            
            # 检查是否需要存储到数据库
            if self._should_save(modbus_address):
                self._save_to_database(sensor.id, data)
                self._last_save_time[modbus_address] = datetime.now()
                
        except Exception as e:
            logger.error(f"处理温湿度数据异常: {e}", exc_info=True)
    
    def _should_save(self, modbus_address: int) -> bool:
        """检查是否应该存储数据（基于时间间隔）"""
        last_time = self._last_save_time.get(modbus_address)
        if last_time is None:
            return True
        
        elapsed = (datetime.now() - last_time).total_seconds()
        return elapsed >= self.MIN_SAVE_INTERVAL
    
    def _save_to_database(self, sensor_id: int, data: TempHumidityData):
        """存储温湿度数据到数据库"""
        try:
            self.repository.save_temp_humidity_data(
                sensor_id=sensor_id,
                temperature=data.temperature,
                humidity=data.humidity,
                raw_temp=data.raw_temp,
                raw_humidity=data.raw_humidity,
                record_time=datetime.now()
            )
            logger.debug(f"温湿度数据已存储: sensor_id={sensor_id}")
        except Exception as e:
            logger.error(f"存储温湿度数据失败: {e}")
    
    def get_realtime_data(self, modbus_address: int) -> Optional[Dict[str, Any]]:
        """获取实时数据（从内存缓存）"""
        return self._latest_data.get(modbus_address)
    
    def get_all_realtime_data(self) -> Dict[int, Dict[str, Any]]:
        """获取所有传感器的实时数据"""
        return self._latest_data.copy()
    
    def is_sensor_online(self, modbus_address: int, timeout_seconds: int = 300) -> bool:
        """检查传感器是否在线"""
        data = self._latest_data.get(modbus_address)
        if data is None:
            return False
        
        update_time = data.get('update_time')
        if update_time is None:
            return False
        
        elapsed = (datetime.now() - update_time).total_seconds()
        return elapsed < timeout_seconds

