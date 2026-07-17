"""
数据库模型定义

【表结构】
1. rooms - 设备间信息
2. sensors - 传感器信息  
3. door_events - 门磁事件（只记录开门/关门状态变化）
4. temp_humidity_data - 温湿度数据（定期采样记录）
5. circuit_breaker_events - 断路器操作事件（开关状态变化）
6. ac_control_events - 空调控制事件（红外发射记录）
"""

from datetime import datetime
from sqlalchemy import (
    Column, Integer, String, Boolean, DateTime, Float,
    ForeignKey, Text, Index, create_engine
)
from sqlalchemy.orm import declarative_base, relationship
from sqlalchemy.sql import func

Base = declarative_base()


class Room(Base):
    """设备间表"""
    __tablename__ = 'rooms'
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    room_code = Column(String(50), unique=True, nullable=False, comment='设备间编号')
    name = Column(String(100), nullable=False, comment='设备间名称')
    location = Column(String(200), comment='位置描述')
    status = Column(String(20), default='offline', comment='状态: online/offline/alarm')
    
    created_at = Column(DateTime, default=func.now())
    updated_at = Column(DateTime, default=func.now(), onupdate=func.now())
    
    sensors = relationship('Sensor', back_populates='room')
    
    def __repr__(self):
        return f"<Room(id={self.id}, code={self.room_code}, name={self.name})>"


class Sensor(Base):
    """传感器表"""
    __tablename__ = 'sensors'
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    room_id = Column(Integer, ForeignKey('rooms.id'), nullable=False, comment='所属设备间')
    sensor_type = Column(String(50), nullable=False, comment='传感器类型: door/temp_humidity/light/ac')
    sensor_code = Column(String(50), unique=True, nullable=False, comment='传感器编号')
    name = Column(String(100), comment='传感器名称')
    modbus_address = Column(Integer, comment='Modbus从站地址(十进制)')
    status = Column(String(20), default='offline', comment='状态: online/offline/alarm')
    
    created_at = Column(DateTime, default=func.now())
    updated_at = Column(DateTime, default=func.now(), onupdate=func.now())
    last_data_at = Column(DateTime, comment='最后数据时间')
    
    room = relationship('Room', back_populates='sensors')
    door_events = relationship('DoorEvent', back_populates='sensor')
    temp_humidity_data = relationship('TempHumidityData', back_populates='sensor')
    circuit_breaker_events = relationship('CircuitBreakerEvent', back_populates='sensor')
    ac_control_events = relationship('ACControlEvent', back_populates='sensor')
    
    __table_args__ = (
        Index('idx_sensor_room_type', 'room_id', 'sensor_type'),
        Index('idx_sensor_modbus', 'modbus_address'),
    )
    
    def __repr__(self):
        return f"<Sensor(id={self.id}, type={self.sensor_type}, code={self.sensor_code})>"


class DoorEvent(Base):
    """
    门磁事件表
    
    只在状态变化时写入：
    - 从关→开 = 开门事件
    - 从开→关 = 关门事件
    """
    __tablename__ = 'door_events'
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    sensor_id = Column(Integer, ForeignKey('sensors.id'), nullable=False, comment='传感器ID')
    
    event_type = Column(String(10), nullable=False, comment='事件类型: open/close')
    event_time = Column(DateTime, nullable=False, comment='事件时间')
    
    created_at = Column(DateTime, default=func.now())
    
    sensor = relationship('Sensor', back_populates='door_events')
    
    __table_args__ = (
        Index('idx_door_event_sensor_time', 'sensor_id', 'event_time'),
        Index('idx_door_event_type', 'event_type'),
        Index('idx_door_event_time', 'event_time'),
    )
    
    def __repr__(self):
        return f"<DoorEvent(id={self.id}, type={self.event_type}, time={self.event_time})>"


