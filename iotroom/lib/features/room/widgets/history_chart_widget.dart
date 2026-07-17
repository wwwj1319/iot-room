import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../services/temp_humidity_service.dart';

/// 📈 历史数据图表组件
/// 
/// 【实现说明】
/// 使用 fl_chart 库绑制曲线图
/// 展示温度和湿度的历史变化趋势
/// 
/// fl_chart 是 Flutter 最流行的图表库之一
/// 官方文档：https://pub.dev/packages/fl_chart
/// 
/// 设计要点：
/// 1. 双Y轴显示温度和湿度
/// 2. 平滑曲线（bezier）
/// 3. 渐变填充
/// 4. 触摸显示数据点详情
/// 5. 支持从 API 获取真实数据
class HistoryChartWidget extends StatefulWidget {
  /// 温湿度传感器 Modbus 地址
  final int modbusAddress;
  
  /// 查询最近多少小时的数据
  final int hours;
  
  const HistoryChartWidget({
    super.key,
    this.modbusAddress = 1,
    this.hours = 24,
  });

  @override
  State<HistoryChartWidget> createState() => _HistoryChartWidgetState();
}

class _HistoryChartWidgetState extends State<HistoryChartWidget> {
  final TempHumidityService _service = TempHumidityService();
  
  // 数据状态
  List<TempHumidityHistoryItem> _historyData = [];
  bool _isLoading = true;
  String? _error;
  
  // 图表数据
  List<FlSpot> _tempSpots = [];
  List<FlSpot> _humiditySpots = [];
  double _minTemp = 0;
  double _maxTemp = 50;
  
  @override
  void initState() {
    super.initState();
    _loadHistory();
  }
  
  /// 加载历史数据
  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    
    try {
      final history = await _service.getHistory(
        modbusAddress: widget.modbusAddress,
        hours: widget.hours,
        limit: 200,
      );
      
      if (history != null && history.data.isNotEmpty) {
        _historyData = history.data;
        _processData();
      } else {
        _error = '暂无历史数据';
      }
    } catch (e) {
      _error = '加载失败';
      debugPrint('[HistoryChart] 加载历史数据失败: $e');
    }
    
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  /// 处理数据，转换为图表格式
  void _processData() {
    if (_historyData.isEmpty) return;
    
    // 按时间排序（从早到晚）
    _historyData.sort((a, b) {
      final aTime = a.dateTime;
      final bTime = b.dateTime;
      if (aTime == null || bTime == null) return 0;
      return aTime.compareTo(bTime);
    });
    
    // 计算温度范围
    double minTemp = double.infinity;
    double maxTemp = double.negativeInfinity;
    for (final item in _historyData) {
      if (item.temperature < minTemp) minTemp = item.temperature;
      if (item.temperature > maxTemp) maxTemp = item.temperature;
    }
    
    // 添加一点边距
    _minTemp = (minTemp - 5).clamp(-20, 60);
    _maxTemp = (maxTemp + 5).clamp(-20, 60);
    
    // 转换为图表点
    _tempSpots = [];
    _humiditySpots = [];
    
    final now = DateTime.now();
    
    for (int i = 0; i < _historyData.length; i++) {
      final item = _historyData[i];
      final time = item.dateTime;
      if (time == null) continue;
      
      // X 轴：距离现在多少小时（倒序，0 = 现在）
      final hoursAgo = now.difference(time).inMinutes / 60.0;
      final x = widget.hours.toDouble() - hoursAgo;
      
      if (x >= 0 && x <= widget.hours) {
        _tempSpots.add(FlSpot(x, item.temperature));
        _humiditySpots.add(FlSpot(x, item.humidity));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 图例
        _buildLegend(),
        
        const SizedBox(height: 16),
        
        // 图表区域
        SizedBox(
          height: 200,
          child: _buildChartContent(),
        ),
      ],
    );
  }
  
