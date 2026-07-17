/// 报警通知服务
/// 
/// 【功能说明】
/// 全局报警通知管理，用于：
/// - 手机推送通知提示
/// - 获取报警时的截图
/// - 查看火灾场景录像（从 WVP 服务器回放）
/// 
/// 【实现说明】
/// 报警流程：
/// 1. 摄像头检测到火灾 → 通过 GB28181 发送报警到 WVP
/// 2. APP 轮询获取新报警
/// 3. 显示通知 + 获取报警截图
/// 4. 自动开始录像（服务器端）
/// 5. 用户可以查看报警时间段的录像回放

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import 'wvp_service.dart';
import 'gallery_service.dart';

/// 报警通知服务（单例）
class AlarmNotificationService {
  static final AlarmNotificationService _instance = AlarmNotificationService._internal();
  factory AlarmNotificationService() => _instance;
  AlarmNotificationService._internal();
  
  /// 全局 NavigatorKey（用于在任意位置显示弹窗）
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  
  /// WVP 服务
  final WvpService _wvpService = WvpService();
  
  /// 相册服务
  final GalleryService _galleryService = GalleryService();
  
  /// 是否已初始化
  bool _isInitialized = false;
  
  /// 报警回调
  void Function(AlarmInfo alarm)? _onAlarmCallback;
  
  /// 报警记录列表（包含截图和录像信息）
  final List<AlarmRecord> _alarmRecords = [];
  
  /// 获取报警记录列表
  List<AlarmRecord> get alarmRecords => List.unmodifiable(_alarmRecords);
  
  /// 初始化报警监听
  void initialize({
    void Function(AlarmInfo alarm)? onAlarm,
  }) {
    if (_isInitialized) return;
    _isInitialized = true;
    _onAlarmCallback = onAlarm;
    
    // 注意：报警轮询已改用 AlarmPollingService（轮询 alarm_receiver.py 服务器）
    // WVP 的报警轮询已移除
    
    debugPrint('[AlarmService] 报警监听已初始化');
  }
  
  /// 停止报警监听
  void dispose() {
    _isInitialized = false;
    debugPrint('[AlarmService] 报警监听已停止');
  }
  
  /// 处理报警
  Future<void> _handleAlarm(AlarmInfo alarm) async {
    debugPrint('[AlarmService] 收到报警: ${alarm.alarmDescription}');
    
    // 1. 震动提醒
    HapticFeedback.heavyImpact();
    
    // 2. 获取报警截图
    String? snapshotUrl;
    try {
      snapshotUrl = await _wvpService.getSnapshot(
        deviceId: alarm.deviceId,
        channelId: WvpConfig.channelId, // 使用视频通道获取截图
      );
      debugPrint('[AlarmService] 报警截图: $snapshotUrl');
    } catch (e) {
      debugPrint('[AlarmService] 获取截图失败: $e');
    }
    
    // 3. 自动开始录像
    final recordStarted = await _startAlarmRecord(alarm);
    
    // 4. 保存报警记录
    _alarmRecords.add(AlarmRecord(
      alarm: alarm,
      startTime: DateTime.now(),
      snapshotUrl: snapshotUrl,
      isRecording: recordStarted,
    ));
    
    // 5. 显示通知
    _showAlarmNotification(alarm, snapshotUrl);
    
    // 6. 触发回调
    _onAlarmCallback?.call(alarm);
    
    // 7. 30秒后自动停止录像
    if (recordStarted) {
      Future.delayed(const Duration(seconds: 30), () {
        _stopAlarmRecord(alarm);
      });
    }
  }
  
  /// 开始报警录像
  Future<bool> _startAlarmRecord(AlarmInfo alarm) async {
    final success = await _wvpService.startRecord(
      deviceId: alarm.deviceId,
      channelId: WvpConfig.channelId, // 使用视频通道录像
    );
    
    if (success) {
      debugPrint('[AlarmService] 报警录像已开始');
    }
    
    return success;
  }
  
