"""
IoT Server 主入口

启动后会：
1. 连接 MQTT Broker，订阅传感器数据（端口 8899）
2. 启动 HTTP API 服务器（端口 8900）
3. 解析 Modbus RTU 数据
4. 只在开门/关门状态变化时存入数据库（数据量小）

运行方式：
    python main.py
"""

import asyncio
import sys
import os
from datetime import datetime
from loguru import logger

# 确保当前目录在 Python 路径中
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from config import config
from server.mqtt_client import MQTTClient
from database.repository import DatabaseRepository
from services.door_linkage_service import DoorLinkageService
from services.temp_humidity_service import TempHumidityService
from services.circuit_breaker_service import CircuitBreakerService
from services.ac_service import ACService
from protocol.modbus_rtu import DoorSensorData, TempHumidityData, CircuitBreakerData

# ==================== 配置 ====================

MQTT_HOST = config.MQTT_BROKER
MQTT_PORT = config.MQTT_PORT
HTTP_HOST = config.HTTP_HOST
HTTP_PORT = config.HTTP_PORT


# ==================== 日志配置 ====================

def setup_logging():
    logger.remove()
    logger.add(
        sys.stdout,
        level=config.LOG_LEVEL,
        format="<green>{time:YYYY-MM-DD HH:mm:ss}</green> | "
               "<level>{level: <8}</level> | "
               "<cyan>{name}</cyan>:<cyan>{function}</cyan>:<cyan>{line}</cyan> | "
               "<level>{message}</level>"
    )


# ==================== IoT 服务器 ====================

