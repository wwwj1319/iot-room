"""
温湿度传感器 API 接口

【接口】
1. GET /api/temp-humidity/status/{modbus_address} - 获取当前状态
2. GET /api/temp-humidity/history/{modbus_address} - 获取历史数据
3. GET /api/temp-humidity/stats/{modbus_address} - 获取统计数据
"""

from datetime import datetime, timedelta
from typing import Optional, List
from fastapi import APIRouter, Query, HTTPException
from pydantic import BaseModel

from database.repository import DatabaseRepository
from services.temp_humidity_service import TempHumidityService
from config import config

router = APIRouter(prefix="/api/temp-humidity", tags=["温湿度传感器"])

# ==================== 数据库实例（支持 main.py 注入 + 懒加载回退）====================
_db_repo: Optional[DatabaseRepository] = None


def set_db_repo(repo: DatabaseRepository):
    """注入全局数据库仓库（建议由 main.py 初始化后注入，避免重复连接）"""
    global _db_repo
    _db_repo = repo


def get_db_repo() -> DatabaseRepository:
    """获取数据库仓库（MySQL 失败自动回退 SQLite）"""
    global _db_repo
    if _db_repo is None:
        try:
            _db_repo = DatabaseRepository(config.MYSQL_URI)
        except Exception:
            _db_repo = DatabaseRepository("sqlite:///iot_data.db")
    return _db_repo

# 温湿度服务实例（会在 main.py 中设置）
_temp_humidity_service: Optional[TempHumidityService] = None


def set_temp_humidity_service(service: TempHumidityService):
    """设置温湿度服务实例"""
    global _temp_humidity_service
    _temp_humidity_service = service


# ==================== 响应模型 ====================

class TempHumidityStatusResponse(BaseModel):
    """温湿度当前状态响应"""
    sensor_id: int
    sensor_code: str
    sensor_name: str
    temperature: float
    humidity: float
    is_online: bool
    last_update: Optional[str] = None
    modbus_address: int


class TempHumidityHistoryItem(BaseModel):
    """温湿度历史记录项"""
    temperature: float
    humidity: float
    record_time: str


class TempHumidityHistoryResponse(BaseModel):
    """温湿度历史数据响应"""
    sensor_id: int
    modbus_address: int
    data: List[TempHumidityHistoryItem]
    total: int


class TempHumidityStatsResponse(BaseModel):
    """温湿度统计响应"""
    sensor_id: int
    modbus_address: int
    period: str  # today/week/month
    temperature: dict  # min, max, avg
    humidity: dict  # min, max, avg
    data_count: int


# ==================== API 接口 ====================

@router.get("/status/{modbus_address}", response_model=TempHumidityStatusResponse)
async def get_temp_humidity_status(modbus_address: int):
    """获取温湿度传感器当前状态"""
    db = get_db_repo()
    
    # 获取传感器信息
    sensor = db.get_sensor_by_modbus_address(modbus_address)
    if not sensor:
        raise HTTPException(status_code=404, detail=f"传感器不存在: {modbus_address}")
    
    # 从内存缓存获取实时数据
    realtime_data = None
    is_online = False
    if _temp_humidity_service:
        realtime_data = _temp_humidity_service.get_realtime_data(modbus_address)
        is_online = _temp_humidity_service.is_sensor_online(modbus_address)
    
    # 如果没有实时数据，从数据库获取最新记录
    if realtime_data:
        temperature = realtime_data['temperature']
        humidity = realtime_data['humidity']
        last_update = realtime_data['update_time'].isoformat()
    else:
        latest = db.get_latest_temp_humidity(sensor.id)
        if latest:
            temperature = latest['temperature']
            humidity = latest['humidity']
            last_update = latest['record_time']
        else:
            temperature = 0.0
            humidity = 0.0
            last_update = None
        
        # 检查数据库时间判断在线状态
        if sensor.last_data_at:
            is_online = (datetime.now() - sensor.last_data_at).total_seconds() < 300
    
    return TempHumidityStatusResponse(
        sensor_id=sensor.id,
        sensor_code=sensor.sensor_code,
        sensor_name=sensor.name or f"温湿度 {modbus_address}",
        temperature=temperature,
        humidity=humidity,
        is_online=is_online,
        last_update=last_update,
        modbus_address=modbus_address
    )


@router.get("/history/{modbus_address}", response_model=TempHumidityHistoryResponse)
async def get_temp_humidity_history(
    modbus_address: int,
    hours: int = Query(24, ge=1, le=168, description="查询最近N小时的数据"),
    limit: int = Query(100, ge=1, le=500, description="最大返回条数")
):
    """获取温湿度历史数据"""
    db = get_db_repo()
    
    sensor = db.get_sensor_by_modbus_address(modbus_address)
    if not sensor:
        raise HTTPException(status_code=404, detail=f"传感器不存在: {modbus_address}")
    
    start_time = datetime.now() - timedelta(hours=hours)
    
    history = db.get_temp_humidity_history(
        sensor_id=sensor.id,
        start_time=start_time,
        limit=limit
    )
    
    data = [
        TempHumidityHistoryItem(
            temperature=item['temperature'],
            humidity=item['humidity'],
            record_time=item['record_time']
        )
        for item in history
    ]
    
    return TempHumidityHistoryResponse(
        sensor_id=sensor.id,
        modbus_address=modbus_address,
        data=data,
        total=len(data)
    )


@router.get("/stats/{modbus_address}", response_model=TempHumidityStatsResponse)
async def get_temp_humidity_stats(
    modbus_address: int,
    period: str = Query("today", regex="^(today|week|month)$", description="统计周期")
):
    """获取温湿度统计数据"""
    db = get_db_repo()
    
    sensor = db.get_sensor_by_modbus_address(modbus_address)
    if not sensor:
        raise HTTPException(status_code=404, detail=f"传感器不存在: {modbus_address}")
    
    # 计算时间范围
    now = datetime.now()
    if period == "today":
        start_time = now.replace(hour=0, minute=0, second=0, microsecond=0)
    elif period == "week":
        start_time = now - timedelta(days=7)
    else:  # month
        start_time = now - timedelta(days=30)
    
    stats = db.get_temp_humidity_stats(
        sensor_id=sensor.id,
        start_time=start_time,
        end_time=now
    )
    
    return TempHumidityStatsResponse(
        sensor_id=sensor.id,
        modbus_address=modbus_address,
        period=period,
        temperature=stats['temperature'],
        humidity=stats['humidity'],
        data_count=stats['count']
    )

