"""
HTTP API 服务器

【功能说明】
使用 FastAPI 提供 REST API 服务，供 Flutter APP 和 Web 前端调用。
与 TCP Server 并行运行，共享数据库连接。
"""

import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from loguru import logger

from api.door_sensor_api import router as door_router
from api.temp_humidity_api import router as temp_humidity_router
from api.circuit_breaker_api import router as circuit_breaker_router
from api.ac_api import router as ac_router

# 创建 FastAPI 应用
app = FastAPI(
    title="IoT Room API",
    description="物联网设备间监控系统 API",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc"
)

# 配置 CORS（跨域请求）
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # 生产环境应该限制来源
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 注册路由
app.include_router(door_router)
app.include_router(temp_humidity_router)
app.include_router(circuit_breaker_router)
app.include_router(ac_router)


# ==================== 通用接口 ====================

@app.get("/")
async def root():
    """API 根路径"""
    return {
        "message": "IoT Room API 服务正常运行",
        "docs": "/docs",
        "version": "1.0.0"
    }


@app.get("/health")
async def health_check():
    """健康检查接口"""
    return {"status": "ok"}


# ==================== 启动函数 ====================

async def start_http_server(host: str = "0.0.0.0", port: int = 8900):
    """
    启动 HTTP 服务器（异步方式）
    
    Args:
        host: 监听地址
        port: 监听端口
    """
    config = uvicorn.Config(
        app=app,
        host=host,
        port=port,
        log_level="info",
        access_log=True
    )
    server = uvicorn.Server(config)
    logger.info(f"HTTP API 服务器启动: http://{host}:{port}")
    logger.info(f"API 文档地址: http://{host}:{port}/docs")
    await server.serve()


if __name__ == "__main__":
    import asyncio
    asyncio.run(start_http_server())

