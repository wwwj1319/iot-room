"""
摄像头抓拍服务

【功能说明】
调用 ZLMediaKit 的 getSnap API 对视频流进行抓拍
抓拍的图片保存到本地文件系统
"""

import os
import asyncio
import aiohttp
from datetime import datetime
from typing import Optional, Tuple
from loguru import logger

from config import config


class SnapshotService:
    """
    摄像头抓拍服务
    
    使用 ZLMediaKit 的 getSnap API:
    http://{ZLM_HOST}:{ZLM_PORT}/index/api/getSnap?secret={SECRET}&url={RTSP_URL}&timeout_sec=10&expire_sec=5
    """
    
    def __init__(self):
        self.zlm_host = config.ZLM_HOST
        self.zlm_port = config.ZLM_PORT
        self.zlm_secret = config.ZLM_SECRET
        self.zlm_rtsp_port = config.ZLM_RTSP_PORT
        self.snapshot_dir = config.SNAPSHOT_DIR
        
        # 确保目录存在
        os.makedirs(self.snapshot_dir, exist_ok=True)
        logger.info(f"抓拍服务初始化: ZLM={self.zlm_host}:{self.zlm_port}, 存储目录={self.snapshot_dir}")
    
    def _get_rtsp_url(self, device_id: str, channel_id: str) -> str:
        """
        构建 RTSP 流地址
        
        格式: rtsp://{host}:{port}/rtp/{stream_id}
        stream_id 通常是 {device_id}_{channel_id}
        """
        stream_id = f"{device_id}_{channel_id}"
        return f"rtsp://{self.zlm_host}:{self.zlm_rtsp_port}/rtp/{stream_id}"
    
    def _get_snap_api_url(self, rtsp_url: str) -> str:
        """构建 getSnap API URL"""
        import urllib.parse
        encoded_url = urllib.parse.quote(rtsp_url, safe='')
        return (
            f"http://{self.zlm_host}:{self.zlm_port}/index/api/getSnap"
            f"?secret={self.zlm_secret}"
            f"&url={encoded_url}"
            f"&timeout_sec=10"
            f"&expire_sec=5"
        )
    
    def _generate_filename(self, sensor_id: int, event_type: str, index: int) -> str:
        """
        生成抓拍文件名
        
        格式: {sensor_id}_{event_type}_{timestamp}_{index}.jpg
        例如: 1_open_20251226_143052_001.jpg
        """
        now = datetime.now()
        timestamp = now.strftime("%Y%m%d_%H%M%S")
        return f"{sensor_id}_{event_type}_{timestamp}_{index:03d}.jpg"
    
    def _get_date_subdir(self) -> str:
        """获取按日期分目录的路径"""
        today = datetime.now().strftime("%Y-%m-%d")
        subdir = os.path.join(self.snapshot_dir, today)
        os.makedirs(subdir, exist_ok=True)
        return subdir
    
    async def take_snapshot(
        self,
        device_id: str,
        channel_id: str,
        sensor_id: int,
        event_type: str,
        index: int = 1
    ) -> Tuple[bool, Optional[str], Optional[str]]:
        """
        执行单次抓拍
        
        Args:
            device_id: 摄像头设备ID（国标编号）
            channel_id: 摄像头通道ID
            sensor_id: 门磁传感器ID（用于文件命名）
            event_type: 事件类型 'open'/'close'
            index: 抓拍序号
            
        Returns:
            (成功标志, 文件相对路径, 错误信息)
        """
        try:
            # 构建RTSP URL
            rtsp_url = self._get_rtsp_url(device_id, channel_id)
            api_url = self._get_snap_api_url(rtsp_url)
            
            logger.debug(f"抓拍请求: {api_url[:100]}...")
            
            # 调用API
            async with aiohttp.ClientSession() as session:
                async with session.get(api_url, timeout=aiohttp.ClientTimeout(total=15)) as response:
                    
                    # 检查Content-Type
                    content_type = response.headers.get('Content-Type', '')
                    
                    if 'image' in content_type:
                        # 成功返回图片
                        image_data = await response.read()
                        
                        # 生成文件名和路径
                        filename = self._generate_filename(sensor_id, event_type, index)
                        subdir = self._get_date_subdir()
                        filepath = os.path.join(subdir, filename)
                        
                        # 保存文件
                        with open(filepath, 'wb') as f:
                            f.write(image_data)
                        
                        # 计算相对路径（用于存储到数据库）
                        relative_path = os.path.relpath(filepath, self.snapshot_dir)
                        
                        logger.info(f"抓拍成功: {relative_path} ({len(image_data)} bytes)")
                        return (True, relative_path, None)
                    
                    else:
                        # API返回JSON错误
                        try:
                            result = await response.json()
                            error_msg = result.get('msg', 'Unknown error')
                            code = result.get('code', -1)
                            logger.warning(f"抓拍API返回错误: code={code}, msg={error_msg}")
                            return (False, None, f"API错误: {error_msg}")
                        except:
                            text = await response.text()
                            logger.warning(f"抓拍API返回非预期内容: {text[:200]}")
                            return (False, None, f"非预期响应: {text[:100]}")
        
        except asyncio.TimeoutError:
            logger.warning(f"抓拍超时: device={device_id}, channel={channel_id}")
            return (False, None, "请求超时")
        
        except aiohttp.ClientError as e:
            logger.warning(f"抓拍网络错误: {e}")
            return (False, None, f"网络错误: {str(e)}")
        
        except Exception as e:
            logger.error(f"抓拍异常: {e}", exc_info=True)
            return (False, None, f"异常: {str(e)}")
    
    async def take_multiple_snapshots(
        self,
        device_id: str,
        channel_id: str,
        sensor_id: int,
        event_type: str,
        count: int = 3,
        interval_ms: int = 1000,
        delay_ms: int = 0
    ) -> Tuple[int, list, list]:
        """
        执行多次抓拍（连拍）
        
        Args:
            device_id: 摄像头设备ID
            channel_id: 摄像头通道ID
            sensor_id: 门磁传感器ID
            event_type: 事件类型
            count: 抓拍张数
            interval_ms: 连拍间隔(毫秒)
            delay_ms: 首次抓拍延迟(毫秒)
            
        Returns:
            (成功数量, 成功的路径列表, 错误信息列表)
        """
        success_paths = []
        errors = []
        
        # 首次延迟
        if delay_ms > 0:
            await asyncio.sleep(delay_ms / 1000)
        
        for i in range(count):
            logger.info(f"开始第 {i+1}/{count} 张抓拍...")
            
            success, path, error = await self.take_snapshot(
                device_id=device_id,
                channel_id=channel_id,
                sensor_id=sensor_id,
                event_type=event_type,
                index=i + 1
            )
            
            if success:
                success_paths.append(path)
                logger.info(f"第 {i+1} 张抓拍成功: {path}")
            else:
                errors.append(error or "未知错误")
                logger.warning(f"第 {i+1} 张抓拍失败: {error}")
            
            # 非最后一次，等待间隔
            if i < count - 1 and interval_ms > 0:
                logger.debug(f"等待 {interval_ms}ms 后拍下一张...")
                await asyncio.sleep(interval_ms / 1000.0)
        
        success_count = len(success_paths)
        logger.info(f"连拍完成: {success_count}/{count} 成功")
        
        return (success_count, success_paths, errors)


# ==================== 测试代码 ====================
if __name__ == '__main__':
    import sys
    logger.remove()
    logger.add(sys.stdout, level="DEBUG")
    
    async def test():
        service = SnapshotService()
        
        # 测试单次抓拍（需要实际的摄像头）
        # success, path, error = await service.take_snapshot(
        #     device_id="demo-device",
        #     channel_id="demo-channel",
        #     sensor_id=1,
        #     event_type="open",
        #     index=1
        # )
        # print(f"结果: success={success}, path={path}, error={error}")
        
        print("抓拍服务测试（需配置真实摄像头）")
        print(f"ZLM地址: {service.zlm_host}:{service.zlm_port}")
        print(f"存储目录: {service.snapshot_dir}")
    
    asyncio.run(test())

