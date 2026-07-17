import 'package:flutter/material.dart';
import 'app_colors.dart';

/// 📝 应用字体样式
/// 
/// 1. 视觉一致性：整个APP的字体大小、粗细保持统一
/// 2. 易于维护：想调整字体，只改这一个文件
/// 3. 语义化：h1、h2、body 这样的命名比 fontSize: 24 更好理解
/// 
/// 字体大小规范（参考 Material Design）：
/// - 大标题：28px
/// - 二级标题：22px
/// - 三级标题：18px
/// - 正文：15px
/// - 小字：13px
/// - 极小字：11px
class AppTextStyles {
  AppTextStyles._();

  // ==================== 标题样式 ====================
  
  /// 大标题 - 用于页面标题
  static const TextStyle h1 = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.5,
    height: 1.2,
  );

  /// 二级标题 - 用于卡片标题、区块标题
  static const TextStyle h2 = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.3,
  );

  /// 三级标题 - 用于列表项标题
  static const TextStyle h3 = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.4,
  );

  /// 四级标题 - 用于小标题
  static const TextStyle h4 = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.4,
  );

  // ==================== 正文样式 ====================
  
  /// 正文 - 主要内容
  static const TextStyle body = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 1.5,
  );

  /// 正文加粗
  static const TextStyle bodyBold = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.5,
  );

  /// 小字 - 辅助信息、时间戳
  static const TextStyle caption = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.4,
  );

  /// 极小字 - 角标、标签
  static const TextStyle tiny = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
    height: 1.2,
  );

  // ==================== 数字样式 ====================
  
  /// 大数字 - 仪表盘核心数据
  /// 【实现说明】数字用等宽字体更好看，宽度一致不会跳动
  static const TextStyle numberLarge = TextStyle(
    fontSize: 48,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -2,
    height: 1.0,
    // 如果有自定义等宽字体，可以在这里设置
    // fontFamily: 'JetBrains Mono',
  );

  /// 中等数字 - 统计卡片
  static const TextStyle numberMedium = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -1,
    height: 1.0,
  );

  /// 小数字 - 列表中的数据
  static const TextStyle numberSmall = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.2,
  );

  // ==================== 按钮样式 ====================
  
  /// 按钮文字
  static const TextStyle button = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    letterSpacing: 0.5,
  );

  /// 小按钮文字
  static const TextStyle buttonSmall = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  // ==================== 辅助方法 ====================
  
  /// 快速修改颜色
  static TextStyle withColor(TextStyle style, Color color) {
    return style.copyWith(color: color);
  }
}

