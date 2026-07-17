import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../alarm/pages/alarm_history_page.dart';

/// 🚨 告警列表组件
/// 
/// 【实现说明】
/// 这个组件展示最近的告警信息
/// 用于首页快速查看，点击可跳转到告警详情
/// 
/// 设计要点：
/// 1. 告警级别用颜色区分（红/橙/黄）
/// 2. 左侧竖条指示告警级别
/// 3. 时间显示相对时间（如"5分钟前"）
/// 4. 点击整行可查看详情
/// 5. 从自建报警服务器（9090端口）获取数据
class AlarmListWidget extends StatefulWidget {
  const AlarmListWidget({super.key});

  @override
  State<AlarmListWidget> createState() => _AlarmListWidgetState();
}

class _AlarmListWidgetState extends State<AlarmListWidget> {
  /// 报警列表
  List<AlarmEvent> _alarms = [];
  
  /// 是否正在加载
  bool _isLoading = true;
  
  /// 错误信息
  String? _errorMessage;
  
  @override
  void initState() {
    super.initState();
    _loadAlarms();
  }
  
  /// 加载报警数据（从 9090 端口的报警服务器获取）
  Future<void> _loadAlarms() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      debugPrint('[AlarmListWidget] 开始加载报警数据...');
      
      final response = await http.get(
        Uri.parse(AlarmServerConfig.alarmsApi),
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> alarmList = data['data'] ?? [];
        
        // 获取全部报警记录
        final alarms = alarmList
            .map((json) => AlarmEvent.fromJson(json))
            .toList();
        
        debugPrint('[AlarmListWidget] 获取到 ${alarms.length} 条报警');
        
        if (mounted) {
          setState(() {
            _alarms = alarms;
            _isLoading = false;
          });
        }
      } else {
        throw Exception('服务器返回 ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[AlarmListWidget] 加载报警失败: $e');
      if (mounted) {
        setState(() {
          _errorMessage = null;  // 不显示错误，只显示空列表
          _alarms = [];
          _isLoading = false;
        });
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      PhosphorIconsBold.warning,
                      color: AppColors.warning,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text('最新告警', style: AppTextStyles.h4),
                    const SizedBox(width: 8),
                    // 显示报警数量
                    if (!_isLoading && _alarms.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.error.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${_alarms.length}',
                          style: AppTextStyles.tiny.copyWith(color: AppColors.error),
                        ),
                      ),
                  ],
                ),
                Row(
                  children: [
                    // 刷新按钮
                    IconButton(
                      onPressed: _isLoading ? null : _loadAlarms,
                      icon: _isLoading 
                          ? const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(PhosphorIconsBold.arrowClockwise, size: 18),
                      tooltip: '刷新',
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.zero,
                    ),
                    TextButton(
                      onPressed: () {
                        // TODO: 跳转到告警列表
                        // HapticFeedback.lightImpact(); // 震动反馈已禁用
                      },
                      child: Text(
                        '查看全部',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // 加载状态
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('正在加载报警数据...'),
                  ],
                ),
              ),
            )
          // 错误状态
          else if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      PhosphorIconsBold.warningCircle,
                      color: AppColors.error,
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: _loadAlarms,
                      icon: const Icon(PhosphorIconsBold.arrowClockwise, size: 16),
                      label: const Text('重试'),
                    ),
                  ],
                ),
              ),
            )
          // 空状态
          else if (_alarms.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      PhosphorIconsBold.checkCircle,
                      color: AppColors.success,
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '暂无告警，一切正常',
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            )
          // 报警列表
          else
            ..._alarms.map((alarm) => _buildAlarmItem(context, alarm)),
        ],
      ),
    );
  }

  /// 构建单个告警项
  Widget _buildAlarmItem(BuildContext context, AlarmEvent alarm) {
    final isFireAlarm = alarm.isFireAlarm;
    final levelColor = isFireAlarm ? AppColors.error : AppColors.warning;
    
    return InkWell(
      onTap: () {
        _showAlarmDetail(context, alarm);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: AppColors.divider, width: 1),
          ),
          color: isFireAlarm ? AppColors.error.withOpacity(0.1) : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 左侧：级别指示条
            Container(
              width: 4,
              height: 48,
              decoration: BoxDecoration(
                color: levelColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            const SizedBox(width: 12),
            
            // 中间：告警信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 第一行：标题 + 状态标签
                  Row(
                    children: [
                      if (isFireAlarm) ...[
                        const Icon(PhosphorIconsBold.fire, size: 16, color: AppColors.error),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          alarm.eventName,
                          style: AppTextStyles.body.copyWith(
                            color: isFireAlarm ? AppColors.error : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildLevelBadge(
                        alarm.isResolved ? '已恢复' : '进行中', 
                        alarm.isResolved ? AppColors.success : levelColor,
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 4),
                  
                  // 第二行：设备 + 时间
                  Row(
                    children: [
                      Icon(
                        PhosphorIconsRegular.camera,
                        size: 14,
                        color: AppColors.textTertiary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          alarm.channelName.isNotEmpty ? alarm.channelName : alarm.deviceID,
                          style: AppTextStyles.tiny,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        PhosphorIconsRegular.clock,
                        size: 14,
                        color: AppColors.textTertiary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        alarm.formattedStartTime,
                        style: AppTextStyles.tiny,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            // 右侧：箭头
            const Icon(
              PhosphorIconsRegular.caretRight,
              size: 20,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
  
  /// 显示报警详情
  void _showAlarmDetail(BuildContext context, AlarmEvent alarm) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: alarm.isFireAlarm ? AppColors.error : AppColors.warning,
            width: 2,
          ),
        ),
        title: Row(
          children: [
            Icon(
              alarm.isFireAlarm ? PhosphorIconsBold.fire : PhosphorIconsBold.warning,
              color: alarm.isFireAlarm ? AppColors.error : AppColors.warning,
              size: 24,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                alarm.eventName,
                style: AppTextStyles.h4.copyWith(
                  color: alarm.isFireAlarm ? AppColors.error : AppColors.warning,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 显示截图（如果有）
              if (alarm.startImage != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    AlarmServerConfig.imageUrl(alarm.startImage),
                    height: 150,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 100,
                      color: AppColors.surfaceBackground,
                      child: const Center(
                        child: Icon(PhosphorIconsBold.imageSquare, color: AppColors.textTertiary),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              _buildDetailRow('设备编号', alarm.deviceID),
              _buildDetailRow('通道名称', alarm.channelName),
              _buildDetailRow('开始时间', alarm.formattedStartTime),
              if (alarm.endTime != null)
                _buildDetailRow('结束时间', alarm.formattedEndTime),
              _buildDetailRow('状态', alarm.isResolved ? '已恢复' : '进行中'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
  
  /// 构建详情行
  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              '$label:',
              style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: AppTextStyles.caption.copyWith(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
  
  /// 构建级别标签
  Widget _buildLevelBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: AppTextStyles.tiny.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

}

