"""
智能断路器 API

【接口说明】
1. GET /status/{address} - 获取断路器状态
2. POST /control/{address} - 控制断路器开关
3. GET /events/{address} - 获取操作历史
4. GET /command/query/{address} - 获取查询命令（调试用）
5. GET /command/control/{address} - 获取控制命令（调试用）
"""

from datetime import datetime
from typing import Optional, List
from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel

from config import config
from database.repository import DatabaseRepository
from services.circuit_breaker_service import CircuitBreakerService


# 创建路由
router = APIRouter(prefix="/api/circuit-breaker", tags=["智能断路器"])

# ==================== 数据库实例（支持 main.py 注入 + 懒加载回退）====================
_db_repo: Optional[DatabaseRepository] = None
_service: Optional[CircuitBreakerService] = None


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


def set_service(service: CircuitBreakerService):
    """注入服务实例"""
    global _service
    _service = service


def get_service() -> CircuitBreakerService:
    """获取服务实例"""
    global _service
    if _service is None:
        _service = CircuitBreakerService(get_db_repo())
    return _service


# ==================== 请求/响应模型 ====================

class CircuitBreakerStatusResponse(BaseModel):
    """断路器状态响应"""
    modbus_address: int
    is_closed: bool         # True=合闸(通电), False=分闸(断电)
    is_online: bool
    status_text: str        # 状态文本描述
    last_update: Optional[str]
    today_switch_count: int


class CircuitBreakerControlRequest(BaseModel):
    """断路器控制请求"""
    close: bool             # True=合闸(通电), False=分闸(断电)
    operator: Optional[str] = None
    remark: Optional[str] = None


class CircuitBreakerControlResponse(BaseModel):
    """断路器控制响应"""
    success: bool
    modbus_address: int
    action: str
    command_hex: str
    error: Optional[str] = None


class CircuitBreakerEventItem(BaseModel):
    """断路器事件项"""
    id: int
    event_type: str         # on/off
    event_time: str
    source: str
    operator: Optional[str]
    remark: Optional[str]
    success: bool
    error_msg: Optional[str]


class CircuitBreakerEventsResponse(BaseModel):
    """断路器事件列表响应"""
    modbus_address: int
    events: List[CircuitBreakerEventItem]
    total: int


class CommandResponse(BaseModel):
    """命令响应（调试用）"""
    modbus_address: int
    command_hex: str
    command_bytes: List[int]
    description: str


# ==================== API 接口 ====================

@router.get("/status/{modbus_address}", response_model=CircuitBreakerStatusResponse)
async def get_circuit_breaker_status(modbus_address: int):
    """获取断路器当前状态"""
    
    service = get_service()
    status = service.get_status(modbus_address)
    
    return CircuitBreakerStatusResponse(
        modbus_address=modbus_address,
        is_closed=status['is_closed'],
        is_online=status['is_online'],
        status_text=status['status_text'],
        last_update=status['last_update'],
        today_switch_count=service.get_today_switch_count(modbus_address)
    )


@router.post("/control/{modbus_address}", response_model=CircuitBreakerControlResponse)
async def control_circuit_breaker(modbus_address: int, request: CircuitBreakerControlRequest):
    """
    控制断路器开关
    
    - close=true: 合闸（通电/开灯）
    - close=false: 分闸（断电/关灯）
    """
    
    service = get_service()
    result = service.control(
        close=request.close,
        modbus_address=modbus_address,
        operator=request.operator,
        remark=request.remark
    )
    
    return CircuitBreakerControlResponse(**result)


@router.get("/events/{modbus_address}", response_model=CircuitBreakerEventsResponse)
async def get_circuit_breaker_events(
    modbus_address: int,
    limit: int = Query(50, ge=1, le=200, description="最大返回条数")
):
    """获取断路器操作事件历史"""
    
    service = get_service()
    events = service.get_events(modbus_address, limit=limit)
    
    return CircuitBreakerEventsResponse(
        modbus_address=modbus_address,
        events=[
            CircuitBreakerEventItem(
                id=e['id'],
                event_type=e['event_type'],
                event_time=e['event_time'],
                source=e['source'],
                operator=e['operator'],
                remark=e['remark'],
                success=e['success'],
                error_msg=e['error_msg']
            )
            for e in events
        ],
        total=len(events)
    )


# ==================== 调试接口 ====================

@router.get("/command/query/{modbus_address}", response_model=CommandResponse)
async def get_query_command(modbus_address: int):
    """
    获取断路器状态查询命令（调试用）
    
    返回可直接发送给断路器的 Modbus RTU 命令
    """
    service = get_service()
    cmd = service.build_query_command(modbus_address)
    
    return CommandResponse(
        modbus_address=modbus_address,
        command_hex=cmd.hex().upper(),
        command_bytes=list(cmd),
        description=f"查询断路器状态 (功能码 0x03, 寄存器 0x0000)"
    )


@router.get("/command/control/{modbus_address}", response_model=CommandResponse)
async def get_control_command(
    modbus_address: int,
    close: bool = Query(True, description="True=合闸(通电), False=分闸(断电)")
):
    """
    获取断路器控制命令（调试用）
    
    返回可直接发送给断路器的 Modbus RTU 命令
    """
    from protocol.modbus_rtu import ModbusRTUParser
    
    cmd = ModbusRTUParser.build_circuit_breaker_control_command(
        device_address=modbus_address,
        close=close
    )
    
    action = "合闸(通电)" if close else "分闸(断电)"
    value = "0x0001" if close else "0x0000"
    
    return CommandResponse(
        modbus_address=modbus_address,
        command_hex=cmd.hex().upper(),
        command_bytes=list(cmd),
        description=f"{action} (功能码 0x06, 寄存器 0x0000, 值 {value})"
    )

