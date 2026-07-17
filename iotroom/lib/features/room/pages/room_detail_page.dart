import 'dart:async';
import 'package:flutter/material.dart';
// import 'package:flutter/services.dart'; // 震动反馈已禁用
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/glass_card.dart';
import '../widgets/gauge_widget.dart';
import '../widgets/device_status_widget.dart';
import '../widgets/history_chart_widget.dart';
// 【实现说明】
// 原来使用萤石云版本：import '../widgets/video_player_widget.dart';
// 现在改用 WVP 自建平台版本，不依赖第三方服务
// 【视频播放器方案】
// - video_player: 原生播放器（性能好，延迟低）
// - webview: WebView 播放器（兼容性好，使用浏览器解码）
import '../widgets/wvp_video_player_widget.dart';
import '../widgets/wvp_webview_player_widget.dart';
import '../../../services/wvp_service.dart';
import '../../../services/gallery_service.dart';
import '../../../services/alarm_polling_service.dart';
import '../../../services/video_player_mode_service.dart';
import '../../../services/door_sensor_service.dart';
import '../../../services/temp_humidity_service.dart';
// 【视频播放器方案】根据模式选择全屏页面
import '../../camera/pages/fullscreen_video_page.dart';
import '../../camera/pages/fullscreen_webview_video_page.dart';
import '../../alarm/pages/alarm_history_page.dart';
import '../widgets/cloud_record_list_widget.dart';
import '../widgets/circuit_breaker_widget.dart';
import '../widgets/ac_control_widget.dart';

/// 🏢 设备间详情页
/// 
/// 【实现说明】
/// 这是核心功能页面，展示单个设备间的所有信息：
/// 1. 温湿度实时数据（仪表盘形式）
/// 2. 设备状态（门、灯、空调、摄像头）
/// 3. 设备控制（远程开关）
/// 4. 历史数据（曲线图）
/// 
/// 页面布局：
/// - 顶部：自定义AppBar
/// - 内容：可滚动的Column
/// - 每个区块用GlassCard包裹
class RoomDetailPage extends StatefulWidget {
  /// 设备间ID（后续用于API请求）
  final String? roomId;
  
  const RoomDetailPage({super.key, this.roomId});

  @override
  State<RoomDetailPage> createState() => _RoomDetailPageState();
}

class _RoomDetailPageState extends State<RoomDetailPage> {
  // ==================== 模拟数据 ====================
  // 【实现说明】先用模拟数据开发UI，后续再对接API
  
  final Map<String, dynamic> _roomInfo = {
    'id': 'A-103',
    'name': '配电间 A-103',
    'location': 'A栋 1楼 103室',
    'status': 1, // 0离线 1在线 2告警
  };

  final Map<String, dynamic> _sensorData = {
    'temperature': 28.5,
    'humidity': 65.0,
    'tempMin': 0.0,
    'tempMax': 50.0,
    'tempAlarmHigh': 35.0,
    'tempAlarmLow': 5.0,
    'humidityMin': 0.0,
    'humidityMax': 100.0,
    'humidityAlarmHigh': 75.0,
  };

  final Map<String, dynamic> _deviceStatus = {
    'door': false,      // 门状态：false=关闭 true=开启
    'light': true,      // 照明状态
    'ac': true,         // 空调状态
    'acMode': 'cool',   // 空调模式：cool/heat/dry
    'acTemp': 26,       // 空调温度
    'camera': true,     // 摄像头在线
  };

  // 门磁传感器数据
  final Map<String, dynamic> _doorSensorData = {
    'sensorId': 'DOOR-A103-01',
    'sensorName': '主入口门磁',
    'isOnline': true,
    'lastOpenTime': '2024-12-10 14:32:15',
    'lastCloseTime': '2024-12-10 14:35:22',
    'todayOpenCount': 8,
    'battery': 85, // 电池电量百分比（如果是无线门磁）
  };

  // 门磁开关历史记录
  final List<Map<String, dynamic>> _doorHistory = [
    {'time': '2024-12-10 14:35:22', 'action': 'close', 'duration': '3分7秒'},
    {'time': '2024-12-10 14:32:15', 'action': 'open', 'duration': null},
    {'time': '2024-12-10 11:20:45', 'action': 'close', 'duration': '15分30秒'},
    {'time': '2024-12-10 11:05:15', 'action': 'open', 'duration': null},
    {'time': '2024-12-10 09:45:30', 'action': 'close', 'duration': '8分20秒'},
    {'time': '2024-12-10 09:37:10', 'action': 'open', 'duration': null},
    {'time': '2024-12-10 08:30:00', 'action': 'close', 'duration': '5分45秒'},
    {'time': '2024-12-10 08:24:15', 'action': 'open', 'duration': null},
    {'time': '2024-12-09 18:05:30', 'action': 'close', 'duration': '昨天关闭'},
    {'time': '2024-12-09 17:58:00', 'action': 'open', 'duration': null},
  ];

  // 截图状态
  bool _isSavingSnapshot = false;
  
  // 服务实例
  final WvpService _wvpService = WvpService();
  final GalleryService _galleryService = GalleryService();
  final AlarmPollingService _alarmPollingService = AlarmPollingService();
  final VideoPlayerModeService _playerModeService = VideoPlayerModeService();
  final DoorSensorService _doorSensorService = DoorSensorService();
  final TempHumidityService _tempHumidityService = TempHumidityService();
  
