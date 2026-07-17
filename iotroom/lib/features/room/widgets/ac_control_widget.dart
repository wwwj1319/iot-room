import 'dart:async';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../services/ac_service.dart';
import '../../../shared/widgets/glass_card.dart';

/// 空调控制面板组件
/// 
/// 功能：
/// 1. 显示空调当前状态（开关、模式、设定温度）
/// 2. 开关控制
/// 3. 模式切换（制冷/制热）
/// 4. 温度调节（升温/降温）
class ACControlWidget extends StatefulWidget {
  /// 空调控制器 Modbus 地址
  final int modbusAddress;
  
  /// 空调名称
  final String name;

  const ACControlWidget({
    super.key,
    this.modbusAddress = 3,
    this.name = '空调',
  });

  @override
  State<ACControlWidget> createState() => _ACControlWidgetState();
}

class _ACControlWidgetState extends State<ACControlWidget> {
  final ACService _service = ACService();
  
  ACStatus? _status;
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

  Future<void> _togglePower() async {
    if (_isControlling || _status == null) return;

    setState(() => _isControlling = true);

    try {
      ACControlResult result;
      if (_status!.isOn) {
        result = await _service.powerOff(
          modbusAddress: widget.modbusAddress,
          operator: 'APP用户',
        );
      } else {
        result = await _service.powerOn(
          mode: _status!.mode,
          modbusAddress: widget.modbusAddress,
          operator: 'APP用户',
        );
      }

      if (mounted) {
        if (result.success) {
          await _loadStatus();
          _showSnackBar(_status!.isOn ? '已开机' : '已关机', isError: false);
        } else {
          _showSnackBar(result.error ?? '操作失败', isError: true);
        }
      }
    } finally {
      if (mounted) setState(() => _isControlling = false);
    }
  }

  Future<void> _switchMode() async {
    if (_isControlling || _status == null || !_status!.isOn) return;

    setState(() => _isControlling = true);

    try {
      final newMode = _status!.mode == 'cool' ? 'heat' : 'cool';
      final result = await _service.powerOn(
        mode: newMode,
        modbusAddress: widget.modbusAddress,
        operator: 'APP用户',
      );

      if (mounted) {
        if (result.success) {
          await _loadStatus();
          _showSnackBar('已切换到${newMode == 'cool' ? '制冷' : '制热'}模式', isError: false);
        } else {
          _showSnackBar(result.error ?? '切换失败', isError: true);
        }
      }
    } finally {
      if (mounted) setState(() => _isControlling = false);
    }
  }

  Future<void> _tempUp() async {
    if (_isControlling || _status == null) return;

    setState(() => _isControlling = true);

    try {
      final result = await _service.tempUp(
        modbusAddress: widget.modbusAddress,
        operator: 'APP用户',
      );

      if (mounted) {
        if (result.success) {
          await _loadStatus();
        } else {
          _showSnackBar(result.error ?? '升温失败', isError: true);
        }
      }
    } finally {
      if (mounted) setState(() => _isControlling = false);
    }
  }

