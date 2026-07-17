/// 相册保存服务
/// 
/// 【功能说明】
/// 将截图和录像保存到手机相册，包括：
/// - 截图保存（从URL下载或从视频帧截取）
/// - 录像保存（保存视频文件到相册）
/// - 权限管理
/// 
/// 【实现说明】
/// 使用 saver_gallery 插件保存到相册（兼容 AGP 8.x）
/// 需要在 Android 和 iOS 配置权限

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:saver_gallery/saver_gallery.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// 相册保存服务（单例）
class GalleryService {
  static final GalleryService _instance = GalleryService._internal();
  factory GalleryService() => _instance;
  GalleryService._internal();
  
  /// 请求存储权限
  /// 
  /// 【实现说明】
  /// Android 13+ 使用 photos 权限
  /// Android 12 及以下使用 storage 权限
  /// iOS 使用 photos 权限
  Future<bool> requestPermission() async {
    if (Platform.isAndroid) {
      // Android 13+ (API 33+)
      if (await Permission.photos.request().isGranted) {
        return true;
      }
      // Android 12 及以下
      if (await Permission.storage.request().isGranted) {
        return true;
      }
      // 检查是否永久拒绝
      if (await Permission.storage.isPermanentlyDenied ||
          await Permission.photos.isPermanentlyDenied) {
        // 引导用户去设置页面
        await openAppSettings();
        return false;
      }
      return false;
    } else if (Platform.isIOS) {
      final status = await Permission.photos.request();
      if (status.isGranted || status.isLimited) {
        return true;
      }
      if (status.isPermanentlyDenied) {
        await openAppSettings();
        return false;
      }
      return false;
    }
    return true;
  }
  
  /// 保存截图到相册（从 URL 下载）
  /// 
  /// [imageUrl] 图片 URL
  /// [fileName] 文件名（可选）
  /// 
  /// 返回保存结果
  Future<SaveResult> saveImageFromUrl(String imageUrl, {String? fileName}) async {
    try {
      // 1. 请求权限
      final hasPermission = await requestPermission();
      if (!hasPermission) {
        return SaveResult.error('需要相册权限才能保存');
      }
      
      // 2. 下载图片
      debugPrint('[Gallery] 下载图片: $imageUrl');
      final response = await http.get(Uri.parse(imageUrl)).timeout(
        const Duration(seconds: 30),
      );
      
      if (response.statusCode != 200) {
        return SaveResult.error('下载图片失败: ${response.statusCode}');
      }
      
      // 3. 保存到相册
      final name = fileName ?? 'IOT_${DateTime.now().millisecondsSinceEpoch}';
      final result = await SaverGallery.saveImage(
        response.bodyBytes,
        fileName: '$name.jpg',
        androidRelativePath: 'Pictures/IOT',
        skipIfExists: false,
      );
      
      debugPrint('[Gallery] 保存结果: ${result.isSuccess}');
      
      if (result.isSuccess) {
        return SaveResult.success(
          message: '已保存到相册',
          filePath: null,
        );
      } else {
        return SaveResult.error('保存失败');
      }
      
    } catch (e) {
      debugPrint('[Gallery] 保存截图失败: $e');
      return SaveResult.error('保存失败: $e');
    }
  }
  
  /// 保存截图到相册（从 Uint8List）
  /// 
  /// [imageBytes] 图片字节数据
  /// [fileName] 文件名（可选）
  Future<SaveResult> saveImageFromBytes(Uint8List imageBytes, {String? fileName}) async {
    try {
      // 1. 请求权限
      final hasPermission = await requestPermission();
      if (!hasPermission) {
        return SaveResult.error('需要相册权限才能保存');
      }
      
      // 2. 保存到相册
      final name = fileName ?? 'IOT_${DateTime.now().millisecondsSinceEpoch}';
      final result = await SaverGallery.saveImage(
        imageBytes,
        fileName: '$name.jpg',
        androidRelativePath: 'Pictures/IOT',
        skipIfExists: false,
      );
      
      debugPrint('[Gallery] 保存结果: ${result.isSuccess}');
      
      if (result.isSuccess) {
        return SaveResult.success(
          message: '已保存到相册',
          filePath: null,
        );
      } else {
        return SaveResult.error('保存失败');
      }
      
    } catch (e) {
      debugPrint('[Gallery] 保存截图失败: $e');
      return SaveResult.error('保存失败: $e');
    }
  }
  
