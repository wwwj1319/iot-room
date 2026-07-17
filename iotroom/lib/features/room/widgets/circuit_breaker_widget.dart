import 'dart:async';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../services/circuit_breaker_service.dart';
import '../../../shared/widgets/glass_card.dart';

/// 智能断路器控制组件
/// 
/// 功能：
/// 1. 显示断路器当前状态（合闸/分闸）
/// 2. 提供开关控制按钮
/// 3. 显示今日开关次数
/// 4. 处理加载/错误状态
class CircuitBreakerWidget extends StatefulWidget {
  /// 断路器 Modbus 地址
  final int modbusAddress;
  
  /// 断路器名称
  final String name;

  const CircuitBreakerWidget({
    super.key,
    this.modbusAddress = 2,
    this.name = '照明控制',
  });

  @override
  State<CircuitBreakerWidget> createState() => _CircuitBreakerWidgetState();
}

class _CircuitBreakerWidgetState extends State<CircuitBreakerWidget> {
  final CircuitBreakerService _service = CircuitBreakerService();
  
  CircuitBreakerStatus? _status;
  bool _isLoading = true;
  bool _isControlling = false;
  String? _error;
  
  /// 自动刷新定时器（每30秒刷新一次）
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadStatus();
    // 启动定时刷新（每10秒刷新一次）
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _loadStatusSilent(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// 静默刷新（不显示加载状态，用于定时刷新）
  Future<void> _loadStatusSilent() async {
    // 如果正在控制中，跳过刷新
    if (_isControlling) return;
    
    try {
      final status = await _service.getStatus(modbusAddress: widget.modbusAddress);
      if (mounted && !_isControlling) {
        setState(() {
          _status = status;
          if (status != null) {
            _error = null;
          }
        });
      }
    } catch (e) {
      // 静默刷新失败不处理
    }
  }

  Future<void> _loadStatus() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final status = await _service.getStatus(modbusAddress: widget.modbusAddress);
      if (mounted) {
        setState(() {
          _status = status;
          _isLoading = false;
          if (status == null) {
            _error = '获取状态失败';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _toggleSwitch() async {
    if (_isControlling || _status == null) return;

    final newState = !_status!.isClosed;
    final oldState = _status!.isClosed;
    final action = newState ? '开灯' : '关灯';

    // 【乐观更新】立即更新 UI 状态，提升用户体验
    setState(() {
      _isControlling = true;
      // 立即更新本地状态
      _status = CircuitBreakerStatus(
        modbusAddress: _status!.modbusAddress,
        isClosed: newState,
        isOnline: _status!.isOnline,
        statusText: newState ? '合闸（通电）' : '分闸（断电）',
        lastUpdate: _status!.lastUpdate,
        todaySwitchCount: _status!.todaySwitchCount,
      );
    });

    try {
      final result = await _service.control(
        close: newState,
        modbusAddress: widget.modbusAddress,
        operator: 'APP用户',
        remark: '手动$action',
      );

      if (mounted) {
        if (result.success) {
          // 成功后静默刷新状态（确保与服务器同步）
          _loadStatus();
          _showSnackBar('$action 成功', isError: false);
        } else {
          // 失败时回滚状态
          setState(() {
            _status = CircuitBreakerStatus(
              modbusAddress: _status!.modbusAddress,
              isClosed: oldState,
              isOnline: _status!.isOnline,
              statusText: oldState ? '合闸（通电）' : '分闸（断电）',
              lastUpdate: _status!.lastUpdate,
              todaySwitchCount: _status!.todaySwitchCount,
            );
          });
          _showSnackBar(result.error ?? '$action 失败', isError: true);
        }
      }
    } catch (e) {
      // 异常时回滚状态
      if (mounted) {
        setState(() {
          _status = CircuitBreakerStatus(
            modbusAddress: _status!.modbusAddress,
            isClosed: oldState,
            isOnline: _status!.isOnline,
            statusText: oldState ? '合闸（通电）' : '分闸（断电）',
            lastUpdate: _status!.lastUpdate,
            todaySwitchCount: _status!.todaySwitchCount,
          );
        });
        _showSnackBar('操作失败: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isControlling = false;
        });
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.success,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  PhosphorIconsBold.lightbulb,
                  color: AppColors.warning,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.name, style: AppTextStyles.h4),
                    Text(
                      '智能断路器',
                      style: AppTextStyles.tiny.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              // 状态标签
              _buildStatusBadge(),
            ],
          ),
          
          const SizedBox(height: 20),
          
          // 内容区域
          _buildContent(),
        ],
      ),
    );
  }

  Widget _buildStatusBadge() {
    if (_isLoading) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.textTertiary.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.textTertiary,
          ),
        ),
      );
    }

    final isOnline = _status?.isOnline ?? false;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isOnline 
            ? AppColors.success.withOpacity(0.15)
            : AppColors.error.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        isOnline ? '在线' : '离线',
        style: AppTextStyles.tiny.copyWith(
          color: isOnline ? AppColors.success : AppColors.error,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return Center(
        child: Column(
          children: [
            const SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 12),
            Text('加载中...', style: AppTextStyles.caption),
          ],
        ),
      );
    }

    if (_error != null || _status == null) {
      return Center(
        child: Column(
          children: [
            Icon(
              PhosphorIconsBold.warning,
              color: AppColors.error,
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? '获取状态失败',
              style: AppTextStyles.caption.copyWith(color: AppColors.error),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _loadStatus,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    // 断路器离线状态
    if (!_status!.isOnline) {
      return Center(
        child: Column(
          children: [
            Icon(
              PhosphorIconsBold.wifiSlash,
              color: AppColors.error,
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              '断路器离线，无法控制',
              style: AppTextStyles.body.copyWith(color: AppColors.textTertiary),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _loadStatus,
              child: Text(
                '点击重试',
                style: AppTextStyles.tiny.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 正常显示
    return Column(
      children: [
        // 开关控制
        Row(
          children: [
            // 当前状态图标
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: _status!.isClosed
                    ? AppColors.warning.withOpacity(0.2)
                    : AppColors.surfaceBackground.withOpacity(0.5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _status!.isClosed
                      ? AppColors.warning.withOpacity(0.5)
                      : AppColors.divider,
                  width: 2,
                ),
              ),
              child: Icon(
                _status!.isClosed
                    ? PhosphorIconsFill.lightbulb
                    : PhosphorIconsBold.lightbulbFilament,
                size: 32,
                color: _status!.isClosed
                    ? AppColors.warning
                    : AppColors.textTertiary,
              ),
            ),
            
            const SizedBox(width: 16),
            
            // 状态文本
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _status!.isClosed ? '已开启' : '已关闭',
                    style: AppTextStyles.h3.copyWith(
                      color: _status!.isClosed
                          ? AppColors.warning
                          : AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    _status!.statusText,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            
            // 开关按钮
            GestureDetector(
              onTap: _isControlling ? null : _toggleSwitch,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 70,
                height: 36,
                decoration: BoxDecoration(
                  color: _status!.isClosed
                      ? AppColors.warning
                      : AppColors.surfaceBackground,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: _status!.isClosed
                        ? AppColors.warning
                        : AppColors.divider,
                    width: 2,
                  ),
                  boxShadow: _status!.isClosed
                      ? [
                          BoxShadow(
                            color: AppColors.warning.withOpacity(0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 200),
                  alignment: _status!.isClosed
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    width: 28,
                    height: 28,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: _isControlling
                          ? AppColors.textTertiary
                          : Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: _isControlling
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : null,
                  ),
                ),
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 16),
        const Divider(height: 1),
        const SizedBox(height: 12),
        
        // 统计信息
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatItem(
              icon: PhosphorIconsBold.clock,
              label: '最后更新',
              value: _formatTime(_status?.lastUpdateTime),
            ),
            Container(
              width: 1,
              height: 30,
              color: AppColors.divider,
            ),
            _buildStatItem(
              icon: PhosphorIconsBold.repeat,
              label: '今日开关',
              value: '${_status?.todaySwitchCount ?? 0} 次',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.textTertiary),
            const SizedBox(width: 4),
            Text(
              label,
              style: AppTextStyles.tiny.copyWith(color: AppColors.textTertiary),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  String _formatTime(DateTime? time) {
    if (time == null) return '--:--';
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}

