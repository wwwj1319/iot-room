import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/glass_card.dart';

/// 📊 仪表盘组件
/// 
/// 【实现说明】
/// 这是一个圆弧形仪表盘，用于展示温度、湿度等数值
/// 
/// 设计要点：
/// 1. 使用 CustomPainter 绘制圆弧
/// 2. 渐变色从低到高变化
/// 3. 当前值用指针或高亮弧线标识
/// 4. 阈值线用虚线标识
/// 5. 数值变化时有动画过渡
/// 
/// 【学习要点】
/// CustomPainter 是 Flutter 中自定义绑制的核心类
/// 可以绑制任何形状、图案
class GaugeWidget extends StatefulWidget {
  /// 标题
  final String title;
  
  /// 当前值
  final double value;
  
  /// 单位
  final String unit;
  
  /// 最小值
  final double min;
  
  /// 最大值
  final double max;
  
  /// 高告警阈值
  final double? alarmHigh;
  
  /// 低告警阈值
  final double? alarmLow;
  
  /// 主题色
  final Color color;
  
  /// 图标
  final IconData icon;

  const GaugeWidget({
    super.key,
    required this.title,
    required this.value,
    required this.unit,
    required this.min,
    required this.max,
    this.alarmHigh,
    this.alarmLow,
    required this.color,
    required this.icon,
  });

  @override
  State<GaugeWidget> createState() => _GaugeWidgetState();
}

class _GaugeWidgetState extends State<GaugeWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _currentValue = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _updateAnimation();
    _controller.forward();
  }

  @override
  void didUpdateWidget(GaugeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _updateAnimation();
      _controller.forward(from: 0);
    }
  }

  void _updateAnimation() {
    _animation = Tween<double>(
      begin: _currentValue,
      end: widget.value,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ))
      ..addListener(() {
        setState(() {
          _currentValue = _animation.value;
        });
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 判断是否超过阈值
    final isAlarm = (widget.alarmHigh != null && widget.value >= widget.alarmHigh!) ||
        (widget.alarmLow != null && widget.value <= widget.alarmLow!);

    return GlassCard(
      borderColor: isAlarm ? AppColors.error.withOpacity(0.5) : null,
      // 使用 LayoutBuilder 来获取可用宽度，实现响应式布局
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 根据可用宽度动态计算尺寸
          // 小屏幕（<140）使用紧凑模式
          final isCompact = constraints.maxWidth < 140;
          final gaugeHeight = isCompact ? 70.0 : 90.0;
          final iconSize = isCompact ? 20.0 : 24.0;
          final fontSize = isCompact ? 24.0 : 32.0;
          final unitFontSize = isCompact ? 11.0 : 14.0;
          
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                color: isAlarm ? AppColors.error : widget.color,
                size: iconSize,
              ),
              
              SizedBox(height: isCompact ? 4 : 8),
              
              // 仪表盘 - 只显示数字
              SizedBox(
                height: gaugeHeight,
                child: CustomPaint(
                  size: Size(double.infinity, gaugeHeight),
                  painter: _GaugePainter(
                    value: _currentValue,
                    min: widget.min,
                    max: widget.max,
                    color: isAlarm ? AppColors.error : widget.color,
                    alarmHigh: widget.alarmHigh,
                    alarmLow: widget.alarmLow,
                    strokeWidth: isCompact ? 8.0 : 10.0,
                  ),
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.only(top: isCompact ? 24 : 32),
                      // 数值 - 使用 FittedBox 防止溢出
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              _currentValue.toStringAsFixed(1),
                              style: AppTextStyles.numberMedium.copyWith(
                                color: isAlarm ? AppColors.error : widget.color,
                                fontSize: fontSize,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              widget.unit,
                              style: AppTextStyles.caption.copyWith(
                                color: (isAlarm ? AppColors.error : widget.color).withOpacity(0.8),
                                fontSize: unitFontSize,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              
              SizedBox(height: isCompact ? 4 : 8),
              
              // 标题
              Text(
                widget.title,
                style: AppTextStyles.caption.copyWith(
                  fontSize: isCompact ? 12.0 : 14.0,
                ),
              ),
              
              // 告警提示
              if (isAlarm) ...[
                SizedBox(height: isCompact ? 2 : 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      PhosphorIconsBold.warning,
                      size: isCompact ? 10 : 12,
                      color: AppColors.error,
                    ),
                    SizedBox(width: isCompact ? 2 : 4),
                    Text(
                      '超过阈值',
                      style: AppTextStyles.tiny.copyWith(
                        color: AppColors.error,
                        fontSize: isCompact ? 9.0 : 10.0,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// 仪表盘绑制器
/// 
/// 【实现说明】
/// CustomPainter 的核心方法是 paint()
/// 里面使用 Canvas 进行绘制
/// 
/// 绑制步骤：
/// 1. 绘制背景弧线（灰色）
/// 2. 绘制当前值弧线（渐变色）
/// 3. 绘制阈值标记（虚线）
class _GaugePainter extends CustomPainter {
  final double value;
  final double min;
  final double max;
  final Color color;
  final double? alarmHigh;
  final double? alarmLow;
  final double strokeWidth;

  _GaugePainter({
    required this.value,
    required this.min,
    required this.max,
    required this.color,
    this.alarmHigh,
    this.alarmLow,
    this.strokeWidth = 12.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height - 10);
    final radius = size.width / 2 - 20;
    
    // 弧线的起始和结束角度（从左下到右下，跨越180度）
    const startAngle = math.pi;  // 180度
    const sweepAngle = math.pi;  // 180度
    
    // 绘制背景弧线
    final bgPaint = Paint()
      ..color = AppColors.surfaceBackground
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      bgPaint,
    );
    
    // 计算当前值对应的角度
    final progress = ((value - min) / (max - min)).clamp(0.0, 1.0);
    final valueSweep = sweepAngle * progress;
    
    // 绘制当前值弧线（渐变）
    final valuePaint = Paint()
      ..shader = SweepGradient(
        center: Alignment.center,
        startAngle: 0,
        endAngle: math.pi,
        colors: [
          color.withOpacity(0.3),
          color,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      valueSweep,
      false,
      valuePaint,
    );
    
    // 绘制阈值标记
    if (alarmHigh != null) {
      _drawThresholdMark(canvas, center, radius, alarmHigh!, max, min, AppColors.error);
    }
    if (alarmLow != null) {
      _drawThresholdMark(canvas, center, radius, alarmLow!, max, min, AppColors.info);
    }
  }

  void _drawThresholdMark(
    Canvas canvas,
    Offset center,
    double radius,
    double threshold,
    double max,
    double min,
    Color markColor,
  ) {
    final thresholdProgress = ((threshold - min) / (max - min)).clamp(0.0, 1.0);
    final thresholdAngle = math.pi + (math.pi * thresholdProgress);
    
    // 计算阈值点位置
    final markRadius = radius + 8;
    final x = center.dx + markRadius * math.cos(thresholdAngle);
    final y = center.dy + markRadius * math.sin(thresholdAngle);
    
    // 绘制小圆点标记
    final markPaint = Paint()
      ..color = markColor
      ..style = PaintingStyle.fill;
    
    canvas.drawCircle(Offset(x, y), 4, markPaint);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) {
    return oldDelegate.value != value;
  }
}