  /// 保存视频到相册
  /// 
  /// [videoPath] 视频文件路径
  /// [fileName] 文件名（可选）
  Future<SaveResult> saveVideo(String videoPath, {String? fileName}) async {
    try {
      // 1. 请求权限
      final hasPermission = await requestPermission();
      if (!hasPermission) {
        return SaveResult.error('需要相册权限才能保存');
      }
      
      // 2. 检查文件是否存在
      final file = File(videoPath);
      if (!await file.exists()) {
        return SaveResult.error('视频文件不存在');
      }
      
      // 3. 保存到相册
      final name = fileName ?? 'IOT_VIDEO_${DateTime.now().millisecondsSinceEpoch}';
      final result = await SaverGallery.saveFile(
        filePath: videoPath,
        fileName: '$name.mp4',
        androidRelativePath: 'Movies/IOT',
        skipIfExists: false,
      );
      
      debugPrint('[Gallery] 保存视频结果: ${result.isSuccess}');
      
      if (result.isSuccess) {
        // 删除临时文件
        await file.delete();
        return SaveResult.success(
          message: '录像已保存到相册',
          filePath: null,
        );
      } else {
        return SaveResult.error('保存失败');
      }
      
    } catch (e) {
      debugPrint('[Gallery] 保存视频失败: $e');
      return SaveResult.error('保存失败: $e');
    }
  }
  
  /// 从 URL 下载视频并保存到相册
  /// 
  /// [videoUrl] 视频 URL
  /// [onProgress] 下载进度回调
  Future<SaveResult> saveVideoFromUrl(
    String videoUrl, {
    String? fileName,
    void Function(double progress)? onProgress,
  }) async {
    try {
      // 1. 请求权限
      final hasPermission = await requestPermission();
      if (!hasPermission) {
        return SaveResult.error('需要相册权限才能保存');
      }
      
      // 2. 获取临时目录
      final tempDir = await getTemporaryDirectory();
      final name = fileName ?? 'IOT_VIDEO_${DateTime.now().millisecondsSinceEpoch}';
      final tempPath = '${tempDir.path}/$name.mp4';
      
      // 3. 下载视频
      debugPrint('[Gallery] 下载视频: $videoUrl');
      final request = http.Request('GET', Uri.parse(videoUrl));
      final response = await http.Client().send(request);
      
      if (response.statusCode != 200) {
        return SaveResult.error('下载视频失败: ${response.statusCode}');
      }
      
      // 获取文件大小
      final contentLength = response.contentLength ?? 0;
      var downloadedBytes = 0;
      
      // 写入临时文件
      final file = File(tempPath);
      final sink = file.openWrite();
      
      await for (final chunk in response.stream) {
        sink.add(chunk);
        downloadedBytes += chunk.length;
        if (contentLength > 0 && onProgress != null) {
          onProgress(downloadedBytes / contentLength);
        }
      }
      
      await sink.close();
      
      // 4. 保存到相册
      final result = await SaverGallery.saveFile(
        filePath: tempPath,
        fileName: '$name.mp4',
        androidRelativePath: 'Movies/IOT',
        skipIfExists: false,
      );
      
      // 5. 删除临时文件
      await file.delete();
      
      debugPrint('[Gallery] 保存视频结果: ${result.isSuccess}');
      
      if (result.isSuccess) {
        return SaveResult.success(
          message: '录像已保存到相册',
          filePath: null,
        );
      } else {
        return SaveResult.error('保存失败');
      }
      
    } catch (e) {
      debugPrint('[Gallery] 下载并保存视频失败: $e');
      return SaveResult.error('保存失败: $e');
    }
  }
  
  /// 获取临时录像文件路径
  Future<String> getTempVideoPath() async {
    final tempDir = await getTemporaryDirectory();
    final name = 'IOT_REC_${DateTime.now().millisecondsSinceEpoch}';
    return '${tempDir.path}/$name.mp4';
  }
}

/// 保存结果
class SaveResult {
  final bool success;
  final String message;
  final String? filePath;
  
  SaveResult({
    required this.success,
    required this.message,
    this.filePath,
  });
  
  factory SaveResult.success({required String message, String? filePath}) {
    return SaveResult(success: true, message: message, filePath: filePath);
  }
  
  factory SaveResult.error(String message) {
    return SaveResult(success: false, message: message);
  }
}
