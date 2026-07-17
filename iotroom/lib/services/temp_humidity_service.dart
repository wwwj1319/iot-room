import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/config/app_config.dart';

/// 温湿度传感器服务
/// 
/// 提供温湿度传感器相关的 API 调用：
/// 1. 获取当前温湿度状态
/// 2. 获取历史数据
/// 3. 获取统计信息
class TempHumidityService {
  /// API 基础地址
  static String get baseUrl => AppConfig.apiBaseUrl;
  
  /// 请求超时时间
  static const Duration timeout = Duration(seconds: 10);

  // ==================== 单例模式 ====================
  
  static final TempHumidityService _instance = TempHumidityService._internal();
  factory TempHumidityService() => _instance;
  TempHumidityService._internal();

  // ==================== API 方法 ====================

  /// 获取温湿度当前状态
  /// 
  /// [modbusAddress] Modbus地址（十进制，如 1 对应 0x01）
  Future<TempHumidityStatusData?> getStatus(int modbusAddress) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/temp-humidity/status/$modbusAddress'),
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return TempHumidityStatusData.fromJson(json);
      } else if (response.statusCode == 404) {
        debugPrint('[TempHumidity] 传感器不存在: $modbusAddress');
        return null;
      } else {
        debugPrint('[TempHumidity] 获取状态失败: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('[TempHumidity] 获取状态异常: $e');
      return null;
    }
  }

  /// 获取温湿度历史数据
  /// 
  /// [modbusAddress] Modbus地址
  /// [hours] 查询最近几小时，默认24小时
  /// [limit] 返回数量限制，默认100条
  Future<TempHumidityHistoryData?> getHistory({
    required int modbusAddress,
    int hours = 24,
    int limit = 100,
  }) async {
    try {
      final queryParams = {
        'hours': hours.toString(),
        'limit': limit.toString(),
      };

      final uri = Uri.parse('$baseUrl/api/temp-humidity/history/$modbusAddress')
          .replace(queryParameters: queryParams);
      
      final response = await http.get(uri).timeout(timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return TempHumidityHistoryData.fromJson(json);
      } else {
        debugPrint('[TempHumidity] 获取历史失败: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('[TempHumidity] 获取历史异常: $e');
      return null;
    }
  }

  /// 获取温湿度统计数据
  /// 
  /// [modbusAddress] Modbus地址
  /// [period] 统计周期: today/week/month
  Future<TempHumidityStatsData?> getStats({
    required int modbusAddress,
    String period = 'today',
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/temp-humidity/stats/$modbusAddress')
          .replace(queryParameters: {'period': period});
      
      final response = await http.get(uri).timeout(timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return TempHumidityStatsData.fromJson(json);
      } else {
        debugPrint('[TempHumidity] 获取统计失败: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('[TempHumidity] 获取统计异常: $e');
      return null;
    }
  }
}


// ==================== 数据模型 ====================

/// 温湿度当前状态数据
class TempHumidityStatusData {
  final int sensorId;
  final String sensorCode;
  final String sensorName;
  final double temperature;
  final double humidity;
  final bool isOnline;
  final String? lastUpdate;
  final int modbusAddress;

  TempHumidityStatusData({
    required this.sensorId,
    required this.sensorCode,
    required this.sensorName,
    required this.temperature,
    required this.humidity,
    required this.isOnline,
    this.lastUpdate,
    required this.modbusAddress,
  });

  factory TempHumidityStatusData.fromJson(Map<String, dynamic> json) {
    return TempHumidityStatusData(
      sensorId: json['sensor_id'] ?? 0,
      sensorCode: json['sensor_code'] ?? '',
      sensorName: json['sensor_name'] ?? '未知传感器',
      temperature: (json['temperature'] ?? 0).toDouble(),
      humidity: (json['humidity'] ?? 0).toDouble(),
      isOnline: json['is_online'] ?? false,
      lastUpdate: json['last_update'],
      modbusAddress: json['modbus_address'] ?? 0,
    );
  }
}


/// 温湿度历史数据
class TempHumidityHistoryData {
  final int sensorId;
  final int modbusAddress;
  final List<TempHumidityHistoryItem> data;
  final int total;

  TempHumidityHistoryData({
    required this.sensorId,
    required this.modbusAddress,
    required this.data,
    required this.total,
  });

  factory TempHumidityHistoryData.fromJson(Map<String, dynamic> json) {
    final List dataJson = json['data'] ?? [];
    return TempHumidityHistoryData(
      sensorId: json['sensor_id'] ?? 0,
      modbusAddress: json['modbus_address'] ?? 0,
      data: dataJson.map((e) => TempHumidityHistoryItem.fromJson(e)).toList(),
      total: json['total'] ?? 0,
    );
  }
}


/// 温湿度历史记录项
class TempHumidityHistoryItem {
  final double temperature;
  final double humidity;
  final String recordTime;

  TempHumidityHistoryItem({
    required this.temperature,
    required this.humidity,
    required this.recordTime,
  });

  factory TempHumidityHistoryItem.fromJson(Map<String, dynamic> json) {
    return TempHumidityHistoryItem(
      temperature: (json['temperature'] ?? 0).toDouble(),
      humidity: (json['humidity'] ?? 0).toDouble(),
      recordTime: json['record_time'] ?? '',
    );
  }

  /// 获取 DateTime 对象
  DateTime? get dateTime {
    try {
      return DateTime.parse(recordTime);
    } catch (_) {
      return null;
    }
  }
}


/// 温湿度统计数据
class TempHumidityStatsData {
  final int sensorId;
  final int modbusAddress;
  final String period;
  final TempStats temperature;
  final TempStats humidity;
  final int dataCount;

  TempHumidityStatsData({
    required this.sensorId,
    required this.modbusAddress,
    required this.period,
    required this.temperature,
    required this.humidity,
    required this.dataCount,
  });

  factory TempHumidityStatsData.fromJson(Map<String, dynamic> json) {
    return TempHumidityStatsData(
      sensorId: json['sensor_id'] ?? 0,
      modbusAddress: json['modbus_address'] ?? 0,
      period: json['period'] ?? 'today',
      temperature: TempStats.fromJson(json['temperature'] ?? {}),
      humidity: TempStats.fromJson(json['humidity'] ?? {}),
      dataCount: json['data_count'] ?? 0,
    );
  }
}


/// 温度/湿度统计
class TempStats {
  final double? min;
  final double? max;
  final double? avg;

  TempStats({this.min, this.max, this.avg});

  factory TempStats.fromJson(Map<String, dynamic> json) {
    return TempStats(
      min: json['min']?.toDouble(),
      max: json['max']?.toDouble(),
      avg: json['avg']?.toDouble(),
    );
  }
}

