# Thermion 数字人动画系统实现

## 项目概述
基于 Flutter + Thermion (Filament 封装) 的数字人 3D 渲染系统中集成 GLTF 骨骼动画支持，实现 idle 动画播放和控制功能。

## 技术架构

### 1. 动画系统核心组件

#### 1.1 Thermion 动画管理器
```dart
// Thermion 内部动画架构
AnimationManager -> FFIAsset -> ThermionViewer
```

**关键特性：**
- 基于 Filament 引擎的动画系统
- 支持 GLTF 嵌入动画和外部动画文件
- 骨骼动画、变形目标动画全支持
- 与渲染循环无缝集成

#### 1.2 动画资产管理
```dart
// 主要变量
ThermionAsset? _characterAsset;  // 角色主模型
ThermionAsset? _animationAsset;  // 动画数据资产
List<String> _animationNames = [];  // 动画列表
int _currentAnimationIndex = -1;    // 当前播放索引
bool _isAnimationPlaying = false;   // 播放状态
bool _isAnimationLooping = true;    // 循环状态
```

### 2. 动画加载流程

#### 2.1 资产分离加载策略
```dart
Future<void> _loadAnimationAssets(ThermionViewer viewer) async {
  // 1. 获取主角色模型（由ViewerWidget加载）
  final assets = await viewer.getAssets();
  _characterAsset = assets.first;

  // 2. 加载动画文件（独立GLB，不添加到场景）
  _animationAsset = await viewer.loadGltf(
    'assets/models/animation_erciyuan_idle.glb',
    addToScene: false,  // 关键：只用于动画数据
  );

  // 3. 获取动画信息
  _animationNames = await _animationAsset!.getGltfAnimationNames();

  // 4. 自动播放第一个动画
  if (_animationNames.isNotEmpty) {
    await _playIdleAnimation();
  }
}
```

**核心设计理念：**
- **资产分离**：角色模型和动画数据分别加载
- **按需加载**：动画文件不添加到场景，仅作动画数据源
- **自动识别**：自动获取动画列表和信息

#### 2.2 动画播放控制
```dart
Future<void> _playIdleAnimation() async {
  // 停止当前动画
  if (_currentAnimationIndex >= 0) {
    await _animationAsset!.stopGltfAnimation(_currentAnimationIndex);
  }

  // 播放新动画
  _currentAnimationIndex = 0;
  await _animationAsset!.playGltfAnimationByName(
    _animationNames[0],
    loop: _isAnimationLooping,      // 循环播放
    replaceActive: true,            // 替换当前动画
    crossfade: 0.3,                 // 平滑过渡
  );

  // 获取动画时长信息
  final duration = await _animationAsset!.getGltfAnimationDuration(0);
  debugPrint('⏱️ 动画时长: ${duration.toStringAsFixed(2)}秒');
}
```

### 3. 用户界面集成

#### 3.1 动画控制面板设计
```dart
// 🎬 动画控制面板UI
SlideTransition(
  position: Tween<Offset>(
    begin: const Offset(1, 0),  // 从右侧滑入
    end: Offset.zero,
  ).animate(_animationController),
  child: Container(
    // 半透明黑色背景 + 蓝色边框
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.8),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
    ),
    child: Column(
      children: [
        // 播放/暂停按钮
        ElevatedButton.icon(
          onPressed: _toggleAnimation,
          icon: Icon(_isAnimationPlaying ? Icons.pause : Icons.play_arrow),
          label: Text(_isAnimationPlaying ? '暂停' : '播放'),
        ),

        // 动画信息显示
        Container(/* 当前动画名称和状态 */),
      ],
    ),
  ),
)
```

#### 3.2 响应式状态管理
- **动态图标**：根据播放状态切换播放/暂停图标
- **状态指示**：实时显示当前动画名称和播放状态
- **颜色编码**：绿色表示播放，橙色表示暂停
- **加载提示**：动画未就绪时显示加载状态

### 4. Thermion API 深度应用

#### 4.1 核心动画接口
```dart
// 按名称播放动画（推荐）
await asset.playGltfAnimationByName(String name, {
  bool loop = false,           // 是否循环
  bool reverse = false,        // 是否反向播放
  bool replaceActive = true,   // 是否替换当前动画
  double crossfade = 0.0,      // 交叉淡化时间
  bool wait = false           // 是否等待动画完成
});

// 按索引播放动画
await asset.playGltfAnimation(int index, {
  bool loop = false,
  bool reverse = false,
  bool replaceActive = true,
  double crossfade = 0.0,
  double startOffset = 0.0
});

// 停止动画
await asset.stopGltfAnimation(int animationIndex);

// 获取动画信息
List<String> names = await asset.getGltfAnimationNames();
double duration = await asset.getGltfAnimationDuration(int index);
```

#### 4.2 高级动画特性

**交叉淡化 (Crossfade)**
- `crossfade: 0.3` 实现动画间平滑过渡
- 避免动画切换时的突兀跳跃
- 适用于 idle -> walk 等状态转换

**循环控制**
- `loop: true` 适用于 idle、walk 等持续动画
- `loop: false` 适用于 jump、attack 等单次动画
- 运行时可动态切换循环模式

**动画替换**
- `replaceActive: true` 立即替换当前动画
- `replaceActive: false` 与当前动画混合播放
- 支持多动画层叠效果

### 5. 集成到现有照明系统

#### 5.1 渲染管线集成
```dart
// 初始化流程中的集成点
onViewerAvailable: (viewer) async {
  // ... 现有的照明系统初始化 ...

  // 阶段8: 加载动画资产（新增）
  await _loadAnimationAssets(viewer);

  // 阶段9: 设置相机
  await _updateSphericalCamera();

  // 阶段10: 启用渲染
  await viewer.setRendering(true);
}
```

#### 5.2 性能优化考虑
- **资产分离**：减少主场景复杂度
- **按需加载**：仅在需要时加载动画数据
- **状态缓存**：避免重复的动画信息查询
- **渲染集成**：动画管理器直接集成到渲染循环

### 6. 资源管理和清理

#### 6.1 生命周期管理
```dart
@override
void dispose() {
  _fpsTimer?.cancel();
  _animationController.dispose();
  _cleanupResources();  // 包含动画资源清理
  super.dispose();
}

Future<void> _cleanupResources() async {
  // 清理动画资源
  if (_animationAsset != null && _currentAnimationIndex >= 0) {
    await _animationAsset!.stopGltfAnimation(_currentAnimationIndex);
  }

  // ... 其他资源清理 ...
}
```

#### 6.2 错误处理机制
- **加载失败处理**：优雅处理动画文件缺失
- **播放异常捕获**：防止动画播放错误影响渲染
- **状态同步保护**：确保UI状态与实际播放状态一致

## 技术特色

### 1. 专业级动画控制
- 支持标准GLTF动画格式
- 完整的播放控制（播放/暂停/循环）
- 平滑的动画过渡效果

### 2. 用户友好界面
- 直观的动画控制面板
- 实时状态反馈
- 响应式UI设计

### 3. 高性能实现
- 基于Filament引擎的底层优化
- 资产分离减少内存占用
- 与专业照明系统无缝集成

## 扩展方向

### 1. 多动画支持
- 动画列表选择器
- 动画过渡编辑器
- 动画混合控制

### 2. 高级控制
- 动画速度调节
- 关键帧预览
- 动画时间轴控制

### 3. 性能优化
- 动画预加载
- LOD动画系统
- 动画压缩和流式加载

---

*本文档记录了 Thermion 数字人动画系统的完整实现过程，为后续动画功能扩展提供技术基础。*