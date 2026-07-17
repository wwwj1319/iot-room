# IoT Server

Python 后端负责 MQTT 数据接收、Modbus RTU 解析、业务处理、数据库持久化和 FastAPI 接口。详细架构、配置与启动方式请查看仓库根目录 [README](../README.md)。

主要目录：

- `protocol/`：CRC16、数据帧解析与控制命令组帧
- `server/`：MQTT 客户端及可选 TCP 传输
- `services/`：门磁、温湿度、断路器、空调业务逻辑
- `api/`：FastAPI 路由
- `database/`：SQLAlchemy 模型和仓储层
- `tests/`：协议层单元测试

