import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/config/app_config.dart';

/// 门磁传感器服务
/// 
/// 【实现说明】
/// 提供门磁传感器相关的 API 调用：
/// 1. 获取门磁当前状态
/// 2. 获取门磁事件历史
/// 3. 获取统计信息
/// 4. 获取传感器列表
class DoorSensorService {
  /// API 基础地址
  /// 【配置说明】
  /// - 开发环境：使用本地服务器 http://localhost:8900
  /// - 生产环境：使用云服务器地址
  /// - 注意：8080 端口被 WVP 平台占用，改用 8900
  static String get baseUrl => AppConfig.apiBaseUrl;
  
  /// 请求超时时间
  static const Duration timeout = Duration(seconds: 10);

  // ==================== 单例模式 ====================
  
  static final DoorSensorService _instance = DoorSensorService._internal();
  factory DoorSensorService() => _instance;
  DoorSensorService._internal();

  // ==================== API 方法 ====================

  /// 获取门磁当前状态
  /// 
  /// [modbusAddress] Modbus地址（十进制，如 65 对应 0x41）
  Future<DoorStatusData?> getDoorStatus(int modbusAddress) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/door/status/$modbusAddress'),
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return DoorStatusData.fromJson(json);
      } else if (response.statusCode == 404) {
        debugPrint('[DoorSensor] 传感器不存在: $modbusAddress');
        return null;
      } else {
        debugPrint('[DoorSensor] 获取状态失败: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('[DoorSensor] 获取状态异常: $e');
      return null;
    }
  }

  /// 获取门磁事件历史
  /// 
  /// [modbusAddress] Modbus地址
  /// [eventType] 事件类型筛选: 'open' / 'close' / null(全部)
  /// [days] 查询最近几天，默认7天
  /// [limit] 返回数量限制，默认50条
  Future<DoorEventsData?> getDoorEvents({
    required int modbusAddress,
    String? eventType,
    int days = 7,
    int limit = 50,
  }) async {
    try {
      final queryParams = {
        'days': days.toString(),
        'limit': limit.toString(),
      };
      if (eventType != null) {
        queryParams['event_type'] = eventType;
      }

      final uri = Uri.parse('$baseUrl/api/door/events/$modbusAddress')
          .replace(queryParameters: queryParams);
      
      final response = await http.get(uri).timeout(timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return DoorEventsData.fromJson(json);
      } else {
        debugPrint('[DoorSensor] 获取事件失败: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('[DoorSensor] 获取事件异常: $e');
      return null;
    }
  }

  /// 获取门磁统计信息
  /// 
  /// [modbusAddress] Modbus地址
  Future<DoorStatsData?> getDoorStats(int modbusAddress) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/door/stats/$modbusAddress'),
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return DoorStatsData.fromJson(json);
      } else {
        debugPrint('[DoorSensor] 获取统计失败: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('[DoorSensor] 获取统计异常: $e');
      return null;
    }
  }

  /// 获取所有门磁传感器列表
  Future<List<DoorSensorInfo>> getDoorSensors() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/door/sensors'),
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final List sensors = json['sensors'] ?? [];
        return sensors.map((e) => DoorSensorInfo.fromJson(e)).toList();
      } else {
        debugPrint('[DoorSensor] 获取传感器列表失败: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('[DoorSensor] 获取传感器列表异常: $e');
      return [];
    }
  }

  /// 检查 API 服务是否可用
  Future<bool> checkHealth() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/health'),
      ).timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}


// ==================== 数据模型 ====================

/// 门磁当前状态数据
class DoorStatusData {
  final int sensorId;
  final String sensorCode;
  final String sensorName;
  final bool isOpen;
  final bool isOnline;
  final String? lastOpenTime;
  final String? lastCloseTime;
  final int todayOpenCount;
  final int modbusAddress;

  DoorStatusData({
    required this.sensorId,
    required this.sensorCode,
    required this.sensorName,
    required this.isOpen,
    required this.isOnline,
    this.lastOpenTime,
    this.lastCloseTime,
    required this.todayOpenCount,
    required this.modbusAddress,
  });

  factory DoorStatusData.fromJson(Map<String, dynamic> json) {
    return DoorStatusData(
      sensorId: json['sensor_id'] ?? 0,
      sensorCode: json['sensor_code'] ?? '',
      sensorName: json['sensor_name'] ?? '未知传感器',
      isOpen: json['is_open'] ?? false,
      isOnline: json['is_online'] ?? false,
      lastOpenTime: json['last_open_time'],
      lastCloseTime: json['last_close_time'],
      todayOpenCount: json['today_open_count'] ?? 0,
      modbusAddress: json['modbus_address'] ?? 0,
    );
  }
}


