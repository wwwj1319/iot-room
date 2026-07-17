"""
数据库操作类

【功能】
1. 设备间管理
2. 传感器管理
3. 门磁事件（只记录开门/关门状态变化）
4. 温湿度数据（定期采样记录）
5. 断路器事件（操作记录）
6. 空调控制事件（红外发射记录）
"""

from datetime import datetime, timedelta
from typing import Optional, List, Dict, Any
from sqlalchemy import create_engine, desc, func
from sqlalchemy.orm import sessionmaker, Session
from loguru import logger

from database.models import Base, Room, Sensor, DoorEvent, TempHumidityData, CircuitBreakerEvent, ACControlEvent


class DatabaseRepository:
    """数据库操作仓库"""
    
    def __init__(self, db_uri: str):
        self.engine = create_engine(db_uri, pool_pre_ping=True)
        self.SessionLocal = sessionmaker(bind=self.engine)
        
        # 创建表（如果不存在）
        Base.metadata.create_all(self.engine)
        logger.info("数据库连接初始化完成")
    
    def get_session(self) -> Session:
        return self.SessionLocal()
    
    # ==================== 设备间操作 ====================
    
    def get_or_create_room(self, room_code: str, name: str = None, location: str = None) -> Room:
        """获取或创建设备间"""
        with self.get_session() as session:
            room = session.query(Room).filter(Room.room_code == room_code).first()
            
            if not room:
                room = Room(
                    room_code=room_code,
                    name=name or f"设备间 {room_code}",
                    location=location,
                    status='online'
                )
                session.add(room)
                session.commit()
                session.refresh(room)
                logger.info(f"创建设备间: {room}")
            
            return room
    
    # ==================== 传感器操作 ====================
    
    def get_sensor_by_modbus_address(self, modbus_address: int) -> Optional[Sensor]:
        """根据 Modbus 地址获取传感器"""
        with self.get_session() as session:
            return session.query(Sensor).filter(
                Sensor.modbus_address == modbus_address
            ).first()
    
    def get_sensor_id_by_modbus(self, modbus_address: int) -> Optional[int]:
        """根据 Modbus 地址获取传感器ID"""
        with self.get_session() as session:
            sensor = session.query(Sensor).filter(
                Sensor.modbus_address == modbus_address
            ).first()
            return sensor.id if sensor else None
    
    def get_or_create_sensor(
        self, 
        modbus_address: int, 
        sensor_type: str = 'door',
        name: str = None
    ) -> Sensor:
        """
        获取或创建传感器
        
        Args:
            modbus_address: Modbus 地址
            sensor_type: 传感器类型 (door/temp_humidity/circuit_breaker)
            name: 传感器名称
        """
        with self.get_session() as session:
            sensor = session.query(Sensor).filter(
                Sensor.modbus_address == modbus_address
            ).first()
            
            if not sensor:
                # 确保默认设备间存在
                room = session.query(Room).filter(Room.room_code == 'DEFAULT').first()
                if not room:
                    room = Room(room_code='DEFAULT', name='默认设备间', status='online')
                    session.add(room)
                    session.flush()
                
                # 根据类型生成编号和名称
                if sensor_type == 'temp_humidity':
                    sensor_code = f"TH-{modbus_address:02X}"
                    default_name = f"温湿度传感器 {modbus_address}"
                elif sensor_type == 'circuit_breaker':
                    sensor_code = f"CB-{modbus_address:02X}"
                    default_name = f"智能断路器 {modbus_address}"
                elif sensor_type == 'ac':
                    sensor_code = f"AC-{modbus_address:02X}"
                    default_name = f"空调控制器 {modbus_address}"
                else:
                    sensor_code = f"DOOR-{modbus_address:02X}"
                    default_name = f"门磁传感器 {modbus_address}"
                
                sensor = Sensor(
                    room_id=room.id,
                    sensor_type=sensor_type,
                    sensor_code=sensor_code,
                    modbus_address=modbus_address,
                    name=name or default_name,
                    status='online'
                )
                session.add(sensor)
                session.commit()
                session.refresh(sensor)
                logger.info(f"创建传感器: {sensor}")
            
            return sensor
    
    def update_sensor_last_data(self, modbus_address: int):
        """更新传感器最后数据时间"""
        with self.get_session() as session:
            sensor = session.query(Sensor).filter(
                Sensor.modbus_address == modbus_address
            ).first()
            if sensor:
                sensor.status = 'online'
                sensor.last_data_at = datetime.now()
                session.commit()
    
    # ==================== 门磁事件操作 ====================
    
    def create_door_event(self, sensor_id: int, event_type: str, event_time: datetime) -> DoorEvent:
        """创建门磁事件"""
        with self.get_session() as session:
            event = DoorEvent(
                sensor_id=sensor_id,
                event_type=event_type,
                event_time=event_time
            )
            session.add(event)
            session.commit()
            session.refresh(event)
            return event
    
    def get_last_door_status(self, sensor_id: int) -> Optional[bool]:
        """
        获取门磁最后状态（用于边沿检测）
        
        Returns:
            True=开, False=关, None=无数据
        """
        with self.get_session() as session:
            event = session.query(DoorEvent).filter(
                DoorEvent.sensor_id == sensor_id
            ).order_by(desc(DoorEvent.id)).first()
            
            if event:
                return event.event_type == 'open'
            return None
    
    def get_door_events(
        self,
        sensor_id: int = None,
        event_type: str = None,
        start_time: datetime = None,
        end_time: datetime = None,
        limit: int = 50
    ) -> List[Dict[str, Any]]:
        """查询门磁事件"""
        with self.get_session() as session:
            query = session.query(DoorEvent)
            
            if sensor_id:
                query = query.filter(DoorEvent.sensor_id == sensor_id)
            if event_type:
                query = query.filter(DoorEvent.event_type == event_type)
            if start_time:
                query = query.filter(DoorEvent.event_time >= start_time)
            if end_time:
                query = query.filter(DoorEvent.event_time <= end_time)
            
            events = query.order_by(desc(DoorEvent.event_time)).limit(limit).all()
            
            result = []
            for e in events:
                result.append({
                    'id': e.id,
                    'sensor_id': e.sensor_id,
                    'event_type': e.event_type,
                    'event_time': e.event_time.isoformat() if e.event_time else None,
                    'created_at': e.created_at.isoformat() if e.created_at else None
                })
            return result
    
    def get_today_door_open_count(self, sensor_id: int) -> int:
        """获取今日开门次数"""
        with self.get_session() as session:
            today_start = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
            
            count = session.query(DoorEvent).filter(
                DoorEvent.sensor_id == sensor_id,
                DoorEvent.event_type == 'open',
                DoorEvent.event_time >= today_start
            ).count()
            
            return count
    
    def get_door_current_status(self, sensor_id: int) -> Optional[bool]:
        """获取门磁当前状态"""
        return self.get_last_door_status(sensor_id)
    
    # ==================== 温湿度数据操作 ====================
    
    def save_temp_humidity_data(
        self,
        sensor_id: int,
        temperature: float,
        humidity: float,
        raw_temp: int = None,
        raw_humidity: int = None,
        record_time: datetime = None
    ) -> TempHumidityData:
        """保存温湿度数据"""
        with self.get_session() as session:
            data = TempHumidityData(
                sensor_id=sensor_id,
                temperature=temperature,
                humidity=humidity,
                raw_temp=raw_temp,
                raw_humidity=raw_humidity,
                record_time=record_time or datetime.now()
            )
            session.add(data)
            session.commit()
            session.refresh(data)
            return data
    
    def get_latest_temp_humidity(self, sensor_id: int) -> Optional[Dict[str, Any]]:
        """获取最新温湿度数据"""
        with self.get_session() as session:
            data = session.query(TempHumidityData).filter(
                TempHumidityData.sensor_id == sensor_id
            ).order_by(desc(TempHumidityData.record_time)).first()
            
            if data:
                return {
                    'id': data.id,
                    'sensor_id': data.sensor_id,
                    'temperature': data.temperature,
                    'humidity': data.humidity,
                    'record_time': data.record_time.isoformat() if data.record_time else None
                }
            return None
    
    def get_temp_humidity_history(
        self,
        sensor_id: int,
        start_time: datetime = None,
        end_time: datetime = None,
        limit: int = 100
    ) -> List[Dict[str, Any]]:
        """获取温湿度历史数据"""
        with self.get_session() as session:
            query = session.query(TempHumidityData).filter(
                TempHumidityData.sensor_id == sensor_id
            )
            
            if start_time:
                query = query.filter(TempHumidityData.record_time >= start_time)
            if end_time:
                query = query.filter(TempHumidityData.record_time <= end_time)
            
            records = query.order_by(desc(TempHumidityData.record_time)).limit(limit).all()
            
            result = []
            for r in records:
                result.append({
                    'id': r.id,
                    'temperature': r.temperature,
                    'humidity': r.humidity,
                    'record_time': r.record_time.isoformat() if r.record_time else None
                })
            return result
    
    def get_temp_humidity_stats(
        self,
        sensor_id: int,
        start_time: datetime = None,
        end_time: datetime = None
    ) -> Dict[str, Any]:
        """获取温湿度统计数据（最高、最低、平均）"""
        with self.get_session() as session:
            query = session.query(
                func.min(TempHumidityData.temperature).label('temp_min'),
                func.max(TempHumidityData.temperature).label('temp_max'),
                func.avg(TempHumidityData.temperature).label('temp_avg'),
                func.min(TempHumidityData.humidity).label('humidity_min'),
                func.max(TempHumidityData.humidity).label('humidity_max'),
                func.avg(TempHumidityData.humidity).label('humidity_avg'),
                func.count(TempHumidityData.id).label('count')
            ).filter(TempHumidityData.sensor_id == sensor_id)
            
            if start_time:
                query = query.filter(TempHumidityData.record_time >= start_time)
            if end_time:
                query = query.filter(TempHumidityData.record_time <= end_time)
            
            result = query.first()
            
            return {
                'temperature': {
                    'min': round(result.temp_min, 1) if result.temp_min else None,
                    'max': round(result.temp_max, 1) if result.temp_max else None,
                    'avg': round(result.temp_avg, 1) if result.temp_avg else None
                },
                'humidity': {
                    'min': round(result.humidity_min, 1) if result.humidity_min else None,
                    'max': round(result.humidity_max, 1) if result.humidity_max else None,
                    'avg': round(result.humidity_avg, 1) if result.humidity_avg else None
                },
                'count': result.count or 0
            }
    
    def cleanup_old_temp_humidity_data(self, days: int = 30):
        """清理超过指定天数的温湿度数据"""
        with self.get_session() as session:
            cutoff_time = datetime.now() - timedelta(days=days)
            deleted = session.query(TempHumidityData).filter(
                TempHumidityData.record_time < cutoff_time
            ).delete()
            session.commit()
            if deleted > 0:
                logger.info(f"清理 {deleted} 条过期温湿度数据")
    
    # ==================== 断路器事件操作 ====================
    
    def create_circuit_breaker_event(
        self,
        sensor_id: int,
        event_type: str,
        event_time: datetime = None,
        source: str = 'unknown',
        operator: str = None,
        remark: str = None,
        success: bool = True,
        error_msg: str = None
    ) -> CircuitBreakerEvent:
        """
        创建断路器操作事件
        
        Args:
            sensor_id: 断路器传感器ID
            event_type: 事件类型 (on/off)
            event_time: 事件时间
            source: 操作来源 (manual/schedule/linkage/unknown)
            operator: 操作者
            remark: 备注
            success: 是否成功
            error_msg: 错误信息
        """
        with self.get_session() as session:
            event = CircuitBreakerEvent(
                sensor_id=sensor_id,
                event_type=event_type,
                event_time=event_time or datetime.now(),
                source=source,
                operator=operator,
                remark=remark,
                success=success,
                error_msg=error_msg
            )
            session.add(event)
            session.commit()
            session.refresh(event)
            return event
    
    def get_last_circuit_breaker_status(self, sensor_id: int) -> Optional[bool]:
        """
        获取断路器最后状态
        
        Returns:
            True=合闸(开), False=分闸(关), None=无数据
        """
        with self.get_session() as session:
            event = session.query(CircuitBreakerEvent).filter(
                CircuitBreakerEvent.sensor_id == sensor_id,
                CircuitBreakerEvent.success == True
            ).order_by(desc(CircuitBreakerEvent.event_time)).first()
            
            if event:
                return event.event_type == 'on'
            return None
    
    def get_circuit_breaker_events(
        self,
        sensor_id: int = None,
        event_type: str = None,
        start_time: datetime = None,
        end_time: datetime = None,
        limit: int = 50
    ) -> List[Dict[str, Any]]:
        """查询断路器操作事件"""
        with self.get_session() as session:
            query = session.query(CircuitBreakerEvent)
            
            if sensor_id:
                query = query.filter(CircuitBreakerEvent.sensor_id == sensor_id)
            if event_type:
                query = query.filter(CircuitBreakerEvent.event_type == event_type)
            if start_time:
                query = query.filter(CircuitBreakerEvent.event_time >= start_time)
            if end_time:
                query = query.filter(CircuitBreakerEvent.event_time <= end_time)
            
            events = query.order_by(desc(CircuitBreakerEvent.event_time)).limit(limit).all()
            
            result = []
            for e in events:
                result.append({
                    'id': e.id,
                    'sensor_id': e.sensor_id,
                    'event_type': e.event_type,
                    'event_time': e.event_time.isoformat() if e.event_time else None,
                    'source': e.source,
                    'operator': e.operator,
                    'remark': e.remark,
                    'success': e.success,
                    'error_msg': e.error_msg,
                    'created_at': e.created_at.isoformat() if e.created_at else None
                })
            return result
    
    def get_today_circuit_breaker_switch_count(self, sensor_id: int) -> int:
        """获取今日断路器开关次数"""
        with self.get_session() as session:
            today_start = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
            
            count = session.query(CircuitBreakerEvent).filter(
                CircuitBreakerEvent.sensor_id == sensor_id,
                CircuitBreakerEvent.event_time >= today_start,
                CircuitBreakerEvent.success == True
            ).count()
            
            return count
    
    def cleanup_old_circuit_breaker_events(self, days: int = 90):
        """清理超过指定天数的断路器事件"""
        with self.get_session() as session:
            cutoff_time = datetime.now() - timedelta(days=days)
            deleted = session.query(CircuitBreakerEvent).filter(
                CircuitBreakerEvent.event_time < cutoff_time
            ).delete()
            session.commit()
            if deleted > 0:
                logger.info(f"清理 {deleted} 条过期断路器事件")
    
    # ==================== 空调控制事件操作 ====================
    
    def create_ac_control_event(
        self,
        sensor_id: int,
        action: str,
        is_on: bool = None,
        mode: str = None,
        target_temp: int = None,
        event_time: datetime = None,
        source: str = 'manual',
        operator: str = None,
        success: bool = True,
        error_msg: str = None
    ) -> ACControlEvent:
        """
        创建空调控制事件
        
        Args:
            sensor_id: 空调控制器ID
            action: 操作类型 (power_on_cool/power_on_heat/power_off/temp_up/temp_down/custom_N)
            is_on: 操作后是否开机
            mode: 模式 (cool/heat)
            target_temp: 设定温度
            event_time: 事件时间
            source: 来源 (manual/schedule/linkage)
            operator: 操作者
            success: 是否成功
            error_msg: 错误信息
        """
        with self.get_session() as session:
            event = ACControlEvent(
                sensor_id=sensor_id,
                action=action,
                is_on=is_on,
                mode=mode,
                target_temp=target_temp,
                event_time=event_time or datetime.now(),
                source=source,
                operator=operator,
                success=success,
                error_msg=error_msg
            )
            session.add(event)
            session.commit()
            session.refresh(event)
            return event
    
    def get_last_ac_state(self, sensor_id: int) -> Optional[Dict[str, Any]]:
        """
        获取空调最后状态（从最近的事件推断）
        
        Returns:
            {'is_on': bool, 'mode': str, 'target_temp': int}
        """
        with self.get_session() as session:
            event = session.query(ACControlEvent).filter(
                ACControlEvent.sensor_id == sensor_id,
                ACControlEvent.success == True
            ).order_by(desc(ACControlEvent.event_time)).first()
            
            if event:
                return {
                    'is_on': event.is_on,
                    'mode': event.mode,
                    'target_temp': event.target_temp,
                    'last_action': event.action,
                    'last_time': event.event_time.isoformat() if event.event_time else None
                }
            return None
    
    def get_ac_control_events(
        self,
        sensor_id: int = None,
        action: str = None,
        start_time: datetime = None,
        end_time: datetime = None,
        limit: int = 50
    ) -> List[Dict[str, Any]]:
        """查询空调控制事件"""
        with self.get_session() as session:
            query = session.query(ACControlEvent)
            
            if sensor_id:
                query = query.filter(ACControlEvent.sensor_id == sensor_id)
            if action:
                query = query.filter(ACControlEvent.action == action)
            if start_time:
                query = query.filter(ACControlEvent.event_time >= start_time)
            if end_time:
                query = query.filter(ACControlEvent.event_time <= end_time)
            
            events = query.order_by(desc(ACControlEvent.event_time)).limit(limit).all()
            
            result = []
            for e in events:
                result.append({
                    'id': e.id,
                    'sensor_id': e.sensor_id,
                    'action': e.action,
                    'is_on': e.is_on,
                    'mode': e.mode,
                    'target_temp': e.target_temp,
                    'event_time': e.event_time.isoformat() if e.event_time else None,
                    'source': e.source,
                    'operator': e.operator,
                    'success': e.success,
                    'error_msg': e.error_msg,
                    'created_at': e.created_at.isoformat() if e.created_at else None
                })
            return result
    
    def get_today_ac_operation_count(self, sensor_id: int) -> int:
        """获取今日空调操作次数"""
        with self.get_session() as session:
            today_start = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
            
            count = session.query(ACControlEvent).filter(
                ACControlEvent.sensor_id == sensor_id,
                ACControlEvent.event_time >= today_start,
                ACControlEvent.success == True
            ).count()
            
            return count
    
    def cleanup_old_ac_events(self, days: int = 90):
        """清理超过指定天数的空调控制事件"""
        with self.get_session() as session:
            cutoff_time = datetime.now() - timedelta(days=days)
            deleted = session.query(ACControlEvent).filter(
                ACControlEvent.event_time < cutoff_time
            ).delete()
            session.commit()
            if deleted > 0:
                logger.info(f"清理 {deleted} 条过期空调控制事件")
