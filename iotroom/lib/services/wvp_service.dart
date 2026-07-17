/// WVP 视频平台服务
/// 
/// 【功能说明】
/// 封装与 WVP-PRO 平台的所有 API 交互，包括：
/// - 视频点播（获取实时流地址）
/// - 截图功能
/// - 录像回放
/// - 报警信息获取
/// - 火灾报警监听
/// 
/// 【实现说明】
/// WVP-PRO 是一个开源的 GB28181 视频平台，我们用它来：
/// 1. 接收摄像头的视频流（通过 GB28181 协议）
/// 2. 转码成 FLV/HLS 格式供 APP 播放
/// 3. 管理设备、录像、报警等
/// 4. 接收摄像头的火灾报警信号（GB28181 MESSAGE）
/// 
/// 【支持 GB28181 的 AI 摄像头】
/// 摄像头侧可提供火焰检测能力：
/// - 检测到火焰时，会通过 GB28181 报警通道发送报警
/// - 报警类型码：5 表示火警
/// - 报警信息包含设备ID、通道ID、报警时间等
/// 
/// API 文档参考：https://doc.wvp-pro.cn/

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/config/app_config.dart';

/// ==================== WVP 服务器配置 ====================
/// 不同环境的连接参数在运行时通过 `--dart-define` 注入。
class WvpConfig {
  /// WVP 服务器地址
  static const String serverHost = AppConfig.wvpHost;
  
  /// WVP API 端口（默认 8080）
  static const int apiPort = AppConfig.wvpApiPort;
  
  /// ZLMediaKit 流媒体端口（HTTP/FLV/HLS）
  static const int mediaPort = AppConfig.mediaPort;
  
  /// RTSP 端口
  static const int rtspPort = AppConfig.rtspPort;
  
  /// RTMP 端口
  static const int rtmpPort = AppConfig.rtmpPort;
  
  /// 设备国标编号（从 WVP 后台查看）
  static const String deviceId = AppConfig.wvpDeviceId;
  
  /// 视频通道编号
  static const String channelId = AppConfig.wvpChannelId;
  
  /// 报警通道编号（用于接收火灾报警）
  static const String alarmChannelId = AppConfig.wvpAlarmChannelId;
  
  /// API 基础地址
  static String get apiBaseUrl => 'http://$serverHost:$apiPort';
  
  /// 流媒体基础地址
  static String get mediaBaseUrl => 'http://$serverHost:$mediaPort';
  
  /// ZLMediaKit HTTP API 密钥
  static const String zlmSecret = AppConfig.zlmSecret;
  
  /// 流地址参数（必须添加，包含 secret 鉴权参数）
  static String get streamParams {
    final auth = zlmSecret.isEmpty
        ? ''
        : 'secret=${Uri.encodeQueryComponent(zlmSecret)}&';
    return '${auth}originTypeStr=rtp_push&videoCodec=H264';
  }
  
  /// 直接构建 HLS 流地址
  /// 【实现说明】
  /// HLS 格式，延迟较高（10-30秒），但兼容性好。
  /// 适用于移动端 APP。
  static String getDirectHlsUrl({String? deviceId, String? channelId}) {
    final device = deviceId ?? WvpConfig.deviceId;
    final channel = channelId ?? WvpConfig.channelId;
    final streamId = '${device}_$channel';
    return 'http://$serverHost:$mediaPort/rtp/$streamId/hls.m3u8?$streamParams';
  }
  
  /// 直接构建 FMP4 流地址（推荐 - 浏览器和APP通用）
  /// 【实现说明】
  /// FMP4 格式兼容性最好，浏览器和 APP 都支持。
  /// 延迟中等，稳定性好。
  static String getDirectFmp4Url({String? deviceId, String? channelId}) {
    final device = deviceId ?? WvpConfig.deviceId;
    final channel = channelId ?? WvpConfig.channelId;
    final streamId = '${device}_$channel';
    return 'http://$serverHost:$mediaPort/rtp/$streamId.live.mp4?$streamParams';
  }
  
  /// 直接构建 FLV 流地址（低延迟）
  /// 【实现说明】
  /// FLV 格式延迟低（1-3秒），适合实时监控。
  /// 浏览器需要 flv.js 支持。
  static String getDirectFlvUrl({String? deviceId, String? channelId}) {
    final device = deviceId ?? WvpConfig.deviceId;
    final channel = channelId ?? WvpConfig.channelId;
    final streamId = '${device}_$channel';
    return 'http://$serverHost:$mediaPort/rtp/$streamId.live.flv?$streamParams';
  }
  
  /// 直接构建 WebSocket FLV 流地址（真正的实时流，最低延迟）
  /// 【实现说明】
  /// WebSocket FLV 是真正的实时流协议，延迟最低（1秒内）。
  /// 配合 flv.js 在 WebView 中播放，支持持续直播流。
  /// 与普通 HTTP FLV 不同，WS-FLV 是双向连接，不会断开。
  static String getDirectWsFlvUrl({String? deviceId, String? channelId}) {
    final device = deviceId ?? WvpConfig.deviceId;
    final channel = channelId ?? WvpConfig.channelId;
    final streamId = '${device}_$channel';
    return 'ws://$serverHost:$mediaPort/rtp/$streamId.live.flv?$streamParams';
  }
  
  /// 直接构建 TS 流地址
  /// 【实现说明】
  /// TS 格式稳定，适合移动端。
  static String getDirectTsUrl({String? deviceId, String? channelId}) {
    final device = deviceId ?? WvpConfig.deviceId;
    final channel = channelId ?? WvpConfig.channelId;
    final streamId = '${device}_$channel';
    return 'http://$serverHost:$mediaPort/rtp/$streamId.live.ts?$streamParams';
  }
  
  /// 直接构建 RTSP 流地址
  static String getDirectRtspUrl({String? deviceId, String? channelId}) {
    final device = deviceId ?? WvpConfig.deviceId;
    final channel = channelId ?? WvpConfig.channelId;
    final streamId = '${device}_$channel';
    return 'rtsp://$serverHost:$rtspPort/rtp/$streamId?$streamParams';
  }
  
  /// 构建截图地址
  static String getSnapshotUrl({String? deviceId, String? channelId}) {
    final device = deviceId ?? WvpConfig.deviceId;
    final channel = channelId ?? WvpConfig.channelId;
    final streamId = '${device}_$channel';
    final secret = Uri.encodeQueryComponent(zlmSecret);
    return 'http://$serverHost:$mediaPort/index/api/getSnap?secret=$secret&url=rtsp://127.0.0.1:$rtspPort/rtp/$streamId&timeout_sec=10&expire_sec=1';
  }
}

/// ==================== 数据模型 ====================

/// 点播结果
class PlayResult {
  final bool success;
  final String? flvUrl;      // FLV 流地址（推荐，延迟低）
  final String? hlsUrl;      // HLS 流地址（兼容性好）
  final String? rtspUrl;     // RTSP 流地址
  final String? streamId;    // 流 ID，用于停止点播
  final String? errorMsg;
  
  PlayResult({
    required this.success,
    this.flvUrl,
    this.hlsUrl,
    this.rtspUrl,
    this.streamId,
    this.errorMsg,
  });
  
  factory PlayResult.success({
    required String flvUrl,
    String? hlsUrl,
    String? rtspUrl,
    String? streamId,
  }) {
    return PlayResult(
      success: true,
      flvUrl: flvUrl,
      hlsUrl: hlsUrl,
      rtspUrl: rtspUrl,
      streamId: streamId,
    );
  }
  
  factory PlayResult.error(String message) {
    return PlayResult(success: false, errorMsg: message);
  }
}

/// 设备信息
class DeviceInfo {
  final String deviceId;
  final String name;
  final bool online;
  final String? manufacturer;
  final String? model;
  
