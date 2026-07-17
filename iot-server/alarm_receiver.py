"""
摄像头 HTTP 告警接收服务

【使用方法】
1. 在服务器上运行此脚本：python alarm_receiver.py
2. 在支持 HTTP 告警推送的摄像头中配置地址：http://你的服务器IP:9090/alarm
3. 触发摄像头报警，查看打印的数据格式
4.后台运行nohup python alarm_receiver.py &
5.查找进程ps aux | grep alarm_receiver

【端口】
默认监听 9090 端口，可以修改下面的 PORT 变量
"""

from http.server import HTTPServer, BaseHTTPRequestHandler
from socketserver import ThreadingMixIn
from datetime import datetime
import json
import os
import re
import sys
import signal
import traceback
from loguru import logger

# ============ 配置 ============
HOST = os.getenv("ALARM_HOST", "0.0.0.0")
PORT = int(os.getenv("ALARM_PORT", "9090"))

# 文件保存目录
DATA_DIR = "alarm_data"   # JSON 报警信息目录
IMAGE_DIR = "alarm_part"  # 图片目录
LOG_DIR = "alarm_log"     # 日志目录

# 确保目录存在
os.makedirs(DATA_DIR, exist_ok=True)
os.makedirs(IMAGE_DIR, exist_ok=True)
os.makedirs(LOG_DIR, exist_ok=True)

# 保存收到的数据
received_data = []
data_count = 0

# 最新报警（用于轮询检测新报警）
latest_alarm_id = None
latest_alarm_time = None

# 服务器启动时间（用于统计）
server_start_time = None


def setup_logging():
    """配置日志系统"""
    # 移除默认的日志处理器
    logger.remove()
    
    # 控制台输出（彩色）
    logger.add(
        sys.stdout,
        level="INFO",
        format="<green>{time:YYYY-MM-DD HH:mm:ss}</green> | "
               "<level>{level: <8}</level> | "
               "<level>{message}</level>",
        colorize=True
    )
    
    # 文件输出（保存到 alarm_log 目录）
    logger.add(
        os.path.join(LOG_DIR, "alarm_server_{time:YYYY-MM-DD}.log"),
        level="DEBUG",
        format="{time:YYYY-MM-DD HH:mm:ss} | {level: <8} | {message}",
        rotation="00:00",      # 每天午夜轮转
        retention="90 days",   # 保留90天
        encoding="utf-8",
        enqueue=True           # 线程安全
    )
    
    logger.info("日志系统初始化完成，日志保存到: {}", LOG_DIR)