  // ==================== 传感器 Modbus 地址配置 ====================
  // 门磁传感器: 0x41 = 65
  static const int _doorModbusAddress = 65;
  // 温湿度传感器: 0x01 = 1
  static const int _tempHumidityModbusAddress = 1;
  
  // ==================== 温湿度传感器数据 ====================
  TempHumidityStatusData? _tempHumidityStatus;
  bool _isTempHumidityLoading = true;
  String? _tempHumidityError;
  Timer? _tempHumidityRefreshTimer;
  
  // 门磁数据状态
  DoorStatusData? _doorStatus;
  DoorEventsData? _doorEvents;
  DoorStatsData? _doorStats;
  bool _isDoorDataLoading = true;
  String? _doorDataError;
  Timer? _doorRefreshTimer;
  
  // 【修复】小屏播放器的 key，用于从全屏退出后重置状态
  // 当 key 改变时，Flutter 会重建组件，从而回到"点击播放实时画面"的初始状态
  Key _videoPlayerKey = UniqueKey();
  
  // 播放模式状态
  VideoPlayerMode _currentPlayerMode = VideoPlayerMode.videoPlayer;
  
  // ==================== 摄像头配置 ====================
  // 【实现说明】
  // 摄像头配置已迁移到 WvpConfig 类中（wvp_service.dart）
  // 现在使用自建的 WVP + ZLMediaKit 平台，不再依赖萤石云
  // 设备编号与服务地址通过 AppConfig / --dart-define 注入。

