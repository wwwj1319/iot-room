/// 报警轮询服务
/// 
/// 【功能说明】
/// 定时轮询服务器检查是否有新报警，有新报警时：
/// 1. 发送系统通知
/// 2. 触发回调函数（用于更新UI）
/// 
/// 【使用方法】
/// 在 main.dart 或首页启动轮询：
/// AlarmPollingService().start(onNewAlarm: (alarm) { ... });

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/config/app_config.dart';
import 'notification_service.dart';

/// 报警服务器配置
class AlarmServerConfig {
  static String get baseUrl => AppConfig.alarmBaseUrl;
  static String get checkAlarmApi => '$baseUrl/api/alarms/check';
}

/// 新报警数据模型
class NewAlarmData {
  final String id;
  final String eventType;
  final String eventDescription;
  final String dateTime;
  final String deviceID;
  final String channelName;
  final String? imageUrl;
  
  NewAlarmData({
    required this.id,
    required this.eventType,
    required this.eventDescription,
    required this.dateTime,
    required this.deviceID,
    required this.channelName,
    this.imageUrl,
  });
  
  factory NewAlarmData.fromJson(Map<String, dynamic> json) {
    return NewAlarmData(
      id: json['id'] ?? '',
      eventType: json['eventType'] ?? '',
      eventDescription: json['eventDescription'] ?? '',
      dateTime: json['dateTime'] ?? '',
      deviceID: json['deviceID'] ?? '',
      channelName: json['channelName'] ?? '',
      imageUrl: json['imageUrl'],
    );
  }
  
  /// 是否是火灾报警
  bool get isFireAlarm => eventType == 'fireSmartFireDetect';
  
  /// 是否是报警恢复
  bool get isRecovery => eventType == 'FirePointAlarmRecovery';
  
  /// 获取通知标题
  String get notificationTitle {
    if (isFireAlarm) return '🔥 火灾警报开始';
    if (isRecovery) return '✅ 火灾警报结束';
    return '⚠️ 设备报警';
  }
  
  /// 获取通知内容
  String get notificationBody {
    final time = _formatTime(dateTime);
    if (isFireAlarm) {
      return '检测到火焰！请立即前往现场查看！\n设备: $channelName\n时间: $time';
    }
    if (isRecovery) {
      return '火灾警报已解除，现场恢复正常。\n设备: $channelName\n时间: $time';
    }
    return '$eventDescription\n时间: $time';
  }
  
  String _formatTime(String dateTime) {
    try {
      // 解析后转换为本地时间，解决时区差8小时问题
      final dt = DateTime.parse(dateTime).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateTime;
    }
  }
}

/// 报警轮询服务（单例）
class AlarmPollingService {
  static final AlarmPollingService _instance = AlarmPollingService._internal();
  factory AlarmPollingService() => _instance;
  AlarmPollingService._internal();
  
  Timer? _timer;
  String? _lastAlarmId;
  bool _isRunning = false;
  
  /// 新报警回调
  void Function(NewAlarmData alarm)? _onNewAlarmCallback;
  
  /// 通知服务
  final NotificationService _notificationService = NotificationService();
  
  /// 轮询间隔（秒）
  static const int _pollingInterval = 5;
  
  /// 开始轮询
  Future<void> start({
    void Function(NewAlarmData alarm)? onNewAlarm,
  }) async {
    if (_isRunning) {
      debugPrint('[AlarmPolling] 已经在运行中');
      return;
    }
    
    _onNewAlarmCallback = onNewAlarm;
    _isRunning = true;
    
    // 初始化通知服务（不在这里请求权限，由 main.dart 处理）
    await _notificationService.initialize();
    
    // 首次检查只获取最新ID，不发送通知（避免启动时有声音）
    await _syncLatestAlarmId();
    
    // 启动定时轮询
    _timer = Timer.periodic(
      const Duration(seconds: _pollingInterval),
      (_) => _checkNewAlarm(),
    );
    
    debugPrint('[AlarmPolling] 轮询已启动，间隔 $_pollingInterval 秒');
  }
  
  /// 同步最新报警ID（启动时调用，不发送通知）
  Future<void> _syncLatestAlarmId() async {
    try {
      final response = await http.get(
        Uri.parse(AlarmServerConfig.checkAlarmApi),
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _lastAlarmId = data['latestId'];
        debugPrint('[AlarmPolling] 同步最新报警ID: $_lastAlarmId');
      }
    } catch (e) {
      // 静默失败
    }
  }
  
  /// 停止轮询
  void stop() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
    _onNewAlarmCallback = null;
    debugPrint('[AlarmPolling] 轮询已停止');
  }
  
  /// 检查是否有新报警
  Future<void> _checkNewAlarm() async {
    try {
      final url = _lastAlarmId != null 
          ? '${AlarmServerConfig.checkAlarmApi}?last_id=$_lastAlarmId'
          : AlarmServerConfig.checkAlarmApi;
      
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 5),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['hasNew'] == true && data['alarm'] != null) {
          final alarm = NewAlarmData.fromJson(data['alarm']);
          
          // 更新最后报警ID
          _lastAlarmId = data['latestId'];
          
          debugPrint('[AlarmPolling] 检测到新报警: ${alarm.eventType}');
          
          // 发送系统通知
          await _sendNotification(alarm);
          
          // 触发回调
          _onNewAlarmCallback?.call(alarm);
        }
      }
    } catch (e) {
      // 静默失败，不打印错误（网络问题很常见）
      // debugPrint('[AlarmPolling] 检查失败: $e');
    }
  }
  
  /// 发送系统通知
  Future<void> _sendNotification(NewAlarmData alarm) async {
    if (alarm.isFireAlarm) {
      await _notificationService.showFireAlarmNotification(
        title: alarm.notificationTitle,
        body: alarm.notificationBody,
        payload: alarm.id,
      );
    } else if (alarm.isRecovery) {
      await _notificationService.showAlarmRecoveryNotification(
        title: alarm.notificationTitle,
        body: alarm.notificationBody,
        payload: alarm.id,
      );
    } else {
      await _notificationService.showDeviceAlarmNotification(
        title: alarm.notificationTitle,
        body: alarm.notificationBody,
        payload: alarm.id,
      );
    }
  }
  
  /// 是否正在运行
  bool get isRunning => _isRunning;
  
  /// 手动触发检查
  Future<void> checkNow() async {
    await _checkNewAlarm();
  }
}
