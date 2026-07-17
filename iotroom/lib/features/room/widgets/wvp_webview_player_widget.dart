/// WVP WebView 视频播放组件
/// 
/// 【功能说明】
/// 使用 WebView 内嵌网页播放视频流，解决鸿蒙系统兼容性问题。
/// 优点：
/// 1. 依赖浏览器内核解码，兼容性更好
/// 2. 支持 HLS/FMP4 等格式
/// 3. 跨平台一致性好
/// 
/// 【实现说明】
/// 原来使用 video_player 插件（基于 ExoPlayer），在鸿蒙系统上
/// 出现 MediaCodecVideoRenderer 解码错误。
/// 改用 WebView 播放可以绕过原生播放器的兼容性问题。

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../services/wvp_service.dart';

/// WVP WebView 视频播放组件
class WvpWebViewPlayerWidget extends StatefulWidget {
  /// 设备国标编号（可选，默认使用配置中的值）
  final String? deviceId;
  
  /// 通道编号（可选，默认使用配置中的值）
  final String? channelId;
  
  /// 摄像头在线状态
  final bool isOnline;
  
  /// 摄像头显示名称
  final String? cameraName;
  
  /// 全屏按钮回调
  final VoidCallback? onFullscreen;
  
  /// 截图回调（返回截图 URL）
  final ValueChanged<String>? onSnapshot;
  
  /// 报警回调
  final ValueChanged<AlarmInfo>? onAlarm;

  const WvpWebViewPlayerWidget({
    super.key,
    this.deviceId,
    this.channelId,
    this.isOnline = true,
    this.cameraName,
    this.onFullscreen,
    this.onSnapshot,
    this.onAlarm,
  });

  @override
  State<WvpWebViewPlayerWidget> createState() => _WvpWebViewPlayerWidgetState();
}

class _WvpWebViewPlayerWidgetState extends State<WvpWebViewPlayerWidget> {
  /// WebView 控制器
  WebViewController? _controller;
  
  /// 状态标志
  bool _isLoading = false;
  bool _isPlaying = false;
  String? _error;
  
