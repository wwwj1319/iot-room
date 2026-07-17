"""
红外空调控制 API

【接口说明】
1. GET /status/{address} - 获取空调状态
2. POST /power-on/{address} - 开机（制冷/制热）
3. POST /power-off/{address} - 关机
4. POST /temp-up/{address} - 升温
5. POST /temp-down/{address} - 降温
6. POST /set-temp/{address} - 设置目标温度
7. GET /events/{address} - 获取操作历史
"""

from typing import Optional, List
from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel

from config import config
from database.repository import DatabaseRepository
from services.ac_service import ACService


# 创建路由
router = APIRouter(prefix="/api/ac", tags=["空调控制"])

# ==================== 数据库实例（支持 main.py 注入 + 懒加载回退）====================
_db_repo: Optional[DatabaseRepository] = None
_service: Optional[ACService] = None


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


def set_service(service: ACService):
    """注入服务实例"""
    global _service
    _service = service


def get_service() -> ACService:
    """获取服务实例"""
    global _service
    if _service is None:
        _service = ACService(get_db_repo())
    return _service


# ==================== 请求/响应模型 ====================

class ACStatusResponse(BaseModel):
    """空调状态响应"""
    modbus_address: int
    is_on: bool
    mode: str           # cool/heat
    mode_text: str      # 制冷/制热
    target_temp: int    # 设定温度
    is_online: bool
    last_update: Optional[str]
    today_operation_count: int


class ACPowerOnRequest(BaseModel):
    """开机请求"""
    mode: str = 'cool'  # cool/heat
    operator: Optional[str] = None


class ACControlResponse(BaseModel):
    """控制响应"""
    success: bool
    action: str
    target_temp: Optional[int] = None
    mode: Optional[str] = None
    command_hex: Optional[str] = None
    error: Optional[str] = None


class ACSetTempRequest(BaseModel):
    """设置温度请求"""
    target_temp: int
    operator: Optional[str] = None


class ACEventItem(BaseModel):
    """空调事件项"""
    id: int
    action: str
    is_on: Optional[bool]
    mode: Optional[str]
    target_temp: Optional[int]
    event_time: str
    source: str
    operator: Optional[str]
    success: bool
    error_msg: Optional[str]


class ACEventsResponse(BaseModel):
    """空调事件列表响应"""
    modbus_address: int
    events: List[ACEventItem]
    total: int


# ==================== API 接口 ====================

@router.get("/status/{modbus_address}", response_model=ACStatusResponse)
async def get_ac_status(modbus_address: int):
    """获取空调当前状态"""
    
    service = get_service()
    status = service.get_status(modbus_address)
    
    return ACStatusResponse(
        modbus_address=modbus_address,
        is_on=status['is_on'],
        mode=status['mode'],
        mode_text=status['mode_text'],
        target_temp=status['target_temp'],
        is_online=status['is_online'],
        last_update=status['last_update'],
        today_operation_count=service.get_today_operation_count(modbus_address)
    )


@router.post("/power-on/{modbus_address}", response_model=ACControlResponse)
async def ac_power_on(modbus_address: int, request: ACPowerOnRequest):
    """
    空调开机
    
    - mode='cool': 制冷模式
    - mode='heat': 制热模式
    """
    if request.mode not in ('cool', 'heat'):
        raise HTTPException(status_code=400, detail="mode 必须是 'cool' 或 'heat'")
    
    service = get_service()
    result = service.power_on(
        mode=request.mode,
        modbus_address=modbus_address,
        operator=request.operator
    )
    
    return ACControlResponse(
        success=result['success'],
        action=result['action'],
        mode=result.get('mode'),
        command_hex=result.get('command_hex'),
        error=result.get('error')
    )


@router.post("/power-off/{modbus_address}", response_model=ACControlResponse)
async def ac_power_off(modbus_address: int, operator: Optional[str] = None):
    """空调关机"""
    
    service = get_service()
    result = service.power_off(
        modbus_address=modbus_address,
        operator=operator
    )
    
    return ACControlResponse(
        success=result['success'],
        action=result['action'],
        command_hex=result.get('command_hex'),
        error=result.get('error')
    )


@router.post("/temp-up/{modbus_address}", response_model=ACControlResponse)
async def ac_temp_up(modbus_address: int, operator: Optional[str] = None):
    """升温（+1°C）"""
    
    service = get_service()
    result = service.temp_up(
        modbus_address=modbus_address,
        operator=operator
    )
    
    return ACControlResponse(
        success=result['success'],
        action=result['action'],
        target_temp=result.get('target_temp'),
        command_hex=result.get('command_hex'),
        error=result.get('error')
    )


@router.post("/temp-down/{modbus_address}", response_model=ACControlResponse)
async def ac_temp_down(modbus_address: int, operator: Optional[str] = None):
    """降温（-1°C）"""
    
    service = get_service()
    result = service.temp_down(
        modbus_address=modbus_address,
        operator=operator
    )
    
    return ACControlResponse(
        success=result['success'],
        action=result['action'],
        target_temp=result.get('target_temp'),
        command_hex=result.get('command_hex'),
        error=result.get('error')
    )


@router.post("/set-temp/{modbus_address}", response_model=ACControlResponse)
async def ac_set_temp(modbus_address: int, request: ACSetTempRequest):
    """设置目标温度（16-30°C）"""
    
    service = get_service()
    result = service.set_temp(
        target_temp=request.target_temp,
        modbus_address=modbus_address,
        operator=request.operator
    )
    
    return ACControlResponse(
        success=result['success'],
        action=result.get('action', 'set_temp'),
        target_temp=result.get('target_temp'),
        error=result.get('error')
    )


@router.get("/events/{modbus_address}", response_model=ACEventsResponse)
async def get_ac_events(
    modbus_address: int,
    limit: int = Query(50, ge=1, le=200, description="最大返回条数")
):
    """获取空调操作历史"""
    
    service = get_service()
    events = service.get_events(modbus_address, limit=limit)
    
    return ACEventsResponse(
        modbus_address=modbus_address,
        events=[
            ACEventItem(
                id=e['id'],
                action=e['action'],
                is_on=e['is_on'],
                mode=e['mode'],
                target_temp=e['target_temp'],
                event_time=e['event_time'],
                source=e['source'],
                operator=e['operator'],
                success=e['success'],
                error_msg=e['error_msg']
            )
            for e in events
        ],
        total=len(events)
    )

