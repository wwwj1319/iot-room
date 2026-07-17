/// WVP 视频播放组件
/// 
/// 【功能说明】
/// 基于 WVP + ZLMediaKit 的视频播放组件，支持：
/// - 实时视频播放（FLV 流）
/// - 截图功能
/// - 录像回放
/// 
/// 【实现说明】
/// 这个组件替代原来的萤石云版本，使用自建的 WVP 平台。
/// 优点：
/// 1. 不依赖第三方平台，数据完全自主可控
/// 2. 无并发限制，不用担心"并发数已达上限"
/// 3. 可以接收摄像头的报警信息（火灾检测等）
/// 
/// 【使用示例】
/// ```dart
/// WvpVideoPlayerWidget(
///   deviceId: 'demo-device',
///   channelId: 'demo-channel',
///   isOnline: true,
///   onSnapshot: (url) => print('截图: $url'),
///   onAlarm: (alarm) => print('报警: ${alarm.alarmDescription}'),
/// )
/// ```

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../services/wvp_service.dart';

/// WVP 视频播放组件
class WvpVideoPlayerWidget extends StatefulWidget {
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

  const WvpVideoPlayerWidget({
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
  State<WvpVideoPlayerWidget> createState() => _WvpVideoPlayerWidgetState();
}

class _WvpVideoPlayerWidgetState extends State<WvpVideoPlayerWidget> {
  /// WVP 服务
  final WvpService _wvpService = WvpService();
  
  /// 视频播放器控制器
  VideoPlayerController? _controller;
  
  /// 状态标志
  bool _isLoading = false;
  bool _isPlaying = false;
  String? _error;
  
  /// 详细调试日志（用于鸿蒙等系统调试）
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

  /// 检测是否为鸿蒙系统
  /// 
  /// 【说明】
  /// 鸿蒙系统在 Flutter 中可能被识别为 Android，但可以通过
  /// 系统属性或其他方式检测。目前使用简单判断。
  bool _isHarmonyOS() {
    if (!Platform.isAndroid) return false;
    // 暂时使用简单判断，默认假设不是鸿蒙
    return false;
  }

  /// 获取格式优先级列表
  /// 
  /// 【格式选择】
  /// 只使用 FMP4 格式，TS 作为备用方案
  /// - FMP4: 主要格式，延迟低，兼容性好
  /// - TS: 备用格式，如果 FMP4 失败时使用
  List<Map<String, dynamic>> _getFormatPriority() {
    // FMP4 格式（主要）
    final fmp4Format = {
      'name': 'FMP4',
      'url': WvpConfig.getDirectFmp4Url(
        deviceId: widget.deviceId,
        channelId: widget.channelId,
      ),
      'timeout': 20,
    };
    
    // TS 格式（备用）
    final tsFormat = {
      'name': 'TS',
      'url': WvpConfig.getDirectTsUrl(
        deviceId: widget.deviceId,
        channelId: widget.channelId,
      ),
      'timeout': 20,
    };
    
    // 优先 FMP4，失败后回退到 TS
    return [fmp4Format, tsFormat];
  }

  /// 开始播放
  /// 
  /// 【格式回退策略】
  /// 使用 FMP4 格式，TS 作为备用：
  /// - FMP4: 主要格式，延迟低，兼容 Android 和鸿蒙
  /// - TS: 备用格式，如果 FMP4 失败时使用
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
    
    // 添加系统信息到调试日志
    _debugLogs.add('=== 调试信息 ===');
    _debugLogs.add('时间: ${DateTime.now()}');
    _debugLogs.add('系统: ${Platform.operatingSystem}');
    _debugLogs.add('版本: ${Platform.operatingSystemVersion}');
    _debugLogs.add('是否为鸿蒙: ${_isHarmonyOS()}');

    // 根据系统类型获取格式优先级
    final formats = _getFormatPriority();

    String? lastError;
    
    for (final format in formats) {
      try {
        final timeout = format['timeout'] as int? ?? 20;
        final url = format['url'] as String;
        
        _debugLogs.add('');
        _debugLogs.add('--- ${format['name']} ---');
        _debugLogs.add('URL: $url');
        _debugLogs.add('超时: ${timeout}秒');
        
        debugPrint('[WVP Player] 尝试 ${format['name']} 格式 (超时${timeout}秒): $url');
        
        // 先释放之前的控制器
        _controller?.dispose();
        _controller = null;
        
        // 创建新的播放器
        // 【兼容性优化】
        // - 添加 User-Agent，某些系统可能需要
        // - 针对不同系统使用不同的 User-Agent
        // - 优化 VideoPlayerOptions 配置，提升鸿蒙和 Android 兼容性
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
        
        // 添加错误监听器，捕获播放过程中的错误
        _controller!.addListener(_onPlayerError);
        
        // 设置超时时间
        // 【优化】增加初始化前的延迟，给播放器更多准备时间
        await Future.delayed(const Duration(milliseconds: 100));
        
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
        
        // 【优化】初始化后稍作延迟再播放，提升兼容性
        await Future.delayed(const Duration(milliseconds: 200));
        
        await _controller!.play();
        
        // 【优化】播放后再次检查错误状态
        await Future.delayed(const Duration(milliseconds: 500));
        if (_controller!.value.hasError) {
          final errorDesc = _controller!.value.errorDescription ?? '播放失败';
          throw Exception('播放失败: $errorDesc');
        }
        
        _debugLogs.add('结果: ✓ 成功');
        debugPrint('[WVP Player] ✓ ${format['name']} 播放成功');
        
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isPlaying = true;
          });
        }
        
        // 成功后直接返回，不再尝试其他格式
        return;
        
      } catch (e, stackTrace) {
        final errorMsg = e.toString();
        lastError = '${format['name']}: $errorMsg';
        
        _debugLogs.add('结果: ✗ 失败');
        _debugLogs.add('错误: $errorMsg');
        
        // 提取更详细的错误信息
        if (e is PlatformException) {
          _debugLogs.add('错误代码: ${e.code}');
          _debugLogs.add('错误消息: ${e.message}');
          _debugLogs.add('错误详情: ${e.details}');
        }
        
        _debugLogs.add('堆栈: ${stackTrace.toString().split('\n').take(3).join('\n')}');
        
        debugPrint('[WVP Player] ✗ ${format['name']} 失败: $e');
        if (e is PlatformException) {
          debugPrint('[WVP Player] 错误详情: code=${e.code}, message=${e.message}, details=${e.details}');
        }
        
        // 清理失败的控制器
        _controller?.removeListener(_onPlayerError);
        _controller?.dispose();
        _controller = null;
        
        // 继续尝试下一个格式前，稍作延迟
        await Future.delayed(const Duration(milliseconds: 300));
        
        // 继续尝试下一个格式
        continue;
      }
    }
    
    // 所有格式都失败了
    _debugLogs.add('');
    _debugLogs.add('=== 所有格式都失败 ===');
    debugPrint('[WVP Player] 所有格式都失败');
    
    if (mounted) {
      setState(() {
        _isLoading = false;
        _error = '视频加载失败\n$lastError\n请检查摄像头是否在推流';
      });
    }
  }

  /// 播放器错误监听器
  void _onPlayerError() {
    if (_controller == null) return;
    
    if (_controller!.value.hasError) {
      final errorDesc = _controller!.value.errorDescription ?? '未知错误';
      debugPrint('[WVP Player] 播放器错误: $errorDesc');
      
      if (mounted) {
        setState(() {
          _error = '播放错误: $errorDesc';
          _isPlaying = false;
          _isLoading = false;
        });
      }
    }
  }

  /// 停止播放
  void _stopPlay() {
    // 移除错误监听器
    _controller?.removeListener(_onPlayerError);
    _controller?.pause();
    _controller?.dispose();
    _controller = null;
    
    // 通知 WVP 停止点播
    _wvpService.stopPlay(
      deviceId: widget.deviceId,
      channelId: widget.channelId,
    );
    
    if (mounted) {
      setState(() {
        _isPlaying = false;
      });
    }
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
    if (_isPlaying && _controller != null && _controller!.value.isInitialized) {
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
                    '(WVP 自建平台)',
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
            // 视频画面
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _controller!.value.size.width,
                  height: _controller!.value.size.height,
                  child: VideoPlayer(_controller!),
                ),
              ),
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
                // 复制日志到剪贴板
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