  /// 详细调试日志
  final List<String> _debugLogs = [];

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _stopPlay();
    super.dispose();
  }
  
  /// 【公开方法】重置到空闲状态
  /// 
  /// 用于从全屏退出后，让小屏播放器回到初始状态（显示"点击播放实时画面"）
  /// 而不是显示错误信息或debug按钮
  void resetToIdle() {
    _stopPlay();
    if (mounted) {
      setState(() {
        _isLoading = false;
        _isPlaying = false;
        _error = null;
        _controller = null;
        _debugLogs.clear();
      });
    }
  }

  /// 开始播放
  /// 
  /// 【WebView 播放策略 - 鸿蒙兼容】
  /// 使用 FMP4 格式，因为：
  /// 1. FMP4 是浏览器原生支持的格式，无需额外 JavaScript 库
  /// 2. 兼容性最好，鸿蒙/Android/iOS 都原生支持
  /// 3. ZLMediaKit 的 .live.mp4 是持续的 HTTP 流，支持直播
  /// 4. 不依赖 hls.js 等第三方库，更稳定
  Future<void> _startPlay() async {
    if (!widget.isOnline) {
      setState(() => _error = '摄像头离线');
      return;
    }
    
    setState(() {
      _isLoading = true;
      _error = null;
      _debugLogs.clear();
    });
    
    _debugLogs.add('=== WebView 播放器调试信息 ===');
    _debugLogs.add('时间: ${DateTime.now()}');
    
    try {
      // 获取视频流 URL
      // WebView 中使用 FMP4 格式，浏览器原生支持，兼容鸿蒙系统
      final fmp4Url = WvpConfig.getDirectFmp4Url(
        deviceId: widget.deviceId,
        channelId: widget.channelId,
      );
      
      _debugLogs.add('FMP4 URL: $fmp4Url');
      
      debugPrint('[WebView Player] 初始化 WebView...');
      debugPrint('[WebView Player] FMP4 URL: $fmp4Url');
      
      // 创建 WebView 控制器
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.black)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (url) {
              debugPrint('[WebView Player] 页面开始加载: $url');
              _debugLogs.add('页面开始加载');
            },
            onPageFinished: (url) {
              debugPrint('[WebView Player] 页面加载完成: $url');
              _debugLogs.add('页面加载完成');
              if (mounted) {
                setState(() {
                  _isLoading = false;
                  _isPlaying = true;
                });
              }
            },
            onWebResourceError: (error) {
              debugPrint('[WebView Player] 加载错误: ${error.description}');
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
      debugPrint('[WebView Player] 初始化失败: $e');
      debugPrint('[WebView Player] 堆栈: $stackTrace');
      _debugLogs.add('初始化失败: $e');
      
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = '播放器初始化失败: $e';
        });
      }
    }
  }

  /// 停止播放
  void _stopPlay() {
    _controller = null;
    
    if (mounted) {
      setState(() {
        _isPlaying = false;
      });
    }
  }

  /// 处理 JavaScript 消息
  void _handleJsMessage(String message) {
    debugPrint('[WebView Player] JS消息: $message');
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
          debugPrint('[WebView Player] 视频已加载');
          break;
      }
    } catch (_) {
      // 非 JSON 消息，忽略
    }
  }

  /// 生成视频播放 HTML
  /// 
  /// 【实现说明】
  /// 这个 HTML 页面包含：
  /// 1. 一个 video 标签用于播放视频（使用 HLS 格式）
  /// 2. 简单的样式让视频铺满整个页面
  /// 3. JavaScript 用于处理播放状态和错误
  /// 4. 自动播放和循环尝试机制
  /// 
  /// 【重要】
  /// HLS 格式在浏览器中会自动处理流媒体播放，持续加载新分片
  /// 而 FMP4 在 HTML5 video 标签中只会加载第一个片段，不适合直播流
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
  <title>视频播放</title>
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
      font-size: 14px;
      text-align: center;
    }
    .loading-spinner {
      width: 40px;
      height: 40px;
      border: 3px solid rgba(0, 212, 255, 0.3);
      border-top-color: #00D4FF;
      border-radius: 50%;
      animation: spin 1s linear infinite;
      margin: 0 auto 10px;
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
      font-size: 14px;
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
        showError('视频加载失败，请点击重试');
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
          // 自动播放失败时，确保静音后重试
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
      // 流停滞时尝试继续加载
      video.load();
    });
    
    video.addEventListener('timeupdate', function() {
      if (video.readyState >= 3) {
        hideLoading();
      }
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

  @override
  Widget build(BuildContext context) {
    // 摄像头离线
    if (!widget.isOnline) {
      return _buildOfflineView();
    }

    // 加载中
    if (_isLoading) {
      return _buildLoadingView();
    }

    // 错误
    if (_error != null) {
      return _buildErrorView();
    }

    // 正在播放
    if (_isPlaying && _controller != null) {
      return _buildPlayerView();
    }

    // 显示播放按钮
    return _buildIdleView();
  }

  /// 空闲状态（显示播放按钮）
  Widget _buildIdleView() {
    return GestureDetector(
      onTap: _startPlay,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Stack(
          children: [
            // 网格背景
            Positioned.fill(
              child: CustomPaint(painter: _VideoGridPainter()),
            ),
            
            // 播放按钮
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.5),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      PhosphorIconsBold.play,
                      color: AppColors.primary,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '点击播放实时画面',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '(WebView 模式)',
                    style: AppTextStyles.tiny.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            
            // 摄像头信息
            if (widget.cameraName != null)
              Positioned(
                top: 12,
                left: 12,
                child: _buildCameraTag(widget.cameraName!, true),
              ),
          ],
        ),
      ),
    );
  }

  /// 播放中视图
  Widget _buildPlayerView() {
    return GestureDetector(
      onTap: _stopPlay,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            // WebView 视频画面
            SizedBox.expand(
              child: WebViewWidget(controller: _controller!),
            ),
            
            // 顶部信息栏
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.6),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // LIVE 标识
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
                          style: AppTextStyles.tiny.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
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
                    // 提示
                    Text(
                      '点击暂停',
                      style: AppTextStyles.tiny.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // 底部控制栏
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.6),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // 全屏按钮
                    if (widget.onFullscreen != null)
                      _buildControlButton(
                        icon: PhosphorIconsBold.arrowsOut,
                        onTap: widget.onFullscreen!,
                        tooltip: '全屏',
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 加载中视图
  Widget _buildLoadingView() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
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
      ),
    );
  }

  /// 错误视图
  Widget _buildErrorView() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              PhosphorIconsBold.warningCircle,
              color: AppColors.error,
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              '连接失败',
              style: AppTextStyles.body.copyWith(color: AppColors.error),
            ),
            const SizedBox(height: 4),
            Text(
              _error ?? '未知错误',
              style: AppTextStyles.tiny.copyWith(color: AppColors.textTertiary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
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
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _showDebugLogs,
                  icon: const Icon(PhosphorIconsBold.bug, size: 16),
                  label: const Text('查看详情'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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

  /// 离线视图
  Widget _buildOfflineView() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              PhosphorIconsBold.videoCameraSlash,
              color: AppColors.textTertiary,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              '摄像头离线',
              style: AppTextStyles.body.copyWith(color: AppColors.textTertiary),
            ),
            const SizedBox(height: 4),
            Text(
              '请检查设备连接',
              style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  /// 摄像头标签
  Widget _buildCameraTag(String name, bool online) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: online ? AppColors.success : AppColors.error,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            name,
            style: AppTextStyles.tiny.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// 控制按钮
  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onTap,
    String? tooltip,
    bool isLoading = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(
          icon,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }
}

/// 视频网格背景
class _VideoGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.border.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;

    const spacing = 20.0;
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