  /// 停止报警录像
  Future<void> _stopAlarmRecord(AlarmInfo alarm) async {
    final recordPath = await _wvpService.stopRecord(
      deviceId: alarm.deviceId,
      channelId: WvpConfig.channelId,
    );
    
    // 更新记录
    final index = _alarmRecords.indexWhere((r) => r.alarm.alarmId == alarm.alarmId);
    if (index != -1) {
      _alarmRecords[index] = AlarmRecord(
        alarm: alarm,
        startTime: _alarmRecords[index].startTime,
        endTime: DateTime.now(),
        snapshotUrl: _alarmRecords[index].snapshotUrl,
        isRecording: false,
        recordPath: recordPath,
      );
    }
    debugPrint('[AlarmService] 报警录像已保存: $recordPath');
  }
  
  /// 显示报警通知
  void _showAlarmNotification(AlarmInfo alarm, String? snapshotUrl) {
    final context = navigatorKey.currentContext;
    if (context == null) return;
    
    // 显示 SnackBar 通知
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(PhosphorIconsBold.warning, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alarm.isFireAlarm ? '🔥 火灾报警' : '⚠️ 设备报警',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    alarm.alarmDescription,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.error,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: '查看',
          textColor: Colors.white,
          onPressed: () {
            _showAlarmDetail(context, alarm, snapshotUrl);
          },
        ),
      ),
    );
  }
  
  /// 显示报警详情弹窗
  void _showAlarmDetail(BuildContext context, AlarmInfo alarm, String? snapshotUrl) {
    showDialog(
      context: context,
      builder: (context) => _AlarmDetailDialog(
        alarm: alarm,
        snapshotUrl: snapshotUrl,
        wvpService: _wvpService,
        galleryService: _galleryService,
      ),
    );
  }
  
  /// 获取报警录像播放地址
  /// 
  /// 【实现说明】
  /// 通过 WVP 的录像回放 API 获取报警时间段的视频
  /// 时间范围：报警时间前 1 分钟 到 报警后 2 分钟
  /// 
  /// 优先使用云端录像（因为没有SD卡）
  Future<CloudRecordPlayResult> getAlarmRecordPlayUrl(AlarmInfo alarm) async {
    final startTime = alarm.alarmTime.subtract(const Duration(minutes: 1));
    final endTime = alarm.alarmTime.add(const Duration(minutes: 2));
    
    // 优先查找云端录像
    return await _wvpService.playCloudRecordByTime(
      startTime: startTime,
      endTime: endTime,
    );
  }
  
  /// 手动触发报警测试
  void testAlarm() {
    final testAlarm = AlarmInfo(
      alarmId: 'test-${DateTime.now().millisecondsSinceEpoch}',
      deviceId: WvpConfig.deviceId,
      channelId: WvpConfig.alarmChannelId,
      alarmType: '5',
      alarmDescription: '检测到火焰（测试报警）',
      alarmTime: DateTime.now(),
    );
    _handleAlarm(testAlarm);
  }
}

/// 报警记录
class AlarmRecord {
  final AlarmInfo alarm;
  final DateTime startTime;
  final DateTime? endTime;
  final String? snapshotUrl;
  final bool isRecording;
  final String? recordPath;
  
  AlarmRecord({
    required this.alarm,
    required this.startTime,
    this.endTime,
    this.snapshotUrl,
    this.isRecording = false,
    this.recordPath,
  });
  
  /// 录像时长（秒）
  int get duration {
    if (endTime == null) return 0;
    return endTime!.difference(startTime).inSeconds;
  }
}

/// 报警详情弹窗
class _AlarmDetailDialog extends StatefulWidget {
  final AlarmInfo alarm;
  final String? snapshotUrl;
  final WvpService wvpService;
  final GalleryService galleryService;
  
  const _AlarmDetailDialog({
    required this.alarm,
    this.snapshotUrl,
    required this.wvpService,
    required this.galleryService,
  });

  @override
  State<_AlarmDetailDialog> createState() => _AlarmDetailDialogState();
}

