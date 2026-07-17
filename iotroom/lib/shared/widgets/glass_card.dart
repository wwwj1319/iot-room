import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// 🪟 玻璃拟态卡片组件
/// 
/// 【实现说明】
/// 什么是玻璃拟态（Glassmorphism）？
/// - 一种现代UI设计风格
/// - 特点：半透明背景 + 模糊效果 + 微妙边框 + 柔和阴影
/// - 让界面有层次感和深度感
/// 
/// 这个组件的设计要点：
/// 1. 使用半透明背景色（withOpacity）
/// 2. 添加白色微妙边框（增加玻璃感）
/// 3. 柔和的阴影（不要太重）
/// 4. 圆角统一为16px
/// 
/// 使用场景：
/// - 统计卡片
/// - 设备状态卡片
/// - 信息展示区块
class GlassCard extends StatelessWidget {
  /// 子组件
  final Widget child;
  
  /// 内边距，默认16
  final EdgeInsetsGeometry? padding;
  
  /// 外边距
  final EdgeInsetsGeometry? margin;
  
  /// 圆角大小，默认16
  final double borderRadius;
  
  /// 背景色，默认使用卡片背景色
  final Color? backgroundColor;
  
  /// 边框颜色
  final Color? borderColor;
  
  /// 点击事件
  final VoidCallback? onTap;
  
  /// 是否显示阴影
  final bool showShadow;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = 16,
    this.backgroundColor,
    this.borderColor,
    this.onTap,
    this.showShadow = true,
  });

  @override
  Widget build(BuildContext context) {
    // 卡片内容
    Widget content = Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        // 半透明背景 - 这是玻璃效果的关键
        color: (backgroundColor ?? AppColors.cardBackground).withOpacity(0.8),
        
        // 统一圆角
        borderRadius: BorderRadius.circular(borderRadius),
        
        // 微妙的边框 - 增加玻璃质感
        border: Border.all(
          color: borderColor ?? Colors.white.withOpacity(0.1),
          width: 1,
        ),
        
        // 柔和阴影
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                  spreadRadius: -5,
                ),
              ]
            : null,
      ),
      child: child,
    );

    // 如果有外边距，包裹Padding
    if (margin != null) {
      content = Padding(padding: margin!, child: content);
    }

    // 如果有点击事件，包裹InkWell
    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(borderRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(borderRadius),
          // 点击时的水波纹颜色
          splashColor: AppColors.primary.withOpacity(0.1),
          highlightColor: AppColors.primary.withOpacity(0.05),
          child: content,
        ),
      );
    }

    return content;
  }
}

/// 🎯 带渐变边框的玻璃卡片
/// 
/// 【实现说明】
/// 这是一个变体，边框使用渐变色
/// 用于突出显示重要的卡片（如当前选中项）
class GradientBorderCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final double borderWidth;
  final Gradient gradient;
  final VoidCallback? onTap;

  const GradientBorderCard({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = 16,
    this.borderWidth = 2,
    this.gradient = AppColors.primaryGradient,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: gradient,
      ),
      padding: EdgeInsets.all(borderWidth),
      child: GlassCard(
        padding: padding,
        borderRadius: borderRadius - borderWidth,
        borderColor: Colors.transparent,
        showShadow: false,
        onTap: onTap,
        child: child,
      ),
    );
  }
}

