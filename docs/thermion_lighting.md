# Thermion 数字人照明优化方案

## 项目背景
基于 Flutter + Thermion (Filament 封装) 的数字人 3D 渲染系统照明优化，从 Three.js 专业灯光师配置迁移到 Thermion 平台，实现影视级数字人照明效果。

## 问题分析

### 初始问题
- 数字人模型显现"发白"、缺乏立体感
- 衣服材质平面化，缺乏质感和层次
- 整体照明过于平淡，无专业级视觉效果

### Three.js 参考配置分析
```json
// AmbientLight.json
{
  "intensity": 1.0,
  "color": 16777215  // 纯白环境光
}

// PointLight.json (头部主光)
{
  "position": [-0.31, 2.07, 0.57],
  "intensity": 1.92,
  "color": 16776693,
  "decay": 2
}

// PointLight (1).json (衣服主照明)
{
  "position": [-1.22, 0.49, 0.75],
  "intensity": 2.36,
  "color": 16709345,  // 暖橙色调
  "decay": 2
}

// PointLight (2).json (右侧补光)
{
  "position": [0.45, 0.49, 0.91],
  "intensity": 1.0,
  "color": 16777215,
  "decay": 2
}

// PointLight (3).json (背后轮廓光)
{
  "position": [0.49, 0.82, -0.46],
  "intensity": 2.52,
  "color": 16109516,
  "decay": 2
}
```

## 核心技术差异

### Three.js vs Thermion 转换要点

1. **环境光处理**
   - Three.js: AmbientLight 直接影响材质照明
   - Thermion: IBL (Image-Based Lighting) 需要更高强度模拟相同效果

2. **点光源衰减模型**
   - Three.js: `decay=2` 物理平方衰减
   - Thermion: `falloffRadius` 控制衰减范围

3. **色温转换**
   - Three.js: 十六进制颜色值 (如 16709345)
   - Thermion: 色温值 (如 2900K)

4. **强度单位**
   - Three.js: 相对强度 (1.0-3.0)
   - Thermion: 绝对强度 (40000-140000)

## 优化方案

### 第一阶段：基础转换
```dart
// IBL 环境光设置
double _iblIntensity = 42000.0;  // 模拟 AmbientLight 效果

// 直接转换 Three.js 配置
await _viewer!.addDirectLight(DirectLight.point(
  color: 5400.0,  // 16776693 -> 5400K
  intensity: 55000.0,  // 1.92 -> 55K (考虑单位差异)
  position: v.Vector3(-0.31, 2.07, 0.57),
  falloffRadius: 5.5,  // 模拟 decay=2
  castShadows: true,
));
```

### 第二阶段：专业级优化

#### 1. 主光 (Key Light) - 面部与上半身照明
```dart
await _viewer!.addDirectLight(DirectLight.point(
  color: 5400.0,          // 自然日光色温
  intensity: 55000.0,     // 增强主光，确保面部细节
  position: v.Vector3(-0.31, 2.07, 0.57),
  falloffRadius: 5.5,     // 覆盖上半身
  castShadows: true,      // 主光产生阴影
));
```

#### 2. 衣服专用照明 (Key Light for Clothing)
```dart
await _viewer!.addDirectLight(DirectLight.point(
  color: 2900.0,          // 钨丝灯暖色温，最大化红色反射
  intensity: 140000.0,    // 大幅增强，专门照亮衣服材质
  position: v.Vector3(-1.15, 0.55, 0.82),  // 微调角度优化
  falloffRadius: 2.5,     // 紧密聚焦衣服区域
  castShadows: false,
));
```

#### 3. 补光 (Fill Light)
```dart
await _viewer!.addDirectLight(DirectLight.point(
  color: 4200.0,          // 温暖色调，与主光形成对比
  intensity: 65000.0,     // 平衡左侧强光
  position: v.Vector3(0.52, 0.58, 0.95),
  falloffRadius: 3.8,     // 柔化右侧阴影
  castShadows: false,
));
```

#### 4. 轮廓光 (Rim Light)
```dart
await _viewer!.addDirectLight(DirectLight.point(
  color: 6200.0,          // 冷白光，与暖主光对比
  intensity: 75000.0,     // 突出边缘轮廓
  position: v.Vector3(0.42, 0.95, -0.52),  // 背后高位
  falloffRadius: 2.2,     // 集中轮廓效果
  castShadows: false,
));
```

### 第三阶段：阴影质量优化
```dart
// 高质量柔和阴影
await _viewer!.setShadowType(ShadowType.PCSS);
await _viewer!.setSoftShadowOptions(3.0, 0.35);  // 更柔和边缘
```

## 优化效果对比

### 优化前
- 模型发白，缺乏层次
- 衣服材质平面化
- 整体照明单调

### 优化后
- ✅ 面部轮廓清晰，自然阴影过渡
- ✅ 红色衣服质感丰富，有明暗层次
- ✅ 冷暖色温对比，营造专业视觉效果
- ✅ 立体感显著增强
- ✅ 保持 60FPS 性能

## 关键技术参数

### 色温配置策略
| 光源类型 | 色温(K) | 作用 |
|---------|--------|------|
| 主光     | 5400   | 自然日光，面部照明 |
| 衣服光   | 2900   | 钨丝灯暖光，增强红色 |
| 补光     | 4200   | 温暖平衡光 |
| 轮廓光   | 6200   | 冷白对比光 |

### 强度配置原理
- **主光**: 55K - 确保面部细节清晰
- **衣服光**: 140K - 材质照明需要更强光源
- **补光**: 65K - 平衡主光，消除硬阴影
- **轮廓光**: 75K - 背景分离效果

### IBL 环境光
- **强度**: 42000 - 平衡整体亮度，避免过曝
- **作用**: 模拟 Three.js AmbientLight 的材质基础照明

## 最佳实践

### 1. 数字人照明三点法则
- **Key Light**: 主要照明，产生主要形状和阴影
- **Fill Light**: 补光，平衡阴影对比度
- **Rim Light**: 轮廓光，分离主体与背景

### 2. 色温层次设计
- 使用冷暖色温对比创造视觉层次
- 暖色温增强红色材质反射
- 冷色温提供清晰的轮廓分离

### 3. 材质针对性照明
- 不同材质需要不同强度和色温的专用光源
- 衣服材质通常需要更强的定向照明
- 皮肤材质适合柔和的漫反射照明

### 4. 性能平衡
- 合理控制光源数量（4个点光源为最佳平衡点）
- 只在主光源启用阴影
- 使用适当的 falloffRadius 避免过度计算

## 后续优化方向

1. **动态光照系统**: 根据动画状态调整光照参数
2. **场景适配**: 不同场景的光照预设
3. **材质响应**: 根据不同材质类型自动调整光照
4. **实时调节**: 提供用户可调节的光照控制界面

---

*本文档记录了 Thermion 数字人照明系统从基础到专业级的完整优化过程，为后续照明优化提供技术基础和参考标准。*