/// 眨眼动画配置文件
/// 提供各种预设的眨眼动画模式
class BlinkPresets {
  /// 自然眨眼模式（默认）
  static const natural = BlinkAnimationConfig(
    minInterval: 2.0,
    maxInterval: 8.0,
    duration: 0.15,
    speed: 60.0,
    typeWeights: {
      BlinkType.both: 0.85, // 大部分时间双眼同时眨眼
      BlinkType.leftOnly: 0.075, // 偶尔单眼眨眼
      BlinkType.rightOnly: 0.075,
    },
  );

  /// 活泼眨眼模式
  static const lively = BlinkAnimationConfig(
    minInterval: 1.5,
    maxInterval: 5.0,
    duration: 0.12,
    speed: 60.0,
    typeWeights: {
      BlinkType.both: 0.7,
      BlinkType.leftOnly: 0.15,
      BlinkType.rightOnly: 0.15,
    },
  );

  /// 慵懒眨眼模式
  static const lazy = BlinkAnimationConfig(
    minInterval: 3.0,
    maxInterval: 12.0,
    duration: 0.2,
    speed: 45.0,
    typeWeights: {
      BlinkType.both: 0.95,
      BlinkType.leftOnly: 0.025,
      BlinkType.rightOnly: 0.025,
    },
  );

  /// 专注眨眼模式（眨眼较少）
  static const focused = BlinkAnimationConfig(
    minInterval: 4.0,
    maxInterval: 15.0,
    duration: 0.1,
    speed: 60.0,
    typeWeights: {
      BlinkType.both: 1.0,
      BlinkType.leftOnly: 0.0,
      BlinkType.rightOnly: 0.0,
    },
  );

  /// 紧张眨眼模式（眨眼频繁）
  static const nervous = BlinkAnimationConfig(
    minInterval: 0.8,
    maxInterval: 3.0,
    duration: 0.08,
    speed: 75.0,
    typeWeights: {
      BlinkType.both: 0.6,
      BlinkType.leftOnly: 0.2,
      BlinkType.rightOnly: 0.2,
    },
  );

  /// 获取所有预设
  static Map<String, BlinkAnimationConfig> getAllPresets() {
    return {
      '自然': natural,
      '活泼': lively,
      '慵懒': lazy,
      '专注': focused,
      '紧张': nervous,
    };
  }
}

/// 眨眼动画配置
class BlinkAnimationConfig {
  final double minInterval; // 最小眨眼间隔（秒）
  final double maxInterval; // 最大眨眼间隔（秒）
  final double duration; // 眨眼持续时间（秒）
  final double speed; // 动画帧率（FPS）
  final Map<BlinkType, double> typeWeights; // 眨眼类型权重

  const BlinkAnimationConfig({
    required this.minInterval,
    required this.maxInterval,
    required this.duration,
    required this.speed,
    required this.typeWeights,
  });

  /// 创建自定义配置
  BlinkAnimationConfig copyWith({
    double? minInterval,
    double? maxInterval,
    double? duration,
    double? speed,
    Map<BlinkType, double>? typeWeights,
  }) {
    return BlinkAnimationConfig(
      minInterval: minInterval ?? this.minInterval,
      maxInterval: maxInterval ?? this.maxInterval,
      duration: duration ?? this.duration,
      speed: speed ?? this.speed,
      typeWeights: typeWeights ?? this.typeWeights,
    );
  }

  @override
  String toString() {
    return 'BlinkAnimationConfig('
        'interval: ${minInterval.toStringAsFixed(1)}-${maxInterval.toStringAsFixed(1)}s, '
        'duration: ${duration.toStringAsFixed(2)}s, '
        'speed: ${speed.toStringAsFixed(0)}fps)';
  }
}

/// 眨眼类型
enum BlinkType {
  both, // 双眼同时眨眼
  leftOnly, // 只眨左眼
  rightOnly, // 只眨右眼
}

extension BlinkTypeExtension on BlinkType {
  String get name {
    switch (this) {
      case BlinkType.both:
        return '双眼';
      case BlinkType.leftOnly:
        return '左眼';
      case BlinkType.rightOnly:
        return '右眼';
    }
  }
}
