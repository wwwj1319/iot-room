/// 全屏 WebView 视频播放页面
/// 
/// 【功能说明】
/// 使用 WebView 播放视频流的全屏页面，解决鸿蒙系统兼容性问题。
/// 支持：
/// - 横屏/竖屏自动切换
/// - 实时截图（通过服务器 API）
/// - 沉浸式体验
///
/// 原来的 FullscreenVideoPage 使用 video_player（ExoPlayer），
/// 在鸿蒙系统上会出现 MediaCodecVideoRenderer 解码错误。
/// 这个 WebView 版本通过浏览器内核播放，兼容性更好。

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../services/wvp_service.dart';
import '../../../services/gallery_service.dart';

/// 全屏 WebView 视频播放页面
class FullscreenWebViewVideoPage extends StatefulWidget {
  /// 设备ID
  final String? deviceId;
  
  /// 通道ID
  final String? channelId;
  
  /// 摄像头名称
  final String? cameraName;

  const FullscreenWebViewVideoPage({
    super.key,
    this.deviceId,
    this.channelId,
    this.cameraName,
  });

  @override
  State<FullscreenWebViewVideoPage> createState() => _FullscreenWebViewVideoPageState();
}

class _FullscreenWebViewVideoPageState extends State<FullscreenWebViewVideoPage>
    with SingleTickerProviderStateMixin {
  /// 服务实例
  final WvpService _wvpService = WvpService();
  final GalleryService _galleryService = GalleryService();
  
  /// WebView 控制器
  WebViewController? _controller;
  
  /// 状态标志
  bool _isLoading = true;
  bool _isPlaying = false;
  bool _showControls = true;
  bool _isSavingSnapshot = false;
  String? _error;
  
  /// 详细调试日志
  final List<String> _debugLogs = [];
  
  /// 报警状态
  bool _hasAlarm = false;
  
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
    
    // 开始播放
    _startPlay();
    
    // 启动控制栏自动隐藏
    _startHideControlsTimer();
  }

  @override
  void dispose() {
    // 【重要】先停止 WebView 播放，避免资源冲突导致崩溃
    _stopPlay();
    _hideControlsTimer?.cancel();
    _alarmAnimController.dispose();
    // 最后恢复屏幕方向
    _restoreOrientation();
    super.dispose();
  }
  
  /// 停止播放并清理 WebView
  void _stopPlay() {
    // 清除 WebView 控制器引用，让系统回收资源
    _controller = null;
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
  /// 【鸿蒙兼容】使用 FMP4 协议，浏览器原生支持
  Future<void> _startPlay() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _debugLogs.clear();
    });
    
    _debugLogs.add('=== WebView 全屏播放器调试信息 ===');
    _debugLogs.add('时间: ${DateTime.now()}');
    
    try {
      // 获取视频流 URL（使用 FMP4，浏览器原生支持，兼容鸿蒙）
      final fmp4Url = WvpConfig.getDirectFmp4Url(
        deviceId: widget.deviceId,
        channelId: widget.channelId,
      );
      
      _debugLogs.add('FMP4 URL: $fmp4Url');
      
      debugPrint('[WebView Fullscreen] 初始化 WebView...');
      debugPrint('[WebView Fullscreen] FMP4 URL: $fmp4Url');
      
      // 创建 WebView 控制器
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.black)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (url) {
              debugPrint('[WebView Fullscreen] 页面开始加载: $url');
              _debugLogs.add('页面开始加载');
            },
            onPageFinished: (url) {
              debugPrint('[WebView Fullscreen] 页面加载完成: $url');
              _debugLogs.add('页面加载完成');
              if (mounted) {
                setState(() {
                  _isLoading = false;
                  _isPlaying = true;
                });
              }
            },
            onWebResourceError: (error) {
              debugPrint('[WebView Fullscreen] 加载错误: ${error.description}');
              _debugLogs.add('错误: ${error.description}');
              if (mounted) {
                setState(() {
                  _isLoading = false;
                  _error = '视频加载失败: ${error.description}';
                });
              }
            },
          ),
        )
        ..addJavaScriptChannel(
          'FlutterChannel',
          onMessageReceived: (message) {
            _handleJsMessage(message.message);
          },
        );
      
      // 生成 HTML 内容（使用 FMP4）
      final htmlContent = _generateVideoHtml(fmp4Url);
      
      // 加载 HTML
      await _controller!.loadHtmlString(htmlContent);
      
      _debugLogs.add('WebView 初始化成功');
      
    } catch (e, stackTrace) {
      debugPrint('[WebView Fullscreen] 初始化失败: $e');
      debugPrint('[WebView Fullscreen] 堆栈: $stackTrace');
      _debugLogs.add('初始化失败: $e');
      
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = '播放器初始化失败: $e';
        });
      }
    }
  }

  /// 处理 JavaScript 消息
  void _handleJsMessage(String message) {
    debugPrint('[WebView Fullscreen] JS消息: $message');
    _debugLogs.add('JS: $message');
    
    try {
      final data = jsonDecode(message);
      final type = data['type'] as String?;
      
      switch (type) {
        case 'error':
          final errorMsg = data['message'] as String? ?? '未知错误';
          if (mounted) {
            setState(() {
              _error = errorMsg;
              _isPlaying = false;
            });
          }
          break;
        case 'playing':
          if (mounted) {
            setState(() {
              _isPlaying = true;
              _isLoading = false;
            });
          }
          break;
        case 'loaded':
          debugPrint('[WebView Fullscreen] 视频已加载');
          break;
      }
    } catch (_) {
      // 非 JSON 消息，忽略
    }
  }

  /// 生成视频播放 HTML（FMP4 格式）
  /// 
  /// 【鸿蒙兼容说明】
  /// FMP4 (Fragmented MP4) 是 HTML5 video 标签原生支持的格式：
  /// 1. 无需任何 JavaScript 库，浏览器直接播放
  /// 2. ZLMediaKit 的 .live.mp4 是持续的 HTTP 流
  /// 3. 兼容 Android/iOS/鸿蒙 所有平台的 WebView
  String _generateVideoHtml(String fmp4Url) {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>全屏视频</title>
  <style>
    * {
      margin: 0;
      padding: 0;
      box-sizing: border-box;
    }
    html, body {
      width: 100%;
      height: 100%;
      background: #000;
      overflow: hidden;
    }
    .video-container {
      width: 100%;
      height: 100%;
      display: flex;
      align-items: center;
      justify-content: center;
      position: relative;
    }
    video {
      width: 100%;
      height: 100%;
      object-fit: contain;
      background: #000;
    }
    .loading {
      position: absolute;
      top: 50%;
      left: 50%;
      transform: translate(-50%, -50%);
      color: #00D4FF;
      font-size: 16px;
      text-align: center;
    }
    .loading-spinner {
      width: 50px;
      height: 50px;
      border: 4px solid rgba(0, 212, 255, 0.3);
      border-top-color: #00D4FF;
      border-radius: 50%;
      animation: spin 1s linear infinite;
      margin: 0 auto 15px;
    }
    @keyframes spin {
      to { transform: rotate(360deg); }
    }
    .error {
      position: absolute;
      top: 50%;
      left: 50%;
      transform: translate(-50%, -50%);
      color: #EF4444;
      font-size: 16px;
      text-align: center;
      padding: 20px;
    }
    .hidden {
      display: none;
    }
  </style>
</head>
<body>
  <div class="video-container">
    <video id="videoPlayer" 
           playsinline 
           webkit-playsinline
           x5-video-player-type="h5"
           x5-video-player-fullscreen="true"
           autoplay
           muted>
      您的浏览器不支持视频播放
    </video>
    <div id="loadingIndicator" class="loading">
      <div class="loading-spinner"></div>
      <div>正在连接摄像头...</div>
    </div>
    <div id="errorIndicator" class="error hidden"></div>
  </div>
  
  <script>
    const video = document.getElementById('videoPlayer');
    const loadingIndicator = document.getElementById('loadingIndicator');
    const errorIndicator = document.getElementById('errorIndicator');
    
    // FMP4 流地址（浏览器原生支持，无需额外库）
    const videoUrl = '$fmp4Url';
    let retryCount = 0;
    const maxRetries = 3;
    
    // 发送消息给 Flutter
    function sendToFlutter(type, message) {
      try {
        FlutterChannel.postMessage(JSON.stringify({ type, message }));
      } catch (e) {
        console.log('FlutterChannel not available:', e);
      }
    }
    
    // 显示错误
    function showError(message) {
      loadingIndicator.classList.add('hidden');
      errorIndicator.classList.remove('hidden');
      errorIndicator.textContent = message;
      sendToFlutter('error', message);
    }
    
    // 隐藏加载指示器
    function hideLoading() {
      loadingIndicator.classList.add('hidden');
    }
    
    // 重试加载
    function retryLoad() {
      retryCount++;
      if (retryCount <= maxRetries) {
        console.log('重试加载 FMP4，第', retryCount, '次');
        setTimeout(() => loadVideo(), 2000);
      } else {
        showError('视频加载失败，请点击重试按钮');
      }
    }
    
    // 尝试播放视频
    function tryPlay() {
      const playPromise = video.play();
      if (playPromise !== undefined) {
        playPromise.then(() => {
          console.log('FMP4 播放成功');
          hideLoading();
          sendToFlutter('playing', 'FMP4');
        }).catch(error => {
          console.log('自动播放失败，尝试静音播放:', error);
          video.muted = true;
          video.play().then(() => {
            console.log('静音播放成功');
            hideLoading();
            sendToFlutter('playing', 'FMP4');
          }).catch(e => {
            console.log('静音播放也失败:', e);
            showError('播放失败，请点击视频重试');
          });
        });
      }
    }
    
    // 加载视频
    function loadVideo() {
      console.log('加载 FMP4 视频:', videoUrl);
      
      // FMP4 格式浏览器原生支持，直接设置 src
      video.src = videoUrl;
      video.load();
      tryPlay();
    }
    
    // 视频事件监听
    video.addEventListener('loadeddata', function() {
      console.log('FMP4 视频数据已加载');
      sendToFlutter('loaded', 'success');
    });
    
    video.addEventListener('canplay', function() {
      console.log('FMP4 视频可以播放');
      hideLoading();
    });
    
    video.addEventListener('playing', function() {
      console.log('FMP4 视频正在播放');
      hideLoading();
      sendToFlutter('playing', 'FMP4');
    });
    
    video.addEventListener('waiting', function() {
      console.log('视频缓冲中...');
    });
    
    video.addEventListener('timeupdate', function() {
      if (video.readyState >= 3) {
        hideLoading();
      }
    });
    
    video.addEventListener('error', function(e) {
      const error = video.error;
      let errorMessage = '视频加载失败';
      
      if (error) {
        switch (error.code) {
          case error.MEDIA_ERR_ABORTED:
            errorMessage = '视频加载被中止';
            break;
          case error.MEDIA_ERR_NETWORK:
            errorMessage = '网络错误，请检查网络连接';
            break;
          case error.MEDIA_ERR_DECODE:
            errorMessage = '视频解码错误';
            break;
          case error.MEDIA_ERR_SRC_NOT_SUPPORTED:
            errorMessage = '视频格式不支持';
            break;
        }
      }
      
      console.log('FMP4 视频错误:', errorMessage, error);
      retryLoad();
    });
    
    video.addEventListener('stalled', function() {
      console.log('视频流停滞，尝试恢复...');
      video.load();
    });
    
    // 点击视频时尝试播放（用户交互触发）
    video.addEventListener('click', function() {
      if (video.paused) {
        video.play().catch(e => console.log('点击播放失败:', e));
      }
    });
    
    // 开始加载
    loadVideo();
    
    // 30秒超时检测
    setTimeout(function() {
      if (video.readyState < 3 && !video.paused) {
        console.log('加载超时');
        retryLoad();
      }
    }, 30000);
  </script>
</body>
</html>
''';
  }

  /// 截图并保存到相册
  Future<void> _takeSnapshot() async {
    if (_isSavingSnapshot) return;
    
    setState(() => _isSavingSnapshot = true);
    
    try {
      // 从服务器获取截图
      debugPrint('[WebView Fullscreen] 正在从服务器获取截图...');
      final imageBytes = await _wvpService.getSnapshotBytes();
      
      if (imageBytes == null || imageBytes.isEmpty) {
        throw Exception('获取截图失败，请确保视频正在播放');
      }
      
      debugPrint('[WebView Fullscreen] 服务器截图成功，保存到相册...');
      final result = await _galleryService.saveImageFromBytes(
        imageBytes,
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
      debugPrint('[WebView Fullscreen] 截图失败: $e');
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
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 视频画面
          _buildVideoView(),
          
          // 【修复】只在播放时才显示透明手势检测层
          // 避免覆盖错误视图中的重试按钮
          if (_isPlaying && _error == null)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _toggleControls,
                child: Container(color: Colors.transparent),
              ),
            ),
          
          // 报警边框（闪烁效果）
          if (_hasAlarm) _buildAlarmBorder(),
          
          // 控制栏（使用动画平滑显示/隐藏）- 只在播放时显示
          if (_isPlaying && _error == null)
            AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_showControls,
                child: Stack(
                  children: [
                    _buildTopBar(),
                    _buildBottomBar(),
                  ],
                ),
              ),
            ),
        ],
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
            SizedBox(height: 8),
            Text(
              '(WebView 模式)',
              style: TextStyle(color: Colors.white54, fontSize: 12),
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
              ElevatedButton.icon(
                onPressed: _startPlay,
                icon: const Icon(PhosphorIconsBold.arrowClockwise, size: 16),
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

    if (_controller != null && _isPlaying) {
      return SizedBox.expand(
        child: WebViewWidget(controller: _controller!),
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
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'WebView',
                            style: AppTextStyles.tiny.copyWith(
                              color: Colors.white70,
                              fontSize: 10,
                            ),
                          ),
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

