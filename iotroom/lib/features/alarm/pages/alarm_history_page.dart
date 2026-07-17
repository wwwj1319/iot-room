/// 报警历史页面
/// 
/// 【功能说明】
/// 显示从支持 HTTP 告警推送的摄像头接收到的报警记录：
/// - 火灾检测报警（开始和结束联动显示）
/// - 查看报警时的抓拍图片
/// - 后续支持查看录像回放
/// 
/// 【数据来源】
/// 从自建服务器 API 获取报警数据：
/// GET http://服务器IP:9090/api/alarms

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../services/wvp_service.dart';
import 'playback_player_page.dart';

/// 报警服务器配置
class AlarmServerConfig {
  static String get baseUrl => AppConfig.alarmBaseUrl;
  static String get alarmsApi => '$baseUrl/api/alarms';
  static String imageUrl(String? path) => path != null ? '$baseUrl$path' : '';
}

/// 报警事件模型
class AlarmEvent {
  final String id;
  final String eventType;
  final String eventName;
  final String deviceID;
  final String channelName;
  final String startTime;
  final String? endTime;
  final String? startImage;
  final String? endImage;
  final String status;  // active=进行中, resolved=已恢复
  
  AlarmEvent({
    required this.id,
    required this.eventType,
    required this.eventName,
    required this.deviceID,
    required this.channelName,
    required this.startTime,
    this.endTime,
    this.startImage,
    this.endImage,
    required this.status,
  });
  
  factory AlarmEvent.fromJson(Map<String, dynamic> json) {
    return AlarmEvent(
      id: json['id'] ?? '',
      eventType: json['eventType'] ?? '',
      eventName: json['eventName'] ?? '未知报警',
      deviceID: json['deviceID'] ?? '',
      channelName: json['channelName'] ?? '',
      startTime: json['startTime'] ?? '',
      endTime: json['endTime'],
      startImage: json['startImage'],
      endImage: json['endImage'],
      status: json['status'] ?? 'unknown',
    );
  }
  
  /// 是否是火灾报警
  bool get isFireAlarm => eventType == 'fire_alarm' || eventType == 'fireSmartFireDetect';
  
  /// 是否已恢复
  bool get isResolved => status == 'resolved';
  
  /// 格式化显示时间
  String get formattedStartTime => _formatDateTime(startTime);
  String get formattedEndTime => endTime != null ? _formatDateTime(endTime!) : '';
  
  String _formatDateTime(String dateTime) {
    try {
      // 解析后转换为本地时间，解决时区问题
      final dt = DateTime.parse(dateTime).toLocal();
      return '${dt.year}/${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateTime;
    }
  }
}

/// 报警历史页面
class AlarmHistoryPage extends StatefulWidget {
  /// 是否显示返回按钮（作为Tab页面时不需要）
  final bool showBackButton;
  
  const AlarmHistoryPage({
    super.key,
    this.showBackButton = true,
  });

  @override
  State<AlarmHistoryPage> createState() => _AlarmHistoryPageState();
}

