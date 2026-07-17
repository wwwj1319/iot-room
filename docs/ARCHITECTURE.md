# 系统架构与数据流

## 模块划分

| 模块 | 目录 | 主要职责 |
|---|---|---|
| Flutter 客户端 | `iotroom/` | 状态展示、历史曲线、远程控制、视频与告警交互 |
| IoT 主服务 | `iot-server/main.py` | 编排 MQTT、业务服务、数据库和 HTTP API |
| 协议层 | `iot-server/protocol/` | Modbus RTU CRC16、帧解析和命令组帧 |
| 业务层 | `iot-server/services/` | 门磁、温湿度、断路器、空调业务规则 |
| 数据层 | `iot-server/database/` | SQLAlchemy 模型和数据访问 |
| 告警服务 | `iot-server/alarm_receiver.py` | 接收 HTTP 告警、保存抓拍、事件配对和查询 |

## 数据链路

### 传感器上报

1. 传感器通过 RS485 输出 Modbus RTU 数据。
2. DTU 将数据封装后发布到 MQTT Broker。
3. IoT Server 订阅主题、校验 CRC 并按设备类型解析。
4. 业务服务执行防抖、边沿检测或采样策略。
5. 数据写入 MySQL/SQLite，并通过 FastAPI 提供查询接口。

### 设备控制

1. Flutter 调用断路器或空调控制 API。
2. 服务端校验参数并生成 Modbus RTU 控制帧。
3. 控制帧经 MQTT 下发到 DTU，再通过 RS485 发送给设备。
4. 服务端记录操作结果，并等待设备后续状态上报。

### 视频与告警

1. 摄像头通过 GB28181 接入 WVP-PRO/ZLMediaKit。
2. Flutter 根据平台接口获取 FMP4、FLV 或 HLS 播放地址。
3. 摄像头侧算法通过 HTTP 推送火灾开始/恢复事件和抓拍图片。
4. Alarm Receiver 保存事件并按设备与时间配对，Flutter 轮询展示新告警。

## 实现边界

- MQTT Broker、WVP-PRO、ZLMediaKit 和 MySQL 是外部依赖，不包含在本仓库中。
- 空调红外控制属于单向控制，服务端维护的是期望状态，不能替代设备真实回读。
- 巡检模块和部分首页快捷入口属于 UI 演示或后续扩展范围。