class TempHumidityData(Base):
    """
    温湿度数据表
    
    存储策略：
    - 定期采样存储（如每5分钟存一条）
    - 用于历史数据查询和图表展示
    - 最新数据直接查最近一条
    """
    __tablename__ = 'temp_humidity_data'
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    sensor_id = Column(Integer, ForeignKey('sensors.id'), nullable=False, comment='传感器ID')
    
    temperature = Column(Float, nullable=False, comment='温度（摄氏度）')
    humidity = Column(Float, nullable=False, comment='湿度（%RH）')
    
    # 原始值（用于调试）
    raw_temp = Column(Integer, comment='温度原始值')
    raw_humidity = Column(Integer, comment='湿度原始值')
    
    record_time = Column(DateTime, nullable=False, comment='采样时间')
    created_at = Column(DateTime, default=func.now())
    
    sensor = relationship('Sensor', back_populates='temp_humidity_data')
    
    __table_args__ = (
        Index('idx_th_sensor_time', 'sensor_id', 'record_time'),
        Index('idx_th_time', 'record_time'),
    )
    
    def __repr__(self):
        return f"<TempHumidityData(id={self.id}, temp={self.temperature}°C, humidity={self.humidity}%)>"


class CircuitBreakerEvent(Base):
    """
    断路器操作事件表
    
    记录断路器的每次状态变化：
    - on = 合闸（通电/开灯）
    - off = 分闸（断电/关灯）
    
    操作来源：
    - manual = 手动操作（APP/API）
    - schedule = 定时任务
    - linkage = 联动触发
    - unknown = 未知（如本地按钮操作）
    """
    __tablename__ = 'circuit_breaker_events'
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    sensor_id = Column(Integer, ForeignKey('sensors.id'), nullable=False, comment='断路器传感器ID')
    
    event_type = Column(String(10), nullable=False, comment='事件类型: on/off')
    event_time = Column(DateTime, nullable=False, comment='事件时间')
    source = Column(String(20), default='unknown', comment='操作来源: manual/schedule/linkage/unknown')
    operator = Column(String(50), comment='操作者（如用户名）')
    remark = Column(String(200), comment='备注')
    
    # 操作结果
    success = Column(Boolean, default=True, comment='是否成功')
    error_msg = Column(String(200), comment='错误信息')
    
    created_at = Column(DateTime, default=func.now())
    
    sensor = relationship('Sensor', back_populates='circuit_breaker_events')
    
    __table_args__ = (
        Index('idx_cb_event_sensor_time', 'sensor_id', 'event_time'),
        Index('idx_cb_event_type', 'event_type'),
        Index('idx_cb_event_time', 'event_time'),
    )
    
    def __repr__(self):
        return f"<CircuitBreakerEvent(id={self.id}, type={self.event_type}, time={self.event_time})>"


class ACControlEvent(Base):
    """
    空调控制事件表
    
    记录红外空调控制器的每次操作：
    - power_on_cool = 制冷开机
    - power_on_heat = 制热开机
    - power_off = 关机
    - temp_up = 升温
    - temp_down = 降温
    - custom_1 ~ custom_20 = 自定义操作
    
    注意：由于红外是单向通信，设定温度为本地维护的值，不是空调真实值
    """
    __tablename__ = 'ac_control_events'
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    sensor_id = Column(Integer, ForeignKey('sensors.id'), nullable=False, comment='空调控制器ID')
    
    # 操作类型
    action = Column(String(30), nullable=False, comment='操作: power_on_cool/power_on_heat/power_off/temp_up/temp_down/custom_N')
    
    # 操作后的状态（本地维护）
    is_on = Column(Boolean, default=False, comment='是否开机')
    mode = Column(String(10), comment='模式: cool/heat')
    target_temp = Column(Integer, comment='设定温度')
    
    # 操作信息
    event_time = Column(DateTime, nullable=False, comment='操作时间')
    source = Column(String(20), default='manual', comment='来源: manual/schedule/linkage')
    operator = Column(String(50), comment='操作者')
    
    # 结果
    success = Column(Boolean, default=True, comment='是否成功发送')
    error_msg = Column(String(200), comment='错误信息')
    
    created_at = Column(DateTime, default=func.now())
    
    sensor = relationship('Sensor', back_populates='ac_control_events')
    
    __table_args__ = (
        Index('idx_ac_event_sensor_time', 'sensor_id', 'event_time'),
        Index('idx_ac_event_action', 'action'),
        Index('idx_ac_event_time', 'event_time'),
    )
    
    def __repr__(self):
        return f"<ACControlEvent(id={self.id}, action={self.action}, temp={self.target_temp})>"


def init_database(db_uri: str, echo: bool = False):
    """初始化数据库"""
    engine = create_engine(db_uri, echo=echo)
    Base.metadata.create_all(engine)
    return engine
