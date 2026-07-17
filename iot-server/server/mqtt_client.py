"""
MQTT 客户端

【功能说明】
订阅 MQTT 主题，接收 DTU 透传的传感器数据。
DTU 透传的是原始 Modbus RTU 帧，需要解析后处理。

【Topic 设计】
- iot/sensor/data           - 统一传感器数据（推荐）
- iot/sensor/door/data      - 门磁传感器数据
- iot/sensor/temp/data      - 温湿度传感器数据
- iot/sensor/breaker/data   - 断路器数据
- iot/control/breaker       - 断路器控制命令下发
"""

import asyncio
from typing import Callable, Optional
from loguru import logger
import paho.mqtt.client as mqtt

from protocol.modbus_rtu import (
    ModbusRTUParser, DoorSensorData, TempHumidityData, CircuitBreakerData
)


class MQTTClient:
    """
    MQTT 客户端
    
    【工作流程】
    1. 连接到 MQTT Broker
    2. 订阅传感器数据主题
    3. 收到消息后解析 Modbus 帧
    4. 调用回调函数处理数据
    """
    
    def __init__(
        self,
        broker_host: str = "localhost",
        broker_port: int = 8899,
        client_id: str = "iot_server",
        on_door_data: Optional[Callable] = None,
        on_temp_humidity_data: Optional[Callable] = None,
        on_circuit_breaker_data: Optional[Callable] = None
    ):
        """
        初始化 MQTT 客户端
        
        Args:
            broker_host: MQTT Broker 地址
            broker_port: MQTT Broker 端口
            client_id: 客户端 ID
            on_door_data: 收到门磁数据的回调函数
            on_temp_humidity_data: 收到温湿度数据的回调函数
            on_circuit_breaker_data: 收到断路器数据的回调函数
        """
        self.broker_host = broker_host
        self.broker_port = broker_port
        self.client_id = client_id
        self.on_door_data = on_door_data
        self.on_temp_humidity_data = on_temp_humidity_data
        self.on_circuit_breaker_data = on_circuit_breaker_data
        
        # 订阅的主题列表
        self.topics = [
            ("iot/sensor/data", 0),           # 统一传感器数据主题
            ("iot/sensor/door/data", 0),      # 门磁数据（兼容）
            ("iot/sensor/temp/data", 0),      # 温湿度数据（兼容）
            ("iot/sensor/breaker/data", 0),   # 断路器数据（兼容）
            ("iot/sensor/+/data", 0),         # 所有传感器数据（通配符）
        ]
        
        # 控制命令下发主题
        self.control_topic = "iot/control/breaker"
        
        # MQTT 客户端
        self._client: Optional[mqtt.Client] = None
        self._loop: Optional[asyncio.AbstractEventLoop] = None
        self._running = False
    
    def _on_connect(self, client, userdata, flags, rc):
        """连接成功回调"""
        if rc == 0:
            logger.info(f"MQTT 连接成功: {self.broker_host}:{self.broker_port}")
            # 订阅主题
            for topic, qos in self.topics:
                client.subscribe(topic, qos)
                logger.info(f"MQTT 订阅主题: {topic}")
        else:
            logger.error(f"MQTT 连接失败，返回码: {rc}")
    
    def _on_disconnect(self, client, userdata, rc):
        """断开连接回调"""
        if rc != 0:
            logger.warning(f"MQTT 意外断开连接，返回码: {rc}，尝试重连...")
        else:
            logger.info("MQTT 连接已断开")
    
    def _on_message(self, client, userdata, msg):
        """
        收到消息回调
        
        DTU 透传的是原始 Modbus RTU 帧（十六进制字节）
        根据设备地址自动识别传感器类型
        """
        try:
            topic = msg.topic
            payload = msg.payload
            
            logger.debug(f"MQTT 收到消息: topic={topic}, payload={payload.hex().upper()}")
            
            # 先尝试获取设备地址来判断传感器类型
            if len(payload) < 5:
                logger.debug(f"数据长度不足: {len(payload)}")
                return
            
            device_address = payload[0]
            
            # 根据设备地址判断传感器类型
            if ModbusRTUParser.is_door_sensor(device_address):
                # 门磁传感器（地址 0x4X）
                door_data = ModbusRTUParser.parse_door_sensor_response(payload)
                if door_data:
                    logger.info(f"解析门磁数据成功: {door_data}")
                    if self.on_door_data and self._loop:
                        asyncio.run_coroutine_threadsafe(
                            self._handle_door_data(door_data),
                            self._loop
                        )
                        
            elif ModbusRTUParser.is_temp_humidity_sensor(device_address):
                # 温湿度传感器（地址 1）
                th_data = ModbusRTUParser.parse_temp_humidity_response(payload)
                if th_data:
                    logger.info(f"解析温湿度数据成功: {th_data}")
                    if self.on_temp_humidity_data and self._loop:
                        asyncio.run_coroutine_threadsafe(
                            self._handle_temp_humidity_data(th_data),
                            self._loop
                        )
                        
            elif ModbusRTUParser.is_circuit_breaker(device_address):
                # 智能断路器（地址 2）
                cb_data = ModbusRTUParser.parse_circuit_breaker_response(payload)
                if cb_data:
                    logger.info(f"解析断路器数据成功: {cb_data}")
                    if self.on_circuit_breaker_data and self._loop:
                        asyncio.run_coroutine_threadsafe(
                            self._handle_circuit_breaker_data(cb_data),
                            self._loop
                        )
            else:
                logger.debug(f"未知设备类型: 地址=0x{device_address:02X}")
        
        except Exception as e:
            logger.error(f"处理 MQTT 消息异常: {e}", exc_info=True)
    
    async def _handle_door_data(self, door_data: DoorSensorData):
        """处理门磁数据（异步）"""
        if self.on_door_data:
            await self.on_door_data(door_data)
    
    async def _handle_temp_humidity_data(self, th_data: TempHumidityData):
        """处理温湿度数据（异步）"""
        if self.on_temp_humidity_data:
            await self.on_temp_humidity_data(th_data)
    
    async def _handle_circuit_breaker_data(self, cb_data: CircuitBreakerData):
        """处理断路器数据（异步）"""
        if self.on_circuit_breaker_data:
            await self.on_circuit_breaker_data(cb_data)
    
    async def start(self):
        """启动 MQTT 客户端"""
        self._loop = asyncio.get_event_loop()
        self._running = True
        
        # 创建 MQTT 客户端
        self._client = mqtt.Client(client_id=self.client_id)
        self._client.on_connect = self._on_connect
        self._client.on_disconnect = self._on_disconnect
        self._client.on_message = self._on_message
        
        # 设置自动重连
        self._client.reconnect_delay_set(min_delay=1, max_delay=30)
        
        try:
            # 连接到 Broker
            logger.info(f"MQTT 正在连接: {self.broker_host}:{self.broker_port}")
            self._client.connect(self.broker_host, self.broker_port, keepalive=60)
            
            # 启动网络循环（在后台线程）
            self._client.loop_start()
            
            # 保持运行
            while self._running:
                await asyncio.sleep(1)
        
        except Exception as e:
            logger.error(f"MQTT 启动失败: {e}", exc_info=True)
            raise
    
    async def stop(self):
        """停止 MQTT 客户端"""
        self._running = False
        
        if self._client:
            self._client.loop_stop()
            self._client.disconnect()
            logger.info("MQTT 客户端已停止")
    
    def publish(self, topic: str, payload: bytes, qos: int = 0) -> bool:
        """
        发布消息（用于下发控制指令）
        
        Args:
            topic: 主题
            payload: 消息内容
            qos: 服务质量
            
        Returns:
            是否发送成功
        """
        if self._client:
            result = self._client.publish(topic, payload, qos)
            logger.debug(f"MQTT 发布: topic={topic}, payload={payload.hex().upper()}")
            return result.rc == mqtt.MQTT_ERR_SUCCESS
        return False
    
    def send_circuit_breaker_command(self, command: bytes) -> bool:
        """
        发送断路器控制命令
        
        Args:
            command: Modbus RTU 命令帧
            
        Returns:
            是否发送成功
        """
        return self.publish(self.control_topic, command, qos=1)


# ==================== 测试代码 ====================
if __name__ == '__main__':
    import sys
    logger.remove()
    logger.add(sys.stdout, level="DEBUG")
    
    async def test_callback(door_data: DoorSensorData):
        """测试回调"""
        print(f"收到门磁数据: {door_data}")
        print(f"  - 设备地址: 0x{door_data.device_address:02X}")
        print(f"  - 门状态: {'开启' if door_data.is_open else '关闭'}")
    
    async def main():
        client = MQTTClient(
            broker_host="localhost",
            broker_port=8899,
            on_door_data=test_callback
        )
        
        print("=" * 60)
        print("MQTT 客户端测试")
        print("等待 DTU 发送数据...")
        print("Ctrl+C 停止")
        print("=" * 60)
        
        try:
            await client.start()
        except KeyboardInterrupt:
            await client.stop()
    
    asyncio.run(main())

