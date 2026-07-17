"""
Modbus RTU 协议解析器

【实现说明】
这个模块负责解析和生成 Modbus RTU 帧。
根据你提供的协议文档，门磁传感器使用的是标准 Modbus RTU 协议。

帧格式：
- 设备地址(1字节) + 功能码(1字节) + 数据(N字节) + CRC16(2字节)

设备地址格式：
- 高4位: 设备类型 (0x4 = 门磁)
- 低4位: 设备地址 (1-15)

功能码：
- 0x03: 读保持寄存器
- 0x04: 读输入寄存器  
- 0x06: 写单个寄存器

CRC16 校验：Modbus 标准 CRC16
"""

from enum import IntEnum
from dataclasses import dataclass
from typing import Optional, Tuple
try:
    from loguru import logger
except ImportError:  # 允许协议层在未安装可选日志依赖时独立测试
    import logging

    logger = logging.getLogger(__name__)


class DeviceType(IntEnum):
    """设备类型枚举"""
    DOOR_SENSOR = 0x4       # 门磁传感器
    TEMP_HUMIDITY = 0x5     # 温湿度传感器
    CIRCUIT_BREAKER = 0x6   # 智能断路器
    AC = 0x7                # 空调控制（预留）


class FunctionCode(IntEnum):
    """Modbus 功能码"""
    READ_HOLDING_REGISTERS = 0x03   # 读保持寄存器
    READ_INPUT_REGISTERS = 0x04     # 读输入寄存器
    WRITE_SINGLE_REGISTER = 0x06    # 写单个寄存器


class DoorSensorRegister(IntEnum):
    """门磁传感器寄存器地址（电力规范）"""
    DOOR_STATUS = 0x0AF1    # 门状态寄存器
    DEVICE_ADDRESS = 0x0AF2 # 设备地址配置


@dataclass
class ModbusFrame:
    """Modbus RTU 帧数据结构"""
    device_address: int     # 设备地址
    function_code: int      # 功能码
    data: bytes             # 数据部分
    crc: int                # CRC16 校验码
    
    @property
    def device_type(self) -> int:
        """获取设备类型（高4位）"""
        return (self.device_address >> 4) & 0x0F
    
    @property
    def device_index(self) -> int:
        """获取设备编号（低4位）"""
        return self.device_address & 0x0F
    
    def is_door_sensor(self) -> bool:
        """是否是门磁传感器"""
        return self.device_type == DeviceType.DOOR_SENSOR


@dataclass
class DoorSensorData:
    """门磁传感器数据"""
    device_address: int     # 设备地址
    device_index: int       # 设备编号 (1-15)
    is_open: bool           # 门是否打开 (True=开, False=关)
    raw_value: int          # 原始值
    function_code: int = 0x04  # 功能码 (03H或04H)
    raw_frame: str = ""     # 原始帧hex字符串（用于调试）
    
    def __str__(self):
        status = "开启" if self.is_open else "关闭"
        return f"门磁传感器[地址:0x{self.device_address:02X}, 编号:{self.device_index}] 状态:{status}"


@dataclass
class TempHumidityData:
    """温湿度传感器数据"""
    device_address: int     # 设备地址（如0x01）
    temperature: float      # 温度（摄氏度）
    humidity: float         # 湿度（%RH）
    raw_temp: int           # 温度原始值
    raw_humidity: int       # 湿度原始值
    function_code: int = 0x03  # 功能码
    raw_frame: str = ""     # 原始帧hex字符串（用于调试）
    
    def __str__(self):
        return f"温湿度传感器[地址:0x{self.device_address:02X}] 温度:{self.temperature}°C, 湿度:{self.humidity}%"


@dataclass
class CircuitBreakerData:
    """
    智能断路器数据
    
    根据协议:
    - 寄存器0x0000: 断路器状态 (0x0000=分闸/关, 0x0001=合闸/开)
    - 功能码0x03: 读状态
    - 功能码0x06: 写控制
    """
    device_address: int     # 设备地址（如0x02）
    is_closed: bool         # 是否合闸 (True=合闸/通电, False=分闸/断电)
    raw_value: int          # 原始值 (0x0000 或 0x0001)
    function_code: int = 0x03  # 功能码
    raw_frame: str = ""     # 原始帧hex字符串（用于调试）
    
    def __str__(self):
        status = "合闸(通电)" if self.is_closed else "分闸(断电)"
        return f"智能断路器[地址:0x{self.device_address:02X}] 状态:{status}"


