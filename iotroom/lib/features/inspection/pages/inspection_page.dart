import 'package:flutter/material.dart';
// import 'package:flutter/services.dart'; // 震动反馈已禁用
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/glass_card.dart';
import '../widgets/calendar_heatmap.dart';
import '../widgets/day_detail_sheet.dart';

/// 📅 巡检日历页面
/// 
/// 【实现说明】
/// 这是一个特色功能页面，用日历热力图展示设备状态：
/// - 🟢 绿色：当天所有设备正常
/// - 🔴 红色：当天有异常/告警
/// - 🟡 黄色：待巡检（计划中未完成）
/// - ⚪ 灰色：无数据
/// 
/// 点击日期可查看当天的详细检测数据。
/// 
/// 技术要点：
/// 1. 自定义日历组件（不使用第三方库，更灵活）
/// 2. 热力图颜色映射
/// 3. 月份切换动画
/// 4. 底部弹窗展示详情
class InspectionPage extends StatefulWidget {
  const InspectionPage({super.key});

  @override
  State<InspectionPage> createState() => _InspectionPageState();
}

class _InspectionPageState extends State<InspectionPage> {
  // 当前显示的月份
  late DateTime _currentMonth;
  
  // 模拟的巡检数据
  // key: 日期字符串 (yyyy-MM-dd)
  // value: 状态 (0=无数据, 1=正常, 2=异常, 3=待巡检)
  final Map<String, int> _inspectionData = {};
  
  // 月度统计
  int _normalDays = 0;
  int _abnormalDays = 0;
  int _pendingDays = 0;

  @override
  void initState() {
    super.initState();
    _currentMonth = DateTime.now();
    _generateMockData();
  }

  /// 生成模拟数据
  void _generateMockData() {
    final now = DateTime.now();
    
    // 生成当月和上月的模拟数据
    for (int monthOffset = -1; monthOffset <= 0; monthOffset++) {
      final month = DateTime(now.year, now.month + monthOffset, 1);
      final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
      
      for (int day = 1; day <= daysInMonth; day++) {
        final date = DateTime(month.year, month.month, day);
        
        // 跳过未来日期
        if (date.isAfter(now)) {
          // 未来几天设为待巡检
          if (date.difference(now).inDays <= 3) {
            _inspectionData[_formatDate(date)] = 3; // 待巡检
          }
          continue;
        }
        
        // 周末无数据
        if (date.weekday == 6 || date.weekday == 7) {
          _inspectionData[_formatDate(date)] = 0;
          continue;
        }
        
        // 随机生成状态（大部分正常，少量异常）
        final random = date.day % 10;
        if (random == 3 || random == 7) {
          _inspectionData[_formatDate(date)] = 2; // 异常
        } else {
          _inspectionData[_formatDate(date)] = 1; // 正常
        }
      }
    }
    
    _calculateStats();
  }

