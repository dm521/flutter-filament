import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'blink_config.dart';

/// 眨眼动画控制器
/// 提供自然的随机眨眼动画，配合idle动画播放
class BlinkAnimationController {
  // 回调函数，用于设置眨眼权重
  final Function(double leftWeight, double rightWeight) onBlinkWeightChanged;
  
  // 动画控制
  Timer? _blinkTimer;
  Timer? _animationTimer;
  bool _isEnabled = false;
  bool _isBlinking = false;
  
  // 眨眼配置
  BlinkAnimationConfig _config = BlinkPresets.natural;
  
  final math.Random _random = math.Random();
  
  BlinkAnimationController({
    required this.onBlinkWeightChanged,
    BlinkAnimationConfig? config,
  }) {
    if (config != null) {
      _config = config;
    }
  }
  
  /// 启动自动眨眼
  void startAutoBlink() {
    if (_isEnabled) {
      if (kDebugMode) debugPrint('⚠️ 自动眨眼已经启动，跳过重复启动');
      return;
    }
    
    _isEnabled = true;
    _scheduleNextBlink();
    
    if (kDebugMode) {
      debugPrint('👁️ 自动眨眼动画已启动');
      debugPrint('   配置: ${_config.toString()}');
    }
  }
  
  /// 停止自动眨眼
  void stopAutoBlink() {
    if (!_isEnabled) return;
    
    _isEnabled = false;
    _blinkTimer?.cancel();
    _animationTimer?.cancel();
    
    // 重置眨眼状态
    onBlinkWeightChanged(0.0, 0.0);
    _isBlinking = false;
    
    if (kDebugMode) {
      debugPrint('👁️ 自动眨眼动画已停止');
    }
  }
  
  /// 手动触发一次眨眼
  void triggerBlink({BlinkType? type}) {
    if (_isBlinking) return;
    
    final blinkType = type ?? _getRandomBlinkType();
    _performBlink(blinkType);
  }
  
  /// 安排下一次眨眼
  void _scheduleNextBlink() {
    if (!_isEnabled) return;
    
    // 随机生成下次眨眼的时间间隔
    final interval = _config.minInterval + 
        _random.nextDouble() * (_config.maxInterval - _config.minInterval);
    
    _blinkTimer = Timer(Duration(milliseconds: (interval * 1000).round()), () {
      if (_isEnabled && !_isBlinking) {
        final blinkType = _getRandomBlinkType();
        _performBlink(blinkType);
      }
      _scheduleNextBlink(); // 安排下一次眨眼
    });
    
    if (kDebugMode) {
      debugPrint('👁️ 下次眨眼将在 ${interval.toStringAsFixed(1)} 秒后');
    }
  }
  
  /// 执行眨眼动画
  void _performBlink(BlinkType type) {
    if (_isBlinking) return;
    
    _isBlinking = true;
    
    if (kDebugMode) {
      debugPrint('👁️ 执行眨眼动画: ${type.name}');
    }
    
    // 计算动画参数
    final totalFrames = (_config.duration * _config.speed).round();
    final frameInterval = Duration(milliseconds: (1000 / _config.speed).round());
    
    int currentFrame = 0;
    
    _animationTimer = Timer.periodic(frameInterval, (timer) {
      if (!_isEnabled) {
        timer.cancel();
        _isBlinking = false;
        return;
      }
      
      // 计算当前帧的眨眼权重
      final progress = currentFrame / totalFrames;
      final weights = _calculateBlinkWeights(progress, type);
      
      // 应用眨眼权重
      onBlinkWeightChanged(weights.left, weights.right);
      
      currentFrame++;
      
      // 动画完成
      if (currentFrame > totalFrames) {
        timer.cancel();
        _isBlinking = false;
        
        // 确保眨眼完全结束
        onBlinkWeightChanged(0.0, 0.0);
        
        if (kDebugMode) {
          debugPrint('👁️ 眨眼动画完成');
        }
      }
    });
  }
  
  /// 计算眨眼权重
  BlinkWeights _calculateBlinkWeights(double progress, BlinkType type) {
    // 使用平滑的眨眼曲线（快速闭合，稍慢睁开）
    double weight;
    
    if (progress <= 0.3) {
      // 闭眼阶段：快速闭合
      weight = _easeInQuart(progress / 0.3);
    } else {
      // 睁眼阶段：稍慢睁开
      weight = 1.0 - _easeOutQuart((progress - 0.3) / 0.7);
    }
    
    // 根据眨眼类型分配权重
    switch (type) {
      case BlinkType.both:
        return BlinkWeights(left: weight, right: weight);
      case BlinkType.leftOnly:
        return BlinkWeights(left: weight, right: 0.0);
      case BlinkType.rightOnly:
        return BlinkWeights(left: 0.0, right: weight);
    }
  }
  
  /// 获取随机眨眼类型
  BlinkType _getRandomBlinkType() {
    final randomValue = _random.nextDouble();
    double cumulativeWeight = 0.0;
    
    for (final entry in _config.typeWeights.entries) {
      cumulativeWeight += entry.value;
      if (randomValue <= cumulativeWeight) {
        return entry.key;
      }
    }
    
    return BlinkType.both; // 默认双眼眨眼
  }
  
  /// 四次方缓入函数
  double _easeInQuart(double t) {
    return t * t * t * t;
  }
  
  /// 四次方缓出函数
  double _easeOutQuart(double t) {
    return 1.0 - math.pow(1.0 - t, 4);
  }
  
  /// 释放资源
  void dispose() {
    stopAutoBlink();
  }
  
  /// 是否正在自动眨眼
  bool get isEnabled => _isEnabled;
  
  /// 是否正在执行眨眼动画
  bool get isBlinking => _isBlinking;
  
  /// 获取当前配置
  BlinkAnimationConfig get config => _config;
  
  /// 更新配置
  void updateConfig(BlinkAnimationConfig newConfig) {
    _config = newConfig;
    
    if (kDebugMode) {
      debugPrint('👁️ 眨眼配置已更新: $_config');
    }
  }
}

/// 眨眼权重
class BlinkWeights {
  final double left;
  final double right;
  
  const BlinkWeights({required this.left, required this.right});
  
  @override
  String toString() => 'BlinkWeights(left: ${left.toStringAsFixed(3)}, right: ${right.toStringAsFixed(3)})';
}