import 'package:flutter/material.dart';
// import 'package:flutter/services.dart'; // 震动反馈已禁用
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/stat_card.dart';
import '../widgets/quick_actions_widget.dart';
import '../../room/pages/room_detail_page.dart';

/// 🏠 首页Tab内容
/// 
/// 【实现说明】
/// 这是首页仪表板的内容，从MainPage中抽取出来
/// 作为PageView的一个子页面
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> with AutomaticKeepAliveClientMixin {
  // 【实现说明】
  // AutomaticKeepAliveClientMixin 用于保持页面状态
  // 当切换到其他Tab时，这个页面的状态不会丢失
  // 必须重写 wantKeepAlive 返回 true
  
  @override
  bool get wantKeepAlive => true;

  // 模拟数据
  final Map<String, dynamic> _stats = {
    'totalRooms': 128,
    'onlineRooms': 120,
    'offlineRooms': 8,
    'alarmCount': 5,
    'urgentAlarms': 2,
    'todayInspections': 12,
  };

  @override
  Widget build(BuildContext context) {
    super.build(context); // 必须调用
    
    return Column(
      children: [
        // 顶部固定区域
        _buildHeader(),
        
        // 中间可滚动区域
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: [
                _buildStatsSection(),
                _buildDeviceOverview(),
                _buildQuickActions(),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 构建顶部区域
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_getGreeting(), style: AppTextStyles.caption),
              const SizedBox(height: 2),
              Text('智能监控平台', style: AppTextStyles.h3),
            ],
          ),
          _buildNotificationButton(),
        ],
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return '早上好 ☀️';
    if (hour < 18) return '下午好 🌤️';
    return '晚上好 🌙';
  }

  Widget _buildNotificationButton() {
    return Stack(
      children: [
        GlassCard(
          padding: const EdgeInsets.all(10),
          borderRadius: 12,
          onTap: () {
            // HapticFeedback.lightImpact(); // 震动反馈已禁用
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('通知中心（待开发）')),
            );
          },
          child: const Icon(
            PhosphorIconsBold.bell,
            color: AppColors.textPrimary,
            size: 20,
          ),
        ),
        if (_stats['urgentAlarms'] > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppColors.error,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStatsSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.15,
        children: [
          StatCard(
            title: '设备间总数',
            value: '${_stats['totalRooms']}',
            icon: PhosphorIconsBold.buildings,
            color: AppColors.primary,
            onTap: () => _navigateToRoomDetail(),
          ),
          StatCard(
            title: '在线设备间',
            value: '${_stats['onlineRooms']}',
            icon: PhosphorIconsBold.wifiHigh,
            color: AppColors.success,
          ),
          StatCard(
            title: '待处理告警',
            value: '${_stats['alarmCount']}',
            icon: PhosphorIconsBold.warning,
            color: AppColors.warning,
          ),
          StatCard(
            title: '今日巡检',
            value: '${_stats['todayInspections']}',
            icon: PhosphorIconsBold.clipboardText,
            color: AppColors.info,
            trend: '+3',
            trendPositive: true,
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceOverview() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('设备状态概览', style: AppTextStyles.h4),
                GestureDetector(
                  onTap: () => _navigateToRoomDetail(),
                  child: Text(
                    '查看全部',
                    style: AppTextStyles.caption.copyWith(color: AppColors.primary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildStatusItem('在线', _stats['onlineRooms'], AppColors.success)),
                Container(width: 1, height: 40, color: AppColors.divider),
                Expanded(child: _buildStatusItem('离线', _stats['offlineRooms'], AppColors.offline)),
                Container(width: 1, height: 40, color: AppColors.divider),
                Expanded(child: _buildStatusItem('告警中', _stats['urgentAlarms'], AppColors.error)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusItem(String label, int count, Color color) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text('$count', style: AppTextStyles.numberSmall.copyWith(color: color)),
          ],
        ),
        const SizedBox(height: 4),
        Text(label, style: AppTextStyles.tiny),
      ],
    );
  }

  Widget _buildQuickActions() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: QuickActionsWidget(),
    );
  }

  void _navigateToRoomDetail() {
    // HapticFeedback.lightImpact(); // 震动反馈已禁用
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) {
          return const RoomDetailPage();
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.easeOutCubic;
          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          return SlideTransition(position: animation.drive(tween), child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }
}