  DeviceInfo({
    required this.deviceId,
    required this.name,
    required this.online,
    this.manufacturer,
    this.model,
  });
  
  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      deviceId: json['deviceId'] ?? '',
      name: json['name'] ?? '未命名设备',
      online: json['online'] == true || json['status'] == 'ON',
      manufacturer: json['manufacturer'],
      model: json['model'],
    );
  }
}

/// 报警信息
/// 
/// 【API 文档对照】
/// 对应 /api/alarm/all 接口返回的 DeviceAlarm 结构
class AlarmInfo {
  final String alarmId;           // id - 数据库id
  final String deviceId;          // deviceId - 设备的国标编号
  final String deviceName;        // deviceName - 设备名称
  final String channelId;         // channelId - 通道的国标编号
  final String alarmPriority;     // alarmPriority - 报警级别(1-4级警情)
  final String alarmPriorityDesc; // alarmPriorityDescription - 报警级别描述
  final String alarmMethod;       // alarmMethod - 报警方式(1-7)
  final String alarmMethodDesc;   // alarmMethodDescription - 报警方式描述
  final String alarmType;         // alarmType - 报警类型
  final String alarmTypeDesc;     // alarmTypeDescription - 报警类型描述
  final String alarmDescription;  // alarmDescription - 报警内容描述
  final DateTime alarmTime;       // alarmTime - 报警时间
  final DateTime? createTime;     // createTime - 创建时间
  final double? longitude;        // longitude - 经度
  final double? latitude;         // latitude - 纬度
  final String? snapshotUrl;      // 报警截图（本地添加）
  final String? recordUrl;        // 报警录像（本地添加）
  
  AlarmInfo({
    required this.alarmId,
    required this.deviceId,
    this.deviceName = '',
    required this.channelId,
    this.alarmPriority = '',
    this.alarmPriorityDesc = '',
    this.alarmMethod = '',
    this.alarmMethodDesc = '',
    required this.alarmType,
    this.alarmTypeDesc = '',
    required this.alarmDescription,
    required this.alarmTime,
    this.createTime,
    this.longitude,
    this.latitude,
    this.snapshotUrl,
    this.recordUrl,
  });
  
  factory AlarmInfo.fromJson(Map<String, dynamic> json) {
    return AlarmInfo(
      alarmId: json['id']?.toString() ?? '',
      deviceId: json['deviceId'] ?? '',
      deviceName: json['deviceName'] ?? '',
      channelId: json['channelId'] ?? '',
      alarmPriority: json['alarmPriority']?.toString() ?? '',
      alarmPriorityDesc: json['alarmPriorityDescription'] ?? '',
      alarmMethod: json['alarmMethod']?.toString() ?? '',
      alarmMethodDesc: json['alarmMethodDescription'] ?? '',
      alarmType: json['alarmType']?.toString() ?? 'unknown',
      alarmTypeDesc: json['alarmTypeDescription'] ?? '',
      alarmDescription: json['alarmDescription'] ?? '未知报警',
      alarmTime: _parseDateTime(json['alarmTime']),
      createTime: json['createTime'] != null ? _parseDateTime(json['createTime']) : null,
      longitude: (json['longitude'] as num?)?.toDouble(),
      latitude: (json['latitude'] as num?)?.toDouble(),
      snapshotUrl: json['snapshotUrl'],
      recordUrl: json['recordUrl'],
    );
  }
  
  /// 解析日期时间
  static DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value;
    if (value is String) {
      // 尝试多种日期格式
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    return DateTime.now();
  }
  
  /// 是否是火灾报警
  /// 根据报警类型或描述判断
  bool get isFireAlarm {
    return alarmType.contains('fire') || 
           alarmDescription.contains('火') ||
           alarmTypeDesc.contains('火') ||
           alarmType == '5' ||  // GB28181 火警类型码
           alarmType == '2';    // 可能的火警类型
  }
  
  /// 获取报警级别颜色
  int get alarmLevel {
    switch (alarmPriority) {
      case '1': return 1; // 一级警情 - 紧急
      case '2': return 2; // 二级警情 - 重要
      case '3': return 3; // 三级警情 - 一般
      case '4': return 4; // 四级警情
      default: return 3;
    }
  }
}

/// 录像信息
class RecordInfo {
  final String name;
  final String filePath;
  final DateTime startTime;
  final DateTime endTime;
  final int duration;  // 秒
  final String? playUrl;
  final String? deviceId;
  final String? channelId;
  
  RecordInfo({
    required this.name,
    required this.filePath,
    required this.startTime,
    required this.endTime,
    required this.duration,
    this.playUrl,
    this.deviceId,
    this.channelId,
  });
  
  factory RecordInfo.fromJson(Map<String, dynamic> json) {
    // 处理时间格式（GB28181格式: 2024-12-25T10:00:00）
    DateTime parseTime(String? timeStr) {
      if (timeStr == null) return DateTime.now();
      // 尝试多种格式
      return DateTime.tryParse(timeStr) ?? 
             DateTime.tryParse(timeStr.replaceAll('T', ' ')) ?? 
             DateTime.now();
    }
    
    return RecordInfo(
      name: json['name'] ?? json['fileName'] ?? '',
      filePath: json['filePath'] ?? '',
      startTime: parseTime(json['startTime']),
      endTime: parseTime(json['endTime']),
      duration: json['duration'] ?? json['timeLen'] ?? json['secLength'] ?? 0,
      playUrl: json['playUrl'],
      deviceId: json['deviceId'],
      channelId: json['channelId'],
    );
  }
  
  /// 格式化时长显示
  String get formattedDuration {
    final hours = duration ~/ 3600;
    final minutes = (duration % 3600) ~/ 60;
    final seconds = duration % 60;
    
    if (hours > 0) {
      return '$hours小时${minutes}分${seconds}秒';
    } else if (minutes > 0) {
      return '$minutes分${seconds}秒';
    } else {
      return '$seconds秒';
    }
  }
}

/// 录像回放结果（国标录像/设备端录像）
/// 
/// 包含回放流的多种格式地址，APP可以根据设备兼容性选择合适的格式播放
class PlaybackResult {
  final bool success;
  final String? flvUrl;       // FLV 流地址（低延迟）
  final String? hlsUrl;       // HLS 流地址（兼容性好）
  final String? fmp4Url;      // FMP4 流地址（推荐）
  final String? streamId;     // 流ID，用于控制回放
  final String? app;          // 应用名
  final DateTime? startTime;  // 回放开始时间
  final DateTime? endTime;    // 回放结束时间
  final double? duration;     // 总时长（秒）
  final String? errorMsg;     // 错误信息
  
  PlaybackResult({
    required this.success,
    this.flvUrl,
    this.hlsUrl,
    this.fmp4Url,
    this.streamId,
    this.app,
    this.startTime,
    this.endTime,
    this.duration,
    this.errorMsg,
  });
  
  /// 获取最佳播放地址
  /// 优先级: FMP4 > HLS > FLV
  String? get bestUrl => fmp4Url ?? hlsUrl ?? flvUrl;
  
  /// 是否有可用的播放地址
  bool get hasPlayUrl => flvUrl != null || hlsUrl != null || fmp4Url != null;
}

/// 流媒体信息（loadRecord API 返回的流地址）
/// 
/// 包含多种协议的播放地址，可以像直播流一样播放录像文件
class StreamInfo {
  final String? app;
  final String? stream;
  final String? flvUrl;       // HTTP-FLV
  final String? httpsFlvUrl;  // HTTPS-FLV
  final String? fmp4Url;      // HTTP-FMP4（推荐）
  final String? httpsFmp4Url; // HTTPS-FMP4
  final String? hlsUrl;       // HLS
  final String? httpsHlsUrl;  // HTTPS-HLS
  final String? tsUrl;        // HTTP-TS
  final String? httpsTsUrl;   // HTTPS-TS
  final String? rtmpUrl;      // RTMP
  final String? rtspUrl;      // RTSP
  final double? duration;     // 时长（秒）
  