  /// 计算月度统计
  void _calculateStats() {
    _normalDays = 0;
    _abnormalDays = 0;
    _pendingDays = 0;
    
    final daysInMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 0).day;
    
    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_currentMonth.year, _currentMonth.month, day);
      final status = _inspectionData[_formatDate(date)] ?? 0;
      
      switch (status) {
        case 1:
          _normalDays++;
          break;
        case 2:
          _abnormalDays++;
          break;
        case 3:
          _pendingDays++;
          break;
      }
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 顶部标题栏
        _buildHeader(),
        
        // 内容区域
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 月度统计卡片
                _buildStatsCard(),
                
                const SizedBox(height: 16),
                
                // 日历热力图
                _buildCalendarCard(),
                
                const SizedBox(height: 16),
                
                // 图例说明
                _buildLegend(),
                
                const SizedBox(height: 16),
                
                // 最近异常记录
                _buildRecentAbnormal(),
                
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 构建顶部标题栏
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(
          bottom: BorderSide(
            color: AppColors.border.withOpacity(0.5),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            PhosphorIconsBold.calendarCheck,
            color: AppColors.primary,
            size: 24,
          ),
          const SizedBox(width: 12),
          Text('巡检日历', style: AppTextStyles.h3),
          const Spacer(),
          // 今日按钮
          GestureDetector(
            onTap: () {
              // HapticFeedback.lightImpact(); // 震动反馈已禁用
              setState(() {
                _currentMonth = DateTime.now();
                _calculateStats();
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '今日',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建月度统计卡片
  Widget _buildStatsCard() {
    final totalDays = _normalDays + _abnormalDays;
    final normalRate = totalDays > 0 ? (_normalDays / totalDays * 100).toStringAsFixed(1) : '0';
    
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('本月概况', style: AppTextStyles.h4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '正常率 $normalRate%',
                  style: AppTextStyles.tiny.copyWith(
                    color: AppColors.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  icon: PhosphorIconsBold.checkCircle,
                  color: AppColors.success,
                  value: _normalDays.toString(),
                  label: '正常天数',
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  icon: PhosphorIconsBold.warningCircle,
                  color: AppColors.error,
                  value: _abnormalDays.toString(),
                  label: '异常天数',
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  icon: PhosphorIconsBold.clock,
                  color: AppColors.warning,
                  value: _pendingDays.toString(),
                  label: '待巡检',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required Color color,
    required String value,
    required String label,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: AppTextStyles.h2.copyWith(color: color),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: AppTextStyles.tiny.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }

  /// 构建日历卡片
  Widget _buildCalendarCard() {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 月份切换
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () {
                  // HapticFeedback.lightImpact(); // 震动反馈已禁用
                  setState(() {
                    _currentMonth = DateTime(
                      _currentMonth.year,
                      _currentMonth.month - 1,
                    );
                    _calculateStats();
                  });
                },
                icon: const Icon(
                  PhosphorIconsBold.caretLeft,
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                '${_currentMonth.year}年${_currentMonth.month}月',
                style: AppTextStyles.h4,
              ),
              IconButton(
                onPressed: () {
                  // HapticFeedback.lightImpact(); // 震动反馈已禁用
                  // 不能超过当前月份后一个月
                  final maxMonth = DateTime(
                    DateTime.now().year,
                    DateTime.now().month + 1,
                  );
                  if (_currentMonth.isBefore(maxMonth)) {
                    setState(() {
                      _currentMonth = DateTime(
                        _currentMonth.year,
                        _currentMonth.month + 1,
                      );
                      _calculateStats();
                    });
                  }
                },
                icon: Icon(
                  PhosphorIconsBold.caretRight,
                  color: _canGoNext() 
                      ? AppColors.textSecondary 
                      : AppColors.textTertiary,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // 日历热力图
          CalendarHeatmap(
            month: _currentMonth,
            data: _inspectionData,
            onDayTap: _showDayDetail,
          ),
        ],
      ),
    );
  }

  bool _canGoNext() {
    final maxMonth = DateTime(
      DateTime.now().year,
      DateTime.now().month + 1,
    );
    return _currentMonth.isBefore(maxMonth);
  }

  /// 构建图例
  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildLegendItem(AppColors.success, '正常'),
          _buildLegendItem(AppColors.error, '异常'),
          _buildLegendItem(AppColors.warning, '待巡检'),
          _buildLegendItem(AppColors.border, '无数据'),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: AppTextStyles.tiny.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }

  /// 构建最近异常记录
  Widget _buildRecentAbnormal() {
    // 获取最近的异常记录
    final abnormalDates = _inspectionData.entries
        .where((e) => e.value == 2)
        .map((e) => e.key)
        .toList()
      ..sort((a, b) => b.compareTo(a));
    
    final recentAbnormal = abnormalDates.take(3).toList();
    
    if (recentAbnormal.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                PhosphorIconsBold.warningCircle,
                color: AppColors.error,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text('最近异常', style: AppTextStyles.h4),
            ],
          ),
          
          const SizedBox(height: 12),
          
          ...recentAbnormal.map((date) => _buildAbnormalItem(date)),
        ],
      ),
    );
  }

  Widget _buildAbnormalItem(String date) {
    return GestureDetector(
      onTap: () {
        // HapticFeedback.lightImpact(); // 震动反馈已禁用
        final parts = date.split('-');
        final dateTime = DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        );
        _showDayDetail(dateTime);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.error.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppColors.error.withOpacity(0.2),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                PhosphorIconsBold.warning,
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
                    date,
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '温度超限告警 2次',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.error,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              PhosphorIconsBold.caretRight,
              color: AppColors.textTertiary,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  /// 显示日期详情
  void _showDayDetail(DateTime date) {
    // HapticFeedback.lightImpact(); // 震动反馈已禁用
    
    final status = _inspectionData[_formatDate(date)] ?? 0;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DayDetailSheet(
        date: date,
        status: status,
      ),
    );
  }
}

