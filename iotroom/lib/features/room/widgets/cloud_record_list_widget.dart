/// 云端录像列表组件
/// 
/// 【功能说明】
/// 显示ZLMediaKit服务器录制的所有云端录像，支持：
/// - 按日期筛选
/// - 分页加载
/// - 点击播放
/// 
/// 【实现说明】
/// 由于摄像头没有SD卡，录像存储在服务器上。
/// 通过 /api/cloud/record/list 接口查询录像列表。

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../services/wvp_service.dart';
import '../../alarm/pages/playback_player_page.dart';

/// 云端录像列表弹窗
class CloudRecordListSheet extends StatefulWidget {
  /// 应用名（默认 rtp）
  final String? app;
  
  /// 流ID（默认使用配置的设备ID）
  final String? stream;

  const CloudRecordListSheet({
    super.key,
    this.app,
    this.stream,
  });

  /// 显示云端录像列表弹窗
  static Future<void> show(BuildContext context, {String? app, String? stream}) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => CloudRecordListSheet(
          app: app,
          stream: stream,
        ),
      ),
    );
  }

  @override
  State<CloudRecordListSheet> createState() => _CloudRecordListSheetState();
}

class _CloudRecordListSheetState extends State<CloudRecordListSheet> {
  final WvpService _wvpService = WvpService();
  
  List<CloudRecordItem> _records = [];
  bool _isLoading = true;
  String? _error;
  
  // 分页
  int _currentPage = 1;
  int _totalPages = 1;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  
  // 日期筛选
  DateTime? _selectedDate;
  
  // 滚动控制器
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadRecords();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 滚动监听（加载更多）
  void _onScroll() {
    if (_scrollController.position.pixels >= 
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  /// 加载录像列表
  Future<void> _loadRecords({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _currentPage = 1;
        _records = [];
        _hasMore = true;
      });
    }
    
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final app = widget.app ?? 'rtp';
      final stream = widget.stream ?? '${WvpConfig.deviceId}_${WvpConfig.channelId}';
      
      // 计算时间范围（选择的日期或最近7天）
      DateTime? startTime;
      DateTime? endTime;
      
      if (_selectedDate != null) {
        startTime = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day);
        endTime = startTime.add(const Duration(days: 1));
      }
      
      debugPrint('[CloudRecord] 查询录像: app=$app, stream=$stream');
      
      final result = await _wvpService.queryCloudRecordList(
        app: app,
        stream: stream,
        startTime: startTime,
        endTime: endTime,
        page: _currentPage,
        count: 20,
        ascOrder: false, // 最新的在前
      );
      
