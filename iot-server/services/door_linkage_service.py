"""
门磁事件服务

【功能】
1. 边沿检测：只在开门/关门状态变化时记录
2. 防抖处理：避免门抖动导致重复事件
3. 数据量控制：正常每天只有几十条记录
"""

from datetime import datetime, timedelta
from typing import Dict, Optional
from loguru import logger

from database.repository import DatabaseRepository
from protocol.modbus_rtu import DoorSensorData


class DoorLinkageService:
    """门磁事件服务"""
    
    DEBOUNCE_SECONDS = 3  # 防抖时间
    
    def __init__(self, db_repo: DatabaseRepository):
        self.db_repo = db_repo
        self._status_cache: Dict[int, bool] = {}  # {modbus_addr: is_open}
        self._debounce_cache: Dict[int, datetime] = {}  # {modbus_addr: last_time}
        logger.info("门磁事件服务初始化完成")
    
    async def process_door_data(self, door_data: DoorSensorData) -> bool:
        """
        处理门磁数据
        
        只有状态变化时才记录事件
        
        Returns:
            True=记录了事件, False=状态未变化
        """
        addr = door_data.device_address
        is_open = door_data.is_open
        
        # 更新传感器最后数据时间
        self.db_repo.update_sensor_last_data(addr)
        
        # 边沿检测
        last_status = self._status_cache.get(addr)
        
        if last_status is None:
            # 首次数据，从数据库查
            sensor_id = self.db_repo.get_sensor_id_by_modbus(addr)
            if sensor_id:
                last_status = self.db_repo.get_last_door_status(sensor_id)
        
        self._status_cache[addr] = is_open
        
        # 状态未变化，不记录
        if last_status is not None and last_status == is_open:
            return False
        
        # 防抖检查
        last_time = self._debounce_cache.get(addr)
        now = datetime.now()
        
        if last_time and (now - last_time) < timedelta(seconds=self.DEBOUNCE_SECONDS):
            logger.debug(f"门磁 0x{addr:02X} 防抖中，跳过")
            return False
        
        self._debounce_cache[addr] = now
        
        # 确保传感器存在
        sensor = self.db_repo.get_or_create_sensor(addr)
        
        # 记录事件
        event_type = 'open' if is_open else 'close'
        self.db_repo.create_door_event(sensor.id, event_type, now)
        
        logger.info(f"门磁 0x{addr:02X} {'开门' if is_open else '关门'}事件已记录")
        return True
