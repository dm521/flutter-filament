import 'package:flutter/foundation.dart';
import 'blink_animation_controller.dart';
import 'blink_config.dart';

/// 眨眼动画系统测试类
class BlinkAnimationTest {
  
  /// 测试所有眨眼预设
  static void testAllPresets() {
    if (!kDebugMode) return;
    
    debugPrint('🧪 开始测试眨眼动画预设...');
    
    final presets = BlinkPresets.getAllPresets();
    
    for (final entry in presets.entries) {
      final name = entry.key;
      final config = entry.value;
      
      debugPrint('📋 预设: $name');
      debugPrint('   间隔: ${config.minInterval.toStringAsFixed(1)}-${config.maxInterval.toStringAsFixed(1)}秒');
      debugPrint('   持续: ${config.duration.toStringAsFixed(2)}秒');
      debugPrint('   帧率: ${config.speed.toStringAsFixed(0)}fps');
      debugPrint('   权重: ${_formatTypeWeights(config.typeWeights)}');
      debugPrint('');
    }
    
    debugPrint('✅ 眨眼动画预设测试完成');
  }
  
  /// 格式化眨眼类型权重
  static String _formatTypeWeights(Map<BlinkType, double> weights) {
    final parts = <String>[];
    
    weights.forEach((type, weight) {
      final percentage = (weight * 100).toStringAsFixed(0);
      parts.add('${type.name}$percentage%');
    });
    
    return parts.join(', ');
  }
  
  /// 模拟眨眼动画测试
  static void simulateBlinkAnimation() {
    if (!kDebugMode) return;
    
    debugPrint('🎬 模拟眨眼动画测试...');
    
    // 创建测试控制器
    final controller = BlinkAnimationController(
      onBlinkWeightChanged: (left, right) {
        debugPrint('👁️ 眨眼权重: 左眼=${left.toStringAsFixed(3)}, 右眼=${right.toStringAsFixed(3)}');
      },
      config: BlinkPresets.natural,
    );
    
    // 测试不同类型的眨眼
    debugPrint('测试双眼眨眼...');
    controller.triggerBlink(type: BlinkType.both);
    
    Future.delayed(Duration(seconds: 1), () {
      debugPrint('测试左眼眨眼...');
      controller.triggerBlink(type: BlinkType.leftOnly);
    });
    
    Future.delayed(Duration(seconds: 2), () {
      debugPrint('测试右眼眨眼...');
      controller.triggerBlink(type: BlinkType.rightOnly);
    });
    
    Future.delayed(Duration(seconds: 3), () {
      debugPrint('✅ 眨眼动画模拟测试完成');
      controller.dispose();
    });
  }
  
  /// 测试眨眼动画曲线
  static void testBlinkCurve() {
    if (!kDebugMode) return;
    
    debugPrint('📈 测试眨眼动画曲线...');
    
    const steps = 10;
    for (int i = 0; i <= steps; i++) {
      final progress = i / steps;
      final weight = _calculateTestBlinkWeight(progress);
      debugPrint('进度: ${(progress * 100).toStringAsFixed(0)}% -> 权重: ${weight.toStringAsFixed(3)}');
    }
    
    debugPrint('✅ 眨眼动画曲线测试完成');
  }
  
  /// 计算测试用的眨眼权重（简化版本）
  static double _calculateTestBlinkWeight(double progress) {
    if (progress <= 0.3) {
      // 闭眼阶段：快速闭合
      final t = progress / 0.3;
      return t * t * t * t; // easeInQuart
    } else {
      // 睁眼阶段：稍慢睁开
      final t = (progress - 0.3) / 0.7;
      return 1.0 - (1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t) * (1.0 - t)); // easeOutQuart
    }
  }
  
  /// 运行所有测试
  static void runAllTests() {
    testAllPresets();
    testBlinkCurve();
    // simulateBlinkAnimation(); // 需要在实际应用中运行
  }
}