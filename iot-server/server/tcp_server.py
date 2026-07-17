"""
TCP Socket 服务器

【实现说明】
这个模块负责接收 DTU 上报的数据。

DTU 的工作模式：
1. 透传模式：DTU 只做数据转发，原样传输 Modbus RTU 帧
2. 协议模式：DTU 有自己的协议封装

这里假设 DTU 是透传模式，直接传输 Modbus RTU 帧。
如果你的 DTU 有自己的协议，需要根据文档调整解析逻辑。

技术要点：
1. 使用 asyncio 实现异步 IO，支持高并发
2. 每个 DTU 连接创建一个独立的处理协程
3. 数据解析后存入数据库 + MQTT 推送
"""

import asyncio
from datetime import datetime
from typing import Dict, Optional, Callable
from loguru import logger

from config import config
from protocol.modbus_rtu import ModbusRTUParser, DoorSensorData


class DTUConnection:
    """
    单个 DTU 连接的处理类
    
    【实现说明】
    每个 DTU 连接都会创建一个 DTUConnection 实例。
    这样可以为每个连接维护独立的状态。
    """
    
    def __init__(
        self,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
        connection_id: str,
        on_data_received: Optional[Callable] = None
    ):
        self.reader = reader
        self.writer = writer
        self.connection_id = connection_id
        self.on_data_received = on_data_received
        
        # 连接信息
        self.remote_addr = writer.get_extra_info('peername')
        self.connected_at = datetime.now()
        self.last_data_at: Optional[datetime] = None
        self.is_closed = False
        
        # 数据缓冲区（用于处理粘包）
        self.buffer = bytearray()
    
    async def handle(self):
        """处理连接的主循环"""
        logger.info(f"[{self.connection_id}] DTU 连接建立: {self.remote_addr}")
        
        try:
            while not self.is_closed:
                # 读取数据（超时30秒）
                try:
                    data = await asyncio.wait_for(
                        self.reader.read(1024),
                        timeout=30.0
                    )
                except asyncio.TimeoutError:
                    # 超时，发送心跳或检查连接
                    logger.debug(f"[{self.connection_id}] 读取超时，检查连接...")
                    continue
                
                if not data:
                    # 连接关闭
                    logger.info(f"[{self.connection_id}] DTU 断开连接")
                    break
                
                # 更新最后数据时间
                self.last_data_at = datetime.now()
                
                # 处理数据
                await self._process_data(data)
                
        except ConnectionResetError:
            logger.warning(f"[{self.connection_id}] 连接被重置")
        except Exception as e:
            logger.error(f"[{self.connection_id}] 处理异常: {e}")
        finally:
            await self.close()
    
    async def _process_data(self, data: bytes):
        """
        处理接收到的数据
        
        【实现说明】
        TCP 是流式协议，可能出现粘包/拆包：
        - 粘包：多个 Modbus 帧粘在一起
        - 拆包：一个帧被分成多次接收
        
        处理方式：使用缓冲区累积数据，然后按帧解析。
        Modbus RTU 没有明确的帧头，我们通过 CRC 校验来验证帧的完整性。
        """
        logger.debug(f"[{self.connection_id}] 收到数据: {data.hex().upper()}")
        
        # 添加到缓冲区
        self.buffer.extend(data)
        
        # 尝试解析完整的帧
        while len(self.buffer) >= 5:  # Modbus 最小帧长度
            # 尝试不同长度的帧
            frame_parsed = False
            
            for frame_len in range(5, min(len(self.buffer) + 1, 256)):
                frame_data = bytes(self.buffer[:frame_len])
                
                # 尝试解析门磁数据
                door_data = ModbusRTUParser.parse_door_sensor_response(frame_data)
                if door_data:
                    logger.info(f"[{self.connection_id}] 解析成功: {door_data}")
                    
                    # 回调处理
                    if self.on_data_received:
                        await self.on_data_received(door_data, self)
                    
                    # 从缓冲区移除已解析的数据
                    del self.buffer[:frame_len]
                    frame_parsed = True
                    break
            
            if not frame_parsed:
                # 无法解析，可能是不完整的帧或无效数据
                # 如果缓冲区太大，清除部分数据防止内存溢出
                if len(self.buffer) > 1024:
                    logger.warning(f"[{self.connection_id}] 缓冲区溢出，清除数据")
                    self.buffer.clear()
                break
    
    async def send(self, data: bytes):
        """发送数据到 DTU"""
        if self.is_closed:
            logger.warning(f"[{self.connection_id}] 连接已关闭，无法发送")
            return
        
        try:
            self.writer.write(data)
            await self.writer.drain()
            logger.debug(f"[{self.connection_id}] 发送数据: {data.hex().upper()}")
        except Exception as e:
            logger.error(f"[{self.connection_id}] 发送失败: {e}")
    
    async def close(self):
        """关闭连接"""
        if self.is_closed:
            return
        
        self.is_closed = True
        try:
            self.writer.close()
            await self.writer.wait_closed()
        except Exception:
            pass
        
        logger.info(f"[{self.connection_id}] 连接已关闭")


