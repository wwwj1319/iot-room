/// 通知服务
/// 
/// 【功能说明】
/// 负责发送系统通知，用于：
/// - 火灾报警通知
/// - 设备异常通知
/// - 其他重要提醒
/// 
/// 【使用方法】
/// 1. 在 main.dart 中初始化：await NotificationService().initialize();
/// 2. 发送通知：NotificationService().showAlarmNotification(...)

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

/// 通知服务（单例）
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();
  
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  
  bool _isInitialized = false;
  
  /// 初始化通知服务
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    
    try {
      // Android 设置
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      
      // iOS 设置
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );
      
      // 初始化
      final result = await _notifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );
      
      _isInitialized = result ?? false;
      
      if (_isInitialized) {
        debugPrint('[NotificationService] 初始化成功');
      } else {
        debugPrint('[NotificationService] 初始化失败');
      }
      
      return _isInitialized;
      
    } catch (e) {
      debugPrint('[NotificationService] 初始化异常: $e');
      return false;
    }
  }
  
  /// 请求通知权限
  Future<bool> requestPermission() async {
    try {
      // Android 13+ 需要请求通知权限
      final status = await Permission.notification.request();
      
      if (status.isGranted) {
        debugPrint('[NotificationService] 通知权限已授予');
        return true;
      } else if (status.isDenied) {
        debugPrint('[NotificationService] 通知权限被拒绝');
        return false;
      } else if (status.isPermanentlyDenied) {
        debugPrint('[NotificationService] 通知权限被永久拒绝，请在设置中手动开启');
        return false;
      }
      
      return false;
    } catch (e) {
      debugPrint('[NotificationService] 请求权限异常: $e');
      return false;
    }
  }
  
  /// 检查通知权限
  Future<bool> hasPermission() async {
    final status = await Permission.notification.status;
    return status.isGranted;
  }
  
  /// 发送火灾报警通知
  Future<void> showFireAlarmNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    await _showNotification(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,  // 标题已包含emoji
      body: body,
      channelId: 'fire_alarm',
      channelName: '火灾报警',
      channelDescription: '火灾检测报警通知 - 最高优先级',
      importance: Importance.max,
      priority: Priority.max,
      payload: payload,
    );
  }
  
  /// 发送设备异常通知
  Future<void> showDeviceAlarmNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    await _showNotification(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: '⚠️ $title',
      body: body,
      channelId: 'device_alarm',
      channelName: '设备报警',
      channelDescription: '设备异常报警通知',
      importance: Importance.high,
      priority: Priority.high,
      payload: payload,
    );
  }
  
  /// 发送报警恢复通知
  Future<void> showAlarmRecoveryNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    await _showNotification(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: '✅ $title',
      body: body,
      channelId: 'alarm_recovery',
      channelName: '报警恢复',
      channelDescription: '报警恢复通知',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      payload: payload,
    );
  }
  
  /// 发送通用通知
  Future<void> _showNotification({
    required int id,
    required String title,
    required String body,
    required String channelId,
    required String channelName,
    required String channelDescription,
    required Importance importance,
    required Priority priority,
    String? payload,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }
    
    try {
      // Android 通知详情
      final androidDetails = AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: importance,
        priority: priority,
        enableVibration: true,
        playSound: true,
        icon: '@mipmap/ic_launcher',
        // 设置通知样式
        styleInformation: BigTextStyleInformation(body),
      );
      
      // iOS 通知详情
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      
      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );
      
      await _notifications.show(
        id,
        title,
        body,
        details,
        payload: payload,
      );
      
      debugPrint('[NotificationService] 通知已发送: $title');
      
    } catch (e) {
      debugPrint('[NotificationService] 发送通知失败: $e');
    }
  }
  
  /// 通知点击回调
  void _onNotificationTapped(NotificationResponse response) {
    debugPrint('[NotificationService] 通知被点击: ${response.payload}');
    // TODO: 根据 payload 跳转到对应页面
  }
  
  /// 取消所有通知
  Future<void> cancelAll() async {
    await _notifications.cancelAll();
  }
  
  /// 取消指定通知
  Future<void> cancel(int id) async {
    await _notifications.cancel(id);
  }
}