      if (result.success) {
        setState(() {
          _records = result.records;
          _totalPages = result.pages;
          _hasMore = _currentPage < _totalPages;
          _isLoading = false;
        });
        debugPrint('[CloudRecord] 获取到 ${result.records.length} 条录像');
      } else {
        throw Exception(result.errorMsg ?? '查询失败');
      }
      
    } catch (e) {
      debugPrint('[CloudRecord] 加载失败: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  /// 加载更多
  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    
    setState(() => _isLoadingMore = true);
    
    try {
      final app = widget.app ?? 'rtp';
      final stream = widget.stream ?? '${WvpConfig.deviceId}_${WvpConfig.channelId}';
      
      DateTime? startTime;
      DateTime? endTime;
      
      if (_selectedDate != null) {
        startTime = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day);
        endTime = startTime.add(const Duration(days: 1));
      }
      
      final result = await _wvpService.queryCloudRecordList(
        app: app,
        stream: stream,
        startTime: startTime,
        endTime: endTime,
        page: _currentPage + 1,
        count: 20,
        ascOrder: false,
      );
      
      if (result.success) {
        setState(() {
          _currentPage++;
          _records.addAll(result.records);
          _hasMore = _currentPage < _totalPages;
          _isLoadingMore = false;
        });
      }
      
    } catch (e) {
      debugPrint('[CloudRecord] 加载更多失败: $e');
      setState(() => _isLoadingMore = false);
    }
  }

  /// 选择日期
  Future<void> _selectDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.primary,
              surface: AppColors.cardBackground,
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _loadRecords(refresh: true);
    }
  }

  /// 清除日期筛选
  void _clearDateFilter() {
    setState(() => _selectedDate = null);
    _loadRecords(refresh: true);
  }

  /// 播放录像
  Future<void> _playRecord(CloudRecordItem record) async {
    // 使用直接播放地址（从 filePath 构建，而不是调用下载接口）
    final playUrl = record.directPlayUrl;
    
    if (playUrl == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('获取播放地址失败'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }
    
    debugPrint('[CloudRecord] 直接播放地址: $playUrl');
    
    // 关闭当前弹窗并跳转到播放页
    if (mounted) {
      Navigator.pop(context);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PlaybackPlayerPage(
            deviceId: WvpConfig.deviceId,
            channelId: WvpConfig.channelId,
            startTime: record.startDateTime,
            endTime: record.endDateTime,
            title: '云端录像',
            cloudRecordId: record.id,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
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
          
          // 标题栏
          _buildHeader(),
          
          const Divider(color: AppColors.border, height: 1),
          
          // 日期筛选
          _buildDateFilter(),
          
          // 内容区域
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  /// 标题栏
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              PhosphorIconsBold.cloudArrowDown,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('云端录像', style: AppTextStyles.h3),
                Text(
                  '服务器录制的视频文件',
                  style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(PhosphorIconsBold.x, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  /// 日期筛选
  Widget _buildDateFilter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // 日期选择按钮
          GestureDetector(
            onTap: _selectDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceBackground,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(PhosphorIconsBold.calendar, size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Text(
                    _selectedDate != null 
                        ? '${_selectedDate!.month}/${_selectedDate!.day}'
                        : '选择日期',
                    style: AppTextStyles.caption.copyWith(color: AppColors.textPrimary),
                  ),
                  const SizedBox(width: 4),
                  const Icon(PhosphorIconsBold.caretDown, size: 14, color: AppColors.textTertiary),
                ],
              ),
            ),
          ),
          
          // 清除筛选
          if (_selectedDate != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _clearDateFilter,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceBackground,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(PhosphorIconsBold.x, size: 14, color: AppColors.textTertiary),
              ),
            ),
          ],
          
          const Spacer(),
          
          // 刷新按钮
          IconButton(
            onPressed: () => _loadRecords(refresh: true),
            icon: const Icon(PhosphorIconsBold.arrowClockwise, size: 18, color: AppColors.textSecondary),
          ),
          
          // 录像数量
          Text(
            '${_records.length} 条',
            style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  /// 内容区域
  Widget _buildContent() {
    if (_isLoading && _records.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            SizedBox(height: 16),
            Text('正在加载录像列表...', style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      );
    }
    
    if (_error != null && _records.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(PhosphorIconsBold.cloudSlash, color: AppColors.error, size: 48),
            const SizedBox(height: 16),
            Text('加载失败', style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            Text(_error!, style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _loadRecords(refresh: true),
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
    
    if (_records.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              PhosphorIconsBold.videoCameraSlash,
              color: AppColors.textTertiary.withOpacity(0.5),
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              _selectedDate != null ? '该日期没有录像' : '暂无云端录像',
              style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              '录像会在视频推流时自动录制',
              style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary),
            ),
          ],
        ),
      );
    }
    
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _records.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _records.length) {
          return _buildLoadingMore();
        }
        return _buildRecordItem(_records[index]);
      },
    );
  }

  /// 录像项
  Widget _buildRecordItem(CloudRecordItem record) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withOpacity(0.5)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _playRecord(record),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // 缩略图/图标
                Container(
                  width: 60,
                  height: 45,
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    PhosphorIconsBold.play,
                    color: AppColors.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                
                // 信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 时间
                      Text(
                        _formatDateTime(record.startDateTime),
                        style: AppTextStyles.body.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // 时长和大小
                      Row(
                        children: [
                          Icon(PhosphorIconsBold.clock, size: 12, color: AppColors.textTertiary),
                          const SizedBox(width: 4),
                          Text(
                            record.formattedDuration,
                            style: AppTextStyles.tiny.copyWith(color: AppColors.textSecondary),
                          ),
                          const SizedBox(width: 12),
                          Icon(PhosphorIconsBold.file, size: 12, color: AppColors.textTertiary),
                          const SizedBox(width: 4),
                          Text(
                            record.formattedFileSize,
                            style: AppTextStyles.tiny.copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                // 播放箭头
                const Icon(
                  PhosphorIconsBold.playCircle,
                  color: AppColors.primary,
                  size: 28,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 加载更多指示器
  Widget _buildLoadingMore() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: _isLoadingMore
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
              )
            : Text(
                '上拉加载更多',
                style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary),
              ),
      ),
    );
  }

  /// 格式化日期时间
  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final recordDate = DateTime(dt.year, dt.month, dt.day);
    
    String dateStr;
    if (recordDate == today) {
      dateStr = '今天';
    } else if (recordDate == yesterday) {
      dateStr = '昨天';
    } else {
      dateStr = '${dt.month}/${dt.day}';
    }
    
    return '$dateStr ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