class ACAction:
    """
    红外空调控制器操作类型
    
    RS-KTC-N01 寄存器定义:
    - 学习寄存器: 0x0007~0x001D (写1触发学习)
    - 发射寄存器: 0x00B9~0x00CF (写1触发发射)
    """
    # 学习寄存器
    LEARN_COOL_ON = 0x0007      # 制冷开机学习
    LEARN_HEAT_ON = 0x0008      # 制热开机学习
    LEARN_OFF = 0x0009          # 关机学习
    LEARN_CUSTOM_BASE = 0x000A  # 自定义学习起始 (0x000A~0x001D = 自定义1~20)
    
    # 发射寄存器
    EMIT_COOL_ON = 0x00B9       # 制冷开机发射
    EMIT_HEAT_ON = 0x00BA       # 制热开机发射
    EMIT_OFF = 0x00BB           # 关机发射
    EMIT_CUSTOM_BASE = 0x00BC   # 自定义发射起始 (0x00BC~0x00CF = 自定义1~20)
    
    # 自定义功能映射（建议）
    EMIT_TEMP_UP = 0x00BC       # 自定义1 = 升温
    EMIT_TEMP_DOWN = 0x00BD     # 自定义2 = 降温


@dataclass
class ACControllerData:
    """
    红外空调控制器数据
    
    RS-KTC-N01 设备自带温湿度传感器
    - 寄存器0x0000: 当前湿度值
    - 寄存器0x0001: 当前温度值
    """
    device_address: int     # 设备地址（如0x03）
    temperature: float      # 环境温度（控制器自带传感器）
    humidity: float         # 环境湿度（控制器自带传感器）
    raw_temp: int           # 温度原始值
    raw_humidity: int       # 湿度原始值
    function_code: int = 0x03
    raw_frame: str = ""
    
    def __str__(self):
        return f"空调控制器[地址:0x{self.device_address:02X}] 环境温度:{self.temperature}°C, 湿度:{self.humidity}%"


