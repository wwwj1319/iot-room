/// 录像回放播放器页面
/// 
/// 【功能说明】
/// 播放指定时间段的录像回放，支持：
/// - 云端录像播放（ZLMediaKit服务器录制）
/// - 在线流媒体播放（不下载到手机）
/// - 播放进度控制
/// - 倍速播放
/// - 全屏模式
/// 
/// 【实现说明】
/// 由于摄像头没有SD卡，录像存储在ZLMediaKit服务器上。
/// 工作流程：
/// 1. 用时间段查询云端录像列表
/// 2. 获取录像文件的播放地址
/// 3. 直接播放MP4文件（不是流媒体回放）

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../services/wvp_service.dart';

/// 录像回放播放器页面
class PlaybackPlayerPage extends StatefulWidget {
  /// 设备ID
  final String deviceId;
  
  /// 通道ID
  final String channelId;
  
  /// 回放开始时间
  final DateTime startTime;
  
  /// 回放结束时间
  final DateTime endTime;
  
  /// 标题（可选）
  final String? title;
  
  /// 直接指定云端录像ID（可选，如果指定则直接播放该录像）
  final int? cloudRecordId;

  const PlaybackPlayerPage({
    super.key,
    required this.deviceId,
    required this.channelId,
    required this.startTime,
    required this.endTime,
    this.title,
    this.cloudRecordId,
  });

  @override
  State<PlaybackPlayerPage> createState() => _PlaybackPlayerPageState();
}

class _PlaybackPlayerPageState extends State<PlaybackPlayerPage> {
  final WvpService _wvpService = WvpService();
  
  VideoPlayerController? _controller;
  
  // 云端录像相关
  CloudRecordPlayResult? _cloudRecordResult;
  List<CloudRecordItem> _recordList = [];
  int _currentRecordIndex = 0;
  
  // 国标回放相关（备用）
  PlaybackResult? _playbackResult;
  
  bool _isLoading = true;
  bool _isPlaying = false;
  bool _isFullscreen = false;
  bool _showControls = true;
  String? _error;
  
  // 播放进度
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  
  // 倍速选项
  final List<double> _speedOptions = [0.5, 1.0, 1.5, 2.0, 4.0];
  double _currentSpeed = 1.0;
  
  // 控制栏自动隐藏定时器
  Timer? _hideControlsTimer;
  
  // 播放模式
  bool _isCloudRecord = true;  // true=云端录像, false=国标回放