class AlarmHandler(BaseHTTPRequestHandler):
    """处理报警请求"""
    
    def _analyze_data(self, body: bytes, content_type: str):
        """分析数据类型"""
        logger.debug("-" * 70)
        logger.debug("🔍 数据分析:")
        
        # 1. 检查是否是 multipart（包含图片的报警）
        if 'multipart' in content_type.lower():
            logger.debug("   类型: multipart（包含图片或附件）")
            self._parse_multipart(body, content_type)
            return
        
        # 2. 检查前几个字节判断类型
        if len(body) > 0:
            # JPEG 图片
            if body[:2] == b'\xff\xd8':
                logger.debug("   类型: JPEG 图片")
                img_file = f"alarm_image_{data_count}.jpg"
                with open(img_file, 'wb') as f:
                    f.write(body)
                logger.info("📷 图片已保存到: {}", img_file)
                return
            
            # PNG 图片
            if body[:4] == b'\x89PNG':
                logger.debug("   类型: PNG 图片")
                img_file = f"alarm_image_{data_count}.png"
                with open(img_file, 'wb') as f:
                    f.write(body)
                logger.info("📷 图片已保存到: {}", img_file)
                return
            
            # XML 数据
            if body[:5] == b'<?xml' or body[:1] == b'<':
                logger.debug("   类型: XML 数据")
                try:
                    xml_str = body.decode('utf-8')
                    logger.debug("   📄 XML 内容:")
                    logger.debug(xml_str[:2000])  # 打印前2000字符
                except:
                    logger.warning("   ⚠️ XML 解码失败")
                return
            
            # JSON 数据
            if body[:1] == b'{' or body[:1] == b'[':
                logger.debug("   类型: JSON 数据")
                try:
                    json_str = body.decode('utf-8')
                    json_data = json.loads(json_str)
                    logger.debug("   📄 JSON 内容:")
                    logger.debug(json.dumps(json_data, indent=2, ensure_ascii=False))
                except:
                    logger.warning("   ⚠️ JSON 解析失败")
                return
        
        # 3. 尝试作为文本解码
        try:
            text = body.decode('utf-8')
            if text.isprintable() or '\n' in text:
                logger.debug("   类型: 文本数据 (UTF-8)")
                logger.debug("   📄 内容:")
                logger.debug(text[:2000])
                return
        except:
            pass
        
        try:
            text = body.decode('gbk')
            if text.isprintable() or '\n' in text:
                logger.debug("   类型: 文本数据 (GBK)")
                logger.debug("   📄 内容:")
                logger.debug(text[:2000])
                return
        except:
            pass
        
        # 4. 二进制数据
        logger.debug("   类型: 二进制数据（可能是加密或未知格式）")
        logger.debug("   前100字节 (hex): {}", body[:100].hex())
        logger.debug("   前100字节 (ascii): {}", body[:100])
    
    def _parse_multipart(self, body: bytes, content_type: str):
        """解析 multipart 数据"""
        # 提取 boundary
        boundary_match = re.search(r'boundary=([^\s;]+)', content_type)
        if not boundary_match:
            logger.warning("   ⚠️ 找不到 boundary")
            return None
        
        boundary = boundary_match.group(1).encode()
        parts = body.split(b'--' + boundary)
        
        logger.debug("   找到 {} 个部分", len(parts) - 2)  # 排除首尾空部分
        
        # 用于生成文件名
        alarm_info = {}
        
        for i, part in enumerate(parts[1:-1], 1):
            logger.debug("\n   📦 Part {}:", i)
            
            # 分离头部和内容
            if b'\r\n\r\n' in part:
                header, content = part.split(b'\r\n\r\n', 1)
                content = content.rstrip(b'\r\n')
                
                try:
                    header_str = header.decode('utf-8')
                    logger.debug("      头部: {}", header_str[:200])
                except:
                    header_str = ""
                
                # 判断内容类型 - JSON 报警信息
                if b'json' in header.lower() or content.strip()[:1] == b'{':
                    try:
                        json_str = content.decode('utf-8')
                        alarm_info = json.loads(json_str)
                        logger.debug("      📄 JSON 内容:")
                        logger.debug(json.dumps(alarm_info, indent=2, ensure_ascii=False)[:800])
                        
                        # 生成规范文件名: 日期_时间_事件类型_设备ID.json
                        filename = self._generate_filename(alarm_info, "json")
                        filepath = os.path.join(DATA_DIR, filename)
                        
                        with open(filepath, 'w', encoding='utf-8') as f:
                            json.dump(alarm_info, f, indent=2, ensure_ascii=False)
                        logger.info("💾 报警信息已保存: {}", filepath)
                        
                        # 更新最新报警ID（用于轮询检测）
                        global latest_alarm_id, latest_alarm_time
                        latest_alarm_id = filename[:-5]  # 去掉 .json
                        latest_alarm_time = datetime.now().isoformat()
                        logger.info("🔔 最新报警ID: {}", latest_alarm_id)
                        
                    except Exception as e:
                        logger.warning("      ⚠️ JSON 解析失败: {}", e)
                
                # 判断内容类型 - 图片
                elif b'image' in header.lower() or content[:2] == b'\xff\xd8':
                    # 生成规范文件名: 日期_时间_事件类型_设备ID.jpg
                    filename = self._generate_filename(alarm_info, "jpg")
                    filepath = os.path.join(IMAGE_DIR, filename)
                    
                    with open(filepath, 'wb') as f:
                        f.write(content)
                    logger.info("📷 图片已保存: {}", filepath)
                
                # XML 数据
                elif b'xml' in header.lower() or content.strip()[:1] == b'<':
                    try:
                        xml_str = content.decode('utf-8')
                        logger.debug("      📄 XML 内容:")
                        logger.debug(xml_str[:1000])
                    except:
                        pass
                else:
                    logger.debug("      大小: {} bytes", len(content))
        
        return alarm_info
    
    def _generate_filename(self, alarm_info: dict, ext: str) -> str:
        """
        生成规范的文件名
        格式: 日期_时间_事件类型_设备ID.扩展名
        例如: 20251223_151428_fireSmartFireDetect_DEMO_CAMERA_001.json
        """
        # 解析报警时间
        date_str = alarm_info.get("dateTime", "")
        if date_str:
            try:
                # 格式: 2025-12-23T15:14:28+08:00
                dt = datetime.fromisoformat(date_str.replace("+08:00", "+0800"))
                time_part = dt.strftime("%Y%m%d_%H%M%S")
            except:
                time_part = datetime.now().strftime("%Y%m%d_%H%M%S")
        else:
            time_part = datetime.now().strftime("%Y%m%d_%H%M%S")
        
        # 事件类型
        event_type = alarm_info.get("eventType", "unknown")
        
        # 设备ID
        device_id = alarm_info.get("deviceID", "unknown")
        
        # 组合文件名
        filename = f"{time_part}_{event_type}_{device_id}.{ext}"
        
        return filename
    
    def do_POST(self):
        """处理 POST 请求"""
        global data_count, received_data
        
        try:
            data_count += 1
            
            # 【修复】正确读取请求头和请求体
            content_length = int(self.headers.get('Content-Length', 0))
            content_type = self.headers.get('Content-Type', '')
            body = self.rfile.read(content_length) if content_length > 0 else b''
            
            # 记录收到的报警
            logger.info("=" * 60)
            logger.info("📥 收到报警请求 #{} | 路径: {} | 大小: {} bytes", 
                       data_count, self.path, content_length)
            logger.debug("📋 Content-Type: {}", content_type)
            logger.debug("-" * 60)
            logger.debug("📄 请求头:")
            for key, value in self.headers.items():
                logger.debug("   {}: {}", key, value)
            logger.debug("-" * 60)
            
            # 分析并保存数据
            alarm_info = None
            if 'multipart' in content_type.lower():
                logger.debug("🔍 数据分析:")
                logger.debug("   类型: multipart（包含图片或附件）")
                alarm_info = self._parse_multipart(body, content_type)
            else:
                self._analyze_data(body, content_type)
            
            # 【修复】限制内存中保存的数据量，防止内存泄漏
            received_data.append({
                "time": datetime.now().isoformat(),
                "path": self.path,
                "content_type": content_type,
                "size": content_length,
                "alarm_info": alarm_info
            })
            # 只保留最近100条记录，防止内存无限增长
            if len(received_data) > 100:
                received_data = received_data[-100:]
            
            logger.info("=" * 60)
            
            # 返回成功响应
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(b'{"code": 0, "message": "OK"}')
            
        except Exception as e:
            logger.error("处理 POST 请求失败: {}", e)
            logger.error(traceback.format_exc())
            try:
                self.send_response(500)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(b'{"code": -1, "message": "Internal Server Error"}')
            except:
                pass
    
    def do_GET(self):
        """处理 GET 请求"""
        try:
            # API: 检查是否有新报警（轮询用）
            if self.path.startswith('/api/alarms/check'):
                self._handle_check_new_alarm()
            
            # API: 获取报警列表（供 APP 调用）
            elif self.path == '/api/alarms' or self.path.startswith('/api/alarms?'):
                self._handle_get_alarms()
            
            # API: 获取图片（静态文件服务）
            elif self.path.startswith('/images/'):
                self._handle_get_image()
            
            # 调试: 查看原始数据
            elif self.path == '/list':
                self._send_json({
                    "count": len(received_data),
                    "data": received_data[-20:]
                })
            
            # 首页
            else:
                self._handle_index()
                
        except Exception as e:
            logger.error("处理 GET 请求失败: {} - {}", self.path, e)
            logger.error(traceback.format_exc())
            try:
                self._send_json({"code": -1, "message": str(e)})
            except:
                pass
    
    def _handle_get_alarms(self):
        """
        获取报警列表 API
        
        GET /api/alarms
        
        返回格式:
        {
            "code": 0,
            "data": [
                {
                    "id": "20251223_151428_fireSmartFireDetect_DEMO_CAMERA_001",
                    "eventType": "fireSmartFireDetect",
                    "eventState": "active",
                    "dateTime": "2025-12-23T15:14:28+08:00",
                    "deviceID": "DEMO_CAMERA_001",
                    "channelName": "Camera 01",
                    "imageUrl": "/images/20251223_151428_fireSmartFireDetect_DEMO_CAMERA_001.jpg"
                },
                ...
            ]
        }
        """
        try:
            alarms = []
            
            # 读取 alarm_data 目录下的所有 JSON 文件
            if os.path.exists(DATA_DIR):
                files = sorted(os.listdir(DATA_DIR), reverse=True)  # 按时间倒序
                
                for filename in files:
                    if filename.endswith('.json'):
                        filepath = os.path.join(DATA_DIR, filename)
                        try:
                            with open(filepath, 'r', encoding='utf-8') as f:
                                alarm_data = json.load(f)
                            
                            # 生成 ID（文件名去掉扩展名）
                            alarm_id = filename[:-5]
                            
                            # 构建图片 URL
                            image_filename = alarm_id + '.jpg'
                            image_path = os.path.join(IMAGE_DIR, image_filename)
                            image_url = f"/images/{image_filename}" if os.path.exists(image_path) else None
                            
                            # 构建报警记录
                            alarm = {
                                "id": alarm_id,
                                "eventType": alarm_data.get("eventType", "unknown"),
                                "eventState": alarm_data.get("eventState", ""),
                                "eventDescription": alarm_data.get("eventDescription", ""),
                                "dateTime": alarm_data.get("dateTime", ""),
                                "deviceID": alarm_data.get("deviceID", ""),
                                "channelID": alarm_data.get("channelID", 1),
                                "channelName": alarm_data.get("channelName", ""),
                                "ipAddress": alarm_data.get("ipAddress", ""),
                                "imageUrl": image_url,
                                # 原始数据（用于详情页）
                                "raw": alarm_data
                            }
                            alarms.append(alarm)
                            
                        except Exception as e:
                            logger.warning("读取 {} 失败: {}", filename, e)
            
            # 将报警按时间分组（相同设备ID、相近时间的报警归为一组）
            grouped_alarms = self._group_alarms(alarms)
            
            self._send_json({
                "code": 0,
                "message": "OK",
                "total": len(grouped_alarms),
                "data": grouped_alarms
            })
            
        except Exception as e:
            logger.error("获取报警列表失败: {}", e)
            self._send_json({"code": -1, "message": str(e)})
    
    def _group_alarms(self, alarms: list) -> list:
        """
        将报警按事件分组
        
        使用队列思想正确配对：
        1. 所有事件按时间正序排列
        2. 遇到报警开始就加入待配对队列
        3. 遇到恢复就和队列中最早的同设备报警配对（FIFO）
        
        这样可以保证：第一次报警和第一次恢复配对，第二次报警和第二次恢复配对
        """
        if not alarms:
            return []
        
        # 解析时间的辅助函数（统一返回不带时区的 datetime）
        def parse_time(alarm):
            try:
                dt_str = alarm.get("dateTime", "")
                if not dt_str:
                    return datetime.now()
                # 处理时区格式：2025-12-23T15:14:28+08:00
                # 先尝试解析，然后移除时区信息
                dt_str = dt_str.replace("+08:00", "+0800").replace("+0800", "")
                # 移除可能残留的 'Z' 或其他时区标记
                dt_str = dt_str.replace("Z", "").replace("z", "")
                # 解析为不带时区的 datetime
                if "T" in dt_str:
                    return datetime.fromisoformat(dt_str)
                else:
                    return datetime.strptime(dt_str, "%Y-%m-%d %H:%M:%S")
            except Exception as e:
                logger.debug("解析时间失败: {} - {}", alarm.get("dateTime", ""), e)
                return datetime.now()
        
        # 将所有事件放在一起，添加类型标记
        all_events = []
        for alarm in alarms:
            event_type = alarm.get("eventType", "")
            all_events.append({
                "alarm": alarm,
                "time": parse_time(alarm),
                "is_start": event_type == "fireSmartFireDetect",
                "is_recovery": event_type == "FirePointAlarmRecovery"
            })
        
        # 按时间正序排列（最早的在前）
        all_events.sort(key=lambda x: x["time"])
        
        grouped = []
        # 待配对的报警开始（按设备ID分组，使用列表实现队列FIFO）
        pending_starts = {}  # device_id -> list of start events
        
        for event in all_events:
            alarm = event["alarm"]
            device_id = alarm.get("deviceID", "")
            
            if event["is_start"]:
                # 报警开始，加入待配对队列
                if device_id not in pending_starts:
                    pending_starts[device_id] = []
                pending_starts[device_id].append(event)
                
            elif event["is_recovery"]:
                # 恢复事件，尝试配对最早的同设备待配对报警（FIFO）
                if device_id in pending_starts and pending_starts[device_id]:
                    # 取出最早的待配对报警
                    start_event = pending_starts[device_id].pop(0)
                    start_alarm = start_event["alarm"]
                    
                    # 创建配对的报警组
                    group = {
                        "id": start_alarm["id"],
                        "eventType": "fire_alarm",
                        "eventName": "🔥 火灾报警",
                        "deviceID": device_id,
                        "channelName": start_alarm.get("channelName", ""),
                        "startTime": start_alarm.get("dateTime", ""),
                        "endTime": alarm.get("dateTime", ""),
                        "startImage": start_alarm.get("imageUrl"),
                        "endImage": alarm.get("imageUrl"),
                        "status": "resolved",
                        "startAlarm": start_alarm,
                        "endAlarm": alarm
                    }
                    grouped.append(group)
                else:
                    # 没有待配对的报警，单独显示恢复事件
                    group = {
                        "id": alarm["id"],
                        "eventType": "fire_recovery",
                        "eventName": "✅ 火灾恢复",
                        "deviceID": device_id,
                        "channelName": alarm.get("channelName", ""),
                        "startTime": alarm.get("dateTime", ""),
                        "endTime": None,
                        "startImage": alarm.get("imageUrl"),
                        "endImage": None,
                        "status": "resolved",
                        "startAlarm": alarm,
                        "endAlarm": None
                    }
                    grouped.append(group)
            
            else:
                # 其他类型报警
                group = {
                    "id": alarm["id"],
                    "eventType": alarm.get("eventType", "unknown"),
                    "eventName": f"⚠️ {alarm.get('eventDescription', '未知报警')}",
                    "deviceID": device_id,
                    "channelName": alarm.get("channelName", ""),
                    "startTime": alarm.get("dateTime", ""),
                    "endTime": None,
                    "startImage": alarm.get("imageUrl"),
                    "endImage": None,
                    "status": "unknown",
                    "startAlarm": alarm,
                    "endAlarm": None
                }
                grouped.append(group)
        
        # 处理剩余未配对的报警开始（仍在进行中的报警）
        for device_id, starts in pending_starts.items():
            for start_event in starts:
                start_alarm = start_event["alarm"]
                group = {
                    "id": start_alarm["id"],
                    "eventType": "fire_alarm",
                    "eventName": "🔥 火灾报警",
                    "deviceID": device_id,
                    "channelName": start_alarm.get("channelName", ""),
                    "startTime": start_alarm.get("dateTime", ""),
                    "endTime": None,
                    "startImage": start_alarm.get("imageUrl"),
                    "endImage": None,
                    "status": "active",
                    "startAlarm": start_alarm,
                    "endAlarm": None
                }
                grouped.append(group)
        
        # 最后按时间倒序排列（最新的在前）
        grouped.sort(key=lambda x: x.get("startTime", ""), reverse=True)
        
        return grouped
    
    def _handle_get_image(self):
        """提供图片静态文件服务"""
        # 获取文件名
        filename = self.path.replace('/images/', '')
        filepath = os.path.join(IMAGE_DIR, filename)
        
        if os.path.exists(filepath):
            self.send_response(200)
            self.send_header('Content-Type', 'image/jpeg')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            
            with open(filepath, 'rb') as f:
                self.wfile.write(f.read())
        else:
            self.send_response(404)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(b'{"code": 404, "message": "Image not found"}')
    
    def _handle_index(self):
        """首页"""
        # 统计报警数量
        alarm_count = 0
        if os.path.exists(DATA_DIR):
            alarm_count = len([f for f in os.listdir(DATA_DIR) if f.endswith('.json')])
        
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.end_headers()
        
        html = f"""
        <!DOCTYPE html>
        <html>
        <head>
            <title>IoT 报警服务器</title>
            <style>
                body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; padding: 40px; background: #0d1117; color: #c9d1d9; }}
                .container {{ max-width: 800px; margin: 0 auto; }}
                h1 {{ color: #58a6ff; }}
                .card {{ background: #161b22; border-radius: 12px; padding: 20px; margin: 20px 0; border: 1px solid #30363d; }}
                .stat {{ font-size: 48px; font-weight: bold; color: #58a6ff; }}
                code {{ background: #21262d; padding: 2px 8px; border-radius: 4px; }}
                a {{ color: #58a6ff; }}
                .api-list {{ list-style: none; padding: 0; }}
                .api-list li {{ padding: 10px 0; border-bottom: 1px solid #30363d; }}
                .method {{ display: inline-block; padding: 2px 8px; border-radius: 4px; font-size: 12px; font-weight: bold; }}
                .get {{ background: #238636; color: white; }}
                .post {{ background: #1f6feb; color: white; }}
            </style>
        </head>
        <body>
            <div class="container">
                <h1>🔥 IoT 报警服务器</h1>
                
                <div class="card">
                    <p>报警记录数量</p>
                    <div class="stat">{alarm_count}</div>
                </div>
                
                <div class="card">
                    <h3>📡 摄像头配置</h3>
                    <p>HTTP 推送地址: <code>http://服务器IP:{PORT}/alarm</code></p>
                </div>
                
                <div class="card">
                    <h3>📱 APP API 接口</h3>
                    <ul class="api-list">
                        <li>
                            <span class="method get">GET</span>
                            <code>/api/alarms</code> - 获取报警列表
                        </li>
                        <li>
                            <span class="method get">GET</span>
                            <code>/images/{{filename}}</code> - 获取报警图片
                        </li>
                        <li>
                            <span class="method post">POST</span>
                            <code>/alarm</code> - 接收摄像头报警
                        </li>
                    </ul>
                </div>
                
                <div class="card">
                    <h3>🔗 快速链接</h3>
                    <p><a href="/api/alarms">查看报警列表 (JSON)</a></p>
                    <p><a href="/list">查看原始数据</a></p>
                </div>
            </div>
        </body>
        </html>
        """
        self.wfile.write(html.encode('utf-8'))
    
    def _handle_check_new_alarm(self):
        """
        检查是否有新报警 API
        
        GET /api/alarms/check?last_id=xxx
        
        用于 APP 轮询检测新报警，如果有新报警则返回报警信息
        """
        global latest_alarm_id, latest_alarm_time
        
        # 解析参数
        from urllib.parse import urlparse, parse_qs
        query = parse_qs(urlparse(self.path).query)
        client_last_id = query.get('last_id', [None])[0]
        
        # 检查是否有新报警
        has_new = False
        new_alarm = None
        
        if latest_alarm_id and latest_alarm_id != client_last_id:
            has_new = True
            # 读取最新报警信息
            if os.path.exists(DATA_DIR):
                files = sorted(os.listdir(DATA_DIR), reverse=True)
                if files:
                    filepath = os.path.join(DATA_DIR, files[0])
                    try:
                        with open(filepath, 'r', encoding='utf-8') as f:
                            new_alarm = json.load(f)
                        new_alarm['id'] = files[0][:-5]  # 去掉 .json
                        # 添加图片URL
                        img_name = files[0][:-5] + '.jpg'
                        img_path = os.path.join(IMAGE_DIR, img_name)
                        if os.path.exists(img_path):
                            new_alarm['imageUrl'] = f'/images/{img_name}'
                    except:
                        pass
        
        self._send_json({
            "code": 0,
            "hasNew": has_new,
            "latestId": latest_alarm_id,
            "alarm": new_alarm
        })
    
    def _send_json(self, data: dict):
        """发送 JSON 响应"""
        self.send_response(200)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Access-Control-Allow-Origin', '*')  # 允许跨域
        self.end_headers()
        response = json.dumps(data, ensure_ascii=False, indent=2)
        self.wfile.write(response.encode('utf-8'))
    
    def log_message(self, format, *args):
        """简化日志输出"""
        pass  # 不打印默认日志