class IoTServer:
    """IoT 服务器（MQTT 版本）"""
    
    def __init__(self):
        self.db_repo: DatabaseRepository = None
        self.mqtt_client: MQTTClient = None
        self.door_service: DoorLinkageService = None
        self.temp_humidity_service: TempHumidityService = None
        self.circuit_breaker_service: CircuitBreakerService = None
        self.ac_service: ACService = None
        self.stats = {
            'start_time': None,
            'total_messages': 0,
            'door_events': 0,
            'temp_humidity_records': 0,
            'circuit_breaker_events': 0,
            'ac_operations': 0,
        }
    
    async def init(self):
        """初始化服务"""
        # 数据库
        try:
            self.db_repo = DatabaseRepository(config.MYSQL_URI)
            logger.info(f"数据库连接成功: MySQL ({config.MYSQL_HOST}:{config.MYSQL_PORT})")
        except Exception as e:
            logger.warning(f"MySQL 连接失败: {e}，使用 SQLite")
            self.db_repo = DatabaseRepository("sqlite:///iot_data.db")
        
        # 门磁服务
        self.door_service = DoorLinkageService(self.db_repo)
        
        # 温湿度服务
        self.temp_humidity_service = TempHumidityService(self.db_repo)
        
        # 断路器服务
        self.circuit_breaker_service = CircuitBreakerService(self.db_repo)
        
        # 空调控制服务
        self.ac_service = ACService(self.db_repo)
        
        # 设置 API 的服务实例
        from api.temp_humidity_api import set_temp_humidity_service
        from api.temp_humidity_api import set_db_repo as set_th_db_repo
        from api.circuit_breaker_api import set_service as set_cb_service
        from api.circuit_breaker_api import set_db_repo as set_cb_db_repo
        from api.ac_api import set_service as set_ac_service
        from api.ac_api import set_db_repo as set_ac_db_repo
        from api.door_sensor_api import set_db_repo as set_door_db_repo

        # 让所有 API 复用同一个数据库仓库实例（避免 import 时创建多连接/不一致）
        set_th_db_repo(self.db_repo)
        set_cb_db_repo(self.db_repo)
        set_ac_db_repo(self.db_repo)
        set_door_db_repo(self.db_repo)

        set_temp_humidity_service(self.temp_humidity_service)
        set_cb_service(self.circuit_breaker_service)
        set_ac_service(self.ac_service)
        
        # MQTT 客户端
        self.mqtt_client = MQTTClient(
            broker_host=MQTT_HOST,
            broker_port=MQTT_PORT,
            client_id="iot_server",
            on_door_data=self._handle_door_data,
            on_temp_humidity_data=self._handle_temp_humidity_data,
            on_circuit_breaker_data=self._handle_circuit_breaker_data
        )
        
        # 设置控制命令发送回调
        self.circuit_breaker_service.set_send_command_callback(
            self.mqtt_client.send_circuit_breaker_command
        )
        self.ac_service.set_send_command_callback(
            self._send_ac_command
        )
        
        self.stats['start_time'] = datetime.now()
    
    def _send_ac_command(self, cmd: bytes) -> bool:
        """发送空调控制命令"""
        if self.mqtt_client:
            return self.mqtt_client.publish("iot/control/ac", cmd, qos=1)
        return False
    
    async def _handle_door_data(self, data: DoorSensorData):
        """处理门磁数据"""
        self.stats['total_messages'] += 1
        
        try:
            status = "开" if data.is_open else "关"
            logger.debug(f"[MQTT] 门磁 0x{data.device_address:02X} | 状态: {status}")
            
            # 边沿检测，只有状态变化才记录
            event_triggered = await self.door_service.process_door_data(data)
            
            if event_triggered:
                self.stats['door_events'] += 1
                logger.info(f"[事件] 门磁 0x{data.device_address:02X} | {'开门' if data.is_open else '关门'}")
                
                # 非工作时间告警
                now = datetime.now()
                if data.is_open and (now.hour >= 22 or now.hour < 6):
                    logger.warning(f"[告警] 非工作时间开门!")
        
        except Exception as e:
            logger.error(f"处理门磁数据异常: {e}", exc_info=True)
    
    async def _handle_temp_humidity_data(self, data: TempHumidityData):
        """处理温湿度数据"""
        self.stats['total_messages'] += 1
        
        try:
            logger.debug(
                f"[MQTT] 温湿度 0x{data.device_address:02X} | "
                f"温度: {data.temperature}°C, 湿度: {data.humidity}%"
            )
            
            # 处理温湿度数据
            await self.temp_humidity_service.process_temp_humidity_data(data)
            self.stats['temp_humidity_records'] += 1
            
            # 温湿度告警检查
            if data.temperature > 35:
                logger.warning(f"[告警] 温度过高: {data.temperature}°C")
            elif data.temperature < 5:
                logger.warning(f"[告警] 温度过低: {data.temperature}°C")
            
            if data.humidity > 80:
                logger.warning(f"[告警] 湿度过高: {data.humidity}%")
        
        except Exception as e:
            logger.error(f"处理温湿度数据异常: {e}", exc_info=True)
    
    async def _handle_circuit_breaker_data(self, data: CircuitBreakerData):
        """处理断路器数据"""
        self.stats['total_messages'] += 1
        
        try:
            status = "合闸(通电)" if data.is_closed else "分闸(断电)"
            logger.debug(f"[MQTT] 断路器 0x{data.device_address:02X} | 状态: {status}")
            
            # 处理断路器状态数据
            status_changed = self.circuit_breaker_service.process_status_data(data)
            
            if status_changed:
                self.stats['circuit_breaker_events'] += 1
                logger.info(f"[事件] 断路器 0x{data.device_address:02X} | {status}")
        
        except Exception as e:
            logger.error(f"处理断路器数据异常: {e}", exc_info=True)
    
    async def stop(self):
        """停止服务"""
        logger.info("IoT Server 停止中...")
        
        if self.mqtt_client:
            await self.mqtt_client.stop()
        
        if self.stats['start_time']:
            runtime = datetime.now() - self.stats['start_time']
            logger.info(f"运行时长: {runtime}")
            logger.info(f"总消息数: {self.stats['total_messages']}")
            logger.info(f"门磁事件: {self.stats['door_events']}")
            logger.info(f"温湿度记录: {self.stats['temp_humidity_records']}")
            logger.info(f"断路器事件: {self.stats['circuit_breaker_events']}")
            logger.info(f"空调操作: {self.stats['ac_operations']}")


# ==================== 主函数 ====================

async def main():
    setup_logging()
    
    logger.info("=" * 50)
    logger.info("IoT Server 启动中...")
    logger.info("=" * 50)
    
    server = IoTServer()
    await server.init()
    
    from api.http_server import start_http_server
    
    logger.info("=" * 50)
    logger.info("启动完成!")
    logger.info(f"MQTT: {MQTT_HOST}:{MQTT_PORT}")
    logger.info(f"HTTP: http://{HTTP_HOST}:{HTTP_PORT}")
    logger.info(f"文档: http://{HTTP_HOST}:{HTTP_PORT}/docs")
    logger.info("=" * 50)
    logger.info("订阅主题:")
    logger.info("  - iot/sensor/door/data (门磁)")
    logger.info("  - iot/sensor/temp/data (温湿度)")
    logger.info("  - iot/sensor/breaker/data (断路器)")
    logger.info("控制主题:")
    logger.info("  - iot/control/breaker (断路器控制)")
    logger.info("  - iot/control/ac (空调控制)")
    logger.info("Ctrl+C 停止")
    logger.info("=" * 50)
    
    try:
        await asyncio.gather(
            server.mqtt_client.start(),
            start_http_server(host=HTTP_HOST, port=HTTP_PORT)
        )
    except KeyboardInterrupt:
        pass
    finally:
        await server.stop()


if __name__ == '__main__':
    asyncio.run(main())
