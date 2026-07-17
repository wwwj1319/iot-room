import 'package:flutter/material.dart';
// import 'package:flutter/services.dart'; // 震动反馈已禁用
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// 📋 日期详情弹窗
/// 
/// 【实现说明】
/// 点击日历中的某一天后，弹出此弹窗展示当天的详细检测数据：
/// - 各设备间的状态
/// - 异常设备高亮
/// - 告警详情
/// - 可跳转到具体设备间查看
class DayDetailSheet extends StatelessWidget {
  final DateTime date;
  final int status; // 0=无数据, 1=正常, 2=异常, 3=待巡检

  const DayDetailSheet({
    super.key,
    required this.date,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // 拖动条
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            
            // 标题区域
            _buildHeader(context),
            
            const Divider(color: AppColors.border, height: 1),
            
            // 内容区域
            Expanded(
              child: _buildContent(scrollController),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建标题区域
  Widget _buildHeader(BuildContext context) {
    final statusInfo = _getStatusInfo();
    final weekday = _getWeekday(date.weekday);
    
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 12, 16),
      child: Row(
        children: [
          // 日期信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '${date.month}月${date.day}日',
                      style: AppTextStyles.h2,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      weekday,
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: statusInfo['color'] as Color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      statusInfo['text'] as String,
                      style: AppTextStyles.caption.copyWith(
                        color: statusInfo['color'] as Color,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // 关闭按钮
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(
              PhosphorIconsBold.x,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建内容区域
  Widget _buildContent(ScrollController scrollController) {
    if (status == 0) {
      return _buildNoData();
    }
    
    if (status == 3) {
      return _buildPending();
    }
    
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(20),
      children: [
        // 概览统计
        _buildOverview(),
        
        const SizedBox(height: 20),
        
        // 设备间状态列表
        Text(
          '设备间状态',
          style: AppTextStyles.h4.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        
        // 设备间列表
        ..._getMockRoomData().map((room) => _buildRoomItem(room)),
        
        // 如果有异常，显示告警详情
        if (status == 2) ...[
          const SizedBox(height: 20),
          Text(
            '告警详情',
            style: AppTextStyles.h4.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          ..._getMockAlarms().map((alarm) => _buildAlarmItem(alarm)),
        ],
        
        const SizedBox(height: 20),
      ],
    );
  }

  /// 无数据状态
  Widget _buildNoData() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            PhosphorIconsBold.calendarX,
            size: 64,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: 16),
          Text(
            '该日期无巡检数据',
            style: AppTextStyles.body.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '可能是休息日或系统未运行',
            style: AppTextStyles.caption,
          ),
        ],
      ),
    );
  }

  /// 待巡检状态
  Widget _buildPending() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              PhosphorIconsBold.clock,
              size: 48,
              color: AppColors.warning,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '待巡检',
            style: AppTextStyles.h3.copyWith(
              color: AppColors.warning,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '该日期的巡检计划尚未完成',
            style: AppTextStyles.caption,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              // HapticFeedback.lightImpact(); // 震动反馈已禁用
              // TODO: 跳转到巡检任务
            },
            icon: const Icon(PhosphorIconsBold.clipboardText),
            label: const Text('查看巡检任务'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 概览统计
  Widget _buildOverview() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildOverviewItem(
              icon: PhosphorIconsBold.buildings,
              value: '5',
              label: '设备间',
              color: AppColors.primary,
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: AppColors.border,
          ),
          Expanded(
            child: _buildOverviewItem(
              icon: PhosphorIconsBold.checkCircle,
              value: status == 1 ? '5' : '4',
              label: '正常',
              color: AppColors.success,
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: AppColors.border,
          ),
          Expanded(
            child: _buildOverviewItem(
              icon: PhosphorIconsBold.warning,
              value: status == 1 ? '0' : '1',
              label: '异常',
              color: AppColors.error,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewItem({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTextStyles.h3.copyWith(color: color),
        ),
        Text(
          label,
          style: AppTextStyles.tiny.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }

  /// 设备间状态项
  Widget _buildRoomItem(Map<String, dynamic> room) {
    final hasAlarm = room['hasAlarm'] as bool;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: hasAlarm 
            ? AppColors.error.withOpacity(0.1)
            : AppColors.surfaceBackground,
        borderRadius: BorderRadius.circular(12),
        border: hasAlarm
            ? Border.all(color: AppColors.error.withOpacity(0.3))
            : null,
      ),
      child: Row(
        children: [
          // 状态图标
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: hasAlarm
                  ? AppColors.error.withOpacity(0.15)
                  : AppColors.success.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              hasAlarm 
                  ? PhosphorIconsBold.warning
                  : PhosphorIconsBold.checkCircle,
              color: hasAlarm ? AppColors.error : AppColors.success,
              size: 20,
            ),
          ),
          
          const SizedBox(width: 12),
          
          // 设备间信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  room['name'] as String,
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  room['location'] as String,
                  style: AppTextStyles.tiny.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          
          // 温湿度数据
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    PhosphorIconsBold.thermometerHot,
                    size: 14,
                    color: (room['temp'] as double) > 30 
                        ? AppColors.error 
                        : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${room['temp']}°C',
                    style: AppTextStyles.caption.copyWith(
                      color: (room['temp'] as double) > 30 
                          ? AppColors.error 
                          : AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    PhosphorIconsBold.drop,
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${room['humidity']}%',
                    style: AppTextStyles.caption.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
          
          const SizedBox(width: 8),
          
          Icon(
            PhosphorIconsBold.caretRight,
            color: AppColors.textTertiary,
            size: 16,
          ),
        ],
      ),
    );
  }

  /// 告警项
  Widget _buildAlarmItem(Map<String, dynamic> alarm) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              PhosphorIconsBold.bellRinging,
              color: AppColors.error,
              size: 18,
            ),
          ),
          
          const SizedBox(width: 12),
          
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alarm['title'] as String,
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.error,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  alarm['description'] as String,
                  style: AppTextStyles.caption,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      PhosphorIconsBold.clock,
                      size: 12,
                      color: AppColors.textTertiary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      alarm['time'] as String,
                      style: AppTextStyles.tiny.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: (alarm['handled'] as bool)
                            ? AppColors.success.withOpacity(0.1)
                            : AppColors.warning.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        (alarm['handled'] as bool) ? '已处理' : '待处理',
                        style: AppTextStyles.tiny.copyWith(
                          color: (alarm['handled'] as bool)
                              ? AppColors.success
                              : AppColors.warning,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 获取状态信息
  Map<String, dynamic> _getStatusInfo() {
    switch (status) {
      case 1:
        return {'color': AppColors.success, 'text': '全部正常'};
      case 2:
        return {'color': AppColors.error, 'text': '存在异常'};
      case 3:
        return {'color': AppColors.warning, 'text': '待巡检'};
      default:
        return {'color': AppColors.textTertiary, 'text': '无数据'};
    }
  }

  /// 获取星期几
  String _getWeekday(int weekday) {
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return weekdays[weekday - 1];
  }

  /// 模拟设备间数据
  List<Map<String, dynamic>> _getMockRoomData() {
    return [
      {
        'name': '配电间 A-101',
        'location': 'A栋 1楼',
        'temp': 26.5,
        'humidity': 55,
        'hasAlarm': false,
      },
      {
        'name': '配电间 A-103',
        'location': 'A栋 1楼',
        'temp': status == 2 ? 36.5 : 27.0, // 异常状态时温度超标
        'humidity': 60,
        'hasAlarm': status == 2,
      },
      {
        'name': '配电间 B-201',
        'location': 'B栋 2楼',
        'temp': 25.8,
        'humidity': 52,
        'hasAlarm': false,
      },
      {
        'name': '配电间 B-205',
        'location': 'B栋 2楼',
        'temp': 28.2,
        'humidity': 58,
        'hasAlarm': false,
      },
      {
        'name': '配电间 C-301',
        'location': 'C栋 3楼',
        'temp': 27.5,
        'humidity': 54,
        'hasAlarm': false,
      },
    ];
  }

  /// 模拟告警数据
  List<Map<String, dynamic>> _getMockAlarms() {
    return [
      {
        'title': '温度超限告警',
        'description': '配电间 A-103 温度达到 36.5°C，超过阈值 35°C',
        'time': '14:32:15',
        'handled': true,
      },
      {
        'title': '温度预警',
        'description': '配电间 A-103 温度持续偏高，建议检查空调',
        'time': '14:45:22',
        'handled': false,
      },
    ];
  }
}

