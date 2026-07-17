import 'package:flutter/material.dart';
// import 'package:flutter/services.dart'; // 震动反馈已禁用
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// 🎛️ 设备控制面板组件
/// 
/// 【实现说明】
/// 提供设备远程控制功能：
/// - 照明开关
/// - 空调开关 + 温度调节 + 模式切换
/// 
/// 设计要点：
/// 1. 开关使用自定义的发光效果
/// 2. 温度调节使用 +/- 按钮
/// 3. 模式切换使用 SegmentedButton
/// 4. 操作时有loading状态
class ControlPanelWidget extends StatelessWidget {
  final bool lightOn;
  final bool lightLoading;
  final bool acOn;
  final bool acLoading;
  final int acTemp;
  final String acMode;
  final VoidCallback onLightToggle;
  final VoidCallback onAcToggle;
  final ValueChanged<int> onAcTempChange;
  final ValueChanged<String> onAcModeChange;

  const ControlPanelWidget({
    super.key,
    required this.lightOn,
    required this.lightLoading,
    required this.acOn,
    required this.acLoading,
    required this.acTemp,
    required this.acMode,
    required this.onLightToggle,
    required this.onAcToggle,
    required this.onAcTempChange,
    required this.onAcModeChange,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 照明控制
        _buildLightControl(),
        
        const SizedBox(height: 16),
        
        // 分割线
        Container(
          height: 1,
          color: AppColors.divider,
        ),
        
        const SizedBox(height: 16),
        
        // 空调控制
        _buildAcControl(),
      ],
    );
  }

  /// 构建照明控制
  Widget _buildLightControl() {
    return Row(
      children: [
        // 图标
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: (lightOn ? AppColors.warning : AppColors.textTertiary)
                .withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            lightOn
                ? PhosphorIconsBold.lightbulbFilament
                : PhosphorIconsRegular.lightbulbFilament,
            color: lightOn ? AppColors.warning : AppColors.textTertiary,
            size: 22,
          ),
        ),
        
        const SizedBox(width: 12),
        
        // 标签和状态
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('照明控制', style: AppTextStyles.body),
              Text(
                lightOn ? '已开启' : '已关闭',
                style: AppTextStyles.tiny,
              ),
            ],
          ),
        ),
        
        // 开关按钮
        _buildSwitch(
          value: lightOn,
          loading: lightLoading,
          onTap: onLightToggle,
          activeColor: AppColors.warning,
        ),
      ],
    );
  }

  /// 构建空调控制
  Widget _buildAcControl() {
    return Column(
      children: [
        // 第一行：空调开关
        Row(
          children: [
            // 图标
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: (acOn ? AppColors.info : AppColors.textTertiary)
                    .withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                acOn ? PhosphorIconsBold.snowflake : PhosphorIconsRegular.fan,
                color: acOn ? AppColors.info : AppColors.textTertiary,
                size: 22,
              ),
            ),
            
            const SizedBox(width: 12),
            
            // 标签和状态
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('空调控制', style: AppTextStyles.body),
                  Text(
                    acOn ? '已开启 · ${_getAcModeText()}' : '已关闭',
                    style: AppTextStyles.tiny,
                  ),
                ],
              ),
            ),
            
            // 开关按钮
            _buildSwitch(
              value: acOn,
              loading: acLoading,
              onTap: onAcToggle,
              activeColor: AppColors.info,
            ),
          ],
        ),
        
        // 空调详细控制（仅当空调开启时显示）
        if (acOn) ...[
          const SizedBox(height: 16),
          
          // 温度控制
          _buildTempControl(),
          
          const SizedBox(height: 12),
          
          // 模式控制
          _buildModeControl(),
        ],
      ],
    );
  }

  /// 构建温度控制
  Widget _buildTempControl() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('设定温度', style: AppTextStyles.caption),
          
          // 温度调节
          Row(
            children: [
              // 减少按钮
              _buildTempButton(
                icon: PhosphorIconsBold.minus,
                onTap: acTemp > 16 ? () => onAcTempChange(acTemp - 1) : null,
              ),
              
              // 温度显示
              Container(
                width: 60,
                alignment: Alignment.center,
                child: Text(
                  '$acTemp°C',
                  style: AppTextStyles.h4.copyWith(
                    color: AppColors.info,
                  ),
                ),
              ),
              
              // 增加按钮
              _buildTempButton(
                icon: PhosphorIconsBold.plus,
                onTap: acTemp < 30 ? () => onAcTempChange(acTemp + 1) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 温度调节按钮
  Widget _buildTempButton({
    required IconData icon,
    VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    
    return GestureDetector(
      onTap: () {
        if (enabled) {
          // HapticFeedback.lightImpact(); // 震动反馈已禁用
          onTap();
        }
      },
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: enabled
              ? AppColors.primary.withOpacity(0.15)
              : AppColors.surfaceBackground,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: enabled
                ? AppColors.primary.withOpacity(0.3)
                : AppColors.border,
          ),
        ),
        child: Icon(
          icon,
          size: 18,
          color: enabled ? AppColors.primary : AppColors.textTertiary,
        ),
      ),
    );
  }

  /// 构建模式控制
  Widget _buildModeControl() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _buildModeItem('cool', '制冷', PhosphorIconsBold.snowflake),
          _buildModeItem('heat', '制热', PhosphorIconsBold.sun),
          _buildModeItem('dry', '除湿', PhosphorIconsBold.drop),
        ],
      ),
    );
  }

  /// 模式选项
  Widget _buildModeItem(String mode, String label, IconData icon) {
    final selected = acMode == mode;
    
    return Expanded(
      child: GestureDetector(
        onTap: () {
          // HapticFeedback.lightImpact(); // 震动反馈已禁用
          onAcModeChange(mode);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? Colors.white : AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: AppTextStyles.tiny.copyWith(
                  color: selected ? Colors.white : AppColors.textSecondary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建开关组件
  Widget _buildSwitch({
    required bool value,
    required bool loading,
    required VoidCallback onTap,
    required Color activeColor,
  }) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 56,
        height: 32,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: value ? activeColor : AppColors.surfaceBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: value ? activeColor : AppColors.border,
            width: 1,
          ),
          // 开启时有发光效果
          boxShadow: value
              ? [
                  BoxShadow(
                    color: activeColor.withOpacity(0.4),
                    blurRadius: 8,
                    spreadRadius: 0,
                  ),
                ]
              : null,
        ),
        child: loading
            ? Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: value ? Colors.white : AppColors.textTertiary,
                  ),
                ),
              )
            : AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                alignment:
                    value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

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
}