  StreamInfo({
    this.app,
    this.stream,
    this.flvUrl,
    this.httpsFlvUrl,
    this.fmp4Url,
    this.httpsFmp4Url,
    this.hlsUrl,
    this.httpsHlsUrl,
    this.tsUrl,
    this.httpsTsUrl,
    this.rtmpUrl,
    this.rtspUrl,
    this.duration,
  });
  
  factory StreamInfo.fromJson(Map<String, dynamic> json) {
    // 给所有 URL 添加 secret 参数用于鉴权
    String? addSecret(String? url) {
      if (url == null || url.isEmpty) return url;
      final separator = url.contains('?') ? '&' : '?';
      return '$url${separator}secret=${WvpConfig.zlmSecret}';
    }
    
    return StreamInfo(
      app: json['app'],
      stream: json['stream'],
      flvUrl: addSecret(json['flv']),
      httpsFlvUrl: addSecret(json['https_flv']),
      fmp4Url: addSecret(json['fmp4']),
      httpsFmp4Url: addSecret(json['https_fmp4']),
      hlsUrl: addSecret(json['hls']),
      httpsHlsUrl: addSecret(json['https_hls']),
      tsUrl: addSecret(json['ts']),
      httpsTsUrl: addSecret(json['https_ts']),
      rtmpUrl: addSecret(json['rtmp']),
      rtspUrl: addSecret(json['rtsp']),
      duration: (json['duration'] as num?)?.toDouble(),
    );
  }
  
  /// 获取最佳播放地址（优先 FMP4，兼容性好）
  String? get bestUrl => fmp4Url ?? httpsFmp4Url ?? hlsUrl ?? httpsHlsUrl ?? flvUrl ?? httpsFlvUrl;
  
  /// 是否有可用的播放地址
  bool get hasPlayUrl => flvUrl != null || hlsUrl != null || fmp4Url != null;
}

/// 云端录像项（ZLMediaKit服务器录制的录像）
class CloudRecordItem {
  final int id;                   // 录像ID
  final String app;               // 应用名
  final String stream;            // 流ID
  final String? callId;           // 每次录像的唯一标识
  final int startTime;            // 开始时间（时间戳毫秒）
  final int endTime;              // 结束时间（时间戳毫秒）
  final String? mediaServerId;    // 流媒体ID
  final String? fileName;         // 文件名
  final String? filePath;         // 文件路径
  final String? folder;           // 文件夹
  final bool collect;             // 是否收藏
  final bool reserve;             // 是否保留
  final int fileSize;             // 文件大小（字节）
  final double timeLen;           // 时长（秒）
  final String? serverId;         // 服务ID
  
  CloudRecordItem({
    required this.id,
    required this.app,
    required this.stream,
    this.callId,
    required this.startTime,
    required this.endTime,
    this.mediaServerId,
    this.fileName,
    this.filePath,
    this.folder,
    this.collect = false,
    this.reserve = false,
    this.fileSize = 0,
    this.timeLen = 0,
    this.serverId,
  });
  
  factory CloudRecordItem.fromJson(Map<String, dynamic> json) {
    return CloudRecordItem(
      id: json['id'] ?? 0,
      app: json['app'] ?? '',
      stream: json['stream'] ?? '',
      callId: json['callId'],
      startTime: json['startTime'] ?? 0,
      endTime: json['endTime'] ?? 0,
      mediaServerId: json['mediaServerId'],
      fileName: json['fileName'],
      filePath: json['filePath'],
      folder: json['folder'],
      collect: json['collect'] ?? false,
      reserve: json['reserve'] ?? false,
      fileSize: json['fileSize'] ?? 0,
      timeLen: (json['timeLen'] ?? 0).toDouble(),
      serverId: json['serverId'],
    );
  }
  
  /// 开始时间（DateTime）
  DateTime get startDateTime => DateTime.fromMillisecondsSinceEpoch(startTime);
  
  /// 结束时间（DateTime）
  DateTime get endDateTime => DateTime.fromMillisecondsSinceEpoch(endTime);
  
  /// 格式化时长
  String get formattedDuration {
    final seconds = timeLen.toInt();
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
  
  /// 格式化文件大小
  String get formattedFileSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    if (fileSize < 1024 * 1024 * 1024) return '${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(fileSize / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
  
  /// 获取直接播放地址（带 API 密钥）
  /// 
  /// ZLMediaKit 有 IP 访问限制，需要通过 downloadFile API 并附带密钥访问
  /// 使用 /index/api/downloadFile?file_path=xxx&secret=xxx 格式
  String? get directPlayUrl {
    if (filePath == null || filePath!.isEmpty) return null;
    
    // 使用 downloadFile API 并带上密钥
    final encodedPath = Uri.encodeComponent(filePath!);
    return '${WvpConfig.mediaBaseUrl}/index/api/downloadFile?file_path=$encodedPath&secret=${WvpConfig.zlmSecret}';
  }
  
  /// 获取 HTTPS 直接播放地址（带 API 密钥）
  String? get directPlayUrlHttps {
    if (filePath == null || filePath!.isEmpty) return null;
    
    final encodedPath = Uri.encodeComponent(filePath!);
    return 'https://${WvpConfig.serverHost}:443/index/api/downloadFile?file_path=$encodedPath&secret=${WvpConfig.zlmSecret}';
  }
}

/// 云端录像列表查询结果
class CloudRecordListResult {
  final bool success;
  final int total;
  final List<CloudRecordItem> records;
  final int pageNum;
  final int pages;
  final String? errorMsg;
  
  CloudRecordListResult({
    required this.success,
    this.total = 0,
    this.records = const [],
    this.pageNum = 1,
    this.pages = 1,
    this.errorMsg,
  });
}

/// 云端录像播放地址
class CloudRecordPlayPath {
  final String? httpPath;
  final String? httpsPath;
  final String? httpDomainPath;
  final String? httpsDomainPath;
  
  CloudRecordPlayPath({
    this.httpPath,
    this.httpsPath,
    this.httpDomainPath,
    this.httpsDomainPath,
  });
  
  factory CloudRecordPlayPath.fromJson(Map<String, dynamic> json) {
    return CloudRecordPlayPath(
      httpPath: json['httpPath'],
      httpsPath: json['httpsPath'],
      httpDomainPath: json['httpDomainPath'],
      httpsDomainPath: json['httpsDomainPath'],
    );
  }
  
  /// 获取最佳播放地址（优先HTTPS）
  String? get bestUrl => httpsPath ?? httpsDomainPath ?? httpPath ?? httpDomainPath;
}

/// 云端录像播放结果
class CloudRecordPlayResult {
  final bool success;
  final StreamInfo? streamInfo;            // 流媒体播放信息（通过 loadRecord API 获取）
  final CloudRecordItem? record;           // 当前播放的录像
  final List<CloudRecordItem>? allRecords; // 所有匹配的录像（用于连续播放）
  final String? errorMsg;
  
  CloudRecordPlayResult({
    required this.success,
    this.streamInfo,
    this.record,
    this.allRecords,
    this.errorMsg,
  });
  
  /// 获取最佳播放地址
  /// 优先级：FMP4 > HLS > FLV（兼容性和延迟的平衡）
  String? get bestUrl {
    // 优先使用流媒体地址（通过 loadRecord API 获取）
    if (streamInfo != null) {
      return streamInfo!.fmp4Url ?? streamInfo!.hlsUrl ?? streamInfo!.flvUrl;
    }
    return null;
  }
  