class ModbusRTUParser:
    """
    Modbus RTU 协议解析器
    
    【实现说明】
    这个类负责：
    1. 解析 DTU 上报的原始字节数据
    2. 校验 CRC16
    3. 提取传感器数据
    """
    
    @classmethod
    def calculate_crc16(cls, data: bytes) -> int:
        """
        计算 Modbus CRC16 校验码（逐位计算法）
        
        Modbus CRC-16 算法：
        - 多项式: 0xA001 (0x8005 的反转)
        - 初始值: 0xFFFF
        """
        crc = 0xFFFF
        for byte in data:
            crc ^= byte
            for _ in range(8):
                if crc & 0x0001:
                    crc = (crc >> 1) ^ 0xA001
                else:
                    crc >>= 1
        return crc
    
    @classmethod
    def verify_crc(cls, frame: bytes) -> bool:
        """验证帧的 CRC 校验码"""
        if len(frame) < 4:
            return False
        
        # 数据部分（不含CRC）
        data = frame[:-2]
        # 接收到的 CRC（小端序）
        received_crc = frame[-2] | (frame[-1] << 8)
        # 计算的 CRC
        calculated_crc = cls.calculate_crc16(data)
        
        return received_crc == calculated_crc
    
    @classmethod
    def parse_frame(cls, raw_data: bytes) -> Optional[ModbusFrame]:
        """
        解析 Modbus RTU 帧
        
        Args:
            raw_data: 原始字节数据
            
        Returns:
            ModbusFrame 对象，解析失败返回 None
        """
        # 最小帧长度: 地址(1) + 功能码(1) + 数据(至少1) + CRC(2) = 5
        if len(raw_data) < 5:
            logger.warning(f"帧长度不足: {len(raw_data)} bytes")
            return None
        
        # CRC 校验
        if not cls.verify_crc(raw_data):
            logger.warning(f"CRC 校验失败: {raw_data.hex().upper()}")
            return None
        
        # 解析帧
        device_address = raw_data[0]
        function_code = raw_data[1]
        data = raw_data[2:-2]
        crc = raw_data[-2] | (raw_data[-1] << 8)
        
        return ModbusFrame(
            device_address=device_address,
            function_code=function_code,
            data=data,
            crc=crc
        )
    
    @classmethod
    def parse_door_sensor_response(cls, raw_data: bytes) -> Optional[DoorSensorData]:
        """
        解析门磁传感器响应数据
        
        支持两种格式：
        
        1. 03H功能码（电力规范）:
           41 03 02 00 00 B9 8B
           数据字节数=2, 状态在第1个寄存器
        
        2. 04H功能码（用户实际设备）:
           41 04 04 00 00 00 41 7A 70
           │  │  │  └──┬──┘ └──┬──┘
           │  │  │     │      └── CRC
           │  │  │     └── 2个寄存器数据(4字节), 第1个寄存器=状态
           │  │  └── 字节数: 4
           │  └── 功能码: 0x04 (读输入寄存器)
           └── 设备地址: 0x41 (十进制65)
           
           状态: 00 00 = 关门(is_open=False)
                 00 01 = 开门(is_open=True)
        """
        frame = cls.parse_frame(raw_data)
        if frame is None:
            return None
        
        # 检查是否是门磁传感器（地址高4位=0x4）
        if not frame.is_door_sensor():
            logger.debug(f"非门磁传感器数据: 设备类型=0x{frame.device_type:X}")
            return None
        
        # 支持 03H 和 04H 功能码
        if frame.function_code not in (FunctionCode.READ_HOLDING_REGISTERS, 
                                        FunctionCode.READ_INPUT_REGISTERS):
            logger.debug(f"非读取响应: 功能码=0x{frame.function_code:02X}")
            return None
        
        # 解析数据
        # 数据格式: 字节数(1) + 数据(N字节)
        if len(frame.data) < 1:
            logger.warning(f"数据长度不足: {len(frame.data)}")
            return None
        
        byte_count = frame.data[0]
        
        # 检查数据长度
        if len(frame.data) < byte_count + 1:
            logger.warning(f"数据实际长度({len(frame.data)-1})小于声明长度({byte_count})")
            return None
        
        # 读取第一个寄存器的值（状态值）
        # 03H: 通常 byte_count=2, 数据=2字节
        # 04H: 通常 byte_count=4, 数据=4字节（第1个寄存器是状态）
        if byte_count >= 2:
            # 第一个寄存器（大端序）
            status_value = (frame.data[1] << 8) | frame.data[2]
        else:
            logger.warning(f"字节数不足: {byte_count}")
            return None
        
        # 门状态: 0=关闭, 非0=打开
        is_open = status_value != 0
        
        return DoorSensorData(
            device_address=frame.device_address,
            device_index=frame.device_index,
            is_open=is_open,
            raw_value=status_value,
            function_code=frame.function_code,
            raw_frame=raw_data.hex().upper()
        )
    
    @classmethod
    def parse_temp_humidity_response(cls, raw_data: bytes) -> Optional[TempHumidityData]:
        """
        解析温湿度传感器响应数据
        
        帧格式（0x03 功能码）:
        01 03 04 02 92 FF 9B 5A 3D
        │  │  │  └──┬──┘ └──┬──┘ └─CRC
        │  │  │     │       └─ 温度原始值
        │  │  │     └─ 湿度原始值
        │  │  └─ 字节数: 4
        │  └─ 功能码: 0x03
        └─ 设备地址: 0x01
        
        数据计算:
        - 湿度: raw / 10.0 = %RH
        - 温度: raw / 10.0 = °C (负数用补码，如 0xFF9B = -101 → -10.1°C)
        """
        frame = cls.parse_frame(raw_data)
        if frame is None:
            return None
        
        # 检查功能码（只支持 0x03）
        if frame.function_code != FunctionCode.READ_HOLDING_REGISTERS:
            logger.debug(f"非读保持寄存器响应: 功能码=0x{frame.function_code:02X}")
            return None
        
        # 解析数据
        if len(frame.data) < 5:  # 字节数(1) + 湿度(2) + 温度(2)
            logger.warning(f"温湿度数据长度不足: {len(frame.data)}")
            return None
        
        byte_count = frame.data[0]
        if byte_count < 4:
            logger.warning(f"温湿度字节数不足: {byte_count}")
            return None
        
        # 湿度（寄存器0x0000）- 大端序
        raw_humidity = (frame.data[1] << 8) | frame.data[2]
        humidity = raw_humidity / 10.0
        
        # 温度（寄存器0x0001）- 大端序，可能是负数（补码）
        raw_temp = (frame.data[3] << 8) | frame.data[4]
        # 处理负数（16位有符号整数）
        if raw_temp > 0x7FFF:
            raw_temp = raw_temp - 0x10000
        temperature = raw_temp / 10.0
        
        return TempHumidityData(
            device_address=frame.device_address,
            temperature=temperature,
            humidity=humidity,
            raw_temp=raw_temp,
            raw_humidity=raw_humidity,
            function_code=frame.function_code,
            raw_frame=raw_data.hex().upper()
        )
    
    @classmethod
    def is_temp_humidity_sensor(cls, device_address: int) -> bool:
        """
        判断是否是温湿度传感器
        
        温湿度传感器地址: 1 (0x01)
        """
        return device_address == 1
    
    @classmethod
    def is_circuit_breaker(cls, device_address: int) -> bool:
        """
        判断是否是智能断路器
        
        断路器地址: 2 (0x02)
        """
        return device_address == 2
    
    @classmethod
    def is_ac_controller(cls, device_address: int) -> bool:
        """
        判断是否是红外空调控制器
        
        空调控制器地址: 3 (0x03)
        """
        return device_address == 3
    
    @classmethod
    def is_door_sensor(cls, device_address: int) -> bool:
        """
        判断是否是门磁传感器
        
        门磁传感器地址: 高4位=4 (0x41-0x4F)
        例如: 65 (0x41) = 门磁传感器 #1
        """
        return (device_address >> 4) == 0x4
    
    @classmethod
    def build_door_query_command(cls, device_address: int = 0x41) -> bytes:
        """
        构建门磁查询命令
        
        命令格式（电力规范）:
        41 03 0A F1 00 01 D8 E1
        """
        cmd = bytes([
            device_address,                     # 设备地址
            FunctionCode.READ_HOLDING_REGISTERS,# 功能码 0x03
            0x0A, 0xF1,                         # 寄存器地址 0x0AF1
            0x00, 0x01                          # 读取1个寄存器
        ])
        
        # 计算并附加 CRC
        crc = cls.calculate_crc16(cmd)
        cmd += bytes([crc & 0xFF, (crc >> 8) & 0xFF])
        
        return cmd
    
    @classmethod
    def build_temp_humidity_query_command(cls, device_address: int = 0x01) -> bytes:
        """
        构建温湿度查询命令
        
        命令格式:
        01 03 00 00 00 02 C4 0B
        │  │  └──┬──┘ └──┬──┘ └─CRC
        │  │     │       └─ 读取2个寄存器
        │  │     └─ 起始地址 0x0000
        │  └─ 功能码 0x03
        └─ 设备地址 0x01 (1)
        """
        cmd = bytes([
            device_address,                     # 设备地址
            FunctionCode.READ_HOLDING_REGISTERS,# 功能码 0x03
            0x00, 0x00,                         # 寄存器起始地址 0x0000
            0x00, 0x02                          # 读取2个寄存器
        ])
        
        # 计算并附加 CRC
        crc = cls.calculate_crc16(cmd)
        cmd += bytes([crc & 0xFF, (crc >> 8) & 0xFF])
        
        return cmd
    
    # ==================== 智能断路器相关 ====================
    
    @classmethod
    def parse_circuit_breaker_response(cls, raw_data: bytes) -> Optional[CircuitBreakerData]:
        """
        解析智能断路器响应数据
        
        读状态响应帧格式（功能码0x03）:
        02 03 02 00 00 B8 44
        │  │  │  └──┬──┘ └─CRC
        │  │  │     └─ 状态值 (0x0000=分闸, 0x0001=合闸)
        │  │  └─ 字节数: 2
        │  └─ 功能码: 0x03
        └─ 设备地址: 0x02
        
        写控制响应帧格式（功能码0x06，回显请求）:
        02 06 00 00 00 01 48 38
        │  │  └──┬──┘ └──┬──┘ └─CRC
        │  │     │       └─ 写入值 (0x0000=分闸, 0x0001=合闸)
        │  │     └─ 寄存器地址 0x0000
        │  └─ 功能码: 0x06
        └─ 设备地址: 0x02
        """
        frame = cls.parse_frame(raw_data)
        if frame is None:
            return None
        
        # 检查是否是断路器（地址=2）
        if not cls.is_circuit_breaker(frame.device_address):
            logger.debug(f"非断路器数据: 地址=0x{frame.device_address:02X}")
            return None
        
        # 支持 03H (读) 和 06H (写) 功能码
        if frame.function_code == FunctionCode.READ_HOLDING_REGISTERS:
            # 读响应: 字节数(1) + 数据(2)
            if len(frame.data) < 3:
                logger.warning(f"断路器读响应数据长度不足: {len(frame.data)}")
                return None
            
            byte_count = frame.data[0]
            if byte_count < 2:
                logger.warning(f"断路器字节数不足: {byte_count}")
                return None
            
            # 状态值（大端序）
            status_value = (frame.data[1] << 8) | frame.data[2]
            
        elif frame.function_code == FunctionCode.WRITE_SINGLE_REGISTER:
            # 写响应: 寄存器地址(2) + 写入值(2)
            if len(frame.data) < 4:
                logger.warning(f"断路器写响应数据长度不足: {len(frame.data)}")
                return None
            
            # 写入值（大端序）
            status_value = (frame.data[2] << 8) | frame.data[3]
            
        else:
            logger.debug(f"非断路器响应: 功能码=0x{frame.function_code:02X}")
            return None
        
        # 状态: 0x0000=分闸(断电), 0x0001=合闸(通电)
        is_closed = status_value == 0x0001
        
        return CircuitBreakerData(
            device_address=frame.device_address,
            is_closed=is_closed,
            raw_value=status_value,
            function_code=frame.function_code,
            raw_frame=raw_data.hex().upper()
        )
    
    @classmethod
    def build_circuit_breaker_query_command(cls, device_address: int = 0x02) -> bytes:
        """
        构建断路器状态查询命令
        
        命令格式:
        02 03 00 00 00 01 84 39
        │  │  └──┬──┘ └──┬──┘ └─CRC
        │  │     │       └─ 读取1个寄存器
        │  │     └─ 寄存器地址 0x0000
        │  └─ 功能码 0x03 (读保持寄存器)
        └─ 设备地址 0x02
        """
        cmd = bytes([
            device_address,                     # 设备地址
            FunctionCode.READ_HOLDING_REGISTERS,# 功能码 0x03
            0x00, 0x00,                         # 寄存器地址 0x0000
            0x00, 0x01                          # 读取1个寄存器
        ])
        
        # 计算并附加 CRC
        crc = cls.calculate_crc16(cmd)
        cmd += bytes([crc & 0xFF, (crc >> 8) & 0xFF])
        
        return cmd
    
    @classmethod
    def build_circuit_breaker_control_command(
        cls, 
        device_address: int = 0x02, 
        close: bool = True
    ) -> bytes:
        """
        构建断路器控制命令
        
        Args:
            device_address: 设备地址 (默认 0x02)
            close: True=合闸(通电), False=分闸(断电)
        
        合闸命令（开灯）:
        02 06 00 00 00 01 48 38
        │  │  └──┬──┘ └──┬──┘ └─CRC
        │  │     │       └─ 写入值 0x0001 (合闸)
        │  │     └─ 寄存器地址 0x0000
        │  └─ 功能码 0x06 (写单个寄存器)
        └─ 设备地址 0x02
        
        分闸命令（关灯）:
        02 06 00 00 00 00 89 F8
        └─ 写入值 0x0000 (分闸)
        """
        value = 0x0001 if close else 0x0000
        
        cmd = bytes([
            device_address,                     # 设备地址
            FunctionCode.WRITE_SINGLE_REGISTER, # 功能码 0x06
            0x00, 0x00,                         # 寄存器地址 0x0000
            (value >> 8) & 0xFF,                # 值高字节
            value & 0xFF                        # 值低字节
        ])
        
        # 计算并附加 CRC
        crc = cls.calculate_crc16(cmd)
        cmd += bytes([crc & 0xFF, (crc >> 8) & 0xFF])
        
        return cmd
    
    @classmethod
    def build_circuit_breaker_broadcast_control(cls, close: bool = True) -> bytes:
        """
        构建断路器广播控制命令（控制所有断路器）
        
        协议说明：写单个寄存器(功能码=06)支持广播，广播地址 00
        
        Args:
            close: True=合闸(通电), False=分闸(断电)
        """
        return cls.build_circuit_breaker_control_command(
            device_address=0x00,  # 广播地址
            close=close
        )
    
    # ==================== 红外空调控制器相关 ====================
    
    @classmethod
    def build_ac_emit_command(
        cls, 
        device_address: int = 0x03, 
        register: int = ACAction.EMIT_COOL_ON
    ) -> bytes:
        """
        构建空调红外发射命令
        
        Args:
            device_address: 设备地址 (默认 0x03)
            register: 发射寄存器地址
                - 0x00B9: 制冷开机
                - 0x00BA: 制热开机
                - 0x00BB: 关机
                - 0x00BC: 自定义1（升温）
                - 0x00BD: 自定义2（降温）
        
        命令格式:
        03 06 00 B9 00 01 XX XX
        │  │  └──┬──┘ └──┬──┘ └─CRC
        │  │     │       └─ 写入值 0x0001 (触发发射)
        │  │     └─ 寄存器地址
        │  └─ 功能码 0x06 (写单个寄存器)
        └─ 设备地址 0x03
        """
        cmd = bytes([
            device_address,
            FunctionCode.WRITE_SINGLE_REGISTER,
            (register >> 8) & 0xFF,
            register & 0xFF,
            0x00, 0x01  # 写入1触发发射
        ])
        
        crc = cls.calculate_crc16(cmd)
        cmd += bytes([crc & 0xFF, (crc >> 8) & 0xFF])
        
        return cmd
    
    @classmethod
    def build_ac_power_on_cool(cls, device_address: int = 0x03) -> bytes:
        """构建空调制冷开机命令"""
        return cls.build_ac_emit_command(device_address, ACAction.EMIT_COOL_ON)
    
    @classmethod
    def build_ac_power_on_heat(cls, device_address: int = 0x03) -> bytes:
        """构建空调制热开机命令"""
        return cls.build_ac_emit_command(device_address, ACAction.EMIT_HEAT_ON)
    
    @classmethod
    def build_ac_power_off(cls, device_address: int = 0x03) -> bytes:
        """构建空调关机命令"""
        return cls.build_ac_emit_command(device_address, ACAction.EMIT_OFF)
    
    @classmethod
    def build_ac_temp_up(cls, device_address: int = 0x03) -> bytes:
        """构建空调升温命令（自定义1）"""
        return cls.build_ac_emit_command(device_address, ACAction.EMIT_TEMP_UP)
    
    @classmethod
    def build_ac_temp_down(cls, device_address: int = 0x03) -> bytes:
        """构建空调降温命令（自定义2）"""
        return cls.build_ac_emit_command(device_address, ACAction.EMIT_TEMP_DOWN)
    
    @classmethod
    def build_ac_custom_emit(cls, device_address: int = 0x03, custom_index: int = 1) -> bytes:
        """
        构建自定义红外发射命令
        
        Args:
            device_address: 设备地址
            custom_index: 自定义编号 (1-20)
        """
        if not 1 <= custom_index <= 20:
            raise ValueError(f"自定义编号必须在 1-20 之间: {custom_index}")
        
        register = ACAction.EMIT_CUSTOM_BASE + (custom_index - 1)
        return cls.build_ac_emit_command(device_address, register)
    
    @classmethod
    def build_ac_learn_command(
        cls, 
        device_address: int = 0x03, 
        register: int = ACAction.LEARN_COOL_ON
    ) -> bytes:
        """
        构建空调红外学习命令
        
        发送后设备进入学习模式，等待遥控器信号
        
        Args:
            device_address: 设备地址
            register: 学习寄存器地址
                - 0x0007: 制冷开机学习
                - 0x0008: 制热开机学习
                - 0x0009: 关机学习
                - 0x000A~0x001D: 自定义1-20学习
        """
        cmd = bytes([
            device_address,
            FunctionCode.WRITE_SINGLE_REGISTER,
            (register >> 8) & 0xFF,
            register & 0xFF,
            0x00, 0x01  # 写入1触发学习
        ])
        
        crc = cls.calculate_crc16(cmd)
        cmd += bytes([crc & 0xFF, (crc >> 8) & 0xFF])
        
        return cmd
    
    @classmethod
    def build_ac_read_env_command(cls, device_address: int = 0x03) -> bytes:
        """
        构建读取空调控制器环境温湿度命令
        
        读取寄存器 0x0000（湿度）和 0x0001（温度）
        
        命令格式:
        03 03 00 00 00 02 C4 29
        │  │  └──┬──┘ └──┬──┘ └─CRC
        │  │     │       └─ 读取2个寄存器
        │  │     └─ 起始地址 0x0000
        │  └─ 功能码 0x03 (读保持寄存器)
        └─ 设备地址 0x03
        """
        cmd = bytes([
            device_address,
            FunctionCode.READ_HOLDING_REGISTERS,
            0x00, 0x00,  # 起始地址 0x0000
            0x00, 0x02   # 读取2个寄存器
        ])
        
        crc = cls.calculate_crc16(cmd)
        cmd += bytes([crc & 0xFF, (crc >> 8) & 0xFF])
        
        return cmd
    
    @classmethod
    def parse_ac_env_response(cls, raw_data: bytes) -> Optional[ACControllerData]:
        """
        解析空调控制器环境温湿度响应
        
        响应格式:
        03 03 04 XX XX YY YY CRC
        │  │  │  └──┬──┘ └──┬──┘
        │  │  │     │       └─ 温度值
        │  │  │     └─ 湿度值
        │  │  └─ 字节数: 4
        │  └─ 功能码: 0x03
        └─ 设备地址
        """
        frame = cls.parse_frame(raw_data)
        if frame is None:
            return None
        
        # 检查是否是空调控制器
        if not cls.is_ac_controller(frame.device_address):
            return None
        
        # 检查功能码
        if frame.function_code != FunctionCode.READ_HOLDING_REGISTERS:
            return None
        
        # 解析数据
        if len(frame.data) < 5:
            logger.warning(f"空调控制器数据长度不足: {len(frame.data)}")
            return None
        
        byte_count = frame.data[0]
        if byte_count < 4:
            return None
        
        # 湿度（寄存器0x0000）
        raw_humidity = (frame.data[1] << 8) | frame.data[2]
        humidity = raw_humidity / 10.0
        
        # 温度（寄存器0x0001）
        raw_temp = (frame.data[3] << 8) | frame.data[4]
        if raw_temp > 0x7FFF:
            raw_temp = raw_temp - 0x10000
        temperature = raw_temp / 10.0
        
        return ACControllerData(
            device_address=frame.device_address,
            temperature=temperature,
            humidity=humidity,
            raw_temp=raw_temp,
            raw_humidity=raw_humidity,
            function_code=frame.function_code,
            raw_frame=raw_data.hex().upper()
        )