class _AlarmHistoryPageState extends State<AlarmHistoryPage> {
  List<AlarmEvent> _alarms = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAlarms();
  }

  /// 从服务器加载报警列表
  Future<void> _loadAlarms() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      debugPrint('[AlarmHistory] 正在从服务器获取报警列表...');
      
      final response = await http.get(
        Uri.parse(AlarmServerConfig.alarmsApi),
      ).timeout(const Duration(seconds: 10));
      
      debugPrint('[AlarmHistory] 响应状态: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['code'] == 0 && data['data'] != null) {
          final List<dynamic> list = data['data'];
          final alarms = list.map((e) => AlarmEvent.fromJson(e)).toList();
          
          debugPrint('[AlarmHistory] 获取到 ${alarms.length} 条报警记录');
          
          if (mounted) {
            setState(() {
              _alarms = alarms;
              _isLoading = false;
            });
          }
        } else {
          throw Exception(data['message'] ?? '获取数据失败');
        }
      } else {
        throw Exception('服务器响应错误: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[AlarmHistory] 加载报警列表失败: $e');
      if (mounted) {
        setState(() {
          _error = '加载失败: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.cardBackground,
        elevation: 0,
        title: Text(
          '告警记录',
          style: AppTextStyles.h3.copyWith(color: AppColors.textPrimary),
        ),
        // 根据参数决定是否显示返回按钮
        leading: widget.showBackButton 
            ? IconButton(
                icon: const Icon(PhosphorIconsBold.arrowLeft, color: AppColors.textPrimary),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        automaticallyImplyLeading: widget.showBackButton,
        actions: [
          // 刷新按钮
          IconButton(
            icon: const Icon(PhosphorIconsBold.arrowClockwise, color: AppColors.textPrimary),
            onPressed: _loadAlarms,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            SizedBox(height: 16),
            Text('正在加载报警记录...', style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(PhosphorIconsBold.wifiSlash, color: AppColors.error, size: 48),
            const SizedBox(height: 16),
            Text(_error!, style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            Text(
              '请确保服务器已启动',
              style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadAlarms,
              icon: const Icon(PhosphorIconsBold.arrowClockwise, size: 16),
              label: const Text('重试'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    if (_alarms.isEmpty) {
      return _buildEmptyView();
    }

    return RefreshIndicator(
      onRefresh: _loadAlarms,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _alarms.length,
        itemBuilder: (context, index) => _buildAlarmCard(_alarms[index]),
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            PhosphorIconsBold.bellSlash,
            color: AppColors.textTertiary.withOpacity(0.5),
            size: 64,
          ),
          const SizedBox(height: 16),
          Text(
            '暂无报警记录',
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            '当摄像头检测到火灾时会自动记录',
            style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _buildAlarmCard(AlarmEvent alarm) {
    final isFireAlarm = alarm.isFireAlarm;
    final isResolved = alarm.isResolved;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isFireAlarm 
              ? (isResolved ? AppColors.success.withOpacity(0.3) : AppColors.error.withOpacity(0.5))
              : AppColors.border,
          width: isFireAlarm ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showAlarmDetail(alarm),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 头部：图标 + 标题 + 状态
                Row(
                  children: [
                    // 图标
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: (isFireAlarm 
                            ? (isResolved ? AppColors.success : AppColors.error)
                            : AppColors.warning).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isFireAlarm ? PhosphorIconsBold.fire : PhosphorIconsBold.warning,
                        color: isFireAlarm 
                            ? (isResolved ? AppColors.success : AppColors.error)
                            : AppColors.warning,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    
                    // 标题和时间
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            alarm.eventName,
                            style: AppTextStyles.body.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            alarm.formattedStartTime,
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // 状态标签
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isResolved 
                            ? AppColors.success.withOpacity(0.1)
                            : AppColors.error.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isResolved ? '已恢复' : '进行中',
                        style: AppTextStyles.tiny.copyWith(
                          color: isResolved ? AppColors.success : AppColors.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 12),
                
                // 设备信息
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceBackground,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(PhosphorIconsBold.videoCamera, 
                        color: AppColors.textTertiary, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        alarm.channelName.isNotEmpty ? alarm.channelName : '摄像头',
                        style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                      ),
                      const Spacer(),
                      Icon(PhosphorIconsBold.image, 
                        color: AppColors.textTertiary, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        '${alarm.startImage != null ? 1 : 0}${alarm.endImage != null ? '+1' : ''} 张抓拍',
                        style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                
                // 如果已恢复，显示恢复时间
                if (isResolved && alarm.endTime != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(PhosphorIconsBold.checkCircle, 
                        color: AppColors.success, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        '恢复时间: ${alarm.formattedEndTime}',
                        style: AppTextStyles.caption.copyWith(color: AppColors.success),
                      ),
                    ],
                  ),
                ],
                
                const SizedBox(height: 8),
                
                // 查看详情提示
                Center(
                  child: Text(
                    '点击查看抓拍图片',
                    style: AppTextStyles.tiny.copyWith(color: AppColors.primary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 显示报警详情弹窗
  void _showAlarmDetail(AlarmEvent alarm) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _AlarmDetailSheet(alarm: alarm),
    );
  }
}

/// 报警详情底部弹窗
class _AlarmDetailSheet extends StatefulWidget {
  final AlarmEvent alarm;
  
  const _AlarmDetailSheet({required this.alarm});

  @override
  State<_AlarmDetailSheet> createState() => _AlarmDetailSheetState();
}

class _AlarmDetailSheetState extends State<_AlarmDetailSheet> {
  int _currentImageIndex = 0;  // 0=开始图片, 1=结束图片
  
  @override
  Widget build(BuildContext context) {
    final alarm = widget.alarm;
    final hasStartImage = alarm.startImage != null;
    final hasEndImage = alarm.endImage != null;
    final imageCount = (hasStartImage ? 1 : 0) + (hasEndImage ? 1 : 0);
    
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖动指示条
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // 标题
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  alarm.isFireAlarm ? PhosphorIconsBold.fire : PhosphorIconsBold.warning,
                  color: alarm.isResolved ? AppColors.success : AppColors.error,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        alarm.eventName,
                        style: AppTextStyles.h3.copyWith(color: AppColors.textPrimary),
                      ),
                      Text(
                        alarm.formattedStartTime,
                        style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(PhosphorIconsBold.x, color: AppColors.textSecondary),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          
          const Divider(color: AppColors.border, height: 1),
          
          // 内容（可滚动）
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 图片切换标签（如果有多张图片）
                  if (imageCount > 1) ...[
                    Row(
                      children: [
                        _buildImageTab(0, '🔥 报警时抓拍', hasStartImage),
                        const SizedBox(width: 8),
                        _buildImageTab(1, '✅ 恢复时抓拍', hasEndImage),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  
                  // 抓拍图片
                  if (hasStartImage || hasEndImage) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: double.infinity,
                        height: 220,
                        color: AppColors.surfaceBackground,
                        child: _buildCurrentImage(alarm),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        _currentImageIndex == 0 ? '报警发生时的抓拍' : '报警恢复时的抓拍',
                        style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ] else ...[
                    Container(
                      width: double.infinity,
                      height: 150,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceBackground,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(PhosphorIconsBold.imageSquare, 
                            color: AppColors.textTertiary, size: 40),
                          const SizedBox(height: 8),
                          Text('暂无抓拍图片', 
                            style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  
                  // 详细信息
                  _buildInfoSection(alarm),
                  
                  const SizedBox(height: 20),
                  
                  // 操作按钮
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(PhosphorIconsBold.x, size: 18),
                          label: const Text('关闭'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                            side: const BorderSide(color: AppColors.border),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _openPlayback(context, alarm),
                          icon: const Icon(PhosphorIconsBold.play, size: 18),
                          label: const Text('查看录像'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          // 底部安全区域
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }
  
  Widget _buildImageTab(int index, String label, bool available) {
    final isSelected = _currentImageIndex == index;
    
    return Expanded(
      child: GestureDetector(
        onTap: available ? () => setState(() => _currentImageIndex = index) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary.withOpacity(0.1) : AppColors.surfaceBackground,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? AppColors.primary : Colors.transparent,
              width: 1,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: AppTextStyles.caption.copyWith(
                color: available 
                    ? (isSelected ? AppColors.primary : AppColors.textSecondary)
                    : AppColors.textTertiary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildCurrentImage(AlarmEvent alarm) {
    String? imageUrl;
    if (_currentImageIndex == 0 && alarm.startImage != null) {
      imageUrl = AlarmServerConfig.imageUrl(alarm.startImage);
    } else if (_currentImageIndex == 1 && alarm.endImage != null) {
      imageUrl = AlarmServerConfig.imageUrl(alarm.endImage);
    }
    
    if (imageUrl == null || imageUrl.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(PhosphorIconsBold.imageSquare, color: AppColors.textTertiary, size: 40),
            const SizedBox(height: 8),
            Text('暂无图片', style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary)),
          ],
        ),
      );
    }
    
    return GestureDetector(
      onTap: () => _showFullScreenImage(context, imageUrl!),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            imageUrl,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Center(
                child: CircularProgressIndicator(
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                      : null,
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(PhosphorIconsBold.warning, color: AppColors.error, size: 40),
                    const SizedBox(height: 8),
                    Text('图片加载失败', style: AppTextStyles.caption.copyWith(color: AppColors.error)),
                  ],
                ),
              );
            },
          ),
          // 放大提示图标
          Positioned(
            right: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                PhosphorIconsBold.magnifyingGlassPlus,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  /// 显示全屏图片查看器
  void _showFullScreenImage(BuildContext context, String imageUrl) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (context, animation, secondaryAnimation) {
          return _FullScreenImageViewer(imageUrl: imageUrl);
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
      ),
    );
  }
  
  /// 打开录像回放
  void _openPlayback(BuildContext context, AlarmEvent alarm) {
    // 关闭底部弹窗
    Navigator.pop(context);
    
    // 解析报警时间
    DateTime startTime;
    DateTime endTime;
    
    try {
      // 报警开始时间前1分钟作为回放开始
      startTime = DateTime.parse(alarm.startTime).subtract(const Duration(minutes: 1));
      
      // 如果有结束时间，使用结束时间后1分钟；否则使用开始时间后5分钟
      if (alarm.endTime != null && alarm.endTime!.isNotEmpty) {
        endTime = DateTime.parse(alarm.endTime!).add(const Duration(minutes: 1));
      } else {
        endTime = DateTime.parse(alarm.startTime).add(const Duration(minutes: 5));
      }
    } catch (e) {
      debugPrint('[AlarmDetail] 时间解析失败: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('时间格式错误: $e'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    
    // 导航到回放页面
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlaybackPlayerPage(
          deviceId: WvpConfig.deviceId,  // 使用默认设备ID
          channelId: WvpConfig.channelId, // 使用默认通道ID
          startTime: startTime,
          endTime: endTime,
          title: alarm.eventName,
        ),
      ),
    );
  }
  
  Widget _buildInfoSection(AlarmEvent alarm) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceBackground,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          _buildInfoRow('事件类型', alarm.eventName),
          _buildInfoRow('设备通道', alarm.channelName.isNotEmpty ? alarm.channelName : '-'),
          _buildInfoRow('设备ID', alarm.deviceID.isNotEmpty ? alarm.deviceID : '-'),
          _buildInfoRow('报警时间', alarm.formattedStartTime),
          if (alarm.isResolved && alarm.endTime != null)
            _buildInfoRow('恢复时间', alarm.formattedEndTime),
          _buildInfoRow('状态', alarm.isResolved ? '已恢复' : '进行中', 
            valueColor: alarm.isResolved ? AppColors.success : AppColors.error),
        ],
      ),
    );
  }
  
  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.caption.copyWith(
                color: valueColor ?? AppColors.textPrimary,
                fontWeight: valueColor != null ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 全屏图片查看器
/// 
/// 支持双指缩放、拖动查看大图
class _FullScreenImageViewer extends StatefulWidget {
  final String imageUrl;
  
  const _FullScreenImageViewer({required this.imageUrl});

  @override
  State<_FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<_FullScreenImageViewer> {
  final TransformationController _transformationController = TransformationController();
  
  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }
  
  /// 双击放大/还原
  void _handleDoubleTap() {
    if (_transformationController.value != Matrix4.identity()) {
      // 已放大，还原
      _transformationController.value = Matrix4.identity();
    } else {
      // 未放大，放大到2倍
      _transformationController.value = Matrix4.identity()..scale(2.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 点击背景关闭
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(color: Colors.transparent),
          ),
          
          // 图片查看区域
          Center(
            child: GestureDetector(
              onDoubleTap: _handleDoubleTap,
              child: InteractiveViewer(
                transformationController: _transformationController,
                minScale: 0.5,
                maxScale: 4.0,
                child: Image.network(
                  widget.imageUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Center(
                      child: CircularProgressIndicator(
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                            : null,
                        color: Colors.white,
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(PhosphorIconsBold.warning, color: Colors.white, size: 48),
                          const SizedBox(height: 16),
                          Text(
                            '图片加载失败',
                            style: AppTextStyles.body.copyWith(color: Colors.white),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          
          // 顶部关闭按钮
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  PhosphorIconsBold.x,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
          ),
          
          // 底部提示
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 24,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '双指缩放 · 双击放大 · 点击关闭',
                  style: AppTextStyles.caption.copyWith(color: Colors.white70),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
