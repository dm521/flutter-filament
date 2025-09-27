# 眨眼动画系统使用说明

## 概述

这个眨眼动画系统为你的3D数字人角色提供了自然、随机的眨眼动画效果。系统可以与idle动画完美配合，让角色看起来更加生动自然。

## 主要特性

### 🎯 自动眨眼动画
- **随机间隔**: 在设定的时间范围内随机生成眨眼间隔
- **自然曲线**: 使用平滑的动画曲线模拟真实的眨眼动作
- **多种类型**: 支持双眼同时眨眼、单眼眨眼等不同类型

### 🎨 多种预设模式
- **自然模式**: 模拟正常人的眨眼频率和节奏
- **活泼模式**: 更频繁的眨眼，适合活泼的角色
- **慵懒模式**: 较慢的眨眼频率，适合慵懒的角色
- **专注模式**: 眨眼较少，适合专注状态
- **紧张模式**: 频繁眨眼，适合紧张情绪

### 🎛️ 手动控制
- **手动触发**: 可以随时手动触发一次眨眼
- **精确控制**: 支持左右眼独立的权重控制
- **实时调整**: 可以实时调整眨眼参数

## 使用方法

### 1. 基本使用

```dart
// 创建眨眼控制器
final blinkController = BlinkAnimationController(
  onBlinkWeightChanged: (leftWeight, rightWeight) {
    // 更新角色的眨眼权重
    updateCharacterBlinkWeights(leftWeight, rightWeight);
  },
);

// 启动自动眨眼
blinkController.startAutoBlink();
```

### 2. 使用预设

```dart
// 使用活泼预设
blinkController.updateConfig(BlinkPresets.lively);

// 使用自定义配置
final customConfig = BlinkAnimationConfig(
  minInterval: 1.0,  // 最小间隔1秒
  maxInterval: 5.0,  // 最大间隔5秒
  duration: 0.12,    // 眨眼持续0.12秒
  speed: 60.0,       // 60fps动画
  typeWeights: {
    BlinkType.both: 0.8,
    BlinkType.leftOnly: 0.1,
    BlinkType.rightOnly: 0.1,
  },
);
blinkController.updateConfig(customConfig);
```

### 3. 手动控制

```dart
// 手动触发双眼眨眼
blinkController.triggerBlink();

// 手动触发左眼眨眼
blinkController.triggerBlink(type: BlinkType.leftOnly);

// 停止自动眨眼
blinkController.stopAutoBlink();
```

## 配置参数说明

### BlinkAnimationConfig 参数

| 参数 | 类型 | 说明 | 默认值 |
|------|------|------|--------|
| `minInterval` | double | 最小眨眼间隔（秒） | 2.0 |
| `maxInterval` | double | 最大眨眼间隔（秒） | 8.0 |
| `duration` | double | 眨眼持续时间（秒） | 0.15 |
| `speed` | double | 动画帧率（FPS） | 60.0 |
| `typeWeights` | Map | 眨眼类型权重分布 | 见下表 |

### 眨眼类型权重

| 类型 | 说明 | 自然模式权重 |
|------|------|-------------|
| `BlinkType.both` | 双眼同时眨眼 | 85% |
| `BlinkType.leftOnly` | 只眨左眼 | 7.5% |
| `BlinkType.rightOnly` | 只眨右眼 | 7.5% |

## 预设模式详情

### 自然模式 (Natural)
- 间隔: 2-8秒
- 持续: 0.15秒
- 适用: 日常对话、展示场景

### 活泼模式 (Lively)
- 间隔: 1.5-5秒
- 持续: 0.12秒
- 适用: 活泼角色、互动场景

### 慵懒模式 (Lazy)
- 间隔: 3-12秒
- 持续: 0.2秒
- 适用: 慵懒角色、放松场景

### 专注模式 (Focused)
- 间隔: 4-15秒
- 持续: 0.1秒
- 适用: 工作场景、专注状态

### 紧张模式 (Nervous)
- 间隔: 0.8-3秒
- 持续: 0.08秒
- 适用: 紧张情绪、压力场景

## 与动画系统集成

### 与Idle动画配合
```dart
// 播放idle动画时启动眨眼
await playIdleAnimation();
blinkController.startAutoBlink();

// 播放其他动画时暂停眨眼
await playOtherAnimation();
blinkController.stopAutoBlink();
```

### 与口型同步配合
```dart
// 播放口型动画时暂停眨眼，避免冲突
await playLipSyncAnimation();
blinkController.stopAutoBlink();

// 口型动画结束后恢复眨眼
await stopLipSyncAnimation();
blinkController.startAutoBlink();
```

## 调试和测试

系统提供了完整的测试工具：

```dart
// 运行所有测试
BlinkAnimationTest.runAllTests();

// 测试特定功能
BlinkAnimationTest.testAllPresets();
BlinkAnimationTest.testBlinkCurve();
```

## 性能优化建议

1. **合理设置帧率**: 60fps通常足够，更高的帧率会增加CPU负担
2. **避免频繁切换**: 不要频繁切换预设，会影响动画连续性
3. **及时释放资源**: 不使用时调用`dispose()`释放资源

## 故障排除

### 常见问题

1. **眨眼不工作**
   - 检查是否调用了`startAutoBlink()`
   - 确认`onBlinkWeightChanged`回调正确实现

2. **眨眼太频繁/太少**
   - 调整`minInterval`和`maxInterval`参数
   - 选择合适的预设模式

3. **动画不流畅**
   - 检查帧率设置是否合理
   - 确认主线程没有被阻塞

4. **与其他动画冲突**
   - 在播放口型动画时暂停眨眼
   - 确保权重更新的时机正确

## 扩展开发

如果需要自定义眨眼行为，可以：

1. 创建新的预设配置
2. 修改动画曲线算法
3. 添加新的眨眼类型
4. 集成情绪系统

## 版本历史

- v1.0: 基础眨眼动画系统
- v1.1: 添加多种预设模式
- v1.2: 优化动画曲线和性能

---

这个眨眼动画系统让你的数字人角色更加生动自然。如果有任何问题或建议，欢迎反馈！