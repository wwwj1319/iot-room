"""
业务服务模块

【服务列表】
- door_linkage_service: 门磁事件服务（边沿检测、事件记录）

【已移除】
- snapshot_service: 摄像头抓拍服务（暂不使用，文件保留备用）
"""

from services.door_linkage_service import DoorLinkageService

__all__ = ['DoorLinkageService']
