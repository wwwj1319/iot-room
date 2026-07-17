import 'package:flutter/material.dart';

/// 🎨 应用配色方案
/// 
/// 1. 统一管理：所有颜色在一个地方，修改方便
/// 2. 主题切换：如果要做浅色主题，只需要改这个文件
/// 3. 代码规范：避免在代码中写死颜色值（如 Color(0xFF123456)）
/// 
/// 我们采用深色主题，原因：
/// - 监控类应用深色更专业
/// - 数据可视化在深色背景上更突出
/// - 长时间看屏幕更护眼
class AppColors {
  AppColors._(); // 私有构造函数，防止实例化

  // ==================== 背景色 ====================
  /// 主背景色 - 深邃蓝黑
  static const Color background = Color(0xFF0D1117);
  
  /// 卡片背景色 - 比背景稍亮
  static const Color cardBackground = Color(0xFF161B22);
  
  /// 浮层背景色 - 弹窗、抽屉等
  static const Color surfaceBackground = Color(0xFF21262D);

  // ==================== 主色调 ====================
  /// 主色 - 亮青色（渐变起点）
  static const Color primary = Color(0xFF00D4FF);
  
  /// 主色深 - 深蓝色（渐变终点）
  static const Color primaryDark = Color(0xFF0066FF);
  
  /// 主色渐变
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, primaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ==================== 强调色 ====================
  /// 强调色 - 紫色（渐变起点）
  static const Color accent = Color(0xFF7C3AED);
  
  /// 强调色 - 粉色（渐变终点）
  static const Color accentPink = Color(0xFFDB2777);
  
  /// 强调色渐变 - 用于重要按钮
  static const LinearGradient accentGradient = LinearGradient(
    colors: [accent, accentPink],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ==================== 功能色 ====================
  /// 成功色 - 翠绿
  static const Color success = Color(0xFF10B981);
  
  /// 警告色 - 琥珀
  static const Color warning = Color(0xFFF59E0B);
  
  /// 错误色 - 红色
  static const Color error = Color(0xFFEF4444);
  
  /// 信息色 - 蓝色
  static const Color info = Color(0xFF3B82F6);

  // ==================== 告警级别色 ====================
  /// 紧急告警 - 红色
  static const Color alarmUrgent = Color(0xFFEF4444);
  
  /// 重要告警 - 橙色
  static const Color alarmImportant = Color(0xFFF97316);
  
  /// 一般告警 - 黄色
  static const Color alarmNormal = Color(0xFFFBBF24);

  // ==================== 设备状态色 ====================
  /// 在线 - 绿色
  static const Color online = Color(0xFF10B981);
  
  /// 离线 - 灰色
  static const Color offline = Color(0xFF6B7280);
  
  /// 告警中 - 红色
  static const Color alarming = Color(0xFFEF4444);

  // ==================== 文字色 ====================
  /// 主要文字 - 白色
  static const Color textPrimary = Color(0xFFF9FAFB);
  
  /// 次要文字 - 浅灰
  static const Color textSecondary = Color(0xFF9CA3AF);
  
  /// 辅助文字 - 深灰
  static const Color textTertiary = Color(0xFF6B7280);
  
  /// 禁用文字
  static const Color textDisabled = Color(0xFF4B5563);

  // ==================== 边框和分割线 ====================
  /// 边框色
  static const Color border = Color(0xFF30363D);
  
  /// 分割线色
  static const Color divider = Color(0xFF21262D);

  // ==================== 辅助方法 ====================
  
  /// 根据告警级别获取颜色
  /// [level] 1=紧急 2=重要 3=一般
  static Color getAlarmColor(int level) {
    switch (level) {
      case 1:
        return alarmUrgent;
      case 2:
        return alarmImportant;
      case 3:
        return alarmNormal;
      default:
        return alarmNormal;
    }
  }

  /// 根据设备状态获取颜色
  /// [status] 0=离线 1=在线 2=告警
  static Color getDeviceStatusColor(int status) {
    switch (status) {
      case 0:
        return offline;
      case 1:
        return online;
      case 2:
        return alarming;
      default:
        return offline;
    }
  }
}

