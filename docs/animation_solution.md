# Thermion 动画解决方案

## 问题分析
经过深入研究Thermion源码，发现当前版本**不支持动画重定向**功能，即无法将分离的动画文件直接应用到另一个模型上。

## 技术限制
- GLTF动画与模型层次结构紧密绑定
- 缺乏骨骼映射和动画重定向API
- 动画播放只能在原始包含动画的资产上进行

## 解决方案

### 方案1：使用包含动画的完整模型（推荐）
将角色模型和idle动画合并到一个GLB文件中。

**优点**：
- 简单直接，完全兼容Thermion
- 性能最佳
- 无需复杂的动画重定向逻辑

**实现步骤**：
1. 使用Blender等工具将2D_Girl.glb和animation_erciyuan_idle.glb合并
2. 导出为单一的完整GLB文件
3. 直接加载和播放

### 方案2：使用Thermion骨骼动画API（复杂）
通过低级API手动实现动画重定向。

**步骤**：
1. 解析动画GLB的骨骼变换数据
2. 映射到目标模型的骨骼结构
3. 使用addBoneAnimation()应用动画

**代码示例**：
```dart
// 需要大量的自定义实现
await characterAsset.addBoneAnimation(
  BoneAnimationData(...), // 从动画文件提取的数据
  skinIndex: 0
);
```

### 方案3：预处理工具链
在构建时合并动画。

**工具选择**：
- Blender Python脚本
- glTF Pipeline
- 自定义处理工具

### 方案4：使用Thermion骨骼动画API（新发现）✨
通过深入研究Thermion源码发现的**实用方案**。

**核心发现**：
- Thermion实际支持三种动画系统：glTF动画、骨骼动画、变形动画
- `addBoneAnimation()` API可以将自定义动画数据应用到任何有骨骼的模型
- `animation_tools_dart` 包提供了 `BoneAnimationData` 数据结构

**实现步骤**：
1. 为角色模型添加骨骼动画组件：`await characterAsset.addAnimationComponent()`
2. 加载分离的动画GLB文件以获取动画数据
3. 从动画文件中提取骨骼变换数据
4. 使用 `BoneAnimationData` 将动画数据应用到角色模型
5. 调用 `addBoneAnimation()` 实现动画重定向

**代码示例**：
```dart
// 1. 添加动画组件
await characterAsset.addAnimationComponent();

// 2. 加载动画数据
final animationAsset = await viewer.loadGltf('animation_file.glb');
final boneNames = await characterAsset.getBoneNames();

// 3. 提取和应用骨骼动画数据
// (具体实现需要深入研究骨骼变换数据提取)
```

**优点**：
- 不需要重新合并GLB文件
- 支持动画重定向
- 利用Thermion原生API

**缺点**：
- 实现复杂度较高
- 需要深入理解骨骼动画系统

## 推荐实现

**更新后的建议**：
1. **短期方案**：使用方案1（合并GLB文件），快速实现功能
2. **长期方案**：研究并实现方案4（骨骼动画API），提供更灵活的动画系统

目前已在主应用中实现了方案4的基础框架，正在进行深入的动画数据提取研究。