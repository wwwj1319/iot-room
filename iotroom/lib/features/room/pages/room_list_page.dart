import 'package:flutter/material.dart';
// import 'package:flutter/services.dart'; // 震动反馈已禁用
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../services/temp_humidity_service.dart';
import 'room_detail_page.dart';

/// 🏢 设备间列表页面
/// 
/// 【实现说明】
/// 这个页面展示所有设备间的列表
/// 用户可以：
/// 1. 查看所有设备间及其状态
/// 2. 搜索/筛选设备间
/// 3. 点击进入详情页
/// 
/// 列表使用卡片式布局，每个卡片显示：
/// - 设备间名称和位置
/// - 在线状态
/// - 温湿度实时数据
/// - 是否有告警
class RoomListPage extends StatefulWidget {
  const RoomListPage({super.key});

  @override
  State<RoomListPage> createState() => _RoomListPageState();
}

class _RoomListPageState extends State<RoomListPage> {
  // 搜索关键词
  String _searchKeyword = '';
  
  // 筛选状态：all, online, offline, alarm
  String _filterStatus = 'all';
  
  // 是否正在加载
  bool _isLoading = true;
  
  // 温湿度服务
  final TempHumidityService _tempHumidityService = TempHumidityService();

  // 设备间数据
  final List<Map<String, dynamic>> _rooms = [
    {
      'id': 'A01',
      'name': '配电间 A01',
      'location': '',
      'status': 1, // 0离线 1在线 2告警
      'temperature': 0.0,  // 将从API获取
      'humidity': 0.0,     // 将从API获取
      'alarmCount': 0,
      'modbusAddress': 1,  // 温湿度传感器地址
    },
  ];
  
  @override
  void initState() {
    super.initState();
    _loadRealData();
  }
  
