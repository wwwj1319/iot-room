"""
IoT Server 配置文件

【端口说明】
- MQTT: 8899 (传感器数据接收)
- HTTP: 8900 (APP API 服务)
"""

import os
from dotenv import load_dotenv

# 加载 .env 文件（如果存在）
load_dotenv()


class Config:
    """配置类"""
    
    # ==================== MySQL 配置 ====================
    MYSQL_HOST = os.getenv('MYSQL_HOST', 'localhost')
    MYSQL_PORT = int(os.getenv('MYSQL_PORT', 3306))
    MYSQL_USER = os.getenv('MYSQL_USER', 'iot_user')
    MYSQL_PASSWORD = os.getenv('MYSQL_PASSWORD', '')
    MYSQL_DATABASE = os.getenv('MYSQL_DATABASE', 'iot_room')
    
    @property
    def MYSQL_URI(self):
        return f"mysql+pymysql://{self.MYSQL_USER}:{self.MYSQL_PASSWORD}@{self.MYSQL_HOST}:{self.MYSQL_PORT}/{self.MYSQL_DATABASE}?charset=utf8mb4"
    
    # ==================== MQTT 配置 ====================
    MQTT_BROKER = os.getenv('MQTT_BROKER', 'localhost')
    MQTT_PORT = int(os.getenv('MQTT_PORT', 8899))  # MQTT Broker 端口
    MQTT_USERNAME = os.getenv('MQTT_USERNAME', '')
    MQTT_PASSWORD = os.getenv('MQTT_PASSWORD', '')
    
    # MQTT 主题（传感器数据）
    MQTT_TOPIC_DOOR = 'iot/sensor/door/data'       # 门磁传感器
    MQTT_TOPIC_SENSOR_ALL = 'iot/sensor/+/data'    # 订阅所有传感器（通配符）
    
    # ==================== HTTP API 配置 ====================
    HTTP_HOST = os.getenv('HTTP_HOST', '0.0.0.0')
    HTTP_PORT = int(os.getenv('HTTP_PORT', 8900))  # APP API 端口

    # ==================== ZLMediaKit 配置（可选） ====================
    ZLM_HOST = os.getenv('ZLM_HOST', 'localhost')
    ZLM_PORT = int(os.getenv('ZLM_PORT', 80))
    ZLM_RTSP_PORT = int(os.getenv('ZLM_RTSP_PORT', 554))
    ZLM_SECRET = os.getenv('ZLM_SECRET', '')
    SNAPSHOT_DIR = os.getenv('SNAPSHOT_DIR', 'snapshots')

    # ==================== TCP Server 配置（可选） ====================
    # 如果你使用的是 DTU 透传原始 Modbus RTU 帧（非 MQTT），可以启用 TCP Server
    TCP_HOST = os.getenv('TCP_HOST', '0.0.0.0')
    TCP_PORT = int(os.getenv('TCP_PORT', 8899))
    
    # ==================== 日志配置 ====================
    LOG_LEVEL = os.getenv('LOG_LEVEL', 'DEBUG')
    LOG_FILE = os.getenv('LOG_FILE', 'logs/iot_server.log')


# 全局配置实例
config = Config()
