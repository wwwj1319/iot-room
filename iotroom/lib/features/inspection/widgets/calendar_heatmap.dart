import 'package:flutter/material.dart';
// import 'package:flutter/services.dart'; // 震动反馈已禁用
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// 📅 日历热力图组件
/// 
/// 【实现说明】
/// 这是一个自定义日历组件，用热力图颜色展示每天的状态：
/// - status 0: 无数据（灰色）
/// - status 1: 正常（绿色）
/// - status 2: 异常（红色）
/// - status 3: 待巡检（黄色）
/// 
/// 技术要点：
/// 1. 使用 GridView 布局日期
/// 2. 计算每月第一天是周几，正确对齐
/// 3. 今天的日期特殊标记
/// 4. 点击日期触发回调
class CalendarHeatmap extends StatelessWidget {
  /// 显示的月份
  final DateTime month;
  
  /// 状态数据 Map<日期字符串, 状态>
  final Map<String, int> data;
  
  /// 日期点击回调
  final ValueChanged<DateTime>? onDayTap;

  const CalendarHeatmap({
    super.key,
    required this.month,
    required this.data,
    this.onDayTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 星期标题行
        _buildWeekdayHeader(),
        
        const SizedBox(height: 8),
        
        // 日期网格
        _buildDayGrid(),
      ],
    );
  }

  /// 构建星期标题行
  Widget _buildWeekdayHeader() {
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    
    return Row(
      children: weekdays.map((day) {
        final isWeekend = day == '六' || day == '日';
        return Expanded(
          child: Center(
            child: Text(
              day,
              style: AppTextStyles.tiny.copyWith(
                color: isWeekend 
                    ? AppColors.textTertiary 
                    : AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  /// 构建日期网格
  Widget _buildDayGrid() {
    final firstDayOfMonth = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    
    // 计算第一天是周几（周一=1, 周日=7）
    // 我们需要转换为从0开始（周一=0）
    int firstWeekday = firstDayOfMonth.weekday - 1;
    
    // 计算需要多少行
    final totalCells = firstWeekday + daysInMonth;
    final rows = (totalCells / 7).ceil();
    
    return Column(
      children: List.generate(rows, (rowIndex) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: List.generate(7, (colIndex) {
              final cellIndex = rowIndex * 7 + colIndex;
              final dayNumber = cellIndex - firstWeekday + 1;
              
              // 如果是上月或下月的日期，显示空白
              if (dayNumber < 1 || dayNumber > daysInMonth) {
                return const Expanded(child: SizedBox(height: 40));
              }
              
              final date = DateTime(month.year, month.month, dayNumber);
              final dateStr = _formatDate(date);
              final status = data[dateStr] ?? 0;
              final isToday = _isToday(date);
              
              return Expanded(
                child: _buildDayCell(
                  day: dayNumber,
                  status: status,
                  isToday: isToday,
                  date: date,
                ),
              );
            }),
          ),
        );
      }),
    );
  }

  /// 构建单个日期单元格
  Widget _buildDayCell({
    required int day,
    required int status,
    required bool isToday,
    required DateTime date,
  }) {
    final color = _getStatusColor(status);
    final isFuture = date.isAfter(DateTime.now());
    
    return GestureDetector(
      onTap: () {
        if (onDayTap != null && status != 0) {
          // HapticFeedback.lightImpact(); // 震动反馈已禁用
          onDayTap!(date);
        }
      },
      child: Container(
        height: 40,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: isFuture && status == 0 
              ? Colors.transparent 
              : color.withOpacity(status == 0 ? 0.3 : 0.8),
          borderRadius: BorderRadius.circular(8),
          border: isToday
              ? Border.all(color: AppColors.primary, width: 2)
              : null,
          // 异常状态加上脉冲阴影效果
          boxShadow: status == 2
              ? [
                  BoxShadow(
                    color: AppColors.error.withOpacity(0.3),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 日期数字
            Text(
              day.toString(),
              style: TextStyle(
                fontSize: 14,
                fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
                color: _getTextColor(status, isFuture),
              ),
            ),
            
            // 今天的标记点
            if (isToday)
              Positioned(
                bottom: 4,
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            
            // 异常标记角标
            if (status == 2)
              Positioned(
                top: 2,
                right: 2,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.error,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 根据状态获取颜色
  Color _getStatusColor(int status) {
    switch (status) {
      case 1:
        return AppColors.success;
      case 2:
        return AppColors.error;
      case 3:
        return AppColors.warning;
      default:
        return AppColors.border;
    }
  }

  /// 获取文字颜色
  Color _getTextColor(int status, bool isFuture) {
    if (isFuture && status == 0) {
      return AppColors.textTertiary;
    }
    if (status == 0) {
      return AppColors.textTertiary;
    }
    return Colors.white;
  }

  /// 判断是否是今天
  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  /// 格式化日期
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