# ==================== 测试代码 ====================
if __name__ == '__main__':
    # 配置日志
    from loguru import logger
    import sys
    logger.remove()
    logger.add(sys.stdout, level="DEBUG")
    
    print("=" * 60)
    print("Modbus RTU 协议解析器测试")
    print("=" * 60)
    
    # ========== 门磁传感器测试 ==========
    print("\n>>> 门磁传感器测试 <<<")
    
    # 测试1: 03H功能码（门关闭）
    test_data_03h_closed = bytes.fromhex("41 03 02 00 00 B9 8B".replace(" ", ""))
    print(f"\n[03H] 门关闭: {test_data_03h_closed.hex().upper()}")
    result = ModbusRTUParser.parse_door_sensor_response(test_data_03h_closed)
    if result:
        print(f"  结果: {result}")
        print(f"  is_open={result.is_open}, raw_value={result.raw_value}")
    
    # 测试2: 04H功能码（门关闭 - 用户实际数据）
    test_data_04h_closed = bytes.fromhex("41 04 04 00 00 00 41 7A 70".replace(" ", ""))
    print(f"\n[04H] 门关闭: {test_data_04h_closed.hex().upper()}")
    result = ModbusRTUParser.parse_door_sensor_response(test_data_04h_closed)
    if result:
        print(f"  结果: {result}")
        print(f"  is_open={result.is_open}, function_code=0x{result.function_code:02X}")
    
    # ========== 温湿度传感器测试 ==========
    print("\n" + "=" * 60)
    print(">>> 温湿度传感器测试 <<<")
    
    # 测试: 构造温湿度响应（地址0x01=1，温度25.5°C, 湿度60.0%）
    # 湿度=600(0x0258), 温度=255(0x00FF)
    test_th_data = bytes([0x01, 0x03, 0x04, 0x02, 0x58, 0x00, 0xFF])
    crc = ModbusRTUParser.calculate_crc16(test_th_data)
    test_th_data += bytes([crc & 0xFF, (crc >> 8) & 0xFF])
    print(f"\n温湿度响应(地址0x01): {test_th_data.hex().upper()}")
    th_result = ModbusRTUParser.parse_temp_humidity_response(test_th_data)
    if th_result:
        print(f"  结果: {th_result}")
        print(f"  温度={th_result.temperature}°C, 湿度={th_result.humidity}%")
        print(f"  设备地址: 0x{th_result.device_address:02X} ({th_result.device_address})")
    else:
        print("  解析失败!")
    
    # 测试: 构造负温度数据（-10.1°C, 65.8%）
    # 湿度=658(0x0292), 温度=-101(0xFF9B)
    test_th_negative = bytes([0x01, 0x03, 0x04, 0x02, 0x92, 0xFF, 0x9B])
    crc = ModbusRTUParser.calculate_crc16(test_th_negative)
    test_th_negative += bytes([crc & 0xFF, (crc >> 8) & 0xFF])
    print(f"\n温湿度(负温度): {test_th_negative.hex().upper()}")
    th_result = ModbusRTUParser.parse_temp_humidity_response(test_th_negative)
    if th_result:
        print(f"  结果: {th_result}")
    
    # ========== 查询命令测试 ==========
    print("\n" + "=" * 60)
    print(">>> 查询命令测试 <<<")
    
    door_cmd = ModbusRTUParser.build_door_query_command(0x41)
    print(f"门磁查询命令(地址65): {door_cmd.hex().upper()}")
    
    th_cmd = ModbusRTUParser.build_temp_humidity_query_command(0x01)
    print(f"温湿度查询命令(地址1): {th_cmd.hex().upper()}")
    
    # ========== 智能断路器测试 ==========
    print("\n" + "=" * 60)
    print(">>> 智能断路器测试 <<<")
    
    # 测试: 构造断路器读响应（分闸状态）
    test_cb_off = bytes([0x02, 0x03, 0x02, 0x00, 0x00])
    crc = ModbusRTUParser.calculate_crc16(test_cb_off)
    test_cb_off += bytes([crc & 0xFF, (crc >> 8) & 0xFF])
    print(f"\n断路器读响应(分闸): {test_cb_off.hex().upper()}")
    cb_result = ModbusRTUParser.parse_circuit_breaker_response(test_cb_off)
    if cb_result:
        print(f"  结果: {cb_result}")
        print(f"  is_closed={cb_result.is_closed}, raw_value=0x{cb_result.raw_value:04X}")
    
    # 测试: 构造断路器读响应（合闸状态）
    test_cb_on = bytes([0x02, 0x03, 0x02, 0x00, 0x01])
    crc = ModbusRTUParser.calculate_crc16(test_cb_on)
    test_cb_on += bytes([crc & 0xFF, (crc >> 8) & 0xFF])
    print(f"\n断路器读响应(合闸): {test_cb_on.hex().upper()}")
    cb_result = ModbusRTUParser.parse_circuit_breaker_response(test_cb_on)
    if cb_result:
        print(f"  结果: {cb_result}")
        print(f"  is_closed={cb_result.is_closed}")
    
    # 测试: 断路器查询命令
    cb_query = ModbusRTUParser.build_circuit_breaker_query_command(0x02)
    print(f"\n断路器查询命令(地址2): {cb_query.hex().upper()}")
    
    # 测试: 断路器控制命令
    cb_on_cmd = ModbusRTUParser.build_circuit_breaker_control_command(0x02, close=True)
    print(f"断路器合闸命令(地址2): {cb_on_cmd.hex().upper()}")
    
    cb_off_cmd = ModbusRTUParser.build_circuit_breaker_control_command(0x02, close=False)
    print(f"断路器分闸命令(地址2): {cb_off_cmd.hex().upper()}")
    
    # 测试: 广播控制命令
    cb_broadcast = ModbusRTUParser.build_circuit_breaker_broadcast_control(close=True)
    print(f"断路器广播合闸命令: {cb_broadcast.hex().upper()}")
    
    # ========== 设备类型判断测试 ==========
    print("\n" + "=" * 60)
    print(">>> 设备类型判断测试 <<<")
    
    test_addresses = [0x01, 0x02, 0x03, 0x41, 0x42]
    for addr in test_addresses:
        is_door = ModbusRTUParser.is_door_sensor(addr)
        is_th = ModbusRTUParser.is_temp_humidity_sensor(addr)
        is_cb = ModbusRTUParser.is_circuit_breaker(addr)
        is_ac = ModbusRTUParser.is_ac_controller(addr)
        if is_door:
            type_str = "门磁传感器"
        elif is_th:
            type_str = "温湿度传感器"
        elif is_cb:
            type_str = "智能断路器"
        elif is_ac:
            type_str = "空调控制器"
        else:
            type_str = "未知设备"
        print(f"  地址 0x{addr:02X} ({addr}): {type_str}")
    
    # ========== 空调控制器测试 ==========
    print("\n" + "=" * 60)
    print(">>> 空调控制器测试 <<<")
    
    # 发射命令测试
    ac_cool = ModbusRTUParser.build_ac_power_on_cool(0x03)
    print(f"\n空调制冷开机命令(地址3): {ac_cool.hex().upper()}")
    
    ac_heat = ModbusRTUParser.build_ac_power_on_heat(0x03)
    print(f"空调制热开机命令(地址3): {ac_heat.hex().upper()}")
    
    ac_off = ModbusRTUParser.build_ac_power_off(0x03)
    print(f"空调关机命令(地址3): {ac_off.hex().upper()}")
    
    ac_up = ModbusRTUParser.build_ac_temp_up(0x03)
    print(f"空调升温命令(地址3): {ac_up.hex().upper()}")
    
    ac_down = ModbusRTUParser.build_ac_temp_down(0x03)
    print(f"空调降温命令(地址3): {ac_down.hex().upper()}")
    
    ac_read = ModbusRTUParser.build_ac_read_env_command(0x03)
    print(f"读取环境温湿度命令(地址3): {ac_read.hex().upper()}")
