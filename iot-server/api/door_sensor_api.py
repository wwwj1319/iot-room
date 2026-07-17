"""
门磁传感器 API

提供门磁传感器相关的 REST API：
1. 获取门磁当前状态
2. 获取门磁事件历史
3. 获取今日统计信息
"""

from datetime import datetime, timedelta
from typing import Optional, List
from fastapi import APIRouter, Query, HTTPException
from pydantic import BaseModel
from loguru import logger

from database.repository import DatabaseRepository
from config import config


router = APIRouter(prefix="/api/door", tags=["门磁传感器"])


# ==================== 响应模型 ====================

class DoorStatusResponse(BaseModel):
    sensor_id: int
    sensor_code: str
    sensor_name: str
    is_open: bool
    is_online: bool
    last_open_time: Optional[str] = None
    last_close_time: Optional[str] = None
    today_open_count: int
    modbus_address: int


class DoorEventItem(BaseModel):
    id: int
    event_type: str
    event_time: str
    duration_seconds: Optional[int] = None


class DoorEventsResponse(BaseModel):
    sensor_id: int
    total: int
    events: List[DoorEventItem]


class DoorStatsResponse(BaseModel):
    sensor_id: int
    today_open_count: int
    today_close_count: int
    week_open_count: int
    longest_open_minutes: int
    avg_open_minutes: float


# ==================== 数据库连接 ====================

_db_repo: Optional[DatabaseRepository] = None


def set_db_repo(repo: DatabaseRepository):
    """注入全局数据库仓库（建议由 main.py 初始化后注入，避免重复连接）"""
    global _db_repo
    _db_repo = repo


def get_db_repo() -> DatabaseRepository:
    global _db_repo
    if _db_repo is None:
        try:
            _db_repo = DatabaseRepository(config.MYSQL_URI)
        except Exception as e:
            logger.warning(f"MySQL 连接失败: {e}，使用 SQLite")
            _db_repo = DatabaseRepository("sqlite:///iot_data.db")
    return _db_repo


# ==================== API 接口 ====================

@router.get("/status/{modbus_address}", response_model=DoorStatusResponse)
async def get_door_status(modbus_address: int):
    """获取门磁当前状态"""
    db = get_db_repo()
    
    sensor = db.get_sensor_by_modbus_address(modbus_address)
    if not sensor:
        raise HTTPException(status_code=404, detail=f"传感器不存在: {modbus_address}")
    
    is_open = db.get_door_current_status(sensor.id)
    
    # 获取最近开关时间
    events = db.get_door_events(sensor_id=sensor.id, limit=50)
    last_open_time = None
    last_close_time = None
    
    for e in events:
        if e['event_type'] == 'open' and last_open_time is None:
            last_open_time = e['event_time']
        elif e['event_type'] == 'close' and last_close_time is None:
            last_close_time = e['event_time']
        if last_open_time and last_close_time:
            break
    
    today_count = db.get_today_door_open_count(sensor.id)
    
    # 5分钟内有数据认为在线
    is_online = False
    if sensor.last_data_at:
        is_online = (datetime.now() - sensor.last_data_at).total_seconds() < 300
    
    return DoorStatusResponse(
        sensor_id=sensor.id,
        sensor_code=sensor.sensor_code,
        sensor_name=sensor.name or f"门磁 {modbus_address}",
        is_open=is_open if is_open is not None else False,
        is_online=is_online,
        last_open_time=last_open_time,
        last_close_time=last_close_time,
        today_open_count=today_count,
        modbus_address=modbus_address
    )


@router.get("/events/{modbus_address}", response_model=DoorEventsResponse)
async def get_door_events(
    modbus_address: int,
    event_type: Optional[str] = Query(None, description="open/close"),
    days: int = Query(7, description="查询天数"),
    limit: int = Query(50, description="数量限制")
):
    """获取门磁事件历史"""
    db = get_db_repo()
    
    sensor = db.get_sensor_by_modbus_address(modbus_address)
    if not sensor:
        raise HTTPException(status_code=404, detail=f"传感器不存在: {modbus_address}")
    
    start_time = datetime.now() - timedelta(days=days)
    
    events = db.get_door_events(
        sensor_id=sensor.id,
        event_type=event_type,
        start_time=start_time,
        limit=limit
    )
    
    # 计算开门时长
    result_events = []
    for i, event in enumerate(events):
        duration = None
        if event['event_type'] == 'close' and i + 1 < len(events):
            next_event = events[i + 1]
            if next_event['event_type'] == 'open':
                close_time = datetime.fromisoformat(event['event_time'])
                open_time = datetime.fromisoformat(next_event['event_time'])
                duration = int((close_time - open_time).total_seconds())
        
        result_events.append(DoorEventItem(
            id=event['id'],
            event_type=event['event_type'],
            event_time=event['event_time'],
            duration_seconds=duration
        ))
    
    return DoorEventsResponse(
        sensor_id=sensor.id,
        total=len(result_events),
        events=result_events
    )


@router.get("/stats/{modbus_address}", response_model=DoorStatsResponse)
async def get_door_stats(modbus_address: int):
    """获取门磁统计信息"""
    db = get_db_repo()
    
    sensor = db.get_sensor_by_modbus_address(modbus_address)
    if not sensor:
        raise HTTPException(status_code=404, detail=f"传感器不存在: {modbus_address}")
    
    today_start = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
    today_events = db.get_door_events(sensor_id=sensor.id, start_time=today_start, limit=1000)
    
    today_open = sum(1 for e in today_events if e['event_type'] == 'open')
    today_close = sum(1 for e in today_events if e['event_type'] == 'close')
    
    week_start = today_start - timedelta(days=today_start.weekday())
    week_events = db.get_door_events(sensor_id=sensor.id, start_time=week_start, limit=5000)
    week_open = sum(1 for e in week_events if e['event_type'] == 'open')
    
    # 计算开门时长
    durations = []
    for i, event in enumerate(week_events):
        if event['event_type'] == 'close' and i + 1 < len(week_events):
            next_event = week_events[i + 1]
            if next_event['event_type'] == 'open':
                close_time = datetime.fromisoformat(event['event_time'])
                open_time = datetime.fromisoformat(next_event['event_time'])
                duration_minutes = (close_time - open_time).total_seconds() / 60
                if duration_minutes > 0:
                    durations.append(duration_minutes)
    
    longest_open = int(max(durations)) if durations else 0
    avg_open = round(sum(durations) / len(durations), 1) if durations else 0
    
    return DoorStatsResponse(
        sensor_id=sensor.id,
        today_open_count=today_open,
        today_close_count=today_close,
        week_open_count=week_open,
        longest_open_minutes=longest_open,
        avg_open_minutes=avg_open
    )


@router.get("/sensors")
async def list_door_sensors():
    """获取所有门磁传感器列表"""
    db = get_db_repo()
    
    with db.get_session() as session:
        from database.models import Sensor
        sensors = session.query(Sensor).filter(Sensor.sensor_type == 'door').all()
        
        result = []
        for sensor in sensors:
            is_open = db.get_door_current_status(sensor.id)
            is_online = False
            if sensor.last_data_at:
                is_online = (datetime.now() - sensor.last_data_at).total_seconds() < 300
            
            result.append({
                'sensor_id': sensor.id,
                'sensor_code': sensor.sensor_code,
                'sensor_name': sensor.name,
                'modbus_address': sensor.modbus_address,
                'is_open': is_open if is_open is not None else False,
                'is_online': is_online
            })
        
        return {'sensors': result, 'total': len(result)}
