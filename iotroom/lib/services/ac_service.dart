import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/config/app_config.dart';

/// 红外空调控制服务
/// 
/// 与服务器 API 交互，控制空调开关和温度调节
class ACService {
  /// 服务器地址
  static String get _baseUrl => '${AppConfig.apiBaseUrl}/api/ac';
  
  /// HTTP 请求超时时间
  static const Duration _timeout = Duration(seconds: 10);

  /// 获取空调状态
  Future<ACStatus?> getStatus({int modbusAddress = 3}) async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/status/$modbusAddress'))
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return ACStatus.fromJson(json);
      } else {
        debugPrint('[ACService] 获取状态失败: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('[ACService] 获取状态异常: $e');
      return null;
    }
  }

  /// 开机
  /// [mode] 'cool'=制冷, 'heat'=制热
  Future<ACControlResult> powerOn({
    String mode = 'cool',
    int modbusAddress = 3,
    String? operator,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/power-on/$modbusAddress'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'mode': mode,
              if (operator != null) 'operator': operator,
            }),
          )
          .timeout(_timeout);

      final json = jsonDecode(response.body);
      return ACControlResult.fromJson(json);
    } catch (e) {
      debugPrint('[ACService] 开机异常: $e');
      return ACControlResult(
        success: false,
        action: 'power_on_$mode',
        error: e.toString(),
      );
    }
  }

  /// 关机
  Future<ACControlResult> powerOff({
    int modbusAddress = 3,
    String? operator,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/power-off/$modbusAddress');
      final queryParams = operator != null ? {'operator': operator} : null;
      final response = await http
          .post(uri.replace(queryParameters: queryParams))
          .timeout(_timeout);

      final json = jsonDecode(response.body);
      return ACControlResult.fromJson(json);
    } catch (e) {
      debugPrint('[ACService] 关机异常: $e');
      return ACControlResult(
        success: false,
        action: 'power_off',
        error: e.toString(),
      );
    }
  }

  /// 升温（+1°C）
  Future<ACControlResult> tempUp({
    int modbusAddress = 3,
    String? operator,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/temp-up/$modbusAddress');
      final queryParams = operator != null ? {'operator': operator} : null;
      final response = await http
          .post(uri.replace(queryParameters: queryParams))
          .timeout(_timeout);

      final json = jsonDecode(response.body);
      return ACControlResult.fromJson(json);
    } catch (e) {
      debugPrint('[ACService] 升温异常: $e');
      return ACControlResult(
        success: false,
        action: 'temp_up',
        error: e.toString(),
      );
    }
  }

  /// 降温（-1°C）
  Future<ACControlResult> tempDown({
    int modbusAddress = 3,
    String? operator,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/temp-down/$modbusAddress');
      final queryParams = operator != null ? {'operator': operator} : null;
      final response = await http
          .post(uri.replace(queryParameters: queryParams))
          .timeout(_timeout);

      final json = jsonDecode(response.body);
      return ACControlResult.fromJson(json);
    } catch (e) {
      debugPrint('[ACService] 降温异常: $e');
      return ACControlResult(
        success: false,
        action: 'temp_down',
        error: e.toString(),
      );
    }
  }

  /// 设置目标温度
  Future<ACControlResult> setTemp({
    required int targetTemp,
    int modbusAddress = 3,
    String? operator,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/set-temp/$modbusAddress'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'target_temp': targetTemp,
              if (operator != null) 'operator': operator,
            }),
          )
          .timeout(_timeout);

      final json = jsonDecode(response.body);
      return ACControlResult.fromJson(json);
    } catch (e) {
      debugPrint('[ACService] 设置温度异常: $e');
      return ACControlResult(
        success: false,
        action: 'set_temp',
        error: e.toString(),
      );
    }
  }

  /// 获取操作历史
  Future<List<ACEvent>> getEvents({
    int modbusAddress = 3,
    int limit = 50,
  }) async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/events/$modbusAddress?limit=$limit'))
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final List eventsJson = json['events'] ?? [];
        return eventsJson.map((e) => ACEvent.fromJson(e)).toList();
      } else {
        debugPrint('[ACService] 获取历史失败: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('[ACService] 获取历史异常: $e');
      return [];
    }
  }
}


/// 空调状态
class ACStatus {
  final int modbusAddress;
  final bool isOn;
  final String mode;        // cool/heat
  final String modeText;    // 制冷/制热
  final int targetTemp;
  final bool isOnline;
  final String? lastUpdate;
  final int todayOperationCount;

  ACStatus({
    required this.modbusAddress,
    required this.isOn,
    required this.mode,
    required this.modeText,
    required this.targetTemp,
    required this.isOnline,
    this.lastUpdate,
    required this.todayOperationCount,
  });

  factory ACStatus.fromJson(Map<String, dynamic> json) {
    return ACStatus(
      modbusAddress: json['modbus_address'] ?? 3,
      isOn: json['is_on'] ?? false,
      mode: json['mode'] ?? 'cool',
      modeText: json['mode_text'] ?? '制冷',
      targetTemp: json['target_temp'] ?? 26,
      isOnline: json['is_online'] ?? false,
      lastUpdate: json['last_update'],
      todayOperationCount: json['today_operation_count'] ?? 0,
    );
  }

  /// 是否是制冷模式
  bool get isCooling => mode == 'cool';

  /// 是否是制热模式
  bool get isHeating => mode == 'heat';
}


/// 控制结果
class ACControlResult {
  final bool success;
  final String action;
  final int? targetTemp;
  final String? mode;
  final String? commandHex;
  final String? error;

  ACControlResult({
    required this.success,
    required this.action,
    this.targetTemp,
    this.mode,
    this.commandHex,
    this.error,
  });

  factory ACControlResult.fromJson(Map<String, dynamic> json) {
    return ACControlResult(
      success: json['success'] ?? false,
      action: json['action'] ?? '',
      targetTemp: json['target_temp'],
      mode: json['mode'],
      commandHex: json['command_hex'],
      error: json['error'],
    );
  }
}


/// 操作事件
class ACEvent {
  final int id;
  final String action;
  final bool? isOn;
  final String? mode;
  final int? targetTemp;
  final String eventTime;
  final String source;
  final String? operator;
  final bool success;
  final String? errorMsg;

  ACEvent({
    required this.id,
    required this.action,
    this.isOn,
    this.mode,
    this.targetTemp,
    required this.eventTime,
    required this.source,
    this.operator,
    required this.success,
    this.errorMsg,
  });

  factory ACEvent.fromJson(Map<String, dynamic> json) {
    return ACEvent(
      id: json['id'] ?? 0,
      action: json['action'] ?? '',
      isOn: json['is_on'],
      mode: json['mode'],
      targetTemp: json['target_temp'],
      eventTime: json['event_time'] ?? '',
      source: json['source'] ?? 'manual',
      operator: json['operator'],
      success: json['success'] ?? true,
      errorMsg: json['error_msg'],
    );
  }

  /// 操作描述
  String get actionText {
    switch (action) {
      case 'power_on_cool':
        return '制冷开机';
      case 'power_on_heat':
        return '制热开机';
      case 'power_off':
        return '关机';
      case 'temp_up':
        return '升温';
      case 'temp_down':
        return '降温';
      case 'set_temp':
        return '设置温度';
      default:
        return action;
    }
  }
}