  @override
  void initState() {
    super.initState();
    _startPlayback();
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _stopPlayback();
    _controller?.dispose();
    // 恢复竖屏
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /// 开始回放
  /// 
  /// 优先尝试云端录像，如果没有则尝试国标回放
  Future<void> _startPlayback() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      debugPrint('[Playback] 开始请求回放...');
      debugPrint('[Playback] 设备: ${widget.deviceId}/${widget.channelId}');
      debugPrint('[Playback] 时间: ${widget.startTime} ~ ${widget.endTime}');
      
      // 如果直接指定了云端录像ID，直接加载该录像
      if (widget.cloudRecordId != null) {
        debugPrint('[Playback] 直接加载云端录像 ID: ${widget.cloudRecordId}');
        await _loadCloudRecordById(widget.cloudRecordId!);
        return;
      }
      
      // 否则，通过时间段查询云端录像
      final cloudResult = await _wvpService.playCloudRecordByTime(
        startTime: widget.startTime,
        endTime: widget.endTime,
      );
      
      if (cloudResult.success && cloudResult.bestUrl != null) {
        debugPrint('[Playback] 找到云端录像: ${cloudResult.bestUrl}');
        _cloudRecordResult = cloudResult;
        _recordList = cloudResult.allRecords ?? [];
        _isCloudRecord = true;
        
        // 播放云端录像（流媒体格式）
        await _playCloudRecord(cloudResult.bestUrl!);
        return;
      }
      
      debugPrint('[Playback] 云端录像未找到，尝试国标回放...');
      
      // 云端录像未找到，尝试国标回放（如果摄像头有本地存储）
      final result = await _wvpService.startPlayback(
        deviceId: widget.deviceId,
        channelId: widget.channelId,
        startTime: widget.startTime,
        endTime: widget.endTime,
      );
      
      if (result.success && result.hasPlayUrl) {
        _playbackResult = result;
        _isCloudRecord = false;
        debugPrint('[Playback] 获取到国标回放地址: ${result.bestUrl}');
        
        // 播放国标回放流
        await _initPlayer(result);
        return;
      }
      
      // 两种方式都失败
      throw Exception(cloudResult.errorMsg ?? result.errorMsg ?? '该时间段没有录像');
      
    } catch (e) {
      debugPrint('[Playback] 回放失败: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = '$e';
        });
      }
    }
  }
  
  /// 通过录像ID直接加载云端录像
  Future<void> _loadCloudRecordById(int recordId) async {
    final app = 'rtp';
    final stream = '${WvpConfig.deviceId}_${WvpConfig.channelId}';
    
    debugPrint('[Playback] 加载云端录像: app=$app, stream=$stream, recordId=$recordId');
    
    final streamInfo = await _wvpService.loadCloudRecord(
      app: app,
      stream: stream,
      cloudRecordId: recordId,
    );
    
    if (streamInfo == null || !streamInfo.hasPlayUrl) {
      throw Exception('无法加载录像文件');
    }
    
    final playUrl = streamInfo.bestUrl!;
    debugPrint('[Playback] 获取到流媒体地址: $playUrl');
    
    _isCloudRecord = true;
    await _playCloudRecord(playUrl);
  }

  /// 播放云端录像（流媒体格式）
  /// 
  /// 【鸿蒙适配】增加超时时间，添加 User-Agent，智能格式选择
  Future<void> _playCloudRecord(String url) async {
    try {
      debugPrint('[Playback] 播放云端录像: $url');
      debugPrint('[Playback] 系统: ${Platform.operatingSystem}');
      
      _controller?.dispose();
      
      // 根据系统类型选择 User-Agent
      final userAgent = Platform.isIOS
          ? 'Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X) AppleWebKit/605.1.15'
          : 'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36';
      
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(url),
        httpHeaders: {
          'User-Agent': userAgent,
          'Accept': '*/*',
          'Accept-Language': 'zh-CN,zh;q=0.9',
        },
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: true,
          allowBackgroundPlayback: false,
        ),
      );
      
      // 云端录像使用 30 秒超时，兼容慢网络
      await _controller!.initialize().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('视频加载超时（30秒）');
        },
      );
      
      if (_controller!.value.hasError) {
        throw Exception(_controller!.value.errorDescription ?? '视频加载失败');
      }
      
      // 添加进度监听
      _controller!.addListener(_onPlayerUpdate);
      
      // 设置时长
      _duration = _controller!.value.duration;
      
      // 开始播放
      await _controller!.play();
      
      debugPrint('[Playback] ✓ 云端录像播放成功');
      
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isPlaying = true;
        });
        _startHideControlsTimer();
      }
      
    } catch (e) {
      debugPrint('[Playback] 云端录像播放失败: $e');
      throw Exception('云端录像播放失败: $e');
    }
  }

  /// 检测是否为鸿蒙系统
  bool _isHarmonyOS() {
    if (!Platform.isAndroid) return false;
    // 暂时使用简单判断
    return false;
  }

  /// 获取格式优先级列表
  /// 
  /// 【格式选择】
  /// 只使用 FMP4 格式，FLV 作为备用方案
  List<Map<String, dynamic>> _getFormatPriority(PlaybackResult result) {
    final formats = <Map<String, dynamic>>[];
    
    // FMP4 格式（主要）
    if (result.fmp4Url != null) {
      formats.add({'name': 'FMP4', 'url': result.fmp4Url, 'timeout': 20});
    }
    
    // FLV 格式（备用）
    if (result.flvUrl != null) {
      formats.add({'name': 'FLV', 'url': result.flvUrl, 'timeout': 20});
    }
    
    return formats;
  }

  /// 初始化播放器（国标回放，多格式回退）
  /// 
  /// 【格式选择】
  /// 只使用 FMP4 格式，FLV 作为备用方案
  Future<void> _initPlayer(PlaybackResult result) async {
    // 根据系统类型获取格式优先级
    final formats = _getFormatPriority(result);
    
    if (formats.isEmpty) {
      throw Exception('没有可用的播放格式');
    }
    
    String? lastError;
    
    for (final format in formats) {
      final url = format['url'] as String?;
      if (url == null) continue;
      
      final timeout = format['timeout'] as int? ?? 20;
      
      try {
        debugPrint('[Playback] 尝试 ${format['name']} 格式 (超时${timeout}秒): $url');
        debugPrint('[Playback] 系统: ${Platform.operatingSystem}, 鸿蒙: ${_isHarmonyOS()}');
        
        _controller?.dispose();
        
        // 根据系统类型选择 User-Agent
        final userAgent = Platform.isIOS
            ? 'Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X) AppleWebKit/605.1.15'
            : 'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36';
        
        _controller = VideoPlayerController.networkUrl(
          Uri.parse(url),
          httpHeaders: {
            'User-Agent': userAgent,
            'Accept': '*/*',
            'Accept-Language': 'zh-CN,zh;q=0.9',
          },
          videoPlayerOptions: VideoPlayerOptions(
            mixWithOthers: true,
            allowBackgroundPlayback: false,
          ),
        );
        
        await _controller!.initialize().timeout(
          Duration(seconds: timeout),
          onTimeout: () {
            throw Exception('${format['name']} 初始化超时（${timeout}秒）');
          },
        );
        
        if (_controller!.value.hasError) {
          throw Exception(_controller!.value.errorDescription ?? '初始化失败');
        }
        
        // 添加进度监听
        _controller!.addListener(_onPlayerUpdate);
        
        // 设置时长
        _duration = _controller!.value.duration;
        
        // 开始播放
        await _controller!.play();
        
        debugPrint('[Playback] ✓ ${format['name']} 播放成功');
        
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isPlaying = true;
          });
          _startHideControlsTimer();
        }
        
        return;
        
      } catch (e) {
        lastError = '${format['name']}: $e';
        debugPrint('[Playback] ✗ ${format['name']} 失败: $e');
        _controller?.dispose();
        _controller = null;
      }
    }
    
    // 所有格式都失败
    throw Exception(lastError ?? '无法播放录像');
  }

  /// 停止回放
  Future<void> _stopPlayback() async {
    // 如果是国标回放，需要通知服务器停止
    if (!_isCloudRecord && _playbackResult?.streamId != null) {
      await _wvpService.stopPlayback(
        deviceId: widget.deviceId,
        channelId: widget.channelId,
        streamId: _playbackResult!.streamId,
      );
    }
  }
  
  /// 播放下一个录像片段
  Future<void> _playNextRecord() async {
    if (_recordList.isEmpty || _currentRecordIndex >= _recordList.length - 1) {
      return;
    }
    
    _currentRecordIndex++;
    final record = _recordList[_currentRecordIndex];
    
    final playPath = await _wvpService.getCloudRecordPlayPath(recordId: record.id);
    if (playPath?.bestUrl != null) {
      await _playCloudRecord(playPath!.bestUrl!);
    }
  }
  
  /// 播放上一个录像片段
  Future<void> _playPreviousRecord() async {
    if (_recordList.isEmpty || _currentRecordIndex <= 0) {
      return;
    }
    
    _currentRecordIndex--;
    final record = _recordList[_currentRecordIndex];
    
    final playPath = await _wvpService.getCloudRecordPlayPath(recordId: record.id);
    if (playPath?.bestUrl != null) {
      await _playCloudRecord(playPath!.bestUrl!);
    }
  }

  /// 播放器状态更新
  void _onPlayerUpdate() {
    if (_controller != null && mounted) {
      setState(() {
        _position = _controller!.value.position;
        _isPlaying = _controller!.value.isPlaying;
        
        if (_controller!.value.hasError) {
          _error = _controller!.value.errorDescription;
        }
      });
    }
  }

  /// 切换播放/暂停
  void _togglePlayPause() {
    if (_controller == null) return;
    
    if (_isPlaying) {
      _controller!.pause();
    } else {
      _controller!.play();
    }
    
    _resetHideControlsTimer();
  }

  /// 拖动进度
  void _seekTo(Duration position) {
    _controller?.seekTo(position);
    _resetHideControlsTimer();
  }

  /// 设置倍速
  void _setSpeed(double speed) {
    _controller?.setPlaybackSpeed(speed);
    setState(() => _currentSpeed = speed);
    _resetHideControlsTimer();
  }

  /// 切换全屏
  void _toggleFullscreen() {
    setState(() => _isFullscreen = !_isFullscreen);
    
    if (_isFullscreen) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  /// 显示/隐藏控制栏
  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _startHideControlsTimer();
    }
  }

  /// 启动自动隐藏控制栏定时器
  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  /// 重置隐藏定时器
  void _resetHideControlsTimer() {
    if (_showControls) {
      _startHideControlsTimer();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: !_isFullscreen,
        bottom: !_isFullscreen,
        child: Column(
          children: [
            // 顶部栏（非全屏时显示）
            if (!_isFullscreen) _buildTopBar(),
            
            // 播放器区域
            Expanded(
              child: _buildPlayerArea(),
            ),
            
            // 底部信息（非全屏时显示）
            if (!_isFullscreen) _buildBottomInfo(),
          ],
        ),
      ),
    );
  }

  /// 顶部栏
  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: AppColors.cardBackground,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(PhosphorIconsBold.arrowLeft, color: AppColors.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title ?? '录像回放',
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${_formatTime(widget.startTime)} ~ ${_formatTime(widget.endTime)}',
                  style: AppTextStyles.tiny.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 播放器区域
  Widget _buildPlayerArea() {
    if (_isLoading) {
      return _buildLoadingView();
    }
    
    if (_error != null) {
      return _buildErrorView();
    }
    
    if (_controller != null && _controller!.value.isInitialized) {
      return _buildPlayerView();
    }
    
    return _buildLoadingView();
  }

  /// 加载中视图
  Widget _buildLoadingView() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 16),
            Text(
              '正在加载录像...',
              style: AppTextStyles.body.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              '${_formatTime(widget.startTime)} ~ ${_formatTime(widget.endTime)}',
              style: AppTextStyles.caption.copyWith(color: Colors.white60),
            ),
          ],
        ),
      ),
    );
  }

  /// 错误视图
  Widget _buildErrorView() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(PhosphorIconsBold.warningCircle, color: AppColors.error, size: 48),
            const SizedBox(height: 16),
            Text(
              '录像加载失败',
              style: AppTextStyles.body.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? '未知错误',
              style: AppTextStyles.caption.copyWith(color: Colors.white60),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '可能原因：\n• 该时间段无录像\n• 摄像头未开启本地录制\n• 网络连接问题',
              style: AppTextStyles.tiny.copyWith(color: Colors.white38),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _startPlayback,
              icon: const Icon(PhosphorIconsBold.arrowClockwise, size: 18),
              label: const Text('重试'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 播放器视图
  Widget _buildPlayerView() {
    return GestureDetector(
      onTap: _toggleControls,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 视频画面
          Center(
            child: AspectRatio(
              aspectRatio: _controller!.value.aspectRatio,
              child: VideoPlayer(_controller!),
            ),
          ),
          
          // 控制层
          if (_showControls) ...[
            // 半透明遮罩
            Container(color: Colors.black26),
            
            // 中间播放按钮
            Center(
              child: GestureDetector(
                onTap: _togglePlayPause,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white30, width: 2),
                  ),
                  child: Icon(
                    _isPlaying ? PhosphorIconsBold.pause : PhosphorIconsBold.play,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
            ),
            
            // 底部控制栏
            _buildBottomControls(),
            
            // 顶部控制栏（全屏时显示）
            if (_isFullscreen) _buildFullscreenTopBar(),
          ],
        ],
      ),
    );
  }

  /// 全屏时的顶部栏
  Widget _buildFullscreenTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black54, Colors.transparent],
          ),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(PhosphorIconsBold.arrowLeft, color: Colors.white),
              onPressed: _toggleFullscreen,
            ),
            Expanded(
              child: Text(
                widget.title ?? '录像回放',
                style: AppTextStyles.body.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 底部控制栏
  Widget _buildBottomControls() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black54, Colors.transparent],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 进度条
            Row(
              children: [
                Text(
                  _formatDuration(_position),
                  style: AppTextStyles.tiny.copyWith(color: Colors.white),
                ),
                Expanded(
                  child: Slider(
                    value: _position.inSeconds.toDouble(),
                    min: 0,
                    max: _duration.inSeconds.toDouble().clamp(1, double.infinity),
                    onChanged: (value) => _seekTo(Duration(seconds: value.toInt())),
                    activeColor: AppColors.primary,
                    inactiveColor: Colors.white30,
                  ),
                ),
                Text(
                  _formatDuration(_duration),
                  style: AppTextStyles.tiny.copyWith(color: Colors.white),
                ),
              ],
            ),
            
            // 控制按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // 倍速按钮
                _buildSpeedButton(),
                
                // 后退10秒
                IconButton(
                  icon: const Icon(PhosphorIconsBold.rewind, color: Colors.white),
                  onPressed: () => _seekTo(_position - const Duration(seconds: 10)),
                ),
                
                // 播放/暂停
                IconButton(
                  icon: Icon(
                    _isPlaying ? PhosphorIconsBold.pause : PhosphorIconsBold.play,
                    color: Colors.white,
                    size: 32,
                  ),
                  onPressed: _togglePlayPause,
                ),
                
                // 前进10秒
                IconButton(
                  icon: const Icon(PhosphorIconsBold.fastForward, color: Colors.white),
                  onPressed: () => _seekTo(_position + const Duration(seconds: 10)),
                ),
                
                // 全屏按钮
                IconButton(
                  icon: Icon(
                    _isFullscreen ? PhosphorIconsBold.cornersIn : PhosphorIconsBold.cornersOut,
                    color: Colors.white,
                  ),
                  onPressed: _toggleFullscreen,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 倍速按钮
  Widget _buildSpeedButton() {
    return PopupMenuButton<double>(
      initialValue: _currentSpeed,
      onSelected: _setSpeed,
      color: AppColors.cardBackground,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white54),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '${_currentSpeed}x',
          style: AppTextStyles.tiny.copyWith(color: Colors.white),
        ),
      ),
      itemBuilder: (context) => _speedOptions.map((speed) {
        return PopupMenuItem(
          value: speed,
          child: Text(
            '${speed}x',
            style: TextStyle(
              color: speed == _currentSpeed ? AppColors.primary : AppColors.textPrimary,
            ),
          ),
        );
      }).toList(),
    );
  }

  /// 底部信息区域
  Widget _buildBottomInfo() {
    final currentRecord = _cloudRecordResult?.record;
    
    return Container(
      padding: const EdgeInsets.all(16),
      color: AppColors.cardBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 录像来源标识
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _isCloudRecord ? AppColors.primary.withOpacity(0.1) : AppColors.success.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _isCloudRecord ? '☁️ 云端录像' : '📹 设备录像',
              style: AppTextStyles.tiny.copyWith(
                color: _isCloudRecord ? AppColors.primary : AppColors.success,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          
          const SizedBox(height: 12),
          
          // 设备信息
          Row(
            children: [
              Icon(PhosphorIconsBold.videoCamera, color: AppColors.textSecondary, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '设备: ${widget.deviceId}',
                  style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          // 时间信息
          Row(
            children: [
              Icon(PhosphorIconsBold.clock, color: AppColors.textSecondary, size: 16),
              const SizedBox(width: 8),
              Text(
                '查询时间: ${_formatTime(widget.startTime)} - ${_formatTime(widget.endTime)}',
                style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
          
          // 云端录像信息
          if (_isCloudRecord && currentRecord != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(PhosphorIconsBold.file, color: AppColors.textSecondary, size: 16),
                const SizedBox(width: 8),
                Text(
                  '文件大小: ${currentRecord.formattedFileSize}',
                  style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(width: 16),
                Text(
                  '时长: ${currentRecord.formattedDuration}',
                  style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ],
          
          // 多段录像导航
          if (_recordList.length > 1) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '录像片段: ${_currentRecordIndex + 1}/${_recordList.length}',
                  style: AppTextStyles.caption.copyWith(color: AppColors.textPrimary),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _currentRecordIndex > 0 ? _playPreviousRecord : null,
                  icon: const Icon(PhosphorIconsBold.caretLeft, size: 16),
                  label: const Text('上一段'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
                TextButton.icon(
                  onPressed: _currentRecordIndex < _recordList.length - 1 ? _playNextRecord : null,
                  icon: const Icon(PhosphorIconsBold.caretRight, size: 16),
                  label: const Text('下一段'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ],
            ),
          ],
          
          const SizedBox(height: 12),
          
          // 提示信息
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surfaceBackground,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(PhosphorIconsBold.info, color: AppColors.primary, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '录像在线播放，不占用手机存储空间',
                    style: AppTextStyles.tiny.copyWith(color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 格式化时长
  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// 格式化时间
  String _formatTime(DateTime time) {
    return '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}