class TCPServer:
    """
    TCP 服务器主类
    
    【实现说明】
    使用 asyncio 实现的异步 TCP 服务器。
    可以同时处理多个 DTU 连接。
    """
    
    def __init__(
        self,
        host: str = None,
        port: int = None,
        on_data_received: Optional[Callable] = None
    ):
        self.host = host or config.TCP_HOST
        self.port = port or config.TCP_PORT
        self.on_data_received = on_data_received
        
        # 连接管理
        self.connections: Dict[str, DTUConnection] = {}
        self._connection_counter = 0
        
        # 服务器实例
        self._server: Optional[asyncio.AbstractServer] = None
    
    async def start(self):
        """启动服务器"""
        self._server = await asyncio.start_server(
            self._handle_connection,
            self.host,
            self.port
        )
        
        addr = self._server.sockets[0].getsockname()
        logger.info(f"TCP 服务器启动: {addr[0]}:{addr[1]}")
        
        async with self._server:
            await self._server.serve_forever()
    
    async def _handle_connection(
        self,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter
    ):
        """处理新连接"""
        # 生成连接 ID
        self._connection_counter += 1
        connection_id = f"DTU-{self._connection_counter:04d}"
        
        # 创建连接处理器
        connection = DTUConnection(
            reader=reader,
            writer=writer,
            connection_id=connection_id,
            on_data_received=self.on_data_received
        )
        
        # 保存连接
        self.connections[connection_id] = connection
        
        try:
            await connection.handle()
        finally:
            # 移除连接
            self.connections.pop(connection_id, None)
    
    async def stop(self):
        """停止服务器"""
        if self._server:
            self._server.close()
            await self._server.wait_closed()
            logger.info("TCP 服务器已停止")
    
    def get_connection_count(self) -> int:
        """获取当前连接数"""
        return len(self.connections)


# ==================== 测试代码 ====================
async def _test_data_handler(data: DoorSensorData, connection: DTUConnection):
    """测试用数据处理回调"""
    logger.info(f"收到门磁数据: {data}")
    logger.info(f"  - 设备地址: 0x{data.device_address:02X}")
    logger.info(f"  - 设备编号: {data.device_index}")
    logger.info(f"  - 门状态: {'打开' if data.is_open else '关闭'}")


async def main():
    """测试主函数"""
    from loguru import logger
    import sys
    
    # 配置日志
    logger.remove()
    logger.add(sys.stdout, level="DEBUG", format="{time:HH:mm:ss} | {level} | {message}")
    
    print("=" * 60)
    print("TCP 服务器测试")
    print(f"监听地址: {config.TCP_HOST}:{config.TCP_PORT}")
    print("=" * 60)
    print("\n可以使用以下方式测试：")
    print("1. 使用网络调试助手连接，发送十六进制数据")
    print("2. 测试数据（门关闭）: 41 03 02 00 00 B9 8B")
    print("3. 测试数据（门打开）: 41 03 02 00 01 78 4B")
    print("\nCtrl+C 停止服务器")
    print("=" * 60 + "\n")
    
    server = TCPServer(on_data_received=_test_data_handler)
    
    try:
        await server.start()
    except KeyboardInterrupt:
        await server.stop()


if __name__ == '__main__':
    asyncio.run(main())

