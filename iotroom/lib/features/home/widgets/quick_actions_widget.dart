import 'package:flutter/material.dart';
// import 'package:flutter/services.dart'; // 震动反馈已禁用
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../room/pages/room_detail_page.dart';

/// ⚡ 快捷操作组件
/// 
/// 【实现说明】
/// 提供常用功能的快捷入口，让用户快速跳转
/// 
/// 设计要点：
/// 1. 图标使用不同颜色区分功能
/// 2. 使用渐变背景增加视觉吸引力
/// 3. 点击有震动反馈
class QuickActionsWidget extends StatelessWidget {
  const QuickActionsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final actions = [
      {
        'icon': PhosphorIconsBold.buildings,
        'label': '设备间',
        'color': AppColors.primary,
        'route': '/rooms',
      },
      {
        'icon': PhosphorIconsBold.warning,
        'label': '告警',
        'color': AppColors.warning,
        'route': '/alarms',
      },
      {
        'icon': PhosphorIconsBold.videoCamera,
        'label': '视频',
        'color': AppColors.info,
        'route': '/video',
      },
      {
        'icon': PhosphorIconsBold.clipboardText,
        'label': '巡检',
        'color': AppColors.success,
        'route': '/inspection',
      },
    ];

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('快捷操作', style: AppTextStyles.h4),
          const SizedBox(height: 16),
          
          // 操作按钮网格
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: actions.map((action) {
              return _buildActionItem(
                context,
                icon: action['icon'] as IconData,
                label: action['label'] as String,
                color: action['color'] as Color,
                onTap: () {
                  // HapticFeedback.lightImpact(); // 震动反馈已禁用
                  if (action['route'] == '/video') {
                    // 视频监控：跳转到设备间详情页（里面有视频）
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const RoomDetailPage(),
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${action['label']}（待开发）')),
                    );
                  }
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  /// 构建单个操作项
  Widget _buildActionItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          // 图标容器
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  color.withOpacity(0.2),
                  color.withOpacity(0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: color.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Icon(
              icon,
              color: color,
              size: 26,
            ),
          ),
          
          const SizedBox(height: 8),
          
          // 标签
          Text(
            label,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