class _AlarmDetailDialogState extends State<_AlarmDetailDialog> {
  bool _isSavingSnapshot = false;
  bool _isLoadingRecord = false;
  
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.error, width: 2),
      ),
      title: Row(
        children: [
          Icon(
            widget.alarm.isFireAlarm ? PhosphorIconsBold.fire : PhosphorIconsBold.warning,
            color: AppColors.error,
            size: 28,
          ),
          const SizedBox(width: 12),
          Text(
            widget.alarm.isFireAlarm ? '🔥 火灾报警' : '⚠️ 设备报警',
            style: AppTextStyles.h3.copyWith(color: AppColors.error),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 报警截图（如果有）
            if (widget.snapshotUrl != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  widget.snapshotUrl!,
                  height: 150,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 150,
                    color: AppColors.surfaceBackground,
                    child: const Center(
                      child: Icon(PhosphorIconsBold.imageSquare, 
                        color: AppColors.textTertiary, size: 40),
                    ),
                  ),
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      height: 150,
                      color: AppColors.surfaceBackground,
                      child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
            
            // 报警描述
            Text(
              widget.alarm.alarmDescription,
              style: AppTextStyles.body.copyWith(color: AppColors.textPrimary),
            ),
            const SizedBox(height: 12),
            
            // 报警信息
            _buildInfoRow('报警时间', _formatTime(widget.alarm.alarmTime)),
            _buildInfoRow('设备编号', widget.alarm.deviceId),
            _buildInfoRow('报警通道', widget.alarm.channelId),
            
            const SizedBox(height: 12),
            
            // 录像状态提示
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.success.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(PhosphorIconsBold.videoCamera, 
                    color: AppColors.success, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '录像已自动保存，点击下方按钮查看',
                      style: AppTextStyles.caption.copyWith(color: AppColors.success),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        // 保存截图按钮
        if (widget.snapshotUrl != null)
          TextButton.icon(
            onPressed: _isSavingSnapshot ? null : _saveSnapshot,
            icon: _isSavingSnapshot 
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(PhosphorIconsBold.downloadSimple, size: 18),
            label: const Text('保存截图'),
          ),
        
        // 关闭按钮
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        
        // 查看录像按钮
        ElevatedButton.icon(
          onPressed: _isLoadingRecord ? null : _viewAlarmRecord,
          icon: _isLoadingRecord
              ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
                )
              : const Icon(PhosphorIconsBold.play, size: 18),
          label: const Text('查看录像'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
  
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
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
              value,
              style: AppTextStyles.caption.copyWith(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
  
  String _formatTime(DateTime time) {
    return '${time.year}-${_pad(time.month)}-${_pad(time.day)} '
           '${_pad(time.hour)}:${_pad(time.minute)}:${_pad(time.second)}';
  }
  
  String _pad(int n) => n.toString().padLeft(2, '0');
  
  /// 保存截图到相册
  Future<void> _saveSnapshot() async {
    if (widget.snapshotUrl == null) return;
    
    setState(() => _isSavingSnapshot = true);
    
    try {
      final result = await widget.galleryService.saveImageFromUrl(
        widget.snapshotUrl!,
        fileName: 'IOT_ALARM_${DateTime.now().millisecondsSinceEpoch}',
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: result.success ? AppColors.success : AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingSnapshot = false);
      }
    }
  }
  
  /// 查看报警录像
  Future<void> _viewAlarmRecord() async {
    setState(() => _isLoadingRecord = true);
    
    try {
      // 获取报警时间段的录像
      final startTime = widget.alarm.alarmTime.subtract(const Duration(minutes: 1));
      final endTime = widget.alarm.alarmTime.add(const Duration(minutes: 2));
      
      // 优先使用云端录像（因为没有SD卡）
      final result = await widget.wvpService.playCloudRecordByTime(
        startTime: startTime,
        endTime: endTime,
      );
      
      if (result.success && result.bestUrl != null) {
        // 关闭当前弹窗
        if (mounted) {
          Navigator.pop(context);
          
          // 跳转到录像播放页面
          // TODO: 导航到录像播放页面
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('录像地址: ${result.bestUrl}'),
              backgroundColor: AppColors.success,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      } else {
        throw Exception(result.errorMsg ?? '获取录像失败');
      }
    } catch (e) {
      debugPrint('[AlarmDetail] 获取录像失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('获取录像失败: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingRecord = false);
      }
    }
  }
}
