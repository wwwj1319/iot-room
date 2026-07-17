import 'package:flutter/material.dart';
// import 'package:flutter/services.dart'; // 震动反馈已禁用
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import 'home_tab.dart';
import '../../room/pages/room_list_page.dart';
import '../../alarm/pages/alarm_history_page.dart';
import '../../inspection/pages/inspection_page.dart';

/// 🏠 主页面（底部导航容器）
/// 
/// 【实现说明】
/// 这是APP的主容器，包含底部导航栏和多个Tab页面
/// 
/// 实现丝滑切换的关键：
/// 1. 使用 PageView 实现滑动切换
/// 2. 配合 PageController 控制动画
/// 3. 底部导航和PageView联动
/// 
/// 为什么用PageView而不是IndexedStack？
/// - PageView: 支持滑动切换，有过渡动画，但会重建页面
/// - IndexedStack: 保持页面状态，但没有切换动画
/// 
/// 我们这里用PageView，因为用户体验更流畅
class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  // 当前选中的Tab索引
  int _currentIndex = 0;
  
  // PageView控制器
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: PageView(
          controller: _pageController,
          // 禁止手势滑动切换（可选，根据需求开启）
          // physics: const NeverScrollableScrollPhysics(),
          physics: const BouncingScrollPhysics(),
          onPageChanged: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          children: const [
            // 首页
            HomeTab(),
            // 设备间列表
            RoomListPage(),
            // 告警记录页面
            AlarmHistoryPage(showBackButton: false),
            // 巡检日历
            InspectionPage(),
          ],
        ),
      ),
      // 底部导航栏
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  /// 构建底部导航栏
  Widget _buildBottomNavBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        border: Border(
          top: BorderSide(
            color: AppColors.border.withOpacity(0.5),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, PhosphorIconsBold.house, PhosphorIconsRegular.house, '首页'),
              _buildNavItem(1, PhosphorIconsBold.buildings, PhosphorIconsRegular.buildings, '设备间'),
              _buildNavItem(2, PhosphorIconsBold.warning, PhosphorIconsRegular.warning, '告警'),
              _buildNavItem(3, PhosphorIconsBold.calendarCheck, PhosphorIconsRegular.calendarCheck, '巡检'),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建单个导航项
  Widget _buildNavItem(int index, IconData activeIcon, IconData inactiveIcon, String label) {
    final isSelected = _currentIndex == index;
    
    return GestureDetector(
      onTap: () {
        // HapticFeedback.lightImpact(); // 震动反馈已禁用
        
        // 使用动画切换页面
        _pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 图标 - 带动画效果
            AnimatedScale(
              scale: isSelected ? 1.1 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isSelected 
                      ? AppColors.primary.withOpacity(0.15) 
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isSelected ? activeIcon : inactiveIcon,
                  color: isSelected ? AppColors.primary : AppColors.textTertiary,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(height: 4),
            // 文字
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? AppColors.primary : AppColors.textTertiary,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}
