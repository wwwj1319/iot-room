import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import 'glass_card.dart';

/// 📊 统计卡片组件
/// 
/// 【实现说明】
/// 这是首页仪表板最常用的组件之一
/// 用于展示：设备数量、告警数量、在线率等统计数据
/// 
/// 设计要点：
/// 1. 图标使用渐变背景圆形，增加视觉吸引力
/// 2. 数字使用大号字体，一眼就能看到
/// 3. 标题使用次要颜色，不抢数字的风头
/// 4. 可选的趋势指示（+12%↑ 或 -5%↓）
class StatCard extends StatelessWidget {
  /// 标题（如"设备总数"）
  final String title;
  
  /// 数值（如"128"）
  final String value;
  
  /// 图标
  final IconData icon;
  
  /// 图标背景色
  final Color color;
  
  /// 趋势文本（可选，如"+12%"）
  final String? trend;
  
  /// 趋势是否为正向（true=绿色上升，false=红色下降）
  final bool? trendPositive;
  
  /// 点击事件
  final VoidCallback? onTap;

  const StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.trend,
    this.trendPositive,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 顶部：图标 + 趋势
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 图标容器 - 使用渐变背景
              _buildIconContainer(),
              
              // 趋势指示（如果有）
              if (trend != null) _buildTrendBadge(),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // 数值 - 大号字体突出显示
          Text(
            value,
            style: AppTextStyles.numberMedium,
          ),
          
          const SizedBox(height: 4),
          
          // 标题 - 次要颜色
          Text(
            title,
            style: AppTextStyles.caption,
          ),
        ],
      ),
    );
  }

  /// 构建图标容器
  /// 【实现说明】使用渐变背景让图标更突出
  Widget _buildIconContainer() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        // 使用传入颜色的渐变
        gradient: LinearGradient(
          colors: [
            color.withOpacity(0.8),
            color.withOpacity(0.4),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        icon,
        color: Colors.white,
        size: 24,
      ),
    );
  }

  /// 构建趋势指示标签
  Widget _buildTrendBadge() {
    final isPositive = trendPositive ?? true;
    final trendColor = isPositive ? AppColors.success : AppColors.error;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: trendColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPositive 
                ? PhosphorIconsBold.trendUp 
                : PhosphorIconsBold.trendDown,
            size: 14,
            color: trendColor,
          ),
          const SizedBox(width: 4),
          Text(
            trend!,
            style: AppTextStyles.tiny.copyWith(
              color: trendColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// 📊 紧凑型统计卡片
/// 
/// 用于一行显示多个统计数据的场景
class CompactStatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const CompactStatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 小图标
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        // 文字信息
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value, style: AppTextStyles.h4),
            Text(title, style: AppTextStyles.tiny),
          ],
        ),
      ],
    );
  }
}