  /// 从API加载真实温湿度数据
  Future<void> _loadRealData() async {
    setState(() => _isLoading = true);
    
    try {
      // 遍历所有设备间，获取温湿度数据
      for (int i = 0; i < _rooms.length; i++) {
        final room = _rooms[i];
        final modbusAddress = room['modbusAddress'] as int? ?? 1;
        
        // 调用API获取温湿度状态
        final status = await _tempHumidityService.getStatus(modbusAddress);
        
        if (status != null) {
          // 更新温湿度数据
          _rooms[i]['temperature'] = status.temperature;
          _rooms[i]['humidity'] = status.humidity;
          _rooms[i]['status'] = status.isOnline ? 1 : 0;
        } else {
          // API请求失败，标记为离线
          _rooms[i]['status'] = 0;
        }
      }
    } catch (e) {
      debugPrint('加载温湿度数据失败: $e');
    }
    
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  // 获取筛选后的列表
  List<Map<String, dynamic>> get _filteredRooms {
    return _rooms.where((room) {
      // 关键词筛选
      if (_searchKeyword.isNotEmpty) {
        final keyword = _searchKeyword.toLowerCase();
        final name = (room['name'] as String).toLowerCase();
        final location = (room['location'] as String).toLowerCase();
        if (!name.contains(keyword) && !location.contains(keyword)) {
          return false;
        }
      }
      
      // 状态筛选
      if (_filterStatus != 'all') {
        final status = room['status'] as int;
        switch (_filterStatus) {
          case 'online':
            return status == 1;
          case 'offline':
            return status == 0;
          case 'alarm':
            return status == 2 || (room['alarmCount'] as int) > 0;
        }
      }
      
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 顶部搜索和筛选
        _buildHeader(),
        
        // 列表（支持下拉刷新）
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _loadRealData,
                  color: AppColors.primary,
                  child: _filteredRooms.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                          physics: const BouncingScrollPhysics(
                            parent: AlwaysScrollableScrollPhysics(),
                          ),
                          itemCount: _filteredRooms.length,
                          itemBuilder: (context, index) {
                            return _buildRoomCard(_filteredRooms[index]);
                          },
                        ),
                ),
        ),
      ],
    );
  }

  /// 构建顶部区域
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Text('设备间', style: AppTextStyles.h2),
          
          const SizedBox(height: 12),
          
          // 搜索框
          _buildSearchBar(),
          
          const SizedBox(height: 12),
          
          // 筛选标签
          _buildFilterTabs(),
        ],
      ),
    );
  }

  /// 搜索框
  Widget _buildSearchBar() {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.surfaceBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withOpacity(0.5)),
      ),
      child: TextField(
        onChanged: (value) {
          setState(() {
            _searchKeyword = value;
          });
        },
        style: AppTextStyles.body,
        decoration: InputDecoration(
          hintText: '搜索设备间名称或位置',
          hintStyle: AppTextStyles.body.copyWith(color: AppColors.textTertiary),
          prefixIcon: const Icon(
            PhosphorIconsRegular.magnifyingGlass,
            color: AppColors.textTertiary,
            size: 20,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  /// 筛选标签
  Widget _buildFilterTabs() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildFilterChip('all', '全部', _rooms.length),
          _buildFilterChip('online', '在线', _rooms.where((r) => r['status'] == 1).length),
          _buildFilterChip('offline', '离线', _rooms.where((r) => r['status'] == 0).length),
          _buildFilterChip('alarm', '告警', _rooms.where((r) => r['status'] == 2 || (r['alarmCount'] as int) > 0).length),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String value, String label, int count) {
    final selected = _filterStatus == value;
    
    return GestureDetector(
      onTap: () {
        // HapticFeedback.lightImpact(); // 震动反馈已禁用
        setState(() {
          _filterStatus = value;
        });
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surfaceBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AppTextStyles.caption.copyWith(
                color: selected ? Colors.white : AppColors.textSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: selected 
                    ? Colors.white.withOpacity(0.2) 
                    : AppColors.border,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: AppTextStyles.tiny.copyWith(
                  color: selected ? Colors.white : AppColors.textTertiary,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 空状态
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            PhosphorIconsRegular.buildings,
            size: 64,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: 16),
          Text(
            '没有找到设备间',
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            '尝试更换筛选条件',
            style: AppTextStyles.caption,
          ),
        ],
      ),
    );
  }

  /// 构建设备间卡片
  Widget _buildRoomCard(Map<String, dynamic> room) {
    final status = room['status'] as int;
    final statusColor = AppColors.getDeviceStatusColor(status);
    final hasAlarm = status == 2 || (room['alarmCount'] as int) > 0;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        borderColor: hasAlarm ? AppColors.error.withOpacity(0.5) : null,
        onTap: () {
          // HapticFeedback.lightImpact(); // 震动反馈已禁用
          Navigator.of(context).push(
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) {
                return RoomDetailPage(roomId: room['id'] as String);
              },
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                // 丝滑的滑入动画
                const begin = Offset(1.0, 0.0);
                const end = Offset.zero;
                const curve = Curves.easeOutCubic;
                
                var tween = Tween(begin: begin, end: end).chain(
                  CurveTween(curve: curve),
                );
                
                return SlideTransition(
                  position: animation.drive(tween),
                  child: child,
                );
              },
              transitionDuration: const Duration(milliseconds: 300),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 第一行：名称 + 状态
            Row(
              children: [
                // 状态指示点
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: statusColor.withOpacity(0.5),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                
                // 名称
                Expanded(
                  child: Text(
                    room['name'] as String,
                    style: AppTextStyles.h4,
                  ),
                ),
                
                // 告警角标
                if (hasAlarm)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          PhosphorIconsBold.warning,
                          size: 12,
                          color: AppColors.error,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${room['alarmCount']}',
                          style: AppTextStyles.tiny.copyWith(
                            color: AppColors.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                
                // 箭头
                const SizedBox(width: 8),
                const Icon(
                  PhosphorIconsRegular.caretRight,
                  size: 18,
                  color: AppColors.textTertiary,
                ),
              ],
            ),
            
            const SizedBox(height: 4),
            
            // 第二行：位置
            Row(
              children: [
                const Icon(
                  PhosphorIconsRegular.mapPin,
                  size: 14,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(width: 4),
                Text(
                  room['location'] as String,
                  style: AppTextStyles.caption,
                ),
              ],
            ),
            
            // 第三行：温湿度数据（仅在线时显示）
            if (status != 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceBackground,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    // 温度
                    Expanded(
                      child: _buildDataItem(
                        icon: PhosphorIconsBold.thermometerHot,
                        label: '温度',
                        value: '${room['temperature']}°C',
                        color: (room['temperature'] as double) > 35 
                            ? AppColors.error 
                            : AppColors.warning,
                      ),
                    ),
                    
                    // 分隔线
                    Container(
                      width: 1,
                      height: 32,
                      color: AppColors.border,
                    ),
                    
                    // 湿度
                    Expanded(
                      child: _buildDataItem(
                        icon: PhosphorIconsBold.drop,
                        label: '湿度',
                        value: '${room['humidity']}%',
                        color: (room['humidity'] as double) > 75 
                            ? AppColors.error 
                            : AppColors.info,
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // 离线提示
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceBackground,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      PhosphorIconsRegular.wifiSlash,
                      size: 16,
                      color: AppColors.textTertiary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '设备离线，无法获取数据',
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 数据项
  Widget _buildDataItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTextStyles.tiny),
            Text(
              value,
              style: AppTextStyles.body.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