  /// 获取 FMP4 播放地址
  String? get fmp4Url => streamInfo?.fmp4Url;
  
  /// 获取 HLS 播放地址
  String? get hlsUrl => streamInfo?.hlsUrl;
  
  /// 获取 FLV 播放地址
  String? get flvUrl => streamInfo?.flvUrl;
}

/// ==================== WVP 服务类 ====================
class WvpService {
  /// 单例模式
  static final WvpService _instance = WvpService._internal();
  factory WvpService() => _instance;
  WvpService._internal();
  
  /// HTTP 客户端
  final http.Client _client = http.Client();
  
  /// 当前流 ID（用于停止点播）
  String? _currentStreamId;
  
  
  /// 是否正在录像
  bool _isRecording = false;
  
  /// 当前录像任务ID
  String? _currentRecordId;

  
  // ==================== 视频点播 ====================
  
  /// 开始点播（获取实时视频流地址）
  /// 
  /// 【实现说明】
  /// 点播流程：
  /// 1. APP 调用 WVP 的点播 API
  /// 2. WVP 通过 GB28181 SIP 协议向摄像头发送 INVITE 请求
  /// 3. 摄像头开始向 ZLMediaKit 推送 RTP 视频流
  /// 4. ZLMediaKit 转码成 FLV/HLS，返回播放地址给 APP
  /// 
  /// 参数：
  /// - [deviceId] 设备国标编号
  /// - [channelId] 通道编号（一般和设备编号相同）
  Future<PlayResult> startPlay({
    String? deviceId,
    String? channelId,
  }) async {
    final device = deviceId ?? WvpConfig.deviceId;
    final channel = channelId ?? WvpConfig.channelId;
    
    try {
      debugPrint('[WVP] 开始点播: 设备=$device, 通道=$channel');
      
      // 调用 WVP 点播 API
      // 【实现说明】
      // WVP 的点播 API 会返回多种格式的流地址，我们优先使用 FLV
      // 因为 FLV 延迟低（1-3秒），而 HLS 延迟较高（10-30秒）
      final response = await _client.get(
        Uri.parse('${WvpConfig.apiBaseUrl}/api/play/start/$device/$channel'),
      ).timeout(const Duration(seconds: 30));
      
      debugPrint('[WVP] 点播响应: ${response.statusCode}');
      debugPrint('[WVP] 响应内容: ${response.body}');
      
      if (response.statusCode != 200) {
        return PlayResult.error('服务器响应错误: ${response.statusCode}');
      }
      
      final data = jsonDecode(response.body);
      
      // 检查返回码
      if (data['code'] != 0) {
        return PlayResult.error(data['msg'] ?? '点播失败');
      }
      
      // 解析流地址
      final playData = data['data'];
      if (playData == null) {
        return PlayResult.error('未获取到播放地址');
      }
      
      // 保存流 ID，用于后续停止点播
      _currentStreamId = playData['streamId'];
      
      // 构建流地址
      // 【实现说明】
      // WVP 返回的地址可能是相对路径，需要拼接完整 URL
      String? flvUrl = playData['flv'];
      String? hlsUrl = playData['hls'];
      String? rtspUrl = playData['rtsp'];
      
      // 如果返回的是相对路径，拼接完整地址
      if (flvUrl != null && !flvUrl.startsWith('http')) {
        flvUrl = '${WvpConfig.mediaBaseUrl}$flvUrl';
      }
      if (hlsUrl != null && !hlsUrl.startsWith('http')) {
        hlsUrl = '${WvpConfig.mediaBaseUrl}$hlsUrl';
      }
      
      debugPrint('[WVP] FLV地址: $flvUrl');
      debugPrint('[WVP] HLS地址: $hlsUrl');
      
      return PlayResult.success(
        flvUrl: flvUrl ?? _buildDefaultFlvUrl(device, channel),
        hlsUrl: hlsUrl,
        rtspUrl: rtspUrl,
        streamId: _currentStreamId,
      );
      
    } catch (e) {
      debugPrint('[WVP] 点播异常: $e');
      return PlayResult.error('点播失败: $e');
    }
  }
  
  /// 构建默认的 FLV 流地址
  /// 
  /// 【实现说明】
  /// 如果 WVP API 没有返回流地址，我们可以根据规则自己构建
  /// ZLMediaKit 的流地址格式是固定的：
  /// http://{host}:{port}/rtp/{streamId}.live.flv
  String _buildDefaultFlvUrl(String deviceId, String channelId) {
    final streamId = '${deviceId}_$channelId';
    return '${WvpConfig.mediaBaseUrl}/rtp/$streamId.live.flv';
  }
  
  /// 停止点播
  /// 
  /// 【实现说明】
  /// 停止点播很重要！如果不停止：
  /// 1. 摄像头会持续推流，浪费带宽
  /// 2. 服务器资源不会释放
  /// 3. 可能触发"无人观看"自动关闭
  Future<bool> stopPlay({String? deviceId, String? channelId}) async {
    final device = deviceId ?? WvpConfig.deviceId;
    final channel = channelId ?? WvpConfig.channelId;
    
    try {
      debugPrint('[WVP] 停止点播: 设备=$device, 通道=$channel');
      
      final response = await _client.get(
        Uri.parse('${WvpConfig.apiBaseUrl}/api/play/stop/$device/$channel'),
      ).timeout(const Duration(seconds: 10));
      
      _currentStreamId = null;
      return response.statusCode == 200;
      
    } catch (e) {
      debugPrint('[WVP] 停止点播异常: $e');
      return false;
    }
  }
  
  // ==================== 截图功能 ====================
  
  /// 获取实时截图
  /// 
  /// 【实现说明】
  /// 使用 ZLMediaKit 的截图 API 直接从视频流中截取一帧
  /// API: /index/api/getSnap
  Future<String?> getSnapshot({
    String? deviceId,
    String? channelId,
  }) async {
    final device = deviceId ?? WvpConfig.deviceId;
    final channel = channelId ?? WvpConfig.channelId;
    final streamId = '${device}_$channel';
    
    try {
      debugPrint('[WVP] 获取截图: streamId=$streamId');
      
      // 直接返回 ZLMediaKit 的截图 URL
      // 格式: http://{host}/index/api/getSnap?url=rtsp://...&timeout_sec=10&expire_sec=1
      // 或者更简单的格式: http://{host}/rtp/{streamId}/snap.jpg（需要流正在播放）
      
      // 方式一：使用 ZLMediaKit getSnap API（推荐）
      final rtspUrl = 'rtsp://127.0.0.1:${WvpConfig.rtspPort}/rtp/$streamId';
      final snapshotUrl = '${WvpConfig.mediaBaseUrl}/index/api/getSnap'
          '?secret=${WvpConfig.zlmSecret}'
          '&url=${Uri.encodeComponent(rtspUrl)}'
          '&timeout_sec=10'
          '&expire_sec=3600';
      
      debugPrint('[WVP] 截图URL: $snapshotUrl');
      
      // 验证截图 URL 是否可用
      final response = await _client.head(Uri.parse(snapshotUrl)).timeout(
        const Duration(seconds: 5),
      );
      
      if (response.statusCode == 200) {
        return snapshotUrl;
      }
      
      // 方式二：直接使用流截图地址
      final directUrl = '${WvpConfig.mediaBaseUrl}/rtp/$streamId/snap.jpg';
      debugPrint('[WVP] 尝试直接截图URL: $directUrl');
      
      return directUrl;
      
    } catch (e) {
      debugPrint('[WVP] 截图异常: $e');
      // 返回直接的截图地址，让调用方尝试
      final streamId2 = '${device}_$channel';
      return '${WvpConfig.mediaBaseUrl}/rtp/$streamId2/snap.jpg';
    }
  }
  
