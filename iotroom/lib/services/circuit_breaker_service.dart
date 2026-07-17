import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/config/app_config.dart';

/// 智能断路器服务
/// 
/// 与服务器 API 交互，获取断路器状态和控制开关
class CircuitBreakerService {
  /// 服务器地址
  static String get _baseUrl => '${AppConfig.apiBaseUrl}/api/circuit-breaker';
  
  /// HTTP 请求超时时间
  static const Duration _timeout = Duration(seconds: 10);

  /// 获取断路器状态
  Future<CircuitBreakerStatus?> getStatus({int modbusAddress = 2}) async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/status/$modbusAddress'))
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return CircuitBreakerStatus.fromJson(json);
      } else {
        debugPrint('[CircuitBreakerService] 获取状态失败: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('[CircuitBreakerService] 获取状态异常: $e');
      return null;
    }
  }

  /// 控制断路器开关
  /// 
  /// [close] true=合闸(通电/开灯), false=分闸(断电/关灯)
  Future<CircuitBreakerControlResult> control({
    required bool close,
    int modbusAddress = 2,
    String? operator,
    String? remark,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/control/$modbusAddress'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'close': close,
              if (operator != null) 'operator': operator,
              if (remark != null) 'remark': remark,
            }),
          )
          .timeout(_timeout);

      final json = jsonDecode(response.body);
      
      if (response.statusCode == 200) {
        return CircuitBreakerControlResult.fromJson(json);
      } else {
        return CircuitBreakerControlResult(
          success: false,
          modbusAddress: modbusAddress,
          action: close ? '合闸' : '分闸',
          commandHex: '',
          error: json['detail'] ?? '控制失败',
        );
      }
    } catch (e) {
      debugPrint('[CircuitBreakerService] 控制异常: $e');
      return CircuitBreakerControlResult(
        success: false,
        modbusAddress: modbusAddress,
        action: close ? '合闸' : '分闸',
        commandHex: '',
        error: e.toString(),
      );
    }
  }

  /// 获取操作历史
  Future<List<CircuitBreakerEvent>> getEvents({
    int modbusAddress = 2,
    int limit = 50,
  }) async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/events/$modbusAddress?limit=$limit'))
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final List eventsJson = json['events'] ?? [];
        return eventsJson.map((e) => CircuitBreakerEvent.fromJson(e)).toList();
      } else {
        debugPrint('[CircuitBreakerService] 获取历史失败: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('[CircuitBreakerService] 获取历史异常: $e');
      return [];
    }
  }
}


/// 断路器状态
class CircuitBreakerStatus {
  final int modbusAddress;
  final bool isClosed;      // true=合闸(通电), false=分闸(断电)
  final bool isOnline;
  final String statusText;
  final String? lastUpdate;
  final int todaySwitchCount;

  CircuitBreakerStatus({
    required this.modbusAddress,
    required this.isClosed,
    required this.isOnline,
    required this.statusText,
    this.lastUpdate,
    required this.todaySwitchCount,
  });

  factory CircuitBreakerStatus.fromJson(Map<String, dynamic> json) {
    return CircuitBreakerStatus(
      modbusAddress: json['modbus_address'] ?? 2,
      isClosed: json['is_closed'] ?? false,
      isOnline: json['is_online'] ?? false,
      statusText: json['status_text'] ?? '未知',
      lastUpdate: json['last_update'],
      todaySwitchCount: json['today_switch_count'] ?? 0,
    );
  }

  /// 获取最后更新时间（DateTime）
  DateTime? get lastUpdateTime {
    if (lastUpdate == null) return null;
    try {
      return DateTime.parse(lastUpdate!);
    } catch (_) {
      return null;
    }
  }
}


/// 断路器控制结果
class CircuitBreakerControlResult {
  final bool success;
  final int modbusAddress;
  final String action;
  final String commandHex;
  final String? error;

  CircuitBreakerControlResult({
    required this.success,
    required this.modbusAddress,
    required this.action,
    required this.commandHex,
    this.error,
  });

  factory CircuitBreakerControlResult.fromJson(Map<String, dynamic> json) {
    return CircuitBreakerControlResult(
      success: json['success'] ?? false,
      modbusAddress: json['modbus_address'] ?? 2,
      action: json['action'] ?? '',
      commandHex: json['command_hex'] ?? '',
      error: json['error'],
    );
  }
}


/// 断路器操作事件
class CircuitBreakerEvent {
  final int id;
  final String eventType;     // on/off
  final String eventTime;
  final String source;
  final String? operator;
  final String? remark;
  final bool success;
  final String? errorMsg;

  CircuitBreakerEvent({
    required this.id,
    required this.eventType,
    required this.eventTime,
    required this.source,
    this.operator,
    this.remark,
    required this.success,
    this.errorMsg,
  });

  factory CircuitBreakerEvent.fromJson(Map<String, dynamic> json) {
    return CircuitBreakerEvent(
      id: json['id'] ?? 0,
      eventType: json['event_type'] ?? '',
      eventTime: json['event_time'] ?? '',
      source: json['source'] ?? 'unknown',
      operator: json['operator'],
      remark: json['remark'],
      success: json['success'] ?? true,
      errorMsg: json['error_msg'],
    );
  }

  /// 是否是合闸（通电）事件
  bool get isClosed => eventType == 'on';

  /// 事件时间（DateTime）
  DateTime? get dateTime {
    try {
      return DateTime.parse(eventTime);
    } catch (_) {
      return null;
    }
  }

  /// 操作来源文本
  String get sourceText {
    switch (source) {
      case 'manual':
        return '手动操作';
      case 'schedule':
        return '定时任务';
      case 'linkage':
        return '联动触发';
      default:
        return '未知';
    }
  }
}