  /// 构建图表内容（加载中/错误/正常）
  Widget _buildChartContent() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '加载历史数据...',
              style: AppTextStyles.tiny.copyWith(color: AppColors.textTertiary),
            ),
          ],
        ),
      );
    }
    
    if (_error != null || _tempSpots.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.show_chart,
              size: 40,
              color: AppColors.textTertiary.withOpacity(0.3),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? '暂无数据',
              style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _loadHistory,
              child: Text('重新加载', style: AppTextStyles.tiny),
            ),
          ],
        ),
      );
    }
    
    return LineChart(
      _buildChartData(),
      duration: const Duration(milliseconds: 300),
    );
  }

  /// 构建图例
  Widget _buildLegend() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildLegendItem('温度', AppColors.warning),
        const SizedBox(width: 24),
        _buildLegendItem('湿度', AppColors.info),
      ],
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: AppTextStyles.tiny),
      ],
    );
  }

  /// 构建图表数据
  LineChartData _buildChartData() {
    return LineChartData(
      // 网格线
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: 10,
        getDrawingHorizontalLine: (value) => FlLine(
          color: AppColors.divider,
          strokeWidth: 1,
          dashArray: [5, 5],
        ),
      ),
      
      // 边框
      borderData: FlBorderData(show: false),
      
      // X轴标题
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 32,
            interval: (_maxTemp - _minTemp) / 4,
            getTitlesWidget: (value, meta) => Text(
              '${value.toInt()}°',
              style: AppTextStyles.tiny.copyWith(fontSize: 10),
            ),
          ),
        ),
        rightTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 32,
            interval: 20,
            getTitlesWidget: (value, meta) => Text(
              '${value.toInt()}%',
              style: AppTextStyles.tiny.copyWith(fontSize: 10),
            ),
          ),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 24,
            interval: widget.hours / 6,
            getTitlesWidget: (value, meta) {
              // 计算对应的时间
              final now = DateTime.now();
              final hoursAgo = widget.hours - value;
              final time = now.subtract(Duration(hours: hoursAgo.toInt()));
                return Text(
                '${time.hour.toString().padLeft(2, '0')}:00',
                  style: AppTextStyles.tiny.copyWith(fontSize: 10),
                );
            },
          ),
        ),
      ),
      
      // 数据范围
      minX: 0,
      maxX: widget.hours.toDouble(),
      minY: 0,
      maxY: 100,
      
      // 数据线
      lineBarsData: [
        // 温度曲线
        _buildTempLine(),
        // 湿度曲线
        _buildHumidityLine(),
      ],
      
      // 触摸交互
      lineTouchData: LineTouchData(
        enabled: true,
        touchTooltipData: LineTouchTooltipData(
          tooltipPadding: const EdgeInsets.all(8),
          tooltipMargin: 8,
          getTooltipItems: (touchedSpots) {
            return touchedSpots.map((spot) {
              final isTemp = spot.barIndex == 0;
              final value = isTemp 
                  ? _denormalizeTemp(spot.y)
                  : spot.y;
              return LineTooltipItem(
                '${value.toStringAsFixed(1)}${isTemp ? '°C' : '%'}',
                TextStyle(
                  color: isTemp ? AppColors.warning : AppColors.info,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              );
            }).toList();
          },
        ),
      ),
    );
  }
  
  /// 将温度归一化到 0-100 范围（用于和湿度共享 Y 轴）
  double _normalizeTemp(double temp) {
    return ((temp - _minTemp) / (_maxTemp - _minTemp) * 100).clamp(0, 100);
  }
  
  /// 将归一化的值转回温度
  double _denormalizeTemp(double normalized) {
    return _minTemp + (normalized / 100) * (_maxTemp - _minTemp);
  }

  /// 温度曲线
  LineChartBarData _buildTempLine() {
    return LineChartBarData(
      spots: _tempSpots.map((spot) {
        return FlSpot(spot.x, _normalizeTemp(spot.y));
      }).toList(),
      isCurved: true,
      curveSmoothness: 0.3,
      color: AppColors.warning,
      barWidth: 2,
      isStrokeCapRound: true,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.warning.withOpacity(0.3),
            AppColors.warning.withOpacity(0.0),
          ],
        ),
      ),
    );
  }

  /// 湿度曲线
  LineChartBarData _buildHumidityLine() {
    return LineChartBarData(
      spots: _humiditySpots,
      isCurved: true,
      curveSmoothness: 0.3,
      color: AppColors.info,
      barWidth: 2,
      isStrokeCapRound: true,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.info.withOpacity(0.3),
            AppColors.info.withOpacity(0.0),
          ],
        ),
      ),
    );
  }
}