/// 门磁事件数据
class DoorEventsData {
  final int sensorId;
  final int total;
  final List<DoorEventItem> events;

  DoorEventsData({
    required this.sensorId,
    required this.total,
    required this.events,
  });

  factory DoorEventsData.fromJson(Map<String, dynamic> json) {
    final List eventsJson = json['events'] ?? [];
    return DoorEventsData(
      sensorId: json['sensor_id'] ?? 0,
      total: json['total'] ?? 0,
      events: eventsJson.map((e) => DoorEventItem.fromJson(e)).toList(),
    );
  }
}


/// 单个门磁事件
class DoorEventItem {
  final int id;
  final String eventType;  // 'open' 或 'close'
  final String eventTime;
  final int? durationSeconds;  // 开门持续秒数（关门事件才有）

  DoorEventItem({
    required this.id,
    required this.eventType,
    required this.eventTime,
    this.durationSeconds,
  });

  factory DoorEventItem.fromJson(Map<String, dynamic> json) {
    return DoorEventItem(
      id: json['id'] ?? 0,
      eventType: json['event_type'] ?? 'unknown',
      eventTime: json['event_time'] ?? '',
      durationSeconds: json['duration_seconds'],
    );
  }

  /// 是否是开门事件
  bool get isOpen => eventType == 'open';

  /// 格式化持续时间
  String? get formattedDuration {
    if (durationSeconds == null) return null;
    
    final minutes = durationSeconds! ~/ 60;
    final seconds = durationSeconds! % 60;
    
    if (minutes > 0) {
      return '$minutes分${seconds}秒';
    } else {
      return '$seconds秒';
    }
  }

  /// 格式化时间（显示用）
  String get formattedTime {
    try {
      final dt = DateTime.parse(eventTime);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final eventDate = DateTime(dt.year, dt.month, dt.day);
      
      final time = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
      
      if (eventDate == today) {
        return '今天 $time';
      } else if (eventDate == today.subtract(const Duration(days: 1))) {
        return '昨天 $time';
      } else {
        return '${dt.month}月${dt.day}日 $time';
      }
    } catch (e) {
      return eventTime;
    }
  }
}


/// 门磁统计数据
class DoorStatsData {
  final int sensorId;
  final int todayOpenCount;
  final int todayCloseCount;
  final int weekOpenCount;
  final int longestOpenMinutes;
  final double avgOpenMinutes;
  final List<DayStats> last7Days;

  DoorStatsData({
    required this.sensorId,
    required this.todayOpenCount,
    required this.todayCloseCount,
    required this.weekOpenCount,
    required this.longestOpenMinutes,
    required this.avgOpenMinutes,
    required this.last7Days,
  });

  factory DoorStatsData.fromJson(Map<String, dynamic> json) {
    final List daysJson = json['last_7_days'] ?? [];
    return DoorStatsData(
      sensorId: json['sensor_id'] ?? 0,
      todayOpenCount: json['today_open_count'] ?? 0,
      todayCloseCount: json['today_close_count'] ?? 0,
      weekOpenCount: json['week_open_count'] ?? 0,
      longestOpenMinutes: json['longest_open_minutes'] ?? 0,
      avgOpenMinutes: (json['avg_open_minutes'] ?? 0).toDouble(),
      last7Days: daysJson.map((e) => DayStats.fromJson(e)).toList(),
    );
  }
}


/// 每日统计
class DayStats {
  final String date;
  final int count;

  DayStats({required this.date, required this.count});

  factory DayStats.fromJson(Map<String, dynamic> json) {
    return DayStats(
      date: json['date'] ?? '',
      count: json['count'] ?? 0,
    );
  }
}


/// 传感器信息
class DoorSensorInfo {
  final int sensorId;
  final String sensorCode;
  final String sensorName;
  final int modbusAddress;
  final int roomId;
  final bool isOpen;
  final bool isOnline;
  final String? lastDataAt;

  DoorSensorInfo({
    required this.sensorId,
    required this.sensorCode,
    required this.sensorName,
    required this.modbusAddress,
    required this.roomId,
    required this.isOpen,
    required this.isOnline,
    this.lastDataAt,
  });

  factory DoorSensorInfo.fromJson(Map<String, dynamic> json) {
    return DoorSensorInfo(
      sensorId: json['sensor_id'] ?? 0,
      sensorCode: json['sensor_code'] ?? '',
      sensorName: json['sensor_name'] ?? '未知',
      modbusAddress: json['modbus_address'] ?? 0,
      roomId: json['room_id'] ?? 0,
      isOpen: json['is_open'] ?? false,
      isOnline: json['is_online'] ?? false,
      lastDataAt: json['last_data_at'],
    );
  }
}

