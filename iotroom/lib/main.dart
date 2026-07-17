import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'core/theme/app_theme.dart';
import 'features/home/pages/main_page.dart';
import 'services/alarm_notification_service.dart';
import 'services/alarm_polling_service.dart';
import 'services/notification_service.dart';

/// 🚀 应用入口
/// main.dart 是Flutter应用的入口文件
/// 1. 初始化Flutter框架
/// 2. 设置系统UI样式（状态栏颜色等）
/// 3. 启动应用
/// 4. 初始化报警监听服务
/// 
/// 注意：
/// - WidgetsFlutterBinding.ensureInitialized() 必须在runApp之前调用
/// - 如果有异步初始化（如数据库），也在这里做
void main() async {
  // 确保Flutter绑定初始化
  WidgetsFlutterBinding.ensureInitialized();
  
  // 设置系统UI样式
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      // 状态栏透明
      statusBarColor: Colors.transparent,
      // 状态栏图标为白色（因为我们是深色主题）
      statusBarIconBrightness: Brightness.light,
      // iOS状态栏
      statusBarBrightness: Brightness.dark,
      // 导航栏颜色
      systemNavigationBarColor: Color(0xFF0D1117),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  
  // 设置屏幕方向（只允许竖屏）
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  runApp(const MyApp());
}

/// 📱 应用根组件
/// 
/// 【实现说明】
/// MaterialApp 是整个应用的根组件
/// 它提供了：
/// - 路由导航
/// - 主题配置
/// - 本地化支持
/// - 其他全局配置
/// - 全局报警监听（通过 AlarmNotificationService）
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  /// 报警通知服务
  final AlarmNotificationService _alarmService = AlarmNotificationService();
  
  /// 报警轮询服务
  final AlarmPollingService _pollingService = AlarmPollingService();

  @override
  void initState() {
    super.initState();
    // 延迟初始化，确保 navigatorKey 已绑定
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeApp();
    });
  }
  
  /// 初始化应用（请求权限 + 启动服务）
  Future<void> _initializeApp() async {
    try {
      // 1. 初始化报警弹窗服务
      _alarmService.initialize(
        onAlarm: (alarm) {
          debugPrint('[App] 收到报警通知: ${alarm.alarmDescription}');
        },
      );
      
      // 2. 请求通知权限（直接弹出系统对话框）
      try {
        final notificationStatus = await Permission.notification.request();
        debugPrint('[App] 通知权限: $notificationStatus');
      } catch (e) {
        debugPrint('[App] 请求通知权限失败: $e');
      }
      
      // 3. 请求存储权限（用于保存截图）
      try {
        await Permission.photos.request();
      } catch (e) {
        debugPrint('[App] 请求存储权限失败: $e');
      }
      
      // 4. 初始化通知服务
      try {
        await NotificationService().initialize();
      } catch (e) {
        debugPrint('[App] 初始化通知服务失败: $e');
      }
      
      // 5. 启动报警轮询服务
      _pollingService.start(
        onNewAlarm: (alarm) {
          debugPrint('[App] 轮询检测到新报警: ${alarm.eventType}');
        },
      );
    } catch (e) {
      debugPrint('[App] 初始化失败: $e');
    }
  }

  @override
  void dispose() {
    _alarmService.dispose();
    _pollingService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // 使用全局 NavigatorKey，让报警服务可以在任意位置显示弹窗
      navigatorKey: _alarmService.navigatorKey,
      
      // 应用标题（显示在任务切换器中）
      title: 'IoT智能监控',
      
      // 关闭调试标签
      debugShowCheckedModeBanner: false,
      
      // 应用主题 - 使用我们定义的深色主题
      theme: AppTheme.darkTheme,
      
      // 首页 - 直接显示主页
      home: const MainPage(),
      
      // 后续添加路由配置
      // routes: {
      //   '/rooms': (context) => const RoomListPage(),
      //   '/alarms': (context) => const AlarmListPage(),
      // },
    );
  }
}