  /// 获取截图字节数据
  /// 
  /// 【实现说明】
  /// 直接从 ZLMediaKit 获取截图的二进制数据，用于保存到相册。
  /// 使用 /index/api/getSnap API，参数：
  /// 【修复】使用 WVP 代理截图，避免 ZLMediaKit IP 白名单问题
  /// 
  /// WVP 截图接口：/api/device/query/snap/{deviceId}/{channelId}
  /// WVP 服务器在本地访问 ZLMediaKit，不受 IP 限制。
  Future<Uint8List?> getSnapshotBytes({
    String? deviceId,
    String? channelId,
  }) async {
    final device = deviceId ?? WvpConfig.deviceId;
    final channel = channelId ?? WvpConfig.channelId;
    
    try {
      debugPrint('[WVP] 获取截图: deviceId=$device, channelId=$channel');
      
      // 使用 WVP 的截图接口（路径参数格式）
      // 接口：/api/device/query/snap/{deviceId}/{channelId}
      // 添加时间戳参数避免缓存，确保获取最新画面
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final wvpSnapUrl = '${WvpConfig.apiBaseUrl}/api/device/query/snap/$device/$channel?t=$timestamp';
      
      debugPrint('[WVP] WVP截图接口: $wvpSnapUrl');
      
      final wvpResponse = await _client.get(Uri.parse(wvpSnapUrl)).timeout(
        const Duration(seconds: 20),
      );
      
      debugPrint('[WVP] WVP响应状态: ${wvpResponse.statusCode}');
      
      if (wvpResponse.statusCode == 200) {
        final contentType = wvpResponse.headers['content-type'] ?? '';
        debugPrint('[WVP] 响应类型: $contentType');
        
        // 如果直接返回图片
        if (contentType.contains('image')) {
          debugPrint('[WVP] WVP截图成功（直接返回图片），大小: ${wvpResponse.bodyBytes.length} bytes');
          return wvpResponse.bodyBytes;
        }
        
        // WVP 返回 JSON，包含截图 URL
        try {
          final json = jsonDecode(wvpResponse.body);
          debugPrint('[WVP] WVP返回JSON: $json');
          
          // WVP 返回格式: {"code":0, "data":"http://xxx/snap.jpg"}
          if (json['code'] == 0 && json['data'] != null) {
            final snapUrl = json['data'].toString();
            if (snapUrl.isNotEmpty) {
              debugPrint('[WVP] 获取到截图URL: $snapUrl');
              
              // 下载截图
              final imgResponse = await _client.get(Uri.parse(snapUrl)).timeout(
                const Duration(seconds: 15),
              );
              
              if (imgResponse.statusCode == 200) {
                final imgContentType = imgResponse.headers['content-type'] ?? '';
                if (imgContentType.contains('image')) {
                  debugPrint('[WVP] 截图下载成功，大小: ${imgResponse.bodyBytes.length} bytes');
                  return imgResponse.bodyBytes;
                }
                debugPrint('[WVP] 下载的不是图片: $imgContentType');
              } else {
                debugPrint('[WVP] 下载截图失败: ${imgResponse.statusCode}');
              }
            }
          } else {
            debugPrint('[WVP] WVP返回错误: code=${json['code']}, msg=${json['msg']}');
          }
        } catch (e) {
          debugPrint('[WVP] 解析WVP响应失败: $e, body: ${wvpResponse.body}');
        }
      } else {
        debugPrint('[WVP] WVP截图接口失败: ${wvpResponse.statusCode}, body: ${wvpResponse.body}');
      }
      
      debugPrint('[WVP] 截图失败');
      return null;
      
    } catch (e) {
      debugPrint('[WVP] 获取截图异常: $e');
      return null;
    }
  }
  
  // ==================== 报警功能 ====================
  
  // ==================== WVP 登录认证 ====================
  
  /// WVP 登录凭证。真实值通过 `--dart-define` 注入。
  static const String _wvpUsername = AppConfig.wvpUsername;
  static const String _wvpPasswordMd5 = AppConfig.wvpPasswordMd5;
  
  /// 登录Token
  String? _accessToken;
  
  /// 登录WVP获取Token
  /// 
  /// WVP API 要求密码必须经过 MD5 加密
  Future<bool> login() async {
    if (_wvpUsername.isEmpty || _wvpPasswordMd5.isEmpty) {
      debugPrint('[WVP] 未配置登录凭证，跳过登录');
      return false;
    }

    try {
      debugPrint('[WVP] 正在登录...');
      
      // WVP 登录接口使用 GET 请求，密码需要 MD5 加密
      final uri = Uri.parse('${WvpConfig.apiBaseUrl}/api/user/login')
          .replace(queryParameters: {
            'username': _wvpUsername,
            'password': _wvpPasswordMd5,
          });
      
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      
      debugPrint('[WVP] 登录响应: ${response.statusCode} - ${response.body}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] == 0 && data['data'] != null) {
          _accessToken = data['data']['accessToken'];
          debugPrint('[WVP] 登录成功，Token: ${_accessToken?.substring(0, 20)}...');
          return true;
        }
      }
      
      debugPrint('[WVP] 登录失败');
      return false;
      
    } catch (e) {
      debugPrint('[WVP] 登录异常: $e');
      return false;
    }
  }
  
  /// 带认证的GET请求
  Future<http.Response> _authGet(Uri uri) async {
    // 如果没有token，先登录
    if (_accessToken == null) {
      await login();
    }
    
    final response = await _client.get(
      uri,
      headers: _accessToken != null ? {'access-token': _accessToken!} : null,
    ).timeout(const Duration(seconds: 10));
    
    // 如果返回401，重新登录后再试一次
    if (response.statusCode == 401) {
      debugPrint('[WVP] Token过期，重新登录...');
      await login();
      return _client.get(
        uri,
        headers: _accessToken != null ? {'access-token': _accessToken!} : null,
      ).timeout(const Duration(seconds: 10));
    }
    
    return response;
  }
  
  // ==================== 已废弃的 WVP 报警 API ====================
  // 注意：以下 WVP 报警 API 已停用，改用自建服务器 (alarm_receiver.py)
  // 删除的方法：
  // - getAlarmList() - /api/alarm/all
  // - testAlarmNotify() - /api/alarm/test/notify/alarm
  // - getLatestFireAlarm()
  // - getAllAlarms()
  // - startAlarmPolling()
  // - stopAlarmPolling()
  // - _checkForNewAlarms()
  // 
  // 现在报警数据从 AlarmPollingService 获取（轮询 http://服务器:9090/api/alarms）
  // ================================================================
  
  /// 订阅报警通道
  /// 
  /// 【实现说明】
  /// 这个方法向 WVP 发送订阅请求，让 WVP 主动推送报警信息。
  /// 需要 WVP 配置好报警推送地址（WebHook）。
  Future<bool> subscribeAlarmChannel({
    String? deviceId,
    String? channelId,
  }) async {
    final device = deviceId ?? WvpConfig.deviceId;
    final channel = channelId ?? WvpConfig.alarmChannelId;
    
    try {
      debugPrint('[WVP] 订阅报警通道: 设备=$device, 通道=$channel');
      
      final response = await _client.get(
        Uri.parse('${WvpConfig.apiBaseUrl}/api/device/query/$device/subscribe/$channel'),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['code'] == 0;
      }
      
      return false;
      
    } catch (e) {
      debugPrint('[WVP] 订阅报警通道失败: $e');
      return false;
    }
  }

  
  // ==================== 录像功能 ====================
  