  @override
  void initState() {
    super.initState();
    // 加载播放模式设置
    _loadPlayerMode();
    // 启动报警轮询
    _startAlarmPolling();
    // 加载门磁数据
    _loadDoorSensorData();
    // 加载温湿度数据
    _loadTempHumidityData();
    // 启动门磁数据定时刷新（每10秒刷新一次）
    _doorRefreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _loadDoorSensorData(showLoading: false),
    );
    // 启动温湿度数据定时刷新（每10秒刷新一次）
    _tempHumidityRefreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _loadTempHumidityData(showLoading: false),
    );
  }
  
  /// 加载播放模式设置
  Future<void> _loadPlayerMode() async {
    final mode = await _playerModeService.getMode();
    if (mounted) {
      setState(() {
        _currentPlayerMode = mode;
      });
    }
  }
  
  /// 切换播放模式
  Future<void> _togglePlayerMode() async {
    final newMode = await _playerModeService.toggleMode();
    if (mounted) {
      setState(() {
        _currentPlayerMode = newMode;
        // 重置播放器 key，让播放器重新初始化
        _videoPlayerKey = UniqueKey();
      });
      
      // 显示提示
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已切换到${_playerModeService.getModeDisplayName(newMode)}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
  
  @override
  void dispose() {
    // 停止报警轮询
    _alarmPollingService.stop();
    // 停止门磁数据刷新
    _doorRefreshTimer?.cancel();
    // 停止温湿度数据刷新
    _tempHumidityRefreshTimer?.cancel();
    super.dispose();
  }
  
  /// 加载门磁传感器数据
  /// 
  /// [showLoading] 是否显示加载状态（首次加载显示，后续刷新不显示）
  Future<void> _loadDoorSensorData({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _isDoorDataLoading = true;
        _doorDataError = null;
      });
    }
    
    try {
      // 并行获取状态、事件和统计信息
      final results = await Future.wait([
        _doorSensorService.getDoorStatus(_doorModbusAddress),
        _doorSensorService.getDoorEvents(modbusAddress: _doorModbusAddress, limit: 20),
        _doorSensorService.getDoorStats(_doorModbusAddress),
      ]);
      
      if (mounted) {
        setState(() {
          _doorStatus = results[0] as DoorStatusData?;
          _doorEvents = results[1] as DoorEventsData?;
          _doorStats = results[2] as DoorStatsData?;
          _isDoorDataLoading = false;
          
          // 同步更新设备状态中的门状态
          if (_doorStatus != null) {
            _deviceStatus['door'] = _doorStatus!.isOpen;
          }
          
          // 如果获取成功，清除错误
          if (_doorStatus != null) {
            _doorDataError = null;
          } else {
            _doorDataError = '无法获取门磁数据';
          }
        });
      }
    } catch (e) {
      debugPrint('[DoorSensor] 加载数据失败: $e');
      if (mounted) {
        setState(() {
          _isDoorDataLoading = false;
          _doorDataError = '加载失败: $e';
        });
      }
    }
  }
  
  /// 加载温湿度传感器数据
  /// 
  /// [showLoading] 是否显示加载状态（首次加载显示，后续刷新不显示）
  Future<void> _loadTempHumidityData({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _isTempHumidityLoading = true;
        _tempHumidityError = null;
      });
    }
    
    try {
      final status = await _tempHumidityService.getStatus(_tempHumidityModbusAddress);
      
      if (mounted) {
        setState(() {
          _tempHumidityStatus = status;
          _isTempHumidityLoading = false;
          
          // 更新模拟数据中的温湿度（用于仪表盘显示）
          if (status != null) {
            _sensorData['temperature'] = status.temperature;
            _sensorData['humidity'] = status.humidity;
            _tempHumidityError = null;
          } else {
            _tempHumidityError = '无法获取温湿度数据';
          }
        });
      }
    } catch (e) {
      debugPrint('[TempHumidity] 加载数据失败: $e');
      if (mounted) {
        setState(() {
          _isTempHumidityLoading = false;
          _tempHumidityError = '加载失败: $e';
        });
      }
    }
  }
  
  /// 启动报警轮询
  void _startAlarmPolling() {
    _alarmPollingService.start(
      onNewAlarm: (alarm) {
        // 收到新报警时显示弹窗
        if (mounted) {
          _showNewAlarmDialog(alarm);
        }
      },
    );
  }
  
  /// 显示新报警弹窗
  void _showNewAlarmDialog(NewAlarmData alarm) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: alarm.isFireAlarm ? AppColors.error : AppColors.warning,
            width: 2,
          ),
        ),
        title: Row(
          children: [
            Icon(
              alarm.isFireAlarm 
                  ? PhosphorIconsBold.fire 
                  : (alarm.isRecovery ? PhosphorIconsBold.checkCircle : PhosphorIconsBold.warning),
              color: alarm.isFireAlarm 
                  ? AppColors.error 
                  : (alarm.isRecovery ? AppColors.success : AppColors.warning),
              size: 28,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                alarm.isFireAlarm ? '🔥 火灾报警！' : (alarm.isRecovery ? '✅ 火灾已恢复' : '⚠️ 设备报警'),
                style: AppTextStyles.h4.copyWith(
                  color: alarm.isFireAlarm ? AppColors.error : AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              alarm.notificationBody,
              style: AppTextStyles.body.copyWith(color: AppColors.textPrimary),
            ),
            const SizedBox(height: 12),
            Text(
              '设备: ${alarm.channelName.isNotEmpty ? alarm.channelName : alarm.deviceID}',
              style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _openAlarmHistory();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('查看详情'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // 顶部导航栏
            _buildAppBar(),
            
            // 内容区域（可滚动）
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 温湿度仪表盘
                    _buildGaugeSection(),
                    
                    const SizedBox(height: 16),
                    
                    // 设备状态
                    _buildDeviceStatusSection(),
                    
                    const SizedBox(height: 16),
                    
                    // 门传感器详情
                    _buildDoorSensorSection(),
                    
                    const SizedBox(height: 16),
                    
                    // 照明控制（智能断路器）
                    const CircuitBreakerWidget(
                      modbusAddress: 2,
                      name: '照明控制',
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // 空调控制（红外控制器）
                    const ACControlWidget(
                      modbusAddress: 3,
                      name: '空调',
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // 历史数据
                    _buildHistorySection(),
                    
                    const SizedBox(height: 16),
                    
                    // 视频监控
                    _buildVideoSection(),
                    
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建顶部导航栏
  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // 返回按钮
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(
              PhosphorIconsBold.caretLeft,
              color: AppColors.textPrimary,
            ),
          ),
          
          // 标题
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _roomInfo['name'] as String,
                  style: AppTextStyles.h4,
                ),
                Text(
                  _roomInfo['location'] as String,
                  style: AppTextStyles.tiny,
                ),
              ],
            ),
          ),
          
          // 状态指示
          _buildStatusBadge(),
          
          const SizedBox(width: 4),
          
          // 告警记录按钮
          IconButton(
            onPressed: _openAlarmHistory,
            icon: const Icon(
              PhosphorIconsBold.bell,
              color: AppColors.textPrimary,
            ),
            tooltip: '告警记录',
          ),
          
          // 更多操作按钮
          IconButton(
            onPressed: () {
              // HapticFeedback.lightImpact(); // 震动反馈已禁用
              _showMoreOptions();
            },
            icon: const Icon(
              PhosphorIconsBold.dotsThreeVertical,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建状态标签
  Widget _buildStatusBadge() {
    final status = _roomInfo['status'] as int;
    final color = AppColors.getDeviceStatusColor(status);
    final text = status == 0 ? '离线' : (status == 1 ? '在线' : '告警');
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: AppTextStyles.tiny.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建温湿度仪表盘区域
  /// 
  /// 【响应式设计】
  /// 使用 LayoutBuilder 检测可用宽度，在小屏幕上减小间距
  /// 【实时数据】
  /// 现已对接真实温湿度传感器 API
  Widget _buildGaugeSection() {
    // 获取传感器在线状态
    final isOnline = _tempHumidityStatus?.isOnline ?? false;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 温湿度传感器状态标识
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isOnline 
                    ? AppColors.success.withOpacity(0.15)
                    : AppColors.error.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isOnline 
                        ? PhosphorIconsBold.wifiHigh 
                        : PhosphorIconsBold.wifiSlash,
                    color: isOnline ? AppColors.success : AppColors.error,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isOnline ? '温湿度在线' : '温湿度离线',
                    style: AppTextStyles.tiny.copyWith(
                      color: isOnline ? AppColors.success : AppColors.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            if (_tempHumidityStatus?.lastUpdate != null)
              Text(
                '更新: ${_formatUpdateTime(_tempHumidityStatus!.lastUpdate)}',
                style: AppTextStyles.tiny.copyWith(color: AppColors.textTertiary),
              ),
          ],
        ),
        const SizedBox(height: 12),
        
        // 仪表盘区域
        LayoutBuilder(
          builder: (context, constraints) {
            final spacing = constraints.maxWidth < 320 ? 8.0 : 12.0;
            
            // 加载中状态
            if (_isTempHumidityLoading) {
              return Row(
                children: [
                  Expanded(
                    child: _buildGaugeLoadingPlaceholder('温度'),
                  ),
                  SizedBox(width: spacing),
                  Expanded(
                    child: _buildGaugeLoadingPlaceholder('湿度'),
                  ),
                ],
              );
            }
            
            // 离线或无数据状态
            if (!isOnline || _tempHumidityStatus == null) {
              return Row(
                children: [
                  Expanded(
                    child: _buildGaugeOfflinePlaceholder('温度'),
                  ),
                  SizedBox(width: spacing),
                  Expanded(
                    child: _buildGaugeOfflinePlaceholder('湿度'),
                  ),
                ],
              );
            }
            
            // 正常显示仪表盘
            return Row(
              children: [
                Expanded(
                  child: GaugeWidget(
                    title: '温度',
                    value: _sensorData['temperature'] as double,
                    unit: '°C',
                    min: _sensorData['tempMin'] as double,
                    max: _sensorData['tempMax'] as double,
                    alarmHigh: _sensorData['tempAlarmHigh'] as double,
                    alarmLow: _sensorData['tempAlarmLow'] as double,
                    color: AppColors.warning,
                    icon: PhosphorIconsBold.thermometerHot,
                  ),
                ),
                
                SizedBox(width: spacing),
                
                Expanded(
                  child: GaugeWidget(
                    title: '湿度',
                    value: _sensorData['humidity'] as double,
                    unit: '%',
                    min: _sensorData['humidityMin'] as double,
                    max: _sensorData['humidityMax'] as double,
                    alarmHigh: _sensorData['humidityAlarmHigh'] as double,
                    color: AppColors.info,
                    icon: PhosphorIconsBold.drop,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
  
  /// 构建仪表盘加载中占位符
  Widget _buildGaugeLoadingPlaceholder(String title) {
    return GlassCard(
      child: Column(
        children: [
          Text(title, style: AppTextStyles.h4),
          const SizedBox(height: 20),
          SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primary.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 20),
          Text('加载中...', style: AppTextStyles.tiny.copyWith(color: AppColors.textTertiary)),
        ],
      ),
    );
  }
  
  /// 构建仪表盘离线占位符
  Widget _buildGaugeOfflinePlaceholder(String title) {
    return GlassCard(
      child: Column(
        children: [
          Text(title, style: AppTextStyles.h4),
          const SizedBox(height: 16),
          Icon(
            PhosphorIconsBold.wifiSlash,
            size: 40,
            color: AppColors.textTertiary.withOpacity(0.5),
          ),
          const SizedBox(height: 12),
          Text(
            '传感器离线',
            style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary),
          ),
          Text(
            '无数据',
            style: AppTextStyles.tiny.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
  
  /// 格式化更新时间
  String _formatUpdateTime(String? dateTime) {
    if (dateTime == null || dateTime.isEmpty) {
      return '--:--';
    }
    try {
      final dt = DateTime.parse(dateTime);
      final now = DateTime.now();
      final diff = now.difference(dt);
      
      if (diff.inMinutes < 1) {
        return '刚刚';
      } else if (diff.inMinutes < 60) {
        return '${diff.inMinutes}分钟前';
      } else if (diff.inHours < 24) {
        return '${diff.inHours}小时前';
      } else {
        return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
    } catch (_) {
      return '--:--';
    }
  }

  /// 构建设备状态区域
  Widget _buildDeviceStatusSection() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('设备状态', style: AppTextStyles.h4),
          const SizedBox(height: 16),
          
          DeviceStatusWidget(
            doorOpen: _deviceStatus['door'] as bool,
            lightOn: _deviceStatus['light'] as bool,
            acOn: _deviceStatus['ac'] as bool,
            acMode: _deviceStatus['acMode'] as String,
            acTemp: _deviceStatus['acTemp'] as int,
            cameraOnline: _deviceStatus['camera'] as bool,
            onCameraTap: () {
              // HapticFeedback.lightImpact(); // 震动反馈已禁用
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('视频预览（待开发）')),
              );
            },
          ),
        ],
      ),
    );
  }

  /// 构建门传感器详情区域
  /// 
  /// 【实现说明】
  /// 这个卡片展示门磁传感器的简要信息，点击可查看详细记录。
  /// 设计要点：
  /// 1. 外层展示关键信息：当前状态、最近开关时间、今日次数
  /// 2. 点击展开详细的开关历史记录
  /// 3. 使用颜色区分开门/关门状态
  /// 4. 离线时直接显示"离线无信息"，不显示缓存假数据
  Widget _buildDoorSensorSection() {
    // 获取传感器在线状态
    final isOnline = _doorStatus?.isOnline ?? false;
    
    // 只有在线且有数据时才显示详细信息
    final isOpen = isOnline ? (_doorStatus?.isOpen ?? false) : false;
    final sensorName = _doorStatus?.sensorName ?? '门磁传感器';
    final lastOpenTime = isOnline ? _doorStatus?.lastOpenTime : null;
    final todayOpenCount = isOnline ? (_doorStatus?.todayOpenCount ?? 0) : 0;
    
    // 加载中或错误状态
    if (_isDoorDataLoading) {
      return GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.textTertiary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    PhosphorIconsBold.door,
                    color: AppColors.textTertiary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text('门磁传感器', style: AppTextStyles.h4),
                const Spacer(),
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                '正在加载门磁数据...',
                style: AppTextStyles.caption,
              ),
            ),
          ],
        ),
      );
    }
    
    return GestureDetector(
      onTap: () {
        // HapticFeedback.lightImpact(); // 震动反馈已禁用
        _showDoorSensorDetail();
      },
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题栏
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: !isOnline
                            ? AppColors.textTertiary.withOpacity(0.15)
                            : (isOpen 
                                ? AppColors.warning.withOpacity(0.15)
                                : AppColors.success.withOpacity(0.15)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        !isOnline 
                            ? PhosphorIconsBold.wifiSlash 
                            : (isOpen ? PhosphorIconsBold.doorOpen : PhosphorIconsBold.door),
                        color: !isOnline 
                            ? AppColors.textTertiary 
                            : (isOpen ? AppColors.warning : AppColors.success),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('门磁传感器', style: AppTextStyles.h4),
                            // 实时数据标识（仅在线时显示）
                            if (_doorStatus != null && isOnline) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '实时',
                                  style: AppTextStyles.tiny.copyWith(
                                    color: AppColors.primary,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          sensorName,
                          style: AppTextStyles.caption,
                        ),
                      ],
                    ),
                  ],
                ),
                
                // 状态 + 箭头
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: !isOnline 
                            ? AppColors.error.withOpacity(0.15)
                            : (isOpen 
                                ? AppColors.warning.withOpacity(0.15)
                                : AppColors.success.withOpacity(0.15)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        !isOnline ? '离线' : (isOpen ? '已开启' : '已关闭'),
                        style: AppTextStyles.tiny.copyWith(
                          color: !isOnline 
                              ? AppColors.error 
                              : (isOpen ? AppColors.warning : AppColors.success),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      PhosphorIconsBold.caretRight,
                      color: AppColors.textTertiary,
                      size: 16,
                    ),
                  ],
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // 关键信息展示
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceBackground,
                borderRadius: BorderRadius.circular(12),
              ),
              child: isOnline
                  // 在线状态：显示完整信息
                  ? Row(
                      children: [
                        // 最近开门时间
                        Expanded(
                          child: _buildDoorInfoItem(
                            icon: PhosphorIconsBold.clockCounterClockwise,
                            label: '最近开门',
                            value: _formatTime(lastOpenTime),
                          ),
                        ),
                        
                        // 分隔线
                        Container(
                          width: 1,
                          height: 40,
                          color: AppColors.border,
                        ),
                        
                        // 今日开门次数
                        Expanded(
                          child: _buildDoorInfoItem(
                            icon: PhosphorIconsBold.arrowsLeftRight,
                            label: '今日开门',
                            value: '$todayOpenCount次',
                            valueColor: AppColors.primary,
                          ),
                        ),
                        
                        // 分隔线
                        Container(
                          width: 1,
                          height: 40,
                          color: AppColors.border,
                        ),
                        
                        // 传感器状态
                        Expanded(
                          child: _buildDoorInfoItem(
                            icon: PhosphorIconsBold.wifiHigh,
                            label: '传感器',
                            value: '在线',
                            valueColor: AppColors.success,
                          ),
                        ),
                      ],
                    )
                  // 离线状态：显示"离线无信息"
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          PhosphorIconsBold.wifiSlash,
                          color: AppColors.error,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '传感器离线，无信息',
                          style: AppTextStyles.body.copyWith(
                            color: AppColors.error,
                          ),
                        ),
                      ],
                    ),
            ),
            
            // 获取失败时显示重试按钮
            if (_doorDataError != null && _doorStatus == null) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _loadDoorSensorData,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        PhosphorIconsBold.arrowClockwise,
                        color: AppColors.primary,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '点击重新获取',
                        style: AppTextStyles.tiny.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            
            const SizedBox(height: 12),
            
            // 提示文字
            Center(
              child: Text(
                '点击查看详细开关记录',
                style: AppTextStyles.tiny.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 门磁信息项
  Widget _buildDoorInfoItem({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Column(
      children: [
        Icon(
          icon,
          color: AppColors.textTertiary,
          size: 16,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: AppTextStyles.tiny.copyWith(
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppTextStyles.caption.copyWith(
            color: valueColor ?? AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  /// 格式化时间（只显示时分）
  /// 
  /// 支持 ISO 格式 (2025-12-30T15:00:41) 和普通格式 (2025-12-30 15:00:41)
  String _formatTime(String? dateTime) {
    if (dateTime == null || dateTime.isEmpty) {
      return '--:--';
    }
    try {
      // 使用 DateTime.parse 解析 ISO 格式
      final dt = DateTime.parse(dateTime);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '--:--';
    }
  }

  /// 显示门磁传感器详情弹窗
  /// 
  /// 【更新】支持真实API数据和模拟数据
  void _showDoorSensorDetail() {
    // 获取真实数据或使用模拟数据
    final sensorCode = _doorStatus?.sensorCode ?? (_doorSensorData['sensorId'] as String);
    final todayOpenCount = _doorStats?.todayOpenCount ?? (_doorSensorData['todayOpenCount'] as int);
    final longestOpenMinutes = _doorStats?.longestOpenMinutes ?? 15;
    final avgOpenMinutes = _doorStats?.avgOpenMinutes ?? 5.0;
    
    // 使用真实事件数据或模拟数据
    final hasRealEvents = _doorEvents != null && _doorEvents!.events.isNotEmpty;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Container(
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
              
              // 标题
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('门磁开关记录', style: AppTextStyles.h3),
                            if (hasRealEvents) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.success.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '实时数据',
                                  style: AppTextStyles.tiny.copyWith(
                                    color: AppColors.success,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '传感器: $sensorCode',
                          style: AppTextStyles.caption,
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        // 刷新按钮
                        IconButton(
                          onPressed: () {
                            _loadDoorSensorData();
                            Navigator.pop(context);
                            Future.delayed(const Duration(milliseconds: 500), () {
                              if (mounted) _showDoorSensorDetail();
                            });
                          },
                          icon: const Icon(
                            PhosphorIconsBold.arrowClockwise,
                            color: AppColors.textSecondary,
                            size: 20,
                          ),
                          tooltip: '刷新数据',
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(
                            PhosphorIconsBold.x,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 8),
              
              // 统计信息
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceBackground,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildStatItem(
                          label: '今日开门',
                          value: '$todayOpenCount',
                          unit: '次',
                        ),
                      ),
                      Expanded(
                        child: _buildStatItem(
                          label: '最长开门',
                          value: '$longestOpenMinutes',
                          unit: '分钟',
                        ),
                      ),
                      Expanded(
                        child: _buildStatItem(
                          label: '平均开门',
                          value: avgOpenMinutes.toStringAsFixed(1),
                          unit: '分钟',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // 分隔线
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Text(
                      hasRealEvents 
                          ? '历史记录 (${_doorEvents!.total}条)'
                          : '历史记录 (模拟数据)',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        height: 1,
                        color: AppColors.border,
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 8),
              
              // 历史记录列表
              Expanded(
                child: hasRealEvents
                    ? ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: _doorEvents!.events.length,
                        itemBuilder: (context, index) {
                          final event = _doorEvents!.events[index];
                          final isLast = index == _doorEvents!.events.length - 1;
                          
                          return _buildDoorHistoryItem(
                            time: event.formattedTime,
                            isOpen: event.isOpen,
                            duration: event.formattedDuration,
                            isLast: isLast,
                          );
                        },
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: _doorHistory.length,
                        itemBuilder: (context, index) {
                          final record = _doorHistory[index];
                          final isOpen = record['action'] == 'open';
                          final isLast = index == _doorHistory.length - 1;
                          
                          return _buildDoorHistoryItem(
                            time: record['time'] as String,
                            isOpen: isOpen,
                            duration: record['duration'] as String?,
                            isLast: isLast,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 统计项
  Widget _buildStatItem({
    required String label,
    required String value,
    required String unit,
  }) {
    return Column(
      children: [
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: value,
                style: AppTextStyles.h2.copyWith(
                  color: AppColors.primary,
                ),
              ),
              TextSpan(
                text: ' $unit',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: AppTextStyles.tiny.copyWith(
            color: AppColors.textTertiary,
          ),
        ),
      ],
    );
  }

  /// 门磁历史记录项
  Widget _buildDoorHistoryItem({
    required String time,
    required bool isOpen,
    String? duration,
    bool isLast = false,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 左侧时间轴
          SizedBox(
            width: 60,
            child: Column(
              children: [
                // 时间点
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: isOpen ? AppColors.warning : AppColors.success,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (isOpen ? AppColors.warning : AppColors.success)
                            .withOpacity(0.3),
                        blurRadius: 6,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
                // 连接线
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: AppColors.border,
                    ),
                  ),
              ],
            ),
          ),
          
          // 右侧内容
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceBackground,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isOpen 
                      ? AppColors.warning.withOpacity(0.3)
                      : AppColors.success.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  // 图标
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isOpen 
                          ? AppColors.warning.withOpacity(0.15)
                          : AppColors.success.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isOpen ? PhosphorIconsBold.doorOpen : PhosphorIconsBold.door,
                      color: isOpen ? AppColors.warning : AppColors.success,
                      size: 18,
                    ),
                  ),
                  
                  const SizedBox(width: 12),
                  
                  // 信息
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isOpen ? '门已开启' : '门已关闭',
                          style: AppTextStyles.body.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          time,
                          style: AppTextStyles.tiny.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // 持续时间
                  if (duration != null && !isOpen)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '开门 $duration',
                        style: AppTextStyles.tiny.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建历史数据区域
  Widget _buildHistorySection() {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('历史数据', style: AppTextStyles.h4),
              // 时间范围选择
              _buildTimeRangeSelector(),
            ],
          ),
          const SizedBox(height: 16),
          
          // 图表（传入温湿度传感器地址）
          HistoryChartWidget(
            modbusAddress: _tempHumidityModbusAddress,
          ),
        ],
      ),
    );
  }

  /// 时间范围选择器
  Widget _buildTimeRangeSelector() {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.surfaceBackground,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTimeRangeItem('日', true),
          _buildTimeRangeItem('周', false),
          _buildTimeRangeItem('月', false),
        ],
      ),
    );
  }

  Widget _buildTimeRangeItem(String label, bool selected) {
    return GestureDetector(
      onTap: () {
        // HapticFeedback.lightImpact(); // 震动反馈已禁用
        // TODO: 切换时间范围
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: AppTextStyles.tiny.copyWith(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  /// 构建视频监控区域
  /// 
  /// 【实现说明】
  /// 这是一个预留的视频监控区域，后续可以接入：
  /// 1. RTSP 视频流（需要 flutter_vlc_player 或 video_player 插件）
  /// 2. HLS 视频流
  /// 3. WebRTC 实时视频
  /// 
  /// 目前先做占位UI，确保布局正确，后续接入真实视频流时
  /// 只需替换中间的占位组件即可。
  Widget _buildVideoSection() {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    PhosphorIconsBold.videoCamera,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text('实时监控', style: AppTextStyles.h4),
                ],
              ),
              
              // 摄像头状态
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _deviceStatus['camera'] as bool 
                      ? AppColors.success.withOpacity(0.15)
                      : AppColors.error.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _deviceStatus['camera'] as bool 
                            ? AppColors.success
                            : AppColors.error,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _deviceStatus['camera'] as bool ? '在线' : '离线',
                      style: AppTextStyles.tiny.copyWith(
                        color: _deviceStatus['camera'] as bool 
                            ? AppColors.success
                            : AppColors.error,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // 视频预览区域（16:9 比例）
          // 【播放模式切换】
          // 支持两种播放模式：
          // 1. webview: WebView 播放器（兼容性好，使用浏览器解码）【默认】
          // 2. video_player: 原生播放器（性能好，延迟低）
          AspectRatio(
            aspectRatio: 16 / 9,
            child: _currentPlayerMode == VideoPlayerMode.webView
                ? WvpWebViewPlayerWidget(
                    // 【修复】使用 key 控制重建，全屏退出后会回到初始状态
                    key: _videoPlayerKey,
                    isOnline: _deviceStatus['camera'] as bool,
                    cameraName: 'CAM-${_roomInfo['id']}',
                    onFullscreen: _openFullscreenVideo,
                    onSnapshot: (url) {
                      debugPrint('截图地址: $url');
                    },
                    onAlarm: (alarm) {
                      _handleAlarm(alarm);
                    },
                  )
                : WvpVideoPlayerWidget(
                    // 【修复】使用 key 控制重建，全屏退出后会回到初始状态
                    key: _videoPlayerKey,
                    isOnline: _deviceStatus['camera'] as bool,
                    cameraName: 'CAM-${_roomInfo['id']}',
                    onFullscreen: _openFullscreenVideo,
                    onSnapshot: (url) {
                      debugPrint('截图地址: $url');
                    },
                    onAlarm: (alarm) {
                      _handleAlarm(alarm);
                    },
                  ),
          ),
          
          const SizedBox(height: 12),
          
          // 操作按钮
          Row(
            children: [
              Expanded(
                child: _buildVideoActionButton(
                  icon: PhosphorIconsBold.arrowsOut,
                  label: '全屏',
                  onTap: _openFullscreenVideo,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildVideoActionButton(
                  icon: PhosphorIconsBold.record,
                  label: '录像回放',
                  onTap: _openCloudRecordList,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildVideoActionButton(
                  icon: _isSavingSnapshot 
                      ? PhosphorIconsBold.circleNotch 
                      : PhosphorIconsBold.camera,
                  label: _isSavingSnapshot ? '保存中...' : '截图',
                  onTap: _isSavingSnapshot ? () {} : _takeSnapshot,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // 播放模式切换按钮
          _buildPlayerModeSwitch(),
        ],
      ),
    );
  }

  // 【实现说明】
  // 原来的 _buildVideoPlaceholder 和 _buildCameraOffline 方法已删除
  // 这些功能现在由 WvpVideoPlayerWidget 组件内部实现
  // 保持代码简洁，避免重复

  /// 截图并保存到相册
  Future<void> _takeSnapshot() async {
    if (_isSavingSnapshot) return;
    
    setState(() => _isSavingSnapshot = true);
    
    try {
      // 从服务器获取截图
      debugPrint('[RoomDetail] 正在从服务器获取截图...');
      final imageBytes = await _wvpService.getSnapshotBytes();
      
      if (imageBytes == null || imageBytes.isEmpty) {
        throw Exception('获取截图失败，请确保视频正在播放');
      }
      
      debugPrint('[RoomDetail] 服务器截图成功，保存到相册...');
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
                Expanded(child: Text(result.message)),
              ],
            ),
            backgroundColor: result.success ? AppColors.success : AppColors.error,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('[RoomDetail] 截图失败: $e');
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

  /// 视频操作按钮
  Widget _buildVideoActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppColors.surfaceBackground,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: AppColors.textSecondary,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 打开全屏视频
  /// 
  /// 【播放模式切换】
  /// 根据当前播放模式选择对应的全屏页面：
  /// - video_player: 使用 FullscreenVideoPage
  /// - webview: 使用 FullscreenWebViewVideoPage
  Future<void> _openFullscreenVideo() async {
    // HapticFeedback.lightImpact(); // 震动反馈已禁用
    
    Widget fullscreenPage;
    if (_currentPlayerMode == VideoPlayerMode.videoPlayer) {
      fullscreenPage = FullscreenVideoPage(
        deviceId: WvpConfig.deviceId,
        channelId: WvpConfig.channelId,
        cameraName: 'CAM-${_roomInfo['id']}',
      );
    } else {
      fullscreenPage = FullscreenWebViewVideoPage(
        deviceId: WvpConfig.deviceId,
        channelId: WvpConfig.channelId,
        cameraName: 'CAM-${_roomInfo['id']}',
      );
    }
    
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => fullscreenPage),
    );
    
    // 【修复】全屏退出后，更新 key 触发小屏播放器重建
    // 这样组件会回到初始状态，显示"点击播放实时画面"的界面
    if (mounted) {
      setState(() {
        _videoPlayerKey = UniqueKey();
      });
    }
  }
  
  /// 构建播放模式切换按钮
  Widget _buildPlayerModeSwitch() {
    return Material(
      color: AppColors.surfaceBackground,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: _togglePlayerMode,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(
              color: _currentPlayerMode == VideoPlayerMode.videoPlayer
                  ? AppColors.primary.withValues(alpha: 0.3)
                  : AppColors.warning.withValues(alpha: 0.3),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                _currentPlayerMode == VideoPlayerMode.videoPlayer
                    ? PhosphorIconsBold.videoCamera
                    : PhosphorIconsBold.browser,
                color: _currentPlayerMode == VideoPlayerMode.videoPlayer
                    ? AppColors.primary
                    : AppColors.warning,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _playerModeService.getModeDisplayName(_currentPlayerMode),
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                PhosphorIconsBold.arrowsClockwise,
                color: AppColors.textSecondary,
                size: 18,
              ),
              const SizedBox(width: 4),
              Text(
                '切换',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  /// 打开云端录像列表
  void _openCloudRecordList() {
    CloudRecordListSheet.show(context);
  }
  
  /// 打开告警记录页面
  void _openAlarmHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const AlarmHistoryPage(),
      ),
    );
  }

  /// 处理报警信息
  /// 
  /// 【实现说明】
  /// 当摄像头检测到火灾等异常时，会通过 GB28181 协议发送报警。
  /// WVP 接收报警后，APP 通过轮询或推送获取报警信息。
  /// 这里处理报警的显示和后续操作（如查看录像）。
  void _handleAlarm(AlarmInfo alarm) {
    // 显示报警弹窗
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: Row(
          children: [
            Icon(
              alarm.isFireAlarm 
                  ? PhosphorIconsBold.fireTruck 
                  : PhosphorIconsBold.warning,
              color: AppColors.error,
            ),
            const SizedBox(width: 8),
            Text(
              alarm.isFireAlarm ? '🔥 火灾报警' : '⚠️ 设备报警',
              style: AppTextStyles.h4.copyWith(color: AppColors.error),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              alarm.alarmDescription,
              style: AppTextStyles.body,
            ),
            const SizedBox(height: 8),
            Text(
              '报警时间: ${_formatAlarmTime(alarm.alarmTime)}',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            Text(
              '设备编号: ${alarm.deviceId}',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          if (alarm.recordUrl != null)
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _playAlarmRecord(alarm);
              },
              icon: const Icon(PhosphorIconsBold.play, size: 16),
              label: const Text('查看录像'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
        ],
      ),
    );
  }

  /// 格式化报警时间
  String _formatAlarmTime(DateTime time) {
    return '${time.year}-${_pad(time.month)}-${_pad(time.day)} '
           '${_pad(time.hour)}:${_pad(time.minute)}:${_pad(time.second)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  /// 播放报警录像
  void _playAlarmRecord(AlarmInfo alarm) {
    // TODO: 实现录像回放功能
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('录像回放功能待开发')),
    );
  }

  /// 显示更多操作
  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 拖动条
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              
              _buildOptionItem(
                icon: PhosphorIconsBold.clockCounterClockwise,
                label: '告警记录',
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('告警记录（待开发）')),
                  );
                },
              ),
              _buildOptionItem(
                icon: PhosphorIconsBold.gear,
                label: '阈值设置',
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('阈值设置（待开发）')),
                  );
                },
              ),
              _buildOptionItem(
                icon: PhosphorIconsBold.share,
                label: '分享',
                onTap: () {
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textPrimary),
      title: Text(label, style: AppTextStyles.body),
      onTap: onTap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}

// 【实现说明】
// _VideoGridPainter 类已移至 wvp_video_player_widget.dart
// 避免代码重复，保持单一职责
