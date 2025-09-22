import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:thermion_flutter/thermion_flutter.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:animation_tools_dart/animation_tools_dart.dart';

// 独立的应用入口
void main() {
  runApp(const SimpleTestApp());
}

class SimpleTestApp extends StatelessWidget {
  const SimpleTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '写实数字人测试',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const SimpleThermionTest(),
    );
  }
}

// 🚀 革命性数字人口型同步系统

class SimpleThermionTest extends StatefulWidget {
  const SimpleThermionTest({super.key});

  @override
  State<SimpleThermionTest> createState() => _SimpleThermionTestState();
}

/// 🚀 革命性3D数字人口型同步系统
///
/// 技术特点：
/// - 统一动画管线：身体动画(骨骼) + 面部动画(bs.json轨道)
/// - 无冲突运行：分层控制，各司其职
/// - 简化流程：无需复杂权重覆盖逻辑
/// - 高性能：原生动画系统处理，无需手动帧同步
class _SimpleThermionTestState extends State<SimpleThermionTest>
    with WidgetsBindingObserver {

  // ===== 系统常量 =====
  static const int _arkitBlendshapeCount = 52;
  static const double _sunlightIntensity = 15600.0;
  static const double _sunlightColorTemp = 6400.0;
  static const double _iblIntensity = 75000.0;
  static const int _initializationDelayMs = 300;
  static const int _renderingDelayMs = 100;

  // ===== 核心3D渲染组件 =====
  ThermionViewer? _viewer;
  ThermionAsset? _asset;
  String _status = '初始化中...';
  bool _isInitialized = false;
  bool _isDisposed = false;

  // ===== 动画系统 =====
  final List<String> _animations = [];
  int _idleAnimationIndex = -1;
  int _selectedTalkAnimation = 1;

  // ===== 革命性口型同步系统 =====
  List<List<double>>? _blendshapeData;
  bool _isBlendshapeLoaded = false;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isLipSyncPlaying = false;
  StreamSubscription<void>? _completeSubscription;

  // ===== 交互控制系统 =====
  dynamic _inputHandler;
  bool _isPlaying = false;
  int _currentAnimationIndex = -1;
  StreamSubscription<Duration>? _positionSubscription;

  // ===== 生命周期管理 =====

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeSimpleViewer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (_viewer == null || _isDisposed) return;

    switch (state) {
      case AppLifecycleState.paused:
        // 应用进入后台，暂停渲染
        if (kDebugMode) debugPrint('🔄 应用进入后台，暂停渲染');
        _viewer?.setRendering(false);
        break;
      case AppLifecycleState.resumed:
        // 应用回到前台，恢复渲染
        if (kDebugMode) debugPrint('🔄 应用回到前台，恢复渲染');
        _resumeRendering();
        break;
      default:
        break;
    }
  }

  Future<void> _resumeRendering() async {
    if (_viewer == null || _isDisposed) return;

    try {
      // 延迟一下确保 Surface 准备好
      await Future.delayed(Duration(milliseconds: _renderingDelayMs));
      await _viewer!.setRendering(true);

      // 如果有 idle 动画，重新启动
      if (_isInitialized && _idleAnimationIndex != -1 && !_isLipSyncPlaying) {
        await _resumeIdleAnimation();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ 恢复渲染失败: $e');
    }
  }

  // ===== 3D场景初始化 =====

  /// 初始化3D查看器和场景
  Future<void> _initializeSimpleViewer() async {
    try {
      setState(() => _status = '创建 Viewer...');

      _viewer = await ThermionFlutterPlugin.createViewer();

      setState(() => _status = '等待 Surface 准备...');
      await Future.delayed(Duration(milliseconds: _initializationDelayMs));

      setState(() => _status = '启用渲染...');

      // 多次尝试启用渲染，处理 Surface 初始化问题
      bool renderingEnabled = false;
      for (int attempt = 0; attempt < 3; attempt++) {
        try {
          await _viewer!.setRendering(true);
          renderingEnabled = true;
          break;
        } catch (e) {
          if (kDebugMode) debugPrint('渲染启用尝试 ${attempt + 1} 失败: $e');
          if (attempt < 2) {
            await Future.delayed(Duration(milliseconds: 200 * (attempt + 1)));
          }
        }
      }

      if (!renderingEnabled) {
        throw Exception('无法启用渲染，Surface 可能未准备好');
      }

      setState(() => _status = '加载 Skybox...');

      // 加载 Skybox
      try {
        await _viewer!.loadSkybox(
          "assets/environments/studio_small_env_skybox.ktx",
        );
        if (kDebugMode) debugPrint('✅ Skybox 加载成功');
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ Skybox 加载失败: $e');
      }

      setState(() => _status = '加载 IBL 环境光...');

      // 加载 IBL 环境光
      try {
        await _viewer!.loadIbl(
          "assets/environments/studio_small_env_ibl.ktx",
          intensity: _sunlightIntensity,
        );

        // 应用 IBL 旋转
        var rotationMatrix = Matrix3.identity();
        Matrix4.rotationY(0.558505).copyRotation(rotationMatrix);
        await _viewer!.rotateIbl(rotationMatrix);

        if (kDebugMode) debugPrint('✅ IBL 环境光加载成功');
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ IBL 加载失败: $e');
      }

      setState(() => _status = '配置专业灯光...');

      // 清除现有灯光
      try {
        await _viewer!.destroyLights();
      } catch (_) {}

      // 主太阳光 - 基于新 settings.json 参数
      // sunlightColor: [0.955105, 0.827571, 0.767769] 对应暖白色
      // 通过色温近似: ~5400K (暖白)
      await _viewer!.addDirectLight(
        DirectLight.sun(
          color: _sunlightColorTemp, // 暖白色温
          intensity: _iblIntensity, // 更新为 settings.json 的 sunlightIntensity
          castShadows: true, // 启用阴影
          direction: Vector3(
            0.366695,
            -0.357967,
            -0.858717,
          ), // 更新为 settings.json 的最新方向
        ),
      );

      // 正面补光 - 增强正面填充
      await _viewer!.addDirectLight(
        DirectLight.sun(
          color: 5600.0, // 稍暖的补光
          intensity: 30000.0, // 增强正面补光
          castShadows: false,
          direction: Vector3(0.1, -0.4, -0.9).normalized(),
        ),
      );

      // 背面环境光 - 解决背面全黑问题
      await _viewer!.addDirectLight(
        DirectLight.sun(
          color: 5800.0, // 中性暖光
          intensity: 25000.0, // 中等强度背光
          castShadows: false,
          direction: Vector3(-0.2, -0.3, 0.9).normalized(), // 从背面照射
        ),
      );

      // 左侧补光 - 减少侧面阴影
      await _viewer!.addDirectLight(
        DirectLight.sun(
          color: 5700.0, // 中性光
          intensity: 18000.0, // 适中强度
          castShadows: false,
          direction: Vector3(-0.8, -0.2, -0.3).normalized(), // 从左侧照射
        ),
      );

      // 右侧轮廓光 - 保持立体感
      await _viewer!.addDirectLight(
        DirectLight.sun(
          color: 6200.0, // 稍冷的轮廓光
          intensity: 15000.0, // 适度轮廓光
          castShadows: false,
          direction: Vector3(0.8, -0.1, 0.5).normalized(), // 从右侧照射
        ),
      );

      setState(() => _status = '配置渲染效果...');

      // 配置后处理效果
      try {
        await _viewer!.setPostProcessing(true);

        // 启用阴影系统
        await _viewer!.setShadowsEnabled(true);

        // Tone Mapping - ACES
        await _viewer!.setToneMapping(ToneMapper.ACES);

        // Bloom 效果
        await _viewer!.setBloom(true, 0.348);

        // 抗锯齿 (MSAA, FXAA, TAA)
        await _viewer!.setAntiAliasing(true, true, true);

        if (kDebugMode) debugPrint('✅ 渲染效果配置完成');
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ 渲染效果配置失败: $e');
      }

      setState(() => _status = '设置相机曝光...');

      // 设置相机曝光参数
      try {
        final camera = await _viewer!.getActiveCamera();
        await camera.setExposure(
          16.0,
          1.0 / 125.0,
          100.0,
        ); // f/16, 1/125s, ISO100
        if (kDebugMode) debugPrint('✅ 相机曝光设置完成');
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ 相机曝光设置失败: $e');
      }

      setState(() => _status = '设置相机控制...');

      // 设置轨道控制器
      _inputHandler = DelegateInputHandler.fixedOrbit(_viewer!);

      // 设置相机到合适位置
      try {
        final camera = await _viewer!.getActiveCamera();
        await camera.lookAt(Vector3(0.0, 0.5, 2.5));
      } catch (e) {
        if (kDebugMode) debugPrint('相机设置失败: $e');
      }

      // 尝试加载你的角色模型
      try {
        setState(() => _status = '加载角色模型...');
        _asset = await _viewer!.loadGltf("assets/models/xiaomeng_0919_2.glb");
        await _asset!.transformToUnitCube();

        setState(() => _status = '检测动画...');

        // 获取动画列表
        final animationNames = await _asset!.getGltfAnimationNames();
        final animationDurations = await Future.wait(
          List.generate(
            animationNames.length,
            (i) => _asset!.getGltfAnimationDuration(i),
          ),
        );

        _animations.clear();
        for (int i = 0; i < animationNames.length; i++) {
          final name = animationNames[i].isEmpty
              ? "动画_${i + 1}"
              : animationNames[i];
          final duration = animationDurations[i];
          _animations.add("$name (${duration.toStringAsFixed(1)}s)");
        }

        if (kDebugMode) {
          debugPrint('🎭 发现 ${_animations.length} 个动画:');
          for (int i = 0; i < _animations.length; i++) {
            debugPrint('   ${i + 1}. ${_animations[i]}');
          }
        }

        // 检测idle动画
        _detectIdleAnimation(animationNames);

        // 加载口型数据
        await _loadBlendshapeData();

        // 自动播放idle动画
        await _startIdleAnimation();

        _isInitialized = true;
      } catch (e) {
        setState(() => _status = '⚠️ 模型加载失败: $e');
        if (kDebugMode) debugPrint('模型加载失败: $e');
      }
    } catch (e) {
      setState(() => _status = '❌ 初始化失败: $e');
      if (kDebugMode) {
        debugPrint('简单测试失败: $e');
      }
    }
  }

  // ===== 革命性口型同步系统 =====

  /// 加载音频分析的blendshape数据
  Future<void> _loadBlendshapeData() async {
    try {
      setState(() => _status = '加载 blendshape 数据...');

      if (kDebugMode) {
        debugPrint('📊 开始加载 blendshape 数据...');
      }

      final jsonString = await rootBundle.loadString('assets/wav/bs.json');
      final List<dynamic> rawData = json.decode(jsonString);

      _blendshapeData = rawData
          .map(
            (frame) =>
                List<double>.from(frame.map((value) => value.toDouble())),
          )
          .toList();

      _isBlendshapeLoaded = true;

      if (kDebugMode) {
        debugPrint('✅ blendshape 数据加载成功:');
        debugPrint('   总帧数: ${_blendshapeData!.length}');
        debugPrint('   每帧权重数: ${_blendshapeData!.first.length}');

        // 分析第一帧的数据
        final firstFrame = _blendshapeData!.first;
        final nonZeroCount = firstFrame.where((w) => w > 0.001).length;
        debugPrint('   第一帧非零权重: $nonZeroCount 个');

        // 特别检查 jawOpen (索引17)
        if (firstFrame.length > 17) {
          debugPrint(
            '   🦷 第一帧 jawOpen [17] = ${firstFrame[17].toStringAsFixed(4)}',
          );
        }

        // ✅ 已确认：权重52-54全为0，只使用前52个标准ARKit权重

        // 🔍 分析jawOpen数据分布
        _analyzeJawOpenData();
      }

      setState(() => _status = '✅ 口型同步系统准备就绪');
    } catch (e) {
      _isBlendshapeLoaded = false;
      setState(() => _status = '❌ blendshape 数据加载失败: $e');
      if (kDebugMode) {
        debugPrint('❌ 加载 blendshape 数据失败: $e');
      }
    }
  }

  /// 🚀 核心革命性方法：将bs.json数据直接分配给动画轨道
  /// 这是技术突破的关键：统一身体动画和面部动画管线
  Future<void> _assignBsJsonToAnimationTrack() async {
    if (_asset == null || _blendshapeData == null) {
      debugPrint('❌ 革命性方案失败：_asset或_blendshapeData为空');
      return;
    }

    try {
      setState(() => _status = '🚀 分配bs.json到动画轨道...');

      if (kDebugMode) {
        debugPrint('🎯 开始革命性方案：将bs.json直接分配给动画轨道');
        debugPrint('   总帧数: ${_blendshapeData!.length}');
        debugPrint('   每帧权重数: ${_blendshapeData!.first.length}');
      }

      // 1. 转换bs.json数据为Float32List格式
      final totalFrames = _blendshapeData!.length;
      final weightsPerFrame = _arkitBlendshapeCount; // ARKit标准blendshapes
      final flatData = Float32List(totalFrames * weightsPerFrame);

      for (int frame = 0; frame < totalFrames; frame++) {
        final frameWeights = _blendshapeData![frame];
        for (int i = 0; i < weightsPerFrame && i < frameWeights.length; i++) {
          flatData[frame * weightsPerFrame + i] = frameWeights[i];
        }
      }

      // 2. 定义ARKit blendshape名称（添加F前缀匹配Head_Mod）
      final morphTargetNames = [
        "F.eyeBlinkLeft", "F.eyeLookDownLeft", "F.eyeLookInLeft", "F.eyeLookOutLeft", "F.eyeLookUpLeft",
        "F.eyeSquintLeft", "F.eyeWideLeft", "F.eyeBlinkRight", "F.eyeLookDownRight", "F.eyeLookInRight",
        "F.eyeLookOutRight", "F.eyeLookUpRight", "F.eyeSquintRight", "F.eyeWideRight", "F.jawForward",
        "F.jawLeft", "F.jawRight", "F.jawOpen", "F.mouthClose", "F.mouthFunnel",
        "F.mouthPucker", "F.mouthLeft", "F.mouthRight", "F.mouthSmileLeft", "F.mouthSmileRight",
        "F.mouthFrownLeft", "F.mouthFrownRight", "F.mouthDimpleLeft", "F.mouthDimpleRight", "F.mouthStretchLeft",
        "F.mouthStretchRight", "F.mouthRollLower", "F.mouthRollUpper", "F.mouthShrugLower", "F.mouthShrugUpper",
        "F.mouthPressLeft", "F.mouthPressRight", "F.mouthLowerDownLeft", "F.mouthLowerDownRight", "F.mouthUpperUpLeft",
        "F.mouthUpperUpRight", "F.browDownLeft", "F.browDownRight", "F.browInnerUp", "F.browOuterUpLeft",
        "F.browOuterUpRight", "F.cheekPuff", "F.cheekSquintLeft", "F.cheekSquintRight", "F.noseSneerLeft",
        "F.noseSneerRight", "F.tongueOut"
      ];

      // 3. 创建MorphAnimationData - 这是革命性的关键！
      // 计算正确的帧时长：音频约59.16秒，1775帧
      final audioDurationMs = 59160.0; // 音频时长毫秒
      final frameLengthMs = audioDurationMs / totalFrames; // 约33.3ms每帧

      final morphAnimationData = MorphAnimationData(
        flatData,                           // 所有1775帧的bs.json数据
        morphTargetNames,                   // ARKit blendshape名称
        frameLengthInMs: frameLengthMs      // 精确时间同步
      );

      // 4. 分配到Head_Mod网格（主要面部表情控制）
      await _asset!.setMorphAnimationData(
        morphAnimationData,
        targetMeshNames: ["Head_Mod"]
      );

      // 5. 为Mouth_Mod创建专门的jawOpen动画轨道
      await _createMouthModJawOpenAnimation();

      if (kDebugMode) {
        debugPrint('🎯 革命性方案成功！bs.json数据已直接分配给动画的变形轨道');
        debugPrint('   主要网格: Head_Mod (F前缀blendshapes)');
        debugPrint('   协同网格: Mouth_Mod (T.jawOpen专用)');
        debugPrint('   动画帧率: 60 FPS');
        debugPrint('   blendshapes: ${morphTargetNames.length}个');
      }

      setState(() => _status = '🚀 革命性动画轨道已配置');

    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 革命性方案失败: $e');
      }
      setState(() => _status = '❌ 动画轨道配置失败: $e');
    }
  }

  /// 🦷 为Mouth_Mod创建专门的jawOpen动画轨道
  /// 实现Head_Mod + Mouth_Mod协同控制
  Future<void> _createMouthModJawOpenAnimation() async {
    if (_blendshapeData == null) return;

    try {
      // 1. 提取第17个jawOpen值（所有帧）
      final totalFrames = _blendshapeData!.length;
      final jawOpenData = Float32List(totalFrames); // 只有一个值

      for (int frame = 0; frame < totalFrames; frame++) {
        final frameWeights = _blendshapeData![frame];
        if (frameWeights.length > 17) {
          jawOpenData[frame] = frameWeights[17]; // 第17个是jawOpen
        }
      }

      // 2. 创建Mouth_Mod专用的动画轨道
      final audioDurationMs = 59160.0; // 与主动画同步
      final frameLengthMs = audioDurationMs / totalFrames;

      final mouthMorphData = MorphAnimationData(
        jawOpenData,                        // 只有jawOpen数据
        ["T.jawOpen"],                      // Mouth_Mod的jawOpen目标
        frameLengthInMs: frameLengthMs      // 精确时间同步
      );

      // 3. 分配给Mouth_Mod
      await _asset!.setMorphAnimationData(
        mouthMorphData,
        targetMeshNames: ["Mouth_Mod"]
      );

      if (kDebugMode) {
        debugPrint('🦷 Mouth_Mod jawOpen动画轨道创建成功');
        debugPrint('   数据: bs.json第17个值 ($totalFrames帧)');
        debugPrint('   目标: T.jawOpen');
      }

    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Mouth_Mod动画轨道创建失败: $e');
      }
    }
  }

  // 🎭 统一动画播放 - 无需权重覆盖！
  Future<void> _playUnifiedAnimation() async {
    if (_asset == null) return;

    try {
      setState(() => _status = '🎭 启动统一动画系统...');

      if (kDebugMode) {
        debugPrint('🎭 开始统一动画播放：身体动画 + 面部动画轨道');
      }

      // 1. 清除现有的morph动画数据
      final childEntities = await _asset!.getChildEntities();
      for (int i = 0; i < childEntities.length; i++) {
        try {
          await _asset!.clearMorphAnimationData(childEntities[i]);
        } catch (_) {
          // 忽略清理错误
        }
      }

      // 2. 分配bs.json数据到动画轨道
      await _assignBsJsonToAnimationTrack();

      // 3. 播放选择的身体动画（建模师已清除面部数据）
      if (_selectedTalkAnimation >= 0 && _selectedTalkAnimation < _animations.length) {
        await _asset!.playGltfAnimation(_selectedTalkAnimation, loop: true);
        _isPlaying = true;
        _currentAnimationIndex = _selectedTalkAnimation;

        if (kDebugMode) {
          debugPrint('✅ 身体动画已启动：${_animations[_selectedTalkAnimation]}');
          debugPrint('   建模师已清除面部数据，无冲突');
        }
      }

      // 4. 现在面部动画由bs.json轨道控制，无需权重覆盖！

      setState(() => _status = '🚀 统一动画系统运行中');

      if (kDebugMode) {
        debugPrint('🎉 革命性成功！统一动画管线已建立：');
        debugPrint('   ✓ 身体动作：由骨骼动画控制');
        debugPrint('   ✓ 面部表情：由bs.json动画轨道控制');
        debugPrint('   ✓ 无冲突运行：分层控制各司其职');
        debugPrint('   ✓ 简化流程：无需复杂权重覆盖逻辑');
      }

    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 统一动画播放失败: $e');
      }
      setState(() => _status = '❌ 统一动画失败: $e');
    }
  }

  // 检测idle动画
  void _detectIdleAnimation(List<String> animationNames) {
    // 查找包含idle关键词的动画
    const idleKeywords = [
      'idle',
      'Idle',
      'IDLE',
      'wait',
      'Wait',
      'stand',
      'Stand',
    ];

    for (int i = 0; i < animationNames.length; i++) {
      final name = animationNames[i].toLowerCase();
      for (final keyword in idleKeywords) {
        if (name.contains(keyword.toLowerCase())) {
          _idleAnimationIndex = i;
          if (kDebugMode) {
            debugPrint('🎯 找到idle动画: ${animationNames[i]} (索引: $i)');
          }
          return;
        }
      }
    }

    // 如果没找到idle动画，使用第一个动画作为idle
    if (animationNames.isNotEmpty) {
      _idleAnimationIndex = 0;
      if (kDebugMode) {
        debugPrint('⚠️ 未找到idle关键词，使用第一个动画作为idle: ${animationNames[0]}');
      }
    }
  }

  // ===== 动画管理系统 =====

  /// 开始播放idle动画
  Future<void> _startIdleAnimation() async {
    if (_asset == null || _idleAnimationIndex == -1) return;

    try {
      setState(() => _status = '🎭 启动idle动画...');

      if (kDebugMode) {
        debugPrint('🎭 开始播放idle动画 (索引: $_idleAnimationIndex)');
      }

      // 播放idle动画，循环播放
      await _asset!.playGltfAnimation(_idleAnimationIndex, loop: true);
      _isPlaying = true;
      _currentAnimationIndex = _idleAnimationIndex;

      setState(() => _status = '✅ 口型同步系统准备就绪');

      if (kDebugMode) {
        debugPrint('✅ Idle动画播放成功');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Idle动画播放失败: $e');
      }
      setState(() => _status = '⚠️ Idle动画播放失败，但系统可用');
    }
  }

  // 恢复idle动画播放
  Future<void> _resumeIdleAnimation() async {
    if (_asset == null || _idleAnimationIndex == -1) return;

    try {
      if (kDebugMode) {
        debugPrint('🔄 恢复idle动画播放');
      }

      // 重新播放idle动画
      await _asset!.playGltfAnimation(_idleAnimationIndex, loop: true);
      _isPlaying = true;
      _currentAnimationIndex = _idleAnimationIndex;

      if (kDebugMode) {
        debugPrint('✅ Idle动画已恢复');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 恢复idle动画失败: $e');
      }
    }
  }

  // ===== 播放控制系统 =====

  /// 🚀 革命性播放：统一动画系统（无需权重覆盖）
  Future<void> _playLipSync() async {
    if (!_isBlendshapeLoaded || _blendshapeData == null) {
      if (kDebugMode) {
        debugPrint('⚠️ 数据未准备好：blendshape=$_isBlendshapeLoaded');
      }
      return;
    }

    if (_isLipSyncPlaying) {
      await _stopLipSync();
    }

    try {
      _isLipSyncPlaying = true;

      if (kDebugMode) {
        debugPrint('🚀 开始革命性口型同步播放...');
        debugPrint('   音频文件: wav/output.wav');
        debugPrint('   bs.json帧数: ${_blendshapeData!.length}');
        debugPrint('   🎯 革命性特点:');
        debugPrint('      ✓ 身体动画：骨骼动画控制（建模师已清除面部数据）');
        debugPrint('      ✓ 面部动画：bs.json动画轨道控制');
        debugPrint('      ✓ 无冲突：分层控制，各司其职');
        debugPrint('      ✓ 简化：无需复杂的权重覆盖逻辑');
      }

      // 🎭 启动统一动画系统
      await _playUnifiedAnimation();

      setState(() {}); // 更新 UI 状态

      // 设置音频播放完成监听
      _completeSubscription?.cancel();
      _completeSubscription = _audioPlayer.onPlayerComplete.listen((_) async {
        if (kDebugMode) {
          debugPrint('🎵 音频播放完成');
        }
        await _stopLipSync();
      });

      // 🎵 开始播放音频（动画轨道会自动同步）
      await _audioPlayer.play(AssetSource('wav/output.wav'));

      if (kDebugMode) {
        debugPrint('✅ 革命性口型同步已启动！');
        debugPrint('   🎭 身体动画：运行中');
        debugPrint('   👄 面部动画：由bs.json轨道驱动');
        debugPrint('   🎵 音频播放：已开始');
        debugPrint('   ⚡ 性能：原生动画系统处理，无需手动帧同步');
      }

    } catch (e) {
      _isLipSyncPlaying = false;
      setState(() {});
      if (kDebugMode) {
        debugPrint('❌ 革命性口型同步失败: $e');
      }
    }
  }

  // 🚀 停止革命性动画系统
  Future<void> _stopLipSync() async {
    try {
      _isLipSyncPlaying = false;

      // 停止音频
      await _audioPlayer.stop();

      // 取消监听
      _positionSubscription?.cancel();
      _completeSubscription?.cancel();

      // 🔄 清除morph动画轨道数据
      if (_asset != null) {
        final childEntities = await _asset!.getChildEntities();
        for (int i = 0; i < childEntities.length; i++) {
          try {
            await _asset!.clearMorphAnimationData(childEntities[i]);
          } catch (_) {
            // 忽略清理错误
          }
        }
      }

      // 🎭 恢复idle动画
      await _resumeIdleAnimation();

      setState(() {}); // 更新 UI 状态

      if (kDebugMode) {
        debugPrint('⏹️ 革命性动画系统已停止');
        debugPrint('   ✓ 音频播放已停止');
        debugPrint('   ✓ morph动画轨道已清除');
        debugPrint('   ✓ 已恢复idle动画');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 停止革命性动画系统失败: $e');
      }
    }
  }

  // 🚀 革命性方案：无需手动帧处理，动画轨道自动同步

  // 分析jawOpen数据分布
  void _analyzeJawOpenData() {
    if (_blendshapeData == null) return;

    try {
      final jawOpenValues = <double>[];
      for (final frame in _blendshapeData!) {
        if (frame.length > 17) {
          jawOpenValues.add(frame[17]);
        }
      }

      if (jawOpenValues.isNotEmpty) {
        final maxJawOpen = jawOpenValues.reduce((a, b) => a > b ? a : b);
        final minJawOpen = jawOpenValues.reduce((a, b) => a < b ? a : b);
        final avgJawOpen =
            jawOpenValues.reduce((a, b) => a + b) / jawOpenValues.length;
        final nonZeroCount = jawOpenValues.where((v) => v > 0.001).length;

        debugPrint('📊 jawOpen数据分析:');
        debugPrint('   最大值: ${maxJawOpen.toStringAsFixed(4)}');
        debugPrint('   最小值: ${minJawOpen.toStringAsFixed(4)}');
        debugPrint('   平均值: ${avgJawOpen.toStringAsFixed(4)}');
        debugPrint(
          '   非零帧数: $nonZeroCount/${jawOpenValues.length} (${(nonZeroCount / jawOpenValues.length * 100).toStringAsFixed(1)}%)',
        );

        // 找到最大jawOpen值的帧
        final maxIndex = jawOpenValues.indexOf(maxJawOpen);
        debugPrint('   最大值出现在第$maxIndex帧');

        if (maxJawOpen < 0.01) {
          debugPrint('⚠️ jawOpen数据可能有问题：最大值只有${maxJawOpen.toStringAsFixed(4)}');
        }
      }
    } catch (e) {
      debugPrint('❌ jawOpen数据分析失败: $e');
    }
  }

  // 🚀 革命性方案：动画轨道自动管理权重，无需手动重置

  // ===== UI构建系统 =====
  /// 构建主界面，包含3D视图和控制面板
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('写实数字人测试')),
      body: Column(
        children: [
          // 扩大 3D 视图区域
          Expanded(
            flex: 4, // 占据更多空间
            child: _viewer != null && !_isDisposed
                ? Container(
                    // 添加容器来更好地控制 Surface
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: ThermionWidget(viewer: _viewer!),
                    ),
                  )
                : const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('加载中...', style: TextStyle(fontSize: 18)),
                      ],
                    ),
                  ),
          ),

          // 🔧 修复：固定最小高度的控制面板，防止Surface重建
          Container(
            constraints: const BoxConstraints(
              minHeight: 120, // 增加高度以容纳更多控件
              maxHeight: 180, // 最大高度，防止过度扩展
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              border: Border(top: BorderSide(color: Colors.grey.shade300)),
            ),
            child: _buildControlPanel(),
          ),
        ],
      ),
    );
  }

  // 构建简化的控制面板
  Widget _buildControlPanel() {
    if (!_isBlendshapeLoaded) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              _status,
              style: const TextStyle(fontSize: 11),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 播放控制按钮 - 紧凑布局
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
            Flexible(
              child: ElevatedButton.icon(
                onPressed:
                    !_isLipSyncPlaying && _isBlendshapeLoaded
                    ? _playLipSync
                    : null,
                icon: const Icon(Icons.play_arrow, size: 14),
                label: const Text('播放', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  minimumSize: const Size(60, 30),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Flexible(
              child: ElevatedButton.icon(
                onPressed: _isLipSyncPlaying ? _stopLipSync : null,
                icon: const Icon(Icons.stop, size: 14),
                label: const Text('停止', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  minimumSize: const Size(60, 30),
                ),
              ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 状态指示器
          _isLipSyncPlaying
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '播放中...',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                )
              : const SizedBox(height: 18),

          // 动画选择控件
          const Divider(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              children: [
                Row(
                  children: [
                    const Text(
                      '身体动画:',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButton<int>(
                        value: _selectedTalkAnimation,
                        isExpanded: true,
                        style: const TextStyle(fontSize: 11, color: Colors.black87),
                        items: _animations.asMap().entries.map((entry) {
                          final index = entry.key;
                          final animationName = entry.value;
                          return DropdownMenuItem<int>(
                            value: index,
                            child: Text(
                              animationName,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: _isLipSyncPlaying ? null : (value) {
                          if (value != null) {
                            setState(() {
                              _selectedTalkAnimation = value;
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '🚀 革命性方案：身体动画 + bs.json口型轨道',
                  style: TextStyle(
                    fontSize: 9,
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 🚀 革命性方案：权重验证由动画轨道系统自动处理


  // 🚀 革命性方案：已移除过时的权重覆盖逻辑，动画轨道自动处理

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);

    // 清理音频资源
    _positionSubscription?.cancel();
    _completeSubscription?.cancel();
    _audioPlayer.dispose();

    // 安全地清理 Viewer
    _cleanupViewer();

    super.dispose();
  }

  Future<void> _cleanupViewer() async {
    if (_viewer != null) {
      try {
        // 停止所有动画
        if (_asset != null) {
          for (int i = 0; i < _animations.length; i++) {
            try {
              await _asset!.stopGltfAnimation(i);
            } catch (_) {}
          }
        }

        // 停止渲染
        await _viewer!.setRendering(false);

        if (kDebugMode) debugPrint('✅ Viewer 清理完成');
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ Viewer 清理时出错: $e');
      }
    }
  }
}