  Future<void> _tempDown() async {
    if (_isControlling || _status == null) return;

    setState(() => _isControlling = true);

    try {
      final result = await _service.tempDown(
        modbusAddress: widget.modbusAddress,
        operator: 'APP用户',
      );

      if (mounted) {
        if (result.success) {
          await _loadStatus();
        } else {
          _showSnackBar(result.error ?? '降温失败', isError: true);
        }
      }
    } finally {
      if (mounted) setState(() => _isControlling = false);
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
                  color: AppColors.info.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  PhosphorIconsBold.snowflake,
                  color: AppColors.info,
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
                      '红外空调控制器',
                      style: AppTextStyles.tiny.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
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

    final isOn = _status?.isOn ?? false;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isOn 
            ? AppColors.success.withOpacity(0.15)
            : AppColors.textTertiary.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        isOn ? '运行中' : '已关机',
        style: AppTextStyles.tiny.copyWith(
          color: isOn ? AppColors.success : AppColors.textTertiary,
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

    // 正常显示
    return Column(
      children: [
        // 温度显示和控制
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 降温按钮
            _buildTempButton(
              icon: PhosphorIconsBold.minus,
              onTap: _status!.isOn ? _tempDown : null,
            ),
            
            const SizedBox(width: 20),
            
            // 温度显示
            GestureDetector(
              onTap: _togglePower,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _status!.isOn
                      ? (_status!.isCooling 
                          ? AppColors.info.withOpacity(0.15)
                          : AppColors.warning.withOpacity(0.15))
                      : AppColors.surfaceBackground,
                  border: Border.all(
                    color: _status!.isOn
                        ? (_status!.isCooling ? AppColors.info : AppColors.warning)
                        : AppColors.divider,
                    width: 3,
                  ),
                  boxShadow: _status!.isOn
                      ? [
                          BoxShadow(
                            color: (_status!.isCooling 
                                ? AppColors.info 
                                : AppColors.warning).withOpacity(0.3),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_isControlling)
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else ...[
                      Text(
                        '${_status!.targetTemp}',
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: _status!.isOn
                              ? (_status!.isCooling ? AppColors.info : AppColors.warning)
                              : AppColors.textTertiary,
                        ),
                      ),
                      Text(
                        '°C',
                        style: AppTextStyles.caption.copyWith(
                          color: _status!.isOn
                              ? (_status!.isCooling ? AppColors.info : AppColors.warning)
                              : AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            
            const SizedBox(width: 20),
            
            // 升温按钮
            _buildTempButton(
              icon: PhosphorIconsBold.plus,
              onTap: _status!.isOn ? _tempUp : null,
            ),
          ],
        ),
        
        const SizedBox(height: 16),
        
        // 点击提示
        Text(
          '点击温度圆圈开关机',
          style: AppTextStyles.tiny.copyWith(color: AppColors.textTertiary),
        ),
        
        const SizedBox(height: 16),
        
        // 模式切换
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildModeButton(
              icon: PhosphorIconsBold.snowflake,
              label: '制冷',
              isSelected: _status!.mode == 'cool',
              color: AppColors.info,
              onTap: _status!.isOn && _status!.mode != 'cool' ? _switchMode : null,
            ),
            const SizedBox(width: 16),
            _buildModeButton(
              icon: PhosphorIconsBold.sun,
              label: '制热',
              isSelected: _status!.mode == 'heat',
              color: AppColors.warning,
              onTap: _status!.isOn && _status!.mode != 'heat' ? _switchMode : null,
            ),
          ],
        ),
        
        const SizedBox(height: 16),
        const Divider(height: 1),
        const SizedBox(height: 12),
        
        // 今日操作次数
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              PhosphorIconsBold.clockCounterClockwise,
              size: 14,
              color: AppColors.textTertiary,
            ),
            const SizedBox(width: 4),
            Text(
              '今日操作 ${_status!.todayOperationCount} 次',
              style: AppTextStyles.tiny.copyWith(color: AppColors.textTertiary),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTempButton({
    required IconData icon,
    VoidCallback? onTap,
  }) {
    final isEnabled = onTap != null && !_isControlling;
    
    return GestureDetector(
      onTap: isEnabled ? onTap : null,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isEnabled 
              ? AppColors.primary.withOpacity(0.15)
              : AppColors.surfaceBackground,
          border: Border.all(
            color: isEnabled ? AppColors.primary : AppColors.divider,
            width: 2,
          ),
        ),
        child: Icon(
          icon,
          color: isEnabled ? AppColors.primary : AppColors.textTertiary,
          size: 20,
        ),
      ),
    );
  }

  Widget _buildModeButton({
    required IconData icon,
    required String label,
    required bool isSelected,
    required Color color,
    VoidCallback? onTap,
  }) {
    final isEnabled = onTap != null && !_isControlling;
    
    return GestureDetector(
      onTap: isEnabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : AppColors.divider,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? color : AppColors.textTertiary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTextStyles.caption.copyWith(
                color: isSelected ? color : AppColors.textTertiary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