def print_shutdown_stats():
    """打印关闭统计信息"""
    global server_start_time, data_count
    
    # 计算运行时长
    runtime = datetime.now() - server_start_time
    hours, remainder = divmod(runtime.total_seconds(), 3600)
    minutes, seconds = divmod(remainder, 60)
    
    logger.info("")
    logger.info("=" * 60)
    logger.info("🛑 服务器停止")
    logger.info("=" * 60)
    logger.info("📊 运行统计:")
    logger.info("   - 启动时间: {}", server_start_time.strftime('%Y-%m-%d %H:%M:%S'))
    logger.info("   - 停止时间: {}", datetime.now().strftime('%Y-%m-%d %H:%M:%S'))
    logger.info("   - 运行时长: {}小时{}分钟{}秒", int(hours), int(minutes), int(seconds))
    logger.info("   - 收到报警: {} 次", data_count)
    logger.info("=" * 60)


class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
    """多线程 HTTP 服务器，防止单个请求阻塞整个服务"""
    daemon_threads = True  # 守护线程，主线程退出时自动清理


def main():
    """启动服务器"""
    global server_start_time
    
    # 初始化日志系统
    setup_logging()
    
    server_start_time = datetime.now()
    
    logger.info("=" * 60)
    logger.info("🚀 摄像头 HTTP 告警接收服务器启动")
    logger.info("=" * 60)
    logger.info("📡 监听地址: http://0.0.0.0:{}", PORT)
    logger.info("📋 配置摄像头推送地址: http://你的服务器IP:{}/alarm", PORT)
    logger.info("📊 查看报警列表: http://localhost:{}/api/alarms", PORT)
    logger.info("📁 日志保存目录: {}", LOG_DIR)
    logger.info("🔧 服务器类型: 多线程 (ThreadedHTTPServer)")
    logger.info("=" * 60)
    logger.info("等待接收报警数据... (Ctrl+C 停止)")
    
    # 【修复】使用多线程服务器，提高稳定性
    server = ThreadedHTTPServer((HOST, PORT), AlarmHandler)
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    except Exception as e:
        logger.error("服务器异常: {}", e)
        logger.error(traceback.format_exc())
    finally:
        print_shutdown_stats()
        server.server_close()


if __name__ == "__main__":
    main()
