/// 全屏视频播放页面
/// 
/// 【功能说明】
/// 提供沉浸式的全屏视频监控体验，支持：
/// - 横屏/竖屏自动切换
/// - 实时截图
/// - 录像控制
/// - 报警提示
/// 
/// 【实现说明】
/// 全屏播放是视频监控的核心功能，需要考虑：
/// 1. 屏幕方向控制（强制横屏或跟随系统）
/// 2. 系统UI隐藏（沉浸式体验）
/// 3. 手势操作（双击暂停、滑动调节等）
/// 4. 报警时的红色边框闪烁效果

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../services/wvp_service.dart';
import '../../../services/gallery_service.dart';

/// 全屏视频播放页面
class FullscreenVideoPage extends StatefulWidget {
  /// 设备ID
  final String? deviceId;
  
  /// 通道ID
  final String? channelId;
  
  /// 摄像头名称
  final String? cameraName;

  const FullscreenVideoPage({
    super.key,
    this.deviceId,
    this.channelId,
    this.cameraName,
  });

  @override
  State<FullscreenVideoPage> createState() => _FullscreenVideoPageState();
}

class _FullscreenVideoPageState extends State<FullscreenVideoPage>
    with SingleTickerProviderStateMixin {
  /// 相册服务
  final GalleryService _galleryService = GalleryService();
  
  /// 视频画面截图用的 Key
  final GlobalKey _videoKey = GlobalKey();
  
  /// 视频播放器控制器
  VideoPlayerController? _controller;
  
  /// 状态标志
  bool _isLoading = true;
  bool _isPlaying = false;
  bool _showControls = true;
  bool _isSavingSnapshot = false;
  String? _error;
  
  /// 详细调试日志（用于鸿蒙等系统调试）
  final List<String> _debugLogs = [];
  
  /// 报警状态
  bool _hasAlarm = false;
  // ignore: unused_field - 用于后续扩展功能（如显示报警详情）
  AlarmInfo? _currentAlarm;
  
  /// 报警边框闪烁动画
  late AnimationController _alarmAnimController;
  late Animation<double> _alarmAnimation;
  
  /// 控制栏自动隐藏定时器
  Timer? _hideControlsTimer;

  @override
  void initState() {
    super.initState();
    
    // 初始化报警动画
    _alarmAnimController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _alarmAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _alarmAnimController, curve: Curves.easeInOut),
    );
    
    // 设置横屏
    _setLandscape();
    
    // 注意：报警轮询已移至 AlarmPollingService（轮询 alarm_receiver.py 服务器）
    // WVP 报警 API 已停用
    
    // 开始播放
    _startPlay();
    
    // 启动控制栏自动隐藏
    _startHideControlsTimer();
  }

  @override
  void dispose() {
    _restoreOrientation();
    _hideControlsTimer?.cancel();
    _alarmAnimController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  /// 设置横屏
  void _setLandscape() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  /// 恢复屏幕方向
  void _restoreOrientation() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }


  /// 开始播放
  /// 
  /// 【多格式回退策略】
  /// 为了兼容 Android 和鸿蒙系统，按以下顺序尝试不同格式：
  /// 1. HLS  - 兼容性最好（所有手机都支持），但延迟高
  /// 2. FMP4 - 延迟中等，现代 Android 支持好
  /// 3. TS   - 稳定格式，备用方案
  /// 
  /// 【鸿蒙适配说明】
  /// 鸿蒙系统对 FMP4 格式支持不稳定，优先使用 HLS 可以解决超时问题
  Future<void> _startPlay() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _debugLogs.clear();
    });
    
    // 添加系统信息到调试日志
    _debugLogs.add('=== 调试信息 ===');
    _debugLogs.add('时间: ${DateTime.now()}');
    _debugLogs.add('页面: 全屏视频');

    // 定义格式 URL，只使用 FMP4，TS 作为备用
    final formats = [
      {
        'name': 'FMP4',
        'url': WvpConfig.getDirectFmp4Url(
          deviceId: widget.deviceId,
          channelId: widget.channelId,
        ),
        'timeout': 20,
      },
      {
        'name': 'TS',
        'url': WvpConfig.getDirectTsUrl(
          deviceId: widget.deviceId,
          channelId: widget.channelId,
        ),
        'timeout': 20,
      },
    ];

    String? lastError;
    
    for (final format in formats) {
      try {
        final timeout = format['timeout'] as int? ?? 20;
        final url = format['url'] as String;
        
        _debugLogs.add('');
        _debugLogs.add('--- ${format['name']} ---');
        _debugLogs.add('URL: $url');
        _debugLogs.add('超时: ${timeout}秒');
        
        debugPrint('[FullscreenVideo] 尝试 ${format['name']} 格式 (超时${timeout}秒): $url');
        
        // 先释放之前的控制器
        _controller?.dispose();
        _controller = null;
        
        // 创建新的播放器
        // 【兼容性优化】提升鸿蒙和 Android 兼容性
        final userAgent = Platform.isIOS
            ? 'Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X) AppleWebKit/605.1.15'
            : 'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36';
        
        _controller = VideoPlayerController.networkUrl(
          Uri.parse(url),
          httpHeaders: {
            'User-Agent': userAgent,
            'Accept': '*/*',
            'Accept-Language': 'zh-CN,zh;q=0.9',
            'Connection': 'keep-alive',
            'Cache-Control': 'no-cache',
          },
          videoPlayerOptions: VideoPlayerOptions(
            mixWithOthers: false,  // 改为 false，避免与其他音频混合
            allowBackgroundPlayback: false,
          ),
        );
        
        // 【优化】增加初始化前的延迟
        await Future.delayed(const Duration(milliseconds: 100));
        
        // 设置超时时间
        await _controller!.initialize().timeout(
          Duration(seconds: timeout),
          onTimeout: () {
            throw Exception('初始化超时（${timeout}秒）');
          },
        );
        
        // 检查是否成功初始化
        if (_controller!.value.hasError) {
          final errorDesc = _controller!.value.errorDescription ?? '初始化失败';
          throw Exception('播放器初始化失败: $errorDesc');
        }
        
        // 【优化】初始化后稍作延迟再播放
        await Future.delayed(const Duration(milliseconds: 200));
        
        await _controller!.play();
        
        // 【优化】播放后再次检查错误状态
        await Future.delayed(const Duration(milliseconds: 500));
        if (_controller!.value.hasError) {
          final errorDesc = _controller!.value.errorDescription ?? '播放失败';
          throw Exception('播放失败: $errorDesc');
        }
        
        _debugLogs.add('结果: ✓ 成功');
        debugPrint('[FullscreenVideo] ✓ ${format['name']} 播放成功');
        
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isPlaying = true;
          });
        }
        
        // 成功后直接返回
        return;
        
      } catch (e, stackTrace) {
        final errorMsg = e.toString();
        lastError = '${format['name']}: $errorMsg';
        
        _debugLogs.add('结果: ✗ 失败');
        _debugLogs.add('错误: $errorMsg');
        _debugLogs.add('堆栈: ${stackTrace.toString().split('\n').take(3).join('\n')}');
        
        debugPrint('[FullscreenVideo] ✗ ${format['name']} 失败: $e');
        
        // 清理失败的控制器
        _controller?.dispose();
        _controller = null;
        
        continue;
      }
    }
    
    // 所有格式都失败了
    _debugLogs.add('');
    _debugLogs.add('=== 所有格式都失败 ===');
    debugPrint('[FullscreenVideo] 所有格式都失败');
    
    if (mounted) {
      setState(() {
        _isLoading = false;
        _error = '视频加载失败\n$lastError\n请检查摄像头状态';
      });
    }
  }

  /// 截图并保存到相册
  /// 
  /// 【实现说明】
  /// 直接从当前播放画面截图，保存到手机相册
  /// 不依赖网络 API，速度快
  Future<void> _takeSnapshot() async {
    if (_isSavingSnapshot) return;
    
    setState(() => _isSavingSnapshot = true);
    
    try {
      // 直接从视频画面截图
      final capturedBytes = await _captureVideoFrame();
      if (capturedBytes == null) {
        throw Exception('视频画面未就绪');
      }
      
      debugPrint('[FullscreenVideo] 本地截图成功，保存到相册...');
      final result = await _galleryService.saveImageFromBytes(
        capturedBytes,
        fileName: 'IOT_SNAPSHOT_${DateTime.now().millisecondsSinceEpoch}',
      );
      
      // 显示结果
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  result.success ? PhosphorIconsBold.checkCircle : PhosphorIconsBold.xCircle,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(result.message),
              ],
            ),
            backgroundColor: result.success ? AppColors.success : AppColors.error,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      
    } catch (e) {
      debugPrint('[FullscreenVideo] 截图失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('截图失败: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingSnapshot = false);
      }
    }
  }
  
  /// 从当前视频画面捕获截图
  /// 
  /// 【实现说明】
  /// 使用 RepaintBoundary 捕获当前渲染的视频帧
  /// 这种方式不依赖网络，速度快，但需要视频正在播放
  Future<Uint8List?> _captureVideoFrame() async {
    try {
      final boundary = _videoKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        debugPrint('[FullscreenVideo] 无法获取 RenderRepaintBoundary');
        return null;
      }
      
      // 捕获当前帧
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      
      if (byteData == null) {
        debugPrint('[FullscreenVideo] 无法转换图像数据');
        return null;
      }
      
      return byteData.buffer.asUint8List();
    } catch (e) {
      debugPrint('[FullscreenVideo] 捕获视频帧失败: $e');
      return null;
    }
  }

  /// 启动控制栏自动隐藏定时器
  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  /// 切换控制栏显示
  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _startHideControlsTimer();
    }
  }
  
  /// 显示调试日志对话框
  void _showDebugLogs() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(PhosphorIconsBold.bug, color: AppColors.warning, size: 24),
            const SizedBox(width: 8),
            const Text('调试日志', style: TextStyle(color: AppColors.textPrimary)),
            const Spacer(),
            IconButton(
              onPressed: () {
                // 打印日志到控制台
                final logText = _debugLogs.join('\n');
                debugPrint(logText);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('日志已打印到控制台')),
                );
              },
              icon: const Icon(PhosphorIconsBold.copy, size: 20),
              color: AppColors.textSecondary,
              tooltip: '复制日志',
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                _debugLogs.isEmpty ? '暂无日志' : _debugLogs.join('\n'),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        onDoubleTap: () {
          if (_isPlaying) {
            // 暂停时同时静音，防止声音继续播放
            _controller?.pause();
            _controller?.setVolume(0);
            setState(() => _isPlaying = false);
          } else {
            // 播放时恢复音量
            _controller?.setVolume(1.0);
            _controller?.play();
            setState(() => _isPlaying = true);
          }
        },
        child: Stack(
          children: [
            // 视频画面
            _buildVideoView(),
            
            // 报警边框（闪烁效果）
            if (_hasAlarm) _buildAlarmBorder(),
            
            // 控制栏
            if (_showControls) ...[
              _buildTopBar(),
              _buildBottomBar(),
            ],
          ],
        ),
      ),
    );
  }

  /// 视频画面
  Widget _buildVideoView() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            SizedBox(height: 16),
            Text(
              '正在连接摄像头...',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(PhosphorIconsBold.warningCircle, color: AppColors.error, size: 48),
              const SizedBox(height: 16),
              Text(
                '连接失败',
                style: AppTextStyles.body.copyWith(color: AppColors.error),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _startPlay,
                    icon: const Icon(PhosphorIconsBold.arrowClockwise, size: 16),
                    label: const Text('重试'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: _showDebugLogs,
                    icon: const Icon(PhosphorIconsBold.bug, size: 16),
                    label: const Text('查看详情'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white70,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (_controller != null && _controller!.value.isInitialized) {
      return Center(
        child: RepaintBoundary(
          key: _videoKey,
          child: AspectRatio(
            aspectRatio: _controller!.value.aspectRatio,
            child: VideoPlayer(_controller!),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  /// 报警边框
  Widget _buildAlarmBorder() {
    return AnimatedBuilder(
      animation: _alarmAnimation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: AppColors.error.withOpacity(_alarmAnimation.value),
              width: 4,
            ),
          ),
        );
      },
    );
  }

  /// 顶部控制栏
  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withOpacity(0.7),
              Colors.transparent,
            ],
          ),
        ),
        child: SafeArea(
          child: Row(
            children: [
              // 返回按钮
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(PhosphorIconsBold.x, color: Colors.white),
              ),
              const SizedBox(width: 12),
              
              // 摄像头名称
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.cameraName ?? '摄像头',
                      style: AppTextStyles.body.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.error,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'LIVE',
                          style: AppTextStyles.tiny.copyWith(color: Colors.white70),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // 报警提示
              if (_hasAlarm)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(PhosphorIconsBold.warning, color: Colors.white, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        '火灾报警',
                        style: AppTextStyles.caption.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 底部控制栏
  Widget _buildBottomBar() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withOpacity(0.7),
              Colors.transparent,
            ],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 截图
              _buildControlButton(
                icon: PhosphorIconsBold.camera,
                label: '截图',
                onTap: _isSavingSnapshot ? () {} : _takeSnapshot,
                isLoading: _isSavingSnapshot,
              ),
              const SizedBox(width: 32),
              
              // 播放/暂停
              _buildControlButton(
                icon: _isPlaying ? PhosphorIconsBold.pause : PhosphorIconsBold.play,
                label: _isPlaying ? '暂停' : '播放',
                onTap: () {
                  if (_isPlaying) {
                    // 暂停时同时静音，防止声音继续播放
                    _controller?.pause();
                    _controller?.setVolume(0);
                  } else {
                    // 播放时恢复音量
                    _controller?.setVolume(1.0);
                    _controller?.play();
                  }
                  setState(() => _isPlaying = !_isPlaying);
                },
                isPrimary: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 控制按钮
  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isPrimary = false,
    bool isRecording = false,
    bool isLoading = false,
  }) {
    final color = isRecording ? AppColors.error : (isPrimary ? AppColors.primary : Colors.white);
    
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: isPrimary ? 56 : 44,
            height: isPrimary ? 56 : 44,
            decoration: BoxDecoration(
              color: isPrimary ? AppColors.primary : Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
              border: isRecording ? Border.all(color: AppColors.error, width: 2) : null,
            ),
            child: isLoading
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                  )
                : Icon(
                    icon,
                    color: isPrimary ? Colors.white : color,
                    size: isPrimary ? 28 : 22,
                  ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: AppTextStyles.tiny.copyWith(
              color: color,
              fontWeight: isRecording ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

