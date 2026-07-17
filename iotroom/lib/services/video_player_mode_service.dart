/// 视频播放模式管理服务
/// 
/// 【功能说明】
/// 管理视频播放模式的选择和保存：
/// - video_player: 原生播放器（性能好，但可能有兼容性问题）
/// - webview: WebView 播放器（兼容性好，使用浏览器解码）
/// 
/// 【使用说明】
/// 用户可以在设置中切换播放模式，选择最适合自己设备的模式。

import 'package:shared_preferences/shared_preferences.dart';

/// 播放模式枚举
enum VideoPlayerMode {
  /// 原生播放器（video_player）
  videoPlayer,
  
  /// WebView 播放器（浏览器）
  webView,
}

/// 视频播放模式服务（单例）
class VideoPlayerModeService {
  static final VideoPlayerModeService _instance = VideoPlayerModeService._internal();
  factory VideoPlayerModeService() => _instance;
  VideoPlayerModeService._internal();
  
  /// 默认播放模式
  static const VideoPlayerMode _defaultMode = VideoPlayerMode.webView;
  
  /// 设置键
  static const String _prefsKey = 'video_player_mode';
  
  /// 当前播放模式（缓存）
  VideoPlayerMode? _cachedMode;
  
  /// 获取当前播放模式
  /// 
  /// 如果未设置，返回默认模式（video_player）
  Future<VideoPlayerMode> getMode() async {
    if (_cachedMode != null) {
      return _cachedMode!;
    }
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeString = prefs.getString(_prefsKey);
      
      if (modeString == null) {
        _cachedMode = _defaultMode;
        return _cachedMode!;
      }
      
      _cachedMode = VideoPlayerMode.values.firstWhere(
        (mode) => mode.toString() == modeString,
        orElse: () => _defaultMode,
      );
      
      return _cachedMode!;
    } catch (e) {
      // 如果读取失败，返回默认模式
      return _defaultMode;
    }
  }
  
  /// 设置播放模式
  Future<bool> setMode(VideoPlayerMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final success = await prefs.setString(_prefsKey, mode.toString());
      
      if (success) {
        _cachedMode = mode;
      }
      
      return success;
    } catch (e) {
      return false;
    }
  }
  
  /// 切换播放模式
  /// 
  /// 如果当前是 video_player，切换到 webview
  /// 如果当前是 webview，切换到 video_player
  Future<VideoPlayerMode> toggleMode() async {
    final currentMode = await getMode();
    final newMode = currentMode == VideoPlayerMode.videoPlayer
        ? VideoPlayerMode.webView
        : VideoPlayerMode.videoPlayer;
    
    await setMode(newMode);
    return newMode;
  }
  
  /// 获取播放模式显示名称
  String getModeDisplayName(VideoPlayerMode mode) {
    switch (mode) {
      case VideoPlayerMode.videoPlayer:
        return '原生播放器';
      case VideoPlayerMode.webView:
        return '浏览器播放';
    }
  }
  
  /// 获取播放模式描述
  String getModeDescription(VideoPlayerMode mode) {
    switch (mode) {
      case VideoPlayerMode.videoPlayer:
        return '使用原生播放器，性能好，延迟低';
      case VideoPlayerMode.webView:
        return '使用浏览器播放，兼容性好，适合有问题的设备';
    }
  }
  
  /// 清除缓存（用于重新加载设置）
  void clearCache() {
    _cachedMode = null;
  }
}

