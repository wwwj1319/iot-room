import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// 📋 设备状态组件
/// 
/// 【实现说明】
/// 展示设备间内各个设备的当前状态
/// - 门：开/关
/// - 照明：开/关
/// - 空调：开/关 + 模式 + 温度
/// - 摄像头：在线/离线
class DeviceStatusWidget extends StatelessWidget {
  final bool doorOpen;
  final bool lightOn;
  final bool acOn;
  final String acMode;
  final int acTemp;
  final bool cameraOnline;
  final VoidCallback? onCameraTap;

  const DeviceStatusWidget({
    super.key,
    required this.doorOpen,
    required this.lightOn,
    required this.acOn,
    required this.acMode,
    required this.acTemp,
    required this.cameraOnline,
    this.onCameraTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 门状态
        Expanded(
          child: _buildStatusItem(
            icon: doorOpen ? PhosphorIconsBold.doorOpen : PhosphorIconsBold.door,
            label: '门',
            status: doorOpen ? '开启' : '关闭',
            color: doorOpen ? AppColors.warning : AppColors.success,
            showWarning: doorOpen,
          ),
        ),
        
        // 照明状态
        Expanded(
          child: _buildStatusItem(
            icon: lightOn ? PhosphorIconsBold.lightbulbFilament : PhosphorIconsRegular.lightbulbFilament,
            label: '照明',
            status: lightOn ? '开启' : '关闭',
            color: lightOn ? AppColors.warning : AppColors.textTertiary,
          ),
        ),
        
        // 空调状态
        Expanded(
          child: _buildStatusItem(
            icon: _getAcIcon(),
            label: '空调',
            status: acOn ? '$acTemp°C' : '关闭',
            color: acOn ? AppColors.info : AppColors.textTertiary,
            subtitle: acOn ? _getAcModeText() : null,
          ),
        ),
        
        // 摄像头状态
        Expanded(
          child: GestureDetector(
            onTap: cameraOnline ? onCameraTap : null,
            child: _buildStatusItem(
              icon: PhosphorIconsBold.videoCamera,
              label: '视频',
              status: cameraOnline ? '在线' : '离线',
              color: cameraOnline ? AppColors.success : AppColors.error,
              showArrow: cameraOnline,
            ),
          ),
        ),
      ],
    );
  }

  /// 获取空调图标
  IconData _getAcIcon() {
    if (!acOn) return PhosphorIconsRegular.fan;
    switch (acMode) {
      case 'cool':
        return PhosphorIconsBold.snowflake;
      case 'heat':
        return PhosphorIconsBold.sun;
      case 'dry':
        return PhosphorIconsBold.drop;
      default:
        return PhosphorIconsBold.fan;
    }
  }

  /// 获取空调模式文字
  String _getAcModeText() {
    switch (acMode) {
      case 'cool':
        return '制冷';
      case 'heat':
        return '制热';
      case 'dry':
        return '除湿';
      default:
        return '自动';
    }
  }

  /// 构建单个状态项
  Widget _buildStatusItem({
    required IconData icon,
    required String label,
    required String status,
    required Color color,
    String? subtitle,
    bool showWarning = false,
    bool showArrow = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          // 图标容器
          Stack(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 24,
                ),
              ),
              
              // 警告角标
              if (showWarning)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: AppColors.warning,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.cardBackground,
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      PhosphorIconsBold.exclamationMark,
                      size: 8,
                      color: Colors.white,
                    ),
                  ),
                ),
                
              // 播放箭头
              if (showArrow)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      PhosphorIconsBold.play,
                      size: 10,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          
          const SizedBox(height: 8),
          
          // 标签
          Text(label, style: AppTextStyles.tiny),
          
          const SizedBox(height: 2),
          
          // 状态值
          Text(
            status,
            style: AppTextStyles.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
          
          // 副标题（空调模式）
          if (subtitle != null)
            Text(
              subtitle,
              style: AppTextStyles.tiny.copyWith(
                color: AppColors.textTertiary,
                fontSize: 10,
              ),
            ),
        ],
      ),
    );
  }
}