  /// 开始录像
  /// 
  /// 【实现说明】
  /// 当检测到火灾报警时，自动开始录像，保存报警时刻的视频。
  /// ZLMediaKit 支持服务端录像，录像文件保存在服务器上。
  Future<bool> startRecord({
    String? deviceId,
    String? channelId,
  }) async {
    if (_isRecording) {
      debugPrint('[WVP] 已经在录像中');
      return true;
    }
    
    final device = deviceId ?? WvpConfig.deviceId;
    final channel = channelId ?? WvpConfig.channelId;
    
    try {
      debugPrint('[WVP] 开始录像: 设备=$device, 通道=$channel');
      
      // 调用 ZLMediaKit 的录像 API
      final streamId = '${device}_$channel';
      final url = '${WvpConfig.mediaBaseUrl}/index/api/startRecord'
          '?secret=${WvpConfig.zlmSecret}'
          '&type=1'
          '&vhost=__defaultVhost__'
          '&app=rtp'
          '&stream=$streamId';
      
      debugPrint('[WVP] 录像API: $url');
      
      final response = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      
      debugPrint('[WVP] 录像响应: ${response.statusCode} - ${response.body}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] == 0) {
          _isRecording = true;
          _currentRecordId = streamId;
          debugPrint('[WVP] 录像已开始');
          return true;
        } else {
          debugPrint('[WVP] 录像失败: ${data['msg']}');
        }
      }
      
      return false;
      
    } catch (e) {
      debugPrint('[WVP] 开始录像失败: $e');
      return false;
    }
  }
  
  /// 停止录像
  Future<String?> stopRecord({
    String? deviceId,
    String? channelId,
  }) async {
    if (!_isRecording) {
      debugPrint('[WVP] 没有正在进行的录像');
      return null;
    }
    
    final device = deviceId ?? WvpConfig.deviceId;
    final channel = channelId ?? WvpConfig.channelId;
    
    try {
      debugPrint('[WVP] 停止录像: 设备=$device, 通道=$channel');
      
      final streamId = '${device}_$channel';
      final url = '${WvpConfig.mediaBaseUrl}/index/api/stopRecord'
          '?secret=${WvpConfig.zlmSecret}'
          '&type=1'
          '&vhost=__defaultVhost__'
          '&app=rtp'
          '&stream=$streamId';
      
      debugPrint('[WVP] 停止录像API: $url');
      
      final response = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      
      debugPrint('[WVP] 停止录像响应: ${response.statusCode} - ${response.body}');
      
      _isRecording = false;
      _currentRecordId = null;
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] == 0) {
          debugPrint('[WVP] 录像已停止');
          // 返回录像文件路径（如果有）
          return data['data']?['path'];
        }
      }
      
      return null;
      
    } catch (e) {
      debugPrint('[WVP] 停止录像失败: $e');
      _isRecording = false;
      return null;
    }
  }
  
  /// 获取录像状态
  bool get isRecording => _isRecording;

  
  // ==================== 录像回放 ====================
  
  /// 查询国标录像列表（设备端录像）
  /// 
  /// 【实现说明】
  /// 国标录像是存储在摄像头本地SD卡或NVR上的录像。
  /// 通过GB28181协议查询摄像头有哪些录像文件。
  /// 
  /// 【API 文档】
  /// 接口地址: /api/gb_record/query/{deviceId}/{channelId}
  Future<List<RecordInfo>> queryGbRecordList({
    String? deviceId,
    String? channelId,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    final device = deviceId ?? WvpConfig.deviceId;
    final channel = channelId ?? WvpConfig.channelId;
    
    try {
      final params = {
        'startTime': _formatDateTime(startTime),
        'endTime': _formatDateTime(endTime),
      };
      
      final uri = Uri.parse('${WvpConfig.apiBaseUrl}/api/gb_record/query/$device/$channel')
          .replace(queryParameters: params);
      
      debugPrint('[WVP] 查询国标录像: $uri');
      
      final response = await _authGet(uri).timeout(const Duration(seconds: 30));
      
      debugPrint('[WVP] 国标录像响应: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] == 0 && data['data'] != null) {
          final list = data['data']['recordList'] as List? ?? data['data'] as List? ?? [];
          debugPrint('[WVP] 查询到 ${list.length} 条录像记录');
          return list.map((e) => RecordInfo.fromJson(e)).toList();
        }
      }
      
      return [];
      
    } catch (e) {
      debugPrint('[WVP] 查询国标录像异常: $e');
      return [];
    }
  }
  
  /// 查询云端录像列表（服务器端录像）
  /// 
  /// 【实现说明】
  /// 云端录像是ZLMediaKit服务器录制的录像文件。
  /// 你没有安装SD卡，所以使用这个方式查看录像。
  /// 
  /// 【API 文档】
  /// 接口地址: /api/cloud/record/list
  /// 参数:
  /// - page: 当前页（必填）
  /// - count: 每页查询数量（必填）
  /// - app: 应用名（可选）
  /// - stream: 流ID（可选）
  /// - startTime: 开始时间 yyyy-MM-dd HH:mm:ss（可选）
  /// - endTime: 结束时间 yyyy-MM-dd HH:mm:ss（可选）
  /// - mediaServerId: 流媒体ID（可选）
  /// - ascOrder: 是否升序（可选）
  Future<CloudRecordListResult> queryCloudRecordList({
    String? app,
    String? stream,
    DateTime? startTime,
    DateTime? endTime,
    int page = 1,
    int count = 20,
    String? mediaServerId,
    bool? ascOrder,
  }) async {
    try {
      final params = <String, String>{
        'page': page.toString(),
        'count': count.toString(),
      };
      
      if (app != null) params['app'] = app;
      if (stream != null) params['stream'] = stream;
      if (startTime != null) params['startTime'] = _formatDateTime(startTime);
      if (endTime != null) params['endTime'] = _formatDateTime(endTime);
      if (mediaServerId != null) params['mediaServerId'] = mediaServerId;
      if (ascOrder != null) params['ascOrder'] = ascOrder.toString();
      
      final uri = Uri.parse('${WvpConfig.apiBaseUrl}/api/cloud/record/list')
          .replace(queryParameters: params);
      
      debugPrint('[WVP] 查询云端录像: $uri');
      
      final response = await _authGet(uri).timeout(const Duration(seconds: 30));
      
      debugPrint('[WVP] 云端录像响应: ${response.statusCode}');
      debugPrint('[WVP] 云端录像内容: ${response.body}');
      
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        
        // WVP 响应格式: {"code":0,"msg":"成功","data":{...}}
        if (json['code'] == 0 && json['data'] != null) {
          final data = json['data'];
          if (data['list'] != null) {
            final list = (data['list'] as List)
                .map((e) => CloudRecordItem.fromJson(e))
                .toList();
            return CloudRecordListResult(
              success: true,
              total: data['total'] ?? 0,
              records: list,
              pageNum: data['pageNum'] ?? page,
              pages: data['pages'] ?? 1,
            );
          }
        }
        
        // 返回错误信息
        return CloudRecordListResult(
          success: false, 
          errorMsg: json['msg'] ?? '查询失败',
        );
      }
      
      return CloudRecordListResult(success: false, errorMsg: '服务器错误: ${response.statusCode}');
      
    } catch (e) {
      debugPrint('[WVP] 查询云端录像异常: $e');
      return CloudRecordListResult(success: false, errorMsg: e.toString());
    }
  }
  
  /// 查询存在云端录像的日期
  /// 
  /// 【API 文档】
  /// 接口地址: /api/cloud/record/date/list
  /// 参数:
  /// - app: 应用名（必填）
  /// - stream: 流ID（必填）
  /// - year: 年，置空则查询当年（可选）
  /// - month: 月，置空则查询当月（可选）
  /// - mediaServerId: 流媒体ID（可选）
  Future<List<int>> queryCloudRecordDates({
    required String app,
    required String stream,
    int? year,
    int? month,
    String? mediaServerId,
  }) async {
    try {
      final params = <String, String>{
        'app': app,
        'stream': stream,
      };
      
      if (year != null) params['year'] = year.toString();
      if (month != null) params['month'] = month.toString();
      if (mediaServerId != null) params['mediaServerId'] = mediaServerId;
      
      final uri = Uri.parse('${WvpConfig.apiBaseUrl}/api/cloud/record/date/list')
          .replace(queryParameters: params);
      
      debugPrint('[WVP] 查询录像日期: $uri');
      
      final response = await _authGet(uri).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        
        // WVP 响应格式: {"code":0,"msg":"成功","data":[...]}
        if (json['code'] == 0 && json['data'] != null) {
          final data = json['data'];
          if (data is List) {
            return data.cast<int>();
          }
        }
      }
      
      return [];
      
    } catch (e) {
      debugPrint('[WVP] 查询录像日期异常: $e');
      return [];
    }
  }
  
  /// 获取云端录像播放地址
  /// 
  /// 【API 文档】
  /// 接口地址: /api/cloud/record/play/path
  /// 参数: recordId - 录像记录的ID（从云端录像列表获取）
  /// 
  /// 返回: DownloadFileInfo，包含多种协议的播放地址
  Future<CloudRecordPlayPath?> getCloudRecordPlayPath({
    required int recordId,
  }) async {
    try {
      final uri = Uri.parse('${WvpConfig.apiBaseUrl}/api/cloud/record/play/path')
          .replace(queryParameters: {'recordId': recordId.toString()});
      
      debugPrint('[WVP] 获取云端录像播放地址: $uri');
      
      final response = await _authGet(uri).timeout(const Duration(seconds: 10));
      
      debugPrint('[WVP] 播放地址响应: ${response.statusCode}');
      debugPrint('[WVP] 播放地址内容: ${response.body}');
      
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        
        // WVP 响应格式: {"code":0,"msg":"成功","data":{...}}
        if (json['code'] == 0 && json['data'] != null) {
          final data = json['data'];
          if (data['httpPath'] != null || data['httpsPath'] != null) {
            return CloudRecordPlayPath.fromJson(data);
          }
        }
      }
      
      return null;
      
    } catch (e) {
      debugPrint('[WVP] 获取播放地址异常: $e');
      return null;
    }
  }
  
  /// 加载云端录像文件形成流媒体播放地址
  /// 
  /// 【API 文档】
  /// 接口地址: /api/cloud/record/loadRecord
  /// 请求方式: GET
  /// 
  /// 【重要】
  /// 这个 API 会将 MP4 文件转换成流媒体格式（FLV/HLS/FMP4），
  /// 返回的地址可以像直播流一样播放，无需直接下载文件！
  /// 
  /// 参数:
  /// - app: 应用名（必填，如 "rtp"）
  /// - stream: 流ID（必填，如 "设备ID_通道ID"）
  /// - cloudRecordId: 云端录像ID（必填，从云端录像列表获取）
  /// 
  /// 返回: StreamContent，包含多种协议的播放地址
  Future<StreamInfo?> loadCloudRecord({
    required String app,
    required String stream,
    required int cloudRecordId,
  }) async {
    try {
      final uri = Uri.parse('${WvpConfig.apiBaseUrl}/api/cloud/record/loadRecord')
          .replace(queryParameters: {
            'app': app,
            'stream': stream,
            'cloudRecordId': cloudRecordId.toString(),
          });
      
      debugPrint('[WVP] 加载云端录像: $uri');
      
      final response = await _authGet(uri).timeout(const Duration(seconds: 30));
      
      debugPrint('[WVP] 加载录像响应: ${response.statusCode}');
      debugPrint('[WVP] 加载录像内容: ${response.body}');
      
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        
        // WVP 响应格式: {"code":0,"msg":"成功","data":{...}}
        if (json['code'] == 0 && json['data'] != null) {
          final data = json['data'];
          return StreamInfo.fromJson(data);
        } else {
          debugPrint('[WVP] 加载录像失败: ${json['msg']}');
        }
      }
      
      return null;
      
    } catch (e) {
      debugPrint('[WVP] 加载云端录像异常: $e');
      return null;
    }
  }
  
  /// 根据时间段查找并播放云端录像
  /// 
  /// 【工作流程】
  /// 1. 用时间段查询云端录像列表
  /// 2. 找到最匹配的录像记录
  /// 3. 调用 loadRecord API 将录像文件转换成流媒体格式
  /// 4. 返回流媒体播放地址给 APP
  Future<CloudRecordPlayResult> playCloudRecordByTime({
    required DateTime startTime,
    required DateTime endTime,
    String? app,
    String? stream,
  }) async {
    try {
      // 默认使用 rtp 应用和设备流ID
      final searchApp = app ?? 'rtp';
      final searchStream = stream ?? '${WvpConfig.deviceId}_${WvpConfig.channelId}';
      
      debugPrint('[WVP] 查找云端录像: $searchApp/$searchStream');
      debugPrint('[WVP] 时间范围: ${_formatDateTime(startTime)} ~ ${_formatDateTime(endTime)}');
      
      // 1. 查询时间段内的录像
      final result = await queryCloudRecordList(
        app: searchApp,
        stream: searchStream,
        startTime: startTime,
        endTime: endTime,
        count: 50,  // 查询足够多的记录
        ascOrder: true,  // 按时间升序
      );
      
      if (!result.success || result.records.isEmpty) {
        return CloudRecordPlayResult(
          success: false,
          errorMsg: '该时间段没有找到录像记录',
        );
      }
      
      debugPrint('[WVP] 找到 ${result.records.length} 条录像');
      
      // 2. 加载录像文件形成流媒体播放地址
      final record = result.records.first;
      final streamInfo = await loadCloudRecord(
        app: searchApp,
        stream: searchStream,
        cloudRecordId: record.id,
      );
      
      if (streamInfo == null) {
        return CloudRecordPlayResult(
          success: false,
          errorMsg: '无法加载录像文件',
        );
      }
      
      debugPrint('[WVP] 获取到流媒体播放地址:');
      debugPrint('[WVP]   FMP4: ${streamInfo.fmp4Url}');
      debugPrint('[WVP]   HLS: ${streamInfo.hlsUrl}');
      debugPrint('[WVP]   FLV: ${streamInfo.flvUrl}');
      
      return CloudRecordPlayResult(
        success: true,
        streamInfo: streamInfo,  // 流媒体播放信息
        record: record,
        allRecords: result.records,
      );
      
    } catch (e) {
      debugPrint('[WVP] 播放云端录像异常: $e');
      return CloudRecordPlayResult(
        success: false,
        errorMsg: '播放失败: $e',
      );
    }
  }
  
  /// 开始视频回放
  /// 
  /// 【实现说明】
  /// 录像回放和实时点播类似，但需要指定时间范围。
  /// WVP 会向摄像头发送回放请求，摄像头从本地存储读取录像并推流。
  /// 
  /// 【API 文档】
  /// 接口地址: /api/playback/start/{deviceId}/{channelId}
  /// 参数:
  /// - startTime: 开始时间 (格式: yyyy-MM-dd HH:mm:ss)
  /// - endTime: 结束时间 (格式: yyyy-MM-dd HH:mm:ss)
  /// 
  /// 返回: StreamContent，包含多种格式的流地址（flv/hls/rtsp等）
  Future<PlaybackResult> startPlayback({
    String? deviceId,
    String? channelId,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    final device = deviceId ?? WvpConfig.deviceId;
    final channel = channelId ?? WvpConfig.channelId;
    
    try {
      debugPrint('[WVP] 开始录像回放: $device/$channel');
      debugPrint('[WVP] 时间范围: ${_formatDateTime(startTime)} ~ ${_formatDateTime(endTime)}');
      
      final uri = Uri.parse('${WvpConfig.apiBaseUrl}/api/playback/start/$device/$channel')
          .replace(queryParameters: {
        'startTime': _formatDateTime(startTime),
        'endTime': _formatDateTime(endTime),
          });
      
      final response = await _authGet(uri).timeout(const Duration(seconds: 30));
      
      debugPrint('[WVP] 回放响应: ${response.statusCode}');
      debugPrint('[WVP] 回放内容: ${response.body}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] == 0 && data['data'] != null) {
          final playData = data['data'];
          
          // 解析多种流地址
          String? flvUrl = playData['flv'] ?? playData['ws_flv'];
          String? hlsUrl = playData['hls'] ?? playData['https_hls'];
          String? fmp4Url = playData['fmp4'] ?? playData['ws_fmp4'];
          
          // 添加 secret 鉴权参数
          String addSecret(String url) {
            final separator = url.contains('?') ? '&' : '?';
            return '$url${separator}secret=${WvpConfig.zlmSecret}';
          }
          
          // 如果是相对路径，补全为完整地址，并添加 secret
          if (flvUrl != null) {
            if (!flvUrl.startsWith('http')) {
              flvUrl = '${WvpConfig.mediaBaseUrl}$flvUrl';
            }
            flvUrl = addSecret(flvUrl);
          }
          if (hlsUrl != null) {
            if (!hlsUrl.startsWith('http')) {
              hlsUrl = '${WvpConfig.mediaBaseUrl}$hlsUrl';
            }
            hlsUrl = addSecret(hlsUrl);
          }
          if (fmp4Url != null) {
            if (!fmp4Url.startsWith('http')) {
              fmp4Url = '${WvpConfig.mediaBaseUrl}$fmp4Url';
            }
            fmp4Url = addSecret(fmp4Url);
          }
          
          return PlaybackResult(
            success: true,
            flvUrl: flvUrl,
            hlsUrl: hlsUrl,
            fmp4Url: fmp4Url,
            streamId: playData['stream'] ?? playData['streamId'],
            app: playData['app'],
            startTime: startTime,
            endTime: endTime,
            duration: playData['duration']?.toDouble(),
          );
        }
        return PlaybackResult(
          success: false,
          errorMsg: data['msg'] ?? '录像回放失败',
        );
      }
      
      return PlaybackResult(
        success: false,
        errorMsg: '服务器响应错误: ${response.statusCode}',
      );
      
    } catch (e) {
      debugPrint('[WVP] 录像回放异常: $e');
      return PlaybackResult(
        success: false,
        errorMsg: '录像回放失败: $e',
      );
    }
  }
  
  /// 停止录像回放
  /// 
  /// 【API 文档】
  /// 接口地址: /api/playback/stop/{deviceId}/{channelId}/{stream}
  Future<bool> stopPlayback({
    String? deviceId, 
    String? channelId,
    String? streamId,
  }) async {
    final device = deviceId ?? WvpConfig.deviceId;
    final channel = channelId ?? WvpConfig.channelId;
    
    try {
      String url = '${WvpConfig.apiBaseUrl}/api/playback/stop/$device/$channel';
      if (streamId != null) {
        url += '/$streamId';
      }
      
      debugPrint('[WVP] 停止回放: $url');
      
      final response = await _client.get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      
      return response.statusCode == 200;
      
    } catch (e) {
      debugPrint('[WVP] 停止回放异常: $e');
      return false;
    }
  }
  
  /// 回放倍速播放
  /// 
  /// 【API 文档】
  /// 接口地址: /api/playback/speed/{streamId}/{speed}
  /// 参数:
  /// - streamId: 回放流ID（从startPlayback返回）
  /// - speed: 倍速 0.25/0.5/1/2/4/8
  Future<bool> setPlaybackSpeed({
    required String streamId,
    required double speed,
  }) async {
    try {
      final uri = Uri.parse(
        '${WvpConfig.apiBaseUrl}/api/playback/speed/$streamId/$speed'
      );
      
      debugPrint('[WVP] 设置回放速度: $uri');
      
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      
      return response.statusCode == 200;
      
    } catch (e) {
      debugPrint('[WVP] 设置回放速度异常: $e');
      return false;
    }
  }
  
  /// 回放拖动/定位
  /// 
  /// 【API 文档】
  /// 接口地址: /api/playback/seek/{streamId}/{seekTime}
  /// 参数:
  /// - streamId: 回放流ID
  /// - seekTime: 拖动偏移量，单位秒
  Future<bool> seekPlayback({
    required String streamId,
    required int seekTime,
  }) async {
    try {
      final uri = Uri.parse(
        '${WvpConfig.apiBaseUrl}/api/playback/seek/$streamId/$seekTime'
      );
      
      debugPrint('[WVP] 回放定位: $uri');
      
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      
      return response.statusCode == 200;
      
    } catch (e) {
      debugPrint('[WVP] 回放定位异常: $e');
      return false;
    }
  }
  
  /// 回放暂停
  /// 
  /// 【API 文档】
  /// 接口地址: /api/playback/pause/{streamId}
  Future<bool> pausePlayback({
    required String streamId,
  }) async {
    try {
      final uri = Uri.parse(
        '${WvpConfig.apiBaseUrl}/api/playback/pause/$streamId'
      );
      
      debugPrint('[WVP] 回放暂停: $uri');
      
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      
      return response.statusCode == 200;
      
    } catch (e) {
      debugPrint('[WVP] 回放暂停异常: $e');
      return false;
    }
  }
  
  /// 回放恢复
  /// 
  /// 【API 文档】
  /// 接口地址: /api/playback/resume/{streamId}
  Future<bool> resumePlayback({
    required String streamId,
  }) async {
    try {
      final uri = Uri.parse(
        '${WvpConfig.apiBaseUrl}/api/playback/resume/$streamId'
      );
      
      debugPrint('[WVP] 回放恢复: $uri');
      
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      
      return response.statusCode == 200;
      
    } catch (e) {
      debugPrint('[WVP] 回放恢复异常: $e');
      return false;
    }
  }
  
  // ==================== 设备管理 ====================
  
  /// 获取设备信息
  Future<DeviceInfo?> getDeviceInfo({String? deviceId}) async {
    final device = deviceId ?? WvpConfig.deviceId;
    
    try {
      final response = await _client.get(
        Uri.parse('${WvpConfig.apiBaseUrl}/api/device/query/devices/$device'),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] == 0 && data['data'] != null) {
          return DeviceInfo.fromJson(data['data']);
        }
      }
      
      return null;
      
    } catch (e) {
      debugPrint('[WVP] 获取设备信息异常: $e');
      return null;
    }
  }
  
  /// 检查设备是否在线
  Future<bool> isDeviceOnline({String? deviceId}) async {
    final info = await getDeviceInfo(deviceId: deviceId);
    return info?.online ?? false;
  }
  
  // ==================== 工具方法 ====================
  
  /// 格式化日期时间（WVP API 要求的格式）
  /// 
  /// 注意：WVP 服务器使用北京时间（UTC+8），需要确保传入的是本地时间
  String _formatDateTime(DateTime dt) {
    // 如果是 UTC 时间，转换为本地时间
    final localDt = dt.isUtc ? dt.toLocal() : dt;
    return '${localDt.year}-${_pad(localDt.month)}-${_pad(localDt.day)} '
           '${_pad(localDt.hour)}:${_pad(localDt.minute)}:${_pad(localDt.second)}';
  }
  
  String _pad(int n) => n.toString().padLeft(2, '0');
  
  /// 释放资源
  void dispose() {
    _client.close();
  }
}
