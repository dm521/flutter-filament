import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:thermion_flutter/thermion_flutter.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:animation_tools_dart/animation_tools_dart.dart';
import 'camera_presets.dart';

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
  int _selectedTalkAnimation = 1;

  // ===== 革命性口型同步系统 =====
  List<List<double>>? _blendshapeData;
  bool _isBlendshapeLoaded = false;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isLipSyncPlaying = false;
  StreamSubscription<void>? _completeSubscription;
  bool _isMorphAnimationConfigured = false;

  // 手动滑块控制的状态变量
  double _headJawOpenValue = 0.0;
  double _mouthJawOpenValue = 0.0;
  bool _morphAnimationComponentAdded = false;

  // ===== 简化测试：移除动画更新循环相关变量 =====

  // ===== 交互控制系统 =====
  dynamic _inputHandler;
  StreamSubscription<Duration>? _positionSubscription;

  // ===== 相机预设系统 =====
  CameraPreset _cameraPreset = CameraPreset.soloCloseUp;

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

      // 🚫 禁用idle动画恢复（纯口型测试模式）

      if (kDebugMode) {
        debugPrint('🚫 应用恢复时不启动idle动画（纯口型测试模式）');
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
      if (kDebugMode) debugPrint('✅ 输入处理器已设置: $_inputHandler');

      // 设置相机到合适位置 - 调整为原始模型尺寸
      try {
        final camera = await _viewer!.getActiveCamera();
        // 由于移除了transformToUnitCube，需要调整相机距离和高度
        await camera.lookAt(Vector3(0.0, 1.0, 3.0)); // 后退更远，提高视角
      } catch (e) {
        if (kDebugMode) debugPrint('相机设置失败: $e');
      }

      // 尝试加载你的角色模型
      try {
        setState(() => _status = '加载角色模型...');
        _asset = await _viewer!.loadGltf("assets/models/xiaomeng_0922.glb");
        // 🔧 移除transformToUnitCube，避免破坏骨骼绑定导致模型破裂
        // await _asset!.transformToUnitCube();

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

        // 🔍 调试：打印模型实体信息
        try {
          final childEntities = await _asset!.getChildEntities();
          if (kDebugMode) {
            debugPrint('🎭 模型实体结构分析:');
            debugPrint('   总实体数: ${childEntities.length}');

            // 只检查关键实体：1(映射), 3, 12(口型), 13(口型)
            final keyEntities = [1, 3, 12, 13];
            for (final entityIndex in keyEntities) {
              if (entityIndex < childEntities.length) {
                try {
                  final morphTargets = await _asset!.getMorphTargetNames(
                    entity: childEntities[entityIndex],
                  );
                  debugPrint(
                    '   实体 $entityIndex: ${morphTargets.length} 个 morph targets',
                  );

                  if (morphTargets.isNotEmpty) {
                    // 检查关键blendshape
                    final fBlendshapes = morphTargets
                        .where((name) => name.startsWith('F.'))
                        .length;
                    final tBlendshapes = morphTargets
                        .where((name) => name.startsWith('T.'))
                        .length;

                    debugPrint(
                      '     F前缀: $fBlendshapes 个, T前缀: $tBlendshapes 个',
                    );
                    debugPrint('     前5个: ${morphTargets.take(5).join(', ')}');

                    // 标识实体用途
                    if (entityIndex == 1) {
                      debugPrint('     🎯 实体1: 映射实体');
                    } else if (entityIndex == 12 || entityIndex == 13) {
                      debugPrint('     🎯 实体$entityIndex: 口型驱动实体');
                    }
                  }
                } catch (e) {
                  debugPrint('   实体 $entityIndex: 无法获取morph targets ($e)');
                }
              }
            }
          }
        } catch (e) {
          if (kDebugMode) debugPrint('🔍 模型实体分析失败: $e');
        }

        // 加载口型数据
        await _loadBlendshapeData();

        // 暂时注释掉idle动画，专注测试口型
        // await _startIdleAnimation();
        if (kDebugMode) debugPrint('🎯 Idle动画已禁用，专注口型测试');

        // 🎥 应用默认相机预设（在模型加载完成后）
        try {
          await _applyCameraPresetSafe(_cameraPreset);
          if (kDebugMode) debugPrint('✅ 默认相机预设已应用');
        } catch (e) {
          if (kDebugMode) debugPrint('⚠️ 相机预设应用失败: $e');
        }

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

  /// 🎯 测试GLB内置动画方案（基于GPT-5建议）
  Future<void> _testBuiltInGlbAnimation() async {
    if (_asset == null) return;

    try {
      debugPrint('🎯 GPT-5建议：测试GLB内置的Xiaomeng_talk_03动画');

      // 获取GLB中的所有动画
      final animationNames = await _asset!.getGltfAnimationNames();
      debugPrint('📋 GLB动画列表: $animationNames');

      // 直接测试talk_03双实体同步效果
      int? talk03Index;
      for (int i = 0; i < animationNames.length; i++) {
        final name = animationNames[i];
        debugPrint('   动画$i: $name');
        if (name.contains('talk_03') || name.contains('talk03')) {
          talk03Index = i;
          debugPrint('✅ 找到talk_03动画: $name (索引: $i)');
          break;
        }
      }

      if (talk03Index != null) {
        debugPrint('🚀 播放GLB内置talk_03动画 - 同时驱动Head_Mod + Mouth_Mod');
        await _asset!.playGltfAnimation(talk03Index);
        setState(() => _status = '🎬 播放talk_03 (双实体同步)');
        debugPrint('✅ talk_03动画已启动，应该看到Head_Mod + Mouth_Mod同时动作');
        debugPrint('🔍 观察牙齿是否和GLTF查看器中一样明显可见');

        // 等待3秒观察talk_03效果
        await Future.delayed(Duration(seconds: 3));
        await _asset!.stopGltfAnimation(talk03Index);
        debugPrint('🛑 talk_03动画已停止');

        // 🎯 现在进行极限手动测试
        await _performExtremeJawOpenTest();
      }
    } catch (e) {
      debugPrint('❌ GLB内置动画测试失败: $e');
      setState(() => _status = '❌ 内置动画失败: $e');
    }
  }

  /// 🎯 模仿GLB内置动画：统一MorphAnimationData方法
  Future<void> _testUnifiedMorphAnimation() async {
    if (_asset == null || _blendshapeData == null) return;

    try {
      debugPrint('🎯 我们的方法：统一设置Head_Mod + Mouth_Mod，用bs.json数据同时驱动');

      // 🔍 获取所有需要的morph target名称
      final childEntities = await _asset!.getChildEntities();
      debugPrint('📋 检查实体的morph targets...');

      List<String> allMorphTargetNames = [];
      Map<String, int> morphToIndexMap = {};

      // 收集Head_Mod的morph targets
      for (int i = 0; i < childEntities.length; i++) {
        final entity = childEntities[i];
        final entityName = FilamentApp.instance!.getNameForEntity(entity);
        final morphTargets = await _asset!.getMorphTargetNames(entity: entity);

        if (entityName == "Head_Mod" && morphTargets.isNotEmpty) {
          debugPrint('✅ Head_Mod (实体$i): ${morphTargets.length}个morph targets');
          for (final morphName in morphTargets) {
            if (morphName.startsWith('F.')) {
              allMorphTargetNames.add(morphName);
              morphToIndexMap[morphName] = allMorphTargetNames.length - 1;
            }
          }
        }

        if (entityName == "Mouth_Mod" && morphTargets.isNotEmpty) {
          debugPrint(
            '✅ Mouth_Mod (实体$i): ${morphTargets.length}个morph targets',
          );
          for (final morphName in morphTargets) {
            if (morphName == "T.jawOpen") {
              allMorphTargetNames.add(morphName);
              morphToIndexMap[morphName] = allMorphTargetNames.length - 1;
            }
          }
        }
      }

      debugPrint('📋 统一morph target列表: $allMorphTargetNames');
      debugPrint('🗺️ 映射关系: $morphToIndexMap');

      if (allMorphTargetNames.isEmpty) {
        debugPrint('❌ 未找到任何morph targets');
        return;
      }

      // 🎯 创建统一的动画数据（模仿GLB内置动画的结构）
      final totalFrames = _blendshapeData!.length;
      final frameLengthMs = 59160.0 / totalFrames; // 30 FPS

      final unifiedFlatData = Float32List(
        totalFrames * allMorphTargetNames.length,
      );

      for (int frame = 0; frame < totalFrames; frame++) {
        final frameWeights = _blendshapeData![frame];
        final baseIndex = frame * allMorphTargetNames.length;

        for (int i = 0; i < allMorphTargetNames.length; i++) {
          final morphName = allMorphTargetNames[i];

          if (morphName.startsWith('F.')) {
            // F前缀：从bs.json映射
            final baseName = morphName.substring(2);
            final bsJsonIndex = _findBsJsonIndex(baseName);
            if (bsJsonIndex >= 0 && bsJsonIndex < frameWeights.length) {
              unifiedFlatData[baseIndex + i] = frameWeights[bsJsonIndex];
            }
          } else if (morphName == "T.jawOpen") {
            // T.jawOpen：来自bs.json索引17，增强权重
            if (frameWeights.length > 17) {
              final enhancedWeight = frameWeights[17] * 2.0;
              unifiedFlatData[baseIndex + i] = enhancedWeight > 1.0
                  ? 1.0
                  : enhancedWeight;
            }
          }
        }
      }

      final unifiedMorphData = MorphAnimationData(
        unifiedFlatData,
        allMorphTargetNames,
        frameLengthInMs: frameLengthMs,
      );

      debugPrint('🚀 设置统一MorphAnimationData，同时驱动Head_Mod + Mouth_Mod');

      // 🎯 首先确保animation component已激活
      await _asset!.addAnimationComponent();

      // 🎯 关键：指定targetMeshNames，避免应用到没有morph targets的XiaoMeng_Body
      debugPrint('🎯 指定targetMeshNames: ["Head_Mod", "Mouth_Mod"]');
      await _asset!.setMorphAnimationData(
        unifiedMorphData,
        targetMeshNames: ["Head_Mod", "Mouth_Mod"],
      );

      debugPrint('✅ 统一动画数据已设置，检查Head_Mod + Mouth_Mod是否同时工作');
      setState(() => _status = '🎯 统一morph动画已启动');
    } catch (e) {
      debugPrint('❌ 统一MorphAnimationData失败: $e');
      setState(() => _status = '❌ 统一动画失败: $e');
    }
  }

  /// 辅助方法：查找bs.json中的索引
  int _findBsJsonIndex(String baseName) {
    const bsJsonNames = [
      "browDownLeft",
      "browDownRight",
      "browInnerUp",
      "browOuterUpLeft",
      "browOuterUpRight",
      "cheekPuff",
      "cheekSquintLeft",
      "cheekSquintRight",
      "eyeBlinkLeft",
      "eyeBlinkRight",
      "eyeLookDownLeft",
      "eyeLookDownRight",
      "eyeLookInLeft",
      "eyeLookInRight",
      "eyeLookOutLeft",
      "eyeLookOutRight",
      "eyeLookUpLeft",
      "eyeLookUpRight",
      "eyeSquintLeft",
      "eyeSquintRight",
      "eyeWideLeft",
      "eyeWideRight",
      "jawForward",
      "jawLeft",
      "jawRight",
      "jawOpen",
      "mouthClose",
      "mouthFunnel",
      "mouthPucker",
      "mouthLeft",
      "mouthRight",
      "mouthSmileLeft",
      "mouthSmileRight",
      "mouthFrownLeft",
      "mouthFrownRight",
      "mouthDimpleLeft",
      "mouthDimpleRight",
      "mouthStretchLeft",
      "mouthStretchRight",
      "mouthRollLower",
      "mouthRollUpper",
      "mouthShrugLower",
      "mouthShrugUpper",
      "mouthPressLeft",
      "mouthPressRight",
      "mouthLowerDownLeft",
      "mouthLowerDownRight",
      "mouthUpperUpLeft",
      "mouthUpperUpRight",
      "noseSneerLeft",
      "noseSneerRight",
      "tongueOut",
    ];

    return bsJsonNames.indexOf(baseName);
  }

  /// 🎯 手动控制Head_Mod的F.jawOpen
  Future<void> _setHeadJawOpen(double value) async {
    if (_asset == null) return;

    setState(() => _headJawOpenValue = value);

    try {
      final childEntities = await _asset!.getChildEntities();

      for (int i = 0; i < childEntities.length; i++) {
        final entity = childEntities[i];
        final entityName = FilamentApp.instance!.getNameForEntity(entity);

        if (entityName == "Head_Mod") {
          // 获取Head_Mod的所有morph targets
          final morphTargets = await _asset!.getMorphTargetNames(
            entity: entity,
          );

          // 找到F.jawOpen的索引
          int jawOpenIndex = -1;
          for (int j = 0; j < morphTargets.length; j++) {
            if (morphTargets[j] == "F.jawOpen") {
              jawOpenIndex = j;
              break;
            }
          }

          if (jawOpenIndex >= 0) {
            // 创建权重数组，只设置F.jawOpen
            final weights = List<double>.filled(morphTargets.length, 0.0);
            weights[jawOpenIndex] = value;

            await _asset!.setMorphTargetWeights(entity, weights);
            debugPrint('✅ Head_Mod F.jawOpen设置为: $value');
          } else {
            debugPrint('❌ 未找到F.jawOpen在Head_Mod中');
          }
          break;
        }
      }
    } catch (e) {
      debugPrint('❌ 设置Head_Mod失败: $e');
    }
  }

  /// 🎯 手动控制Mouth_Mod的T.jawOpen
  Future<void> _setMouthJawOpen(double value) async {
    if (_asset == null) return;

    setState(() => _mouthJawOpenValue = value);

    try {
      final childEntities = await _asset!.getChildEntities();

      for (int i = 0; i < childEntities.length; i++) {
        final entity = childEntities[i];
        final entityName = FilamentApp.instance!.getNameForEntity(entity);

        if (entityName == "Mouth_Mod") {
          // 🔍 详细调试：检查Mouth_Mod的状态
          debugPrint('🔍 找到Mouth_Mod实体，实体索引: $i');

          final morphTargets = await _asset!.getMorphTargetNames(
            entity: entity,
          );
          debugPrint('🔍 Mouth_Mod的morph targets: $morphTargets');

          if (morphTargets.isNotEmpty) {
            // 🎯 确保animation component只添加一次
            if (!_morphAnimationComponentAdded) {
              try {
                await _asset!.addAnimationComponent();
                _morphAnimationComponentAdded = true;
                debugPrint('✅ Animation component已添加（一次性）');
              } catch (e) {
                debugPrint('⚠️ addAnimationComponent失败: $e');
              }
            }

            // 🎯 直接设置权重
            await _asset!.setMorphTargetWeights(entity, [value]);
            debugPrint('✅ Mouth_Mod T.jawOpen设置为: $value');
          } else {
            debugPrint('❌ Mouth_Mod没有morph targets！');
          }
          break;
        }
      }
    } catch (e) {
      debugPrint('❌ 设置Mouth_Mod失败: $e');
    }
  }

  /// 🔍 检查GLB模型的所有实体信息
  Future<void> _checkAllEntities() async {
    if (_asset == null) return;

    try {
      debugPrint('🔍 ====== GLB实体详细检查 ======');

      final childEntities = await _asset!.getChildEntities();
      debugPrint('📊 总实体数量: ${childEntities.length}');

      for (int i = 0; i < childEntities.length; i++) {
        final entity = childEntities[i];

        try {
          final entityName = FilamentApp.instance!.getNameForEntity(entity);
          debugPrint('');
          debugPrint('🏷️ 实体 $i:');
          debugPrint('   名称: "$entityName"');

          // 检查morph targets
          final morphTargets = await _asset!.getMorphTargetNames(
            entity: entity,
          );
          if (morphTargets.isNotEmpty) {
            debugPrint('   🎭 Morph Targets (${morphTargets.length}个):');
            for (int j = 0; j < morphTargets.length; j++) {
              debugPrint('      [$j]: ${morphTargets[j]}');
            }
          } else {
            debugPrint('   🚫 无morph targets');
          }
        } catch (e) {
          debugPrint('   ❌ 获取实体$i信息失败: $e');
        }
      }

      debugPrint('');
      debugPrint('🔍 ====== 检查完成 ======');
      setState(() => _status = '✅ GLB实体检查完成，查看日志');
    } catch (e) {
      debugPrint('❌ 检查实体失败: $e');
      setState(() => _status = '❌ 实体检查失败: $e');
    }
  }

  /// 🔥 极限T.jawOpen测试方法
  Future<void> _performExtremeJawOpenTest() async {
    if (_asset == null) return;

    try {
      debugPrint('🔥 开始极限T.jawOpen测试...');
      final childEntities = await _asset!.getChildEntities();

      for (int i = 0; i < childEntities.length; i++) {
        final entity = childEntities[i];
        final entityName = FilamentApp.instance!.getNameForEntity(entity);

        if (entityName == "Mouth_Mod") {
          debugPrint('🎯 找到Mouth_Mod实体，开始极限测试...');

          // 🔥 极限测试：多次大幅度变化
          for (int test = 0; test < 3; test++) {
            debugPrint('🔥 第${test + 1}轮测试：T.jawOpen 1.0');
            await _asset!.setMorphTargetWeights(entity, [1.0]);
            setState(() => _status = '🔥 T.jawOpen权重1.0 (第${test + 1}轮)');
            await Future.delayed(Duration(milliseconds: 1500));

            debugPrint('🔥 第${test + 1}轮测试：T.jawOpen 0.0');
            await _asset!.setMorphTargetWeights(entity, [0.0]);
            setState(() => _status = '🔥 T.jawOpen权重0.0 (第${test + 1}轮)');
            await Future.delayed(Duration(milliseconds: 1500));
          }

          debugPrint('🎯 极限测试完成：如果还是看不到牙齿动作，说明T.jawOpen在thermion中效果极微弱');
          setState(() => _status = '🎯 T.jawOpen极限测试完成');
          break;
        }
      }
    } catch (e) {
      debugPrint('❌ 极限测试失败: $e');
      setState(() => _status = '❌ 极限测试失败: $e');
    }
  }

  /// 🎯 改进的分离设置方法：确保Mouth_Mod正确工作
  Future<void> _testSeparateMorphAnimation() async {
    if (_asset == null || _blendshapeData == null) return;

    try {
      debugPrint('🎯 改进的分离方法：分别设置Head_Mod和Mouth_Mod，确保Mouth_Mod工作');

      final totalFrames = _blendshapeData!.length;
      final frameLengthMs = 59160.0 / totalFrames; // 30 FPS

      // 🎯 步骤1：首先确保animation component已激活
      await _asset!.addAnimationComponent();
      debugPrint('✅ Animation component已激活');

      // 🎯 步骤2：先设置Mouth_Mod（重点测试）
      final jawOnlyData = Float32List(totalFrames);
      for (int frame = 0; frame < totalFrames; frame++) {
        final frameWeights = _blendshapeData![frame];
        if (frameWeights.length > 17) {
          // 极大增强T.jawOpen权重，确保牙齿动作非常明显
          jawOnlyData[frame] = frameWeights[17] * 10.0; // 10倍极限放大！
          if (jawOnlyData[frame] > 1.0) {
            jawOnlyData[frame] = 1.0;
          }
        }
      }

      final mouthMorphData = MorphAnimationData(jawOnlyData, [
        "T.jawOpen",
      ], frameLengthInMs: frameLengthMs);

      debugPrint('🚀 首先设置Mouth_Mod (T.jawOpen 10倍极限增强！)');
      await _asset!.setMorphAnimationData(
        mouthMorphData,
        targetMeshNames: ["Mouth_Mod"],
      );
      debugPrint('✅ Mouth_Mod设置完成');

      // 小延迟让Mouth_Mod先激活
      await Future.delayed(Duration(milliseconds: 100));

      // 🎯 步骤3：设置Head_Mod
      debugPrint('🚀 然后设置Head_Mod (所有bs.json数据5倍放大！)');

      // 简化Head_Mod数据：只包含关键的口型相关blendshapes
      final keyMorphNames = [
        "F.jawOpen",
        "F.mouthClose",
        "F.mouthFunnel",
        "F.mouthPucker",
      ];
      final keyMorphData = Float32List(totalFrames * keyMorphNames.length);

      for (int frame = 0; frame < totalFrames; frame++) {
        final frameWeights = _blendshapeData![frame];
        final baseIndex = frame * keyMorphNames.length;

        // F.jawOpen: 来自bs.json索引25 (jawOpen) - 也要放大
        if (frameWeights.length > 25) {
          final enhancedJawOpen = frameWeights[25] * 5.0; // 5倍增强上颌
          keyMorphData[baseIndex + 0] = enhancedJawOpen > 1.0
              ? 1.0
              : enhancedJawOpen;
        }

        // F.mouthClose: 来自bs.json索引26 - 放大
        if (frameWeights.length > 26) {
          final enhanced = frameWeights[26] * 5.0; // 5倍放大
          keyMorphData[baseIndex + 1] = enhanced > 1.0 ? 1.0 : enhanced;
        }

        // F.mouthFunnel: 来自bs.json索引27 - 放大
        if (frameWeights.length > 27) {
          final enhanced = frameWeights[27] * 5.0; // 5倍放大
          keyMorphData[baseIndex + 2] = enhanced > 1.0 ? 1.0 : enhanced;
        }

        // F.mouthPucker: 来自bs.json索引28 - 放大
        if (frameWeights.length > 28) {
          final enhanced = frameWeights[28] * 5.0; // 5倍放大
          keyMorphData[baseIndex + 3] = enhanced > 1.0 ? 1.0 : enhanced;
        }
      }

      final headMorphData = MorphAnimationData(
        keyMorphData,
        keyMorphNames,
        frameLengthInMs: frameLengthMs,
      );

      await _asset!.setMorphAnimationData(
        headMorphData,
        targetMeshNames: ["Head_Mod"],
      );
      debugPrint('✅ Head_Mod设置完成');

      debugPrint('🎉 分离方法完成：Head_Mod + Mouth_Mod应该同时工作');
      setState(() => _status = '🎯 分离方法：双实体同步');

      // 🔍 验证Mouth_Mod是否响应 - 尝试手动设置权重
      await Future.delayed(Duration(milliseconds: 500));
      debugPrint('🔍 正在验证Mouth_Mod是否响应T.jawOpen...');

      // 🎯 直接测试：手动设置T.jawOpen权重
      debugPrint('🧪 尝试直接设置T.jawOpen权重到1.0...');
      final childEntities = await _asset!.getChildEntities();

      for (int i = 0; i < childEntities.length; i++) {
        final entity = childEntities[i];
        final entityName = FilamentApp.instance!.getNameForEntity(entity);

        if (entityName == "Mouth_Mod") {
          debugPrint('🎯 找到Mouth_Mod实体，检查实际的morph targets...');

          // 🔍 首先检查Mouth_Mod实际有哪些morph targets
          final actualMorphTargets = await _asset!.getMorphTargetNames(
            entity: entity,
          );
          debugPrint('📋 Mouth_Mod实际的morph targets: $actualMorphTargets');

          if (actualMorphTargets.isNotEmpty) {
            debugPrint('🧪 极限测试T.jawOpen动作（多次设置）');
            try {
              // 🎯 极限测试：多次大幅度变化
              for (int test = 0; test < 3; test++) {
                debugPrint('🔥 第${test + 1}轮测试：T.jawOpen 1.0');
                await _asset!.setMorphTargetWeights(entity, [1.0]);
                setState(() => _status = '🔥 T.jawOpen权重1.0 (第${test + 1}轮)');
                await Future.delayed(Duration(milliseconds: 1500));

                debugPrint('🔥 第${test + 1}轮测试：T.jawOpen 0.0');
                await _asset!.setMorphTargetWeights(entity, [0.0]);
                setState(() => _status = '🔥 T.jawOpen权重0.0 (第${test + 1}轮)');
                await Future.delayed(Duration(milliseconds: 1500));
              }

              debugPrint('🎯 极限测试完成：如果还是看不到牙齿动作，说明T.jawOpen在thermion中效果极微弱');

              // 如果有多个morph targets，也测试一下
              if (actualMorphTargets.length > 1) {
                debugPrint(
                  '📋 Mouth_Mod总共有${actualMorphTargets.length}个morph targets',
                );
                for (int j = 0; j < actualMorphTargets.length; j++) {
                  debugPrint('   [$j]: ${actualMorphTargets[j]}');
                }
              }
            } catch (e) {
              debugPrint('❌ 设置Mouth_Mod权重失败: $e');
            }
          } else {
            debugPrint('❌ Mouth_Mod没有任何morph targets！');
          }
          break;
        }
      }
    } catch (e) {
      debugPrint('❌ 分离方法失败: $e');
      setState(() => _status = '❌ 分离方法失败: $e');
    }
  }

  /// 🚀 核心革命性方法：将bs.json数据直接分配给动画轨道
  /// 这是技术突破的关键：统一身体动画和面部动画管线
  Future<void> _assignBsJsonToAnimationTrack() async {
    if (_asset == null || _blendshapeData == null) {
      debugPrint('❌ 革命性方案失败：_asset或_blendshapeData为空');
      return;
    }

    // 🔍 调试：检查可用的子实体和实体名称
    try {
      final childEntities = await _asset!.getChildEntities();
      if (kDebugMode) {
        debugPrint('🔍 模型子实体数量: ${childEntities.length}');

        // 🎯 只检查关键实体：1, 3, 12, 13
        final keyEntities = [1, 3, 12, 13];
        for (final entityIndex in keyEntities) {
          if (entityIndex < childEntities.length) {
            try {
              final morphTargets = await _asset!.getMorphTargetNames(
                entity: childEntities[entityIndex],
              );
              debugPrint(
                '🔍 实体 $entityIndex: ${morphTargets.length} 个 morph targets',
              );

              if (morphTargets.isNotEmpty) {
                debugPrint(
                  '🔍 实体 $entityIndex 的前10个 morph targets: ${morphTargets.take(10).join(', ')}',
                );

                // 🎯 特别检查关键blendshape
                final hasFJawOpen = morphTargets.contains('F.jawOpen');
                final hasTJawOpen = morphTargets.contains('T.jawOpen');
                final hasFEyeBlink = morphTargets.contains('F.eyeBlinkLeft');

                debugPrint('🔍 实体 $entityIndex 关键blendshape:');
                debugPrint('   F.jawOpen: $hasFJawOpen');
                debugPrint('   T.jawOpen: $hasTJawOpen');
                debugPrint('   F.eyeBlinkLeft: $hasFEyeBlink');

                // 🎯 标识实体用途
                if (entityIndex == 1) {
                  debugPrint('🎯 实体1: 映射实体');
                } else if (entityIndex == 12 || entityIndex == 13) {
                  debugPrint('🎯 实体$entityIndex: 口型驱动实体，将接收MorphAnimationData');
                }
              }
            } catch (e) {
              debugPrint('🔍 实体 $entityIndex 无法获取 morph targets: $e');
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('🔍 检查子实体失败: $e');
    }

    try {
      setState(() => _status = '🚀 分配bs.json到动画轨道...');

      if (kDebugMode) {
        debugPrint('🎯 开始革命性方案：将bs.json直接分配给动画轨道');
        debugPrint('   总帧数: ${_blendshapeData!.length}');
        debugPrint('   每帧权重数: ${_blendshapeData!.first.length}');
      }

      // 1. 🎯 获取实体12的实际blendshape名称（精确映射）
      final childEntities = await _asset!.getChildEntities();
      List<String> entity12MorphTargets = [];

      if (childEntities.length > 12) {
        try {
          entity12MorphTargets = await _asset!.getMorphTargetNames(
            entity: childEntities[12],
          );
          if (kDebugMode) {
            debugPrint('🎯 实体12实际blendshape名称:');
            debugPrint('   总数: ${entity12MorphTargets.length}');
            debugPrint('   前10个: ${entity12MorphTargets.take(10).join(', ')}');
          }
        } catch (e) {
          if (kDebugMode) debugPrint('❌ 获取实体12 blendshape失败: $e');
        }
      }

      // 2. 🎯 bs.json标准ARKit顺序（55个权重）
      final bsJsonBlendshapeNames = [
        "eyeBlinkLeft",
        "eyeLookDownLeft",
        "eyeLookInLeft",
        "eyeLookOutLeft",
        "eyeLookUpLeft",
        "eyeSquintLeft",
        "eyeWideLeft",
        "eyeBlinkRight",
        "eyeLookDownRight",
        "eyeLookInRight",
        "eyeLookOutRight",
        "eyeLookUpRight",
        "eyeSquintRight",
        "eyeWideRight",
        "jawForward",
        "jawLeft",
        "jawRight",
        "jawOpen",
        "mouthClose",
        "mouthFunnel",
        "mouthPucker",
        "mouthLeft",
        "mouthRight",
        "mouthSmileLeft",
        "mouthSmileRight",
        "mouthFrownLeft",
        "mouthFrownRight",
        "mouthDimpleLeft",
        "mouthDimpleRight",
        "mouthStretchLeft",
        "mouthStretchRight",
        "mouthRollLower",
        "mouthRollUpper",
        "mouthShrugLower",
        "mouthShrugUpper",
        "mouthPressLeft",
        "mouthPressRight",
        "mouthLowerDownLeft",
        "mouthLowerDownRight",
        "mouthUpperUpLeft",
        "mouthUpperUpRight",
        "browDownLeft",
        "browDownRight",
        "browInnerUp",
        "browOuterUpLeft",
        "browOuterUpRight",
        "cheekPuff",
        "cheekSquintLeft",
        "cheekSquintRight",
        "noseSneerLeft",
        "noseSneerRight",
        "tongueOut",
        "unused52",
        "unused53",
        "unused54",
      ];

      // 3. 🎯 创建精确映射：实体12 blendshape -> bs.json索引
      final List<int> bsToEntity12Mapping = [];
      final List<String> mappedMorphTargetNames = [];

      for (int i = 0; i < entity12MorphTargets.length; i++) {
        final entity12Name = entity12MorphTargets[i];
        int bsJsonIndex = -1;

        // 尝试匹配F.前缀的名称
        if (entity12Name.startsWith('F.')) {
          final baseName = entity12Name.substring(2); // 移除F.前缀
          bsJsonIndex = bsJsonBlendshapeNames.indexOf(baseName);
        }

        if (bsJsonIndex != -1) {
          bsToEntity12Mapping.add(bsJsonIndex);
          mappedMorphTargetNames.add(entity12Name);
          if (kDebugMode && i < 5) {
            // 只打印前5个避免日志过长
            debugPrint(
              '   映射: bs.json[$bsJsonIndex](${bsJsonBlendshapeNames[bsJsonIndex]}) -> 实体12[$i]($entity12Name)',
            );
          }
        } else {
          if (kDebugMode) {
            debugPrint('   ⚠️ 未找到映射: 实体12[$i]($entity12Name)');
          }
        }
      }

      if (kDebugMode) {
        debugPrint('🎯 精确映射结果:');
        debugPrint('   bs.json总数: ${bsJsonBlendshapeNames.length}');
        debugPrint('   实体12总数: ${entity12MorphTargets.length}');
        debugPrint('   成功映射: ${bsToEntity12Mapping.length}');
        debugPrint(
          '   F.jawOpen映射: bs.json[${bsToEntity12Mapping.contains(17) ? 17 : '未找到'}] -> 实体12',
        );
      }

      // 4. 🎯 根据映射创建精确的数据（只包含实际存在的blendshape）
      final totalFrames = _blendshapeData!.length;
      final mappedWeightsPerFrame = bsToEntity12Mapping.length;
      final mappedFlatData = Float32List(totalFrames * mappedWeightsPerFrame);

      for (int frame = 0; frame < totalFrames; frame++) {
        final frameWeights = _blendshapeData![frame];
        final baseIndex = frame * mappedWeightsPerFrame;

        for (int i = 0; i < bsToEntity12Mapping.length; i++) {
          final bsJsonIndex = bsToEntity12Mapping[i];
          if (bsJsonIndex < frameWeights.length) {
            mappedFlatData[baseIndex + i] = frameWeights[bsJsonIndex];
          }
        }
      }

      if (kDebugMode) {
        debugPrint('🎯 目标实体分析:');
        debugPrint('   实体12: 52个F前缀blendshape (主要面部控制)');
        debugPrint('   实体13: 1个T.jawOpen (下巴专用控制)');
        debugPrint(
          '   bs.json: ${_blendshapeData!.length}帧 × ${_blendshapeData!.first.length}权重',
        );
      }

      // 3. 🎯 简化测试：使用固定1秒单帧
      // final audioDurationMs = 59160.0; // 音频时长毫秒
      // final frameLengthMs = audioDurationMs / totalFrames; // 约33.3ms每帧

      // 🎯 优化方案：分别创建专属数据，单次调用
      if (kDebugMode) {
        debugPrint('🎯 开始优化分离策略...');
        debugPrint('   为Head_Mod创建F前缀专属数据');
        debugPrint('   为Mouth_Mod创建T.jawOpen专属数据');
        debugPrint('   单次调用setMorphAnimationData，让thermion分别处理');
      }

      // 🎯 恢复动态多帧数据：牙齿张开需要动态效果才能看到
      debugPrint('🎯 使用完整bs.json数据，保持简化的API调用');

      // 计算30FPS帧时长
      final audioDurationMs = 59160.0; // 音频时长毫秒
      final frameLengthMs = audioDurationMs / totalFrames; // 约33.3ms每帧

      final headMorphData = MorphAnimationData(
        mappedFlatData, // 完整的F前缀数据
        mappedMorphTargetNames,
        frameLengthInMs: frameLengthMs,
      );

      // 为Mouth_Mod创建T.jawOpen动态数据
      final jawOnlyData = Float32List(totalFrames);
      for (int frame = 0; frame < totalFrames; frame++) {
        final frameWeights = _blendshapeData![frame];
        if (frameWeights.length > 17) {
          // 适度增强权重，避免过度放大
          jawOnlyData[frame] = frameWeights[17] * 2.0; // 2倍增强
          if (jawOnlyData[frame] > 1.0) {
            jawOnlyData[frame] = 1.0;
          }
        }
      }

      final mouthMorphData = MorphAnimationData(
        jawOnlyData, // 完整的T.jawOpen动态数据
        ["T.jawOpen"],
        frameLengthInMs: frameLengthMs,
      );

      // 🎯 步骤3：创建包含所有数据的统一结构（用于统一调用）
      // 注意：这里创建一个包含所有morph targets的列表，让thermion自动分配
      final allMorphTargetNames = <String>[];
      allMorphTargetNames.addAll(mappedMorphTargetNames); // F前缀
      allMorphTargetNames.add("T.jawOpen"); // T.jawOpen

      // 创建包含所有数据的扁平数组
      final allWeightsPerFrame = mappedWeightsPerFrame + 1;
      final allFlatData = Float32List(totalFrames * allWeightsPerFrame);

      for (int frame = 0; frame < totalFrames; frame++) {
        final frameWeights = _blendshapeData![frame];
        final baseIndex = frame * allWeightsPerFrame;

        // 复制F前缀数据
        for (int i = 0; i < bsToEntity12Mapping.length; i++) {
          final bsJsonIndex = bsToEntity12Mapping[i];
          if (bsJsonIndex < frameWeights.length) {
            allFlatData[baseIndex + i] = frameWeights[bsJsonIndex];
          }
        }

        // 添加增强的T.jawOpen数据（3倍增强）
        if (frameWeights.length > 17) {
          allFlatData[baseIndex + mappedWeightsPerFrame] =
              frameWeights[17] * 3.0;
          if (allFlatData[baseIndex + mappedWeightsPerFrame] > 1.0) {
            allFlatData[baseIndex + mappedWeightsPerFrame] = 1.0;
          }
        }
      }

      // unifiedMorphData已移除，直接使用分离的headMorphData和mouthMorphData

      // 查找F.jawOpen在映射中的位置（移到外部，供后面使用）
      int fJawOpenIndex = -1;
      for (int i = 0; i < mappedMorphTargetNames.length; i++) {
        if (mappedMorphTargetNames[i] == 'F.jawOpen') {
          fJawOpenIndex = i;
          break;
        }
      }

      if (kDebugMode) {
        debugPrint('🎯 动态数据创建完成:');
        debugPrint('   Head_Mod: ${mappedMorphTargetNames.length}个F前缀');
        debugPrint('   Mouth_Mod: 1个T.jawOpen（2倍增强）');

        // 验证动态数据
        final jawRange =
            '${jawOnlyData.reduce((a, b) => a < b ? a : b).toStringAsFixed(4)} - ${jawOnlyData.reduce((a, b) => a > b ? a : b).toStringAsFixed(4)}';
        final jawNonZero = jawOnlyData.where((v) => v > 0.001).length;
        debugPrint('   T.jawOpen范围: $jawRange');
        debugPrint('   T.jawOpen非零帧: $jawNonZero/$totalFrames');
        debugPrint(
          '   帧率: 30 FPS ($totalFrames帧/${(audioDurationMs / 1000).toStringAsFixed(1)}秒)',
        );

        debugPrint('   统一数据: ${allMorphTargetNames.length}个blendshape');
        debugPrint('   F.jawOpen位置: 索引$fJawOpenIndex');
        debugPrint('   T.jawOpen位置: 索引$mappedWeightsPerFrame');
      }

      // 🎯 步骤4：添加MorphAnimationComponent和激活动画组件
      String? actualHeadMeshName;
      String? actualMouthMeshName;
      try {
        debugPrint('🎯 添加MorphAnimationComponent到口型控制实体...');

        final childEntities = await _asset!.getChildEntities();
        ThermionEntity? headModEntity;
        ThermionEntity? mouthModEntity;

        // 🔍 查找实际的实体12和实体13对应的mesh名称
        for (int i = 0; i < childEntities.length; i++) {
          final entity = childEntities[i];
          final entityName = FilamentApp.instance!.getNameForEntity(entity);

          try {
            final morphTargets = await _asset!.getMorphTargetNames(
              entity: entity,
            );

            // 查找包含F.jawOpen的实体（实体12）
            if (morphTargets.contains('F.jawOpen')) {
              headModEntity = entity;
              actualHeadMeshName = entityName;
              debugPrint('🎯 找到F.jawOpen实体: "$entityName"');
            }

            // 查找包含T.jawOpen的实体（实体13）
            if (morphTargets.contains('T.jawOpen')) {
              mouthModEntity = entity;
              actualMouthMeshName = entityName;
              debugPrint('🎯 找到T.jawOpen实体: "$entityName"');
            }
          } catch (e) {
            // 忽略没有morph targets的实体
          }
        }

        if (headModEntity != null && mouthModEntity != null) {
          final ffiAsset = _asset! as dynamic;
          final animationManager = ffiAsset.animationManager;

          AnimationManager_addMorphAnimationComponent(
            animationManager,
            headModEntity,
          );
          AnimationManager_addMorphAnimationComponent(
            animationManager,
            mouthModEntity,
          );
          debugPrint('✅ MorphAnimationComponent已添加到两个实体');
          debugPrint('   F.jawOpen实体mesh名称: "$actualHeadMeshName"');
          debugPrint('   T.jawOpen实体mesh名称: "$actualMouthMeshName"');

          // 🚀 关键：为每个实体单独激活动画系统
          debugPrint('🎯 尝试为每个mesh单独激活动画组件...');

          // 方法1：先为asset全局激活
          await _asset!.addAnimationComponent();
          debugPrint('✅ asset级别addAnimationComponent()已调用');

          // 方法2：验证每个实体的animation component状态
          debugPrint('🔍 验证各实体的animation component状态...');

          // 🎯 尝试仅为Mouth_Mod设置动画，测试其独立工作能力
          debugPrint('🚧 测试：仅激活Mouth_Mod动画组件...');
          try {
            // 为Mouth_Mod创建简化测试数据（固定权重1.0）
            final testMouthData = MorphAnimationData(
              Float32List.fromList([1.0]), // 单帧固定权重
              ["T.jawOpen"],
              frameLengthInMs: 1000.0, // 1秒持续
            );

            debugPrint('🎯 仅为Mouth_Mod设置动画数据测试...');
            await _asset!.setMorphAnimationData(
              testMouthData,
              targetMeshNames: [actualMouthMeshName!],
            );
            debugPrint('✅ Mouth_Mod独立动画测试数据已设置');

            // 给thermion一点时间处理
            await Future.delayed(Duration(milliseconds: 100));

            // 验证T.jawOpen是否可以手动设置权重
            debugPrint('🔍 验证T.jawOpen手动权重设置...');
            try {
              await _asset!.setMorphTargetWeights(mouthModEntity, [0.8]);
              debugPrint('✅ T.jawOpen手动权重0.8已设置');

              await Future.delayed(Duration(milliseconds: 200));

              await _asset!.setMorphTargetWeights(mouthModEntity, [0.0]);
              debugPrint('✅ T.jawOpen手动权重0.0已设置');
            } catch (e) {
              debugPrint('❌ T.jawOpen手动权重设置失败: $e');
            }

            debugPrint('🔍 Mouth_Mod独立测试完成，检查牙齿是否移动...');
          } catch (e) {
            debugPrint('❌ Mouth_Mod独立测试失败: $e');
          }
        }
      } catch (e) {
        debugPrint('❌ MorphAnimationComponent设置失败: $e');
      }

      // 🎯 步骤5：直接使用策略2（分别设置Head_Mod和Mouth_Mod）
      // 跳过策略1，因为XiaoMeng_Body没有morph targets，全局分配会失败
      bool success = false;
      String strategy = "";

      // 直接使用分离设置策略（使用动态获取的mesh名称）
      try {
        if (actualHeadMeshName != null && actualMouthMeshName != null) {
          if (kDebugMode) debugPrint('🎯 设置F.jawOpen实体（$actualHeadMeshName）');
          await _asset!.setMorphAnimationData(
            headMorphData,
            targetMeshNames: [actualHeadMeshName],
          );

          // 等待一小段时间确保第一次设置完成
          await Future.delayed(const Duration(milliseconds: 50));

          // 然后为T.jawOpen实体设置数据
          if (kDebugMode) debugPrint('🎯 设置T.jawOpen实体（$actualMouthMeshName）');
          await _asset!.setMorphAnimationData(
            mouthMorphData,
            targetMeshNames: [actualMouthMeshName],
          );
        } else {
          throw Exception('无法找到F.jawOpen或T.jawOpen对应的实体mesh名称');
        }

        success = true;
        strategy = "分离设置$actualHeadMeshName+$actualMouthMeshName";
        if (kDebugMode) debugPrint('✅ morph动画数据设置成功：使用实际mesh名称');
      } catch (e) {
        if (kDebugMode) debugPrint('❌ morph动画数据设置失败: $e');
      }

      // 🎯 步骤6：验证调用结果
      if (kDebugMode) {
        debugPrint('🎯 调用结果:');
        debugPrint('   成功: $success');
        debugPrint('   策略: $strategy');

        if (success) {
          debugPrint('🎉 动态morph动画已建立:');
          debugPrint('   使用策略: $strategy');
          debugPrint('   模式: 完整bs.json数据');
          debugPrint('   T.jawOpen: 2倍增强，动态播放');
          debugPrint('   预期效果: Head_Mod张嘴 + Mouth_Mod牙齿协调动作');

          // 🎯 关键：调用render()激活morph动画（参考thermion测试代码）
          try {
            debugPrint('🎯 调用viewer.render()激活morph动画...');
            await _viewer!.render();
            debugPrint('✅ render调用完成，morph动画应已激活');
          } catch (e) {
            debugPrint('❌ render调用失败: $e');
          }

          // 🔧 通过setState触发widget重建，间接触发渲染
          setState(() => _status = '✅ morph动画轨道已设置，等待激活...');
        } else {
          debugPrint('❌ 所有策略都失败，需要进一步诊断');
        }
      }

      // 5. T.jawOpen已在上面的精确分配中处理

      if (kDebugMode) {
        debugPrint('🎯 革命性双实体方案完成！');
        debugPrint(
          '   实体12: F前缀blendshapes ($mappedWeightsPerFrame个) 包含F.jawOpen',
        );
        debugPrint('   实体13: T.jawOpen专用 (bs.json第17个数据)');
        debugPrint('   双重jawOpen: F.jawOpen + T.jawOpen 同步驱动');
        debugPrint('   动画帧率: 30 FPS (${_blendshapeData!.length}帧/59.16秒)');
        debugPrint('   数据来源: 都来自bs.json第17个索引');
      }

      setState(() => _status = '🚀 革命性动画轨道已配置');

      // 🔍 添加Mouth_Mod专项验证
      await _verifyMouthModSetup();

      // 🎯 显式启动morph动画播放
      await _startMorphAnimationPlayback();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 革命性方案失败: $e');
      }
      setState(() => _status = '❌ 动画轨道配置失败: $e');
    }
  }

  /// 🔍 专项验证Mouth_Mod设置状态
  Future<void> _verifyMouthModSetup() async {
    if (_asset == null) return;

    try {
      if (kDebugMode) debugPrint('🔍 开始Mouth_Mod专项验证...');

      final childEntities = await _asset!.getChildEntities();

      // 查找Mouth_Mod实体
      ThermionEntity? mouthModEntity;
      for (int i = 0; i < childEntities.length; i++) {
        final entityName = FilamentApp.instance!.getNameForEntity(
          childEntities[i],
        );
        if (entityName == "Mouth_Mod") {
          mouthModEntity = childEntities[i];
          break;
        }
      }

      if (mouthModEntity != null) {
        if (kDebugMode) debugPrint('✅ 找到Mouth_Mod实体');

        // 检查Mouth_Mod的morph targets
        try {
          final morphTargets = await _asset!.getMorphTargetNames(
            entity: mouthModEntity,
          );
          if (kDebugMode) {
            debugPrint('🔍 Mouth_Mod morph targets: ${morphTargets.length}个');
            debugPrint('   内容: ${morphTargets.join(', ')}');
          }

          // 检查是否包含T.jawOpen
          final hasTJawOpen = morphTargets.contains('T.jawOpen');
          if (kDebugMode) {
            debugPrint('🔍 Mouth_Mod支持T.jawOpen: $hasTJawOpen');
          }

          if (hasTJawOpen) {
            // 测试手动设置T.jawOpen权重
            if (kDebugMode) debugPrint('🧪 测试手动设置T.jawOpen权重...');

            // 设置一个明显的权重值进行测试
            try {
              await _asset!.setMorphTargetWeights(mouthModEntity, [
                0.8,
              ]); // 80%张开
              if (kDebugMode) debugPrint('✅ 手动设置T.jawOpen权重成功');

              // 等待2秒让用户看到效果
              await Future.delayed(const Duration(seconds: 2));

              // 重置权重
              await _asset!.setMorphTargetWeights(mouthModEntity, [0.0]);
              if (kDebugMode) debugPrint('✅ 重置T.jawOpen权重完成');
            } catch (e) {
              if (kDebugMode) debugPrint('❌ 手动设置T.jawOpen权重失败: $e');
            }
          } else {
            if (kDebugMode) debugPrint('❌ Mouth_Mod不包含T.jawOpen！');
          }
        } catch (e) {
          if (kDebugMode) debugPrint('❌ 获取Mouth_Mod morph targets失败: $e');
        }
      } else {
        if (kDebugMode) debugPrint('❌ 未找到Mouth_Mod实体！');

        // 列出所有实体名称以帮助调试
        if (kDebugMode) {
          debugPrint('🔍 可用实体列表:');
          for (int i = 0; i < childEntities.length; i++) {
            try {
              final entityName = FilamentApp.instance!.getNameForEntity(
                childEntities[i],
              );
              debugPrint('   实体$i: $entityName');
            } catch (_) {
              debugPrint('   实体$i: 无法获取名称');
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Mouth_Mod验证失败: $e');
    }
  }

  /// 🎯 显式启动morph动画播放
  Future<void> _startMorphAnimationPlayback() async {
    if (_asset == null) return;

    try {
      if (kDebugMode) debugPrint('🎯 开始启动morph动画播放...');

      // 尝试查找是否有morph动画播放的API
      // 根据thermion文档，setMorphAnimationData后应该自动播放
      // 但我们可以尝试一些可能的启动方法

      final childEntities = await _asset!.getChildEntities();

      // 查找Head_Mod和Mouth_Mod实体
      ThermionEntity? headModEntity;
      ThermionEntity? mouthModEntity;

      for (final entity in childEntities) {
        final entityName = FilamentApp.instance!.getNameForEntity(entity);
        if (entityName == "Head_Mod") {
          headModEntity = entity;
        } else if (entityName == "Mouth_Mod") {
          mouthModEntity = entity;
        }
      }

      if (headModEntity != null && mouthModEntity != null) {
        if (kDebugMode) {
          debugPrint('✅ 找到Head_Mod和Mouth_Mod实体');
          debugPrint('🎯 MorphAnimationComponent已在数据设置阶段添加，无需重复添加');

          // 测试Mouth_Mod是否响应权重设置
          try {
            debugPrint('🧪 测试Mouth_Mod响应性...');

            // 🔥 极限测试：设置T.jawOpen=1.0观察最大效果
            debugPrint('🔥 极限测试：设置T.jawOpen=1.0');
            await _asset!.setMorphTargetWeights(mouthModEntity, [1.0]);
            await Future.delayed(const Duration(milliseconds: 1500)); // 延长观察时间

            // 设置一个中等权重测试
            debugPrint('🧪 中等测试：设置T.jawOpen=0.5');
            await _asset!.setMorphTargetWeights(mouthModEntity, [0.5]);
            await Future.delayed(const Duration(milliseconds: 1000));

            // 重置权重
            debugPrint('🔄 重置T.jawOpen=0.0');
            await _asset!.setMorphTargetWeights(mouthModEntity, [0.0]);

            debugPrint('✅ Mouth_Mod极限测试完成');
          } catch (e) {
            if (kDebugMode) debugPrint('❌ Mouth_Mod权重设置失败: $e');
          }
        }
      } else {
        if (kDebugMode) debugPrint('❌ 未找到Head_Mod或Mouth_Mod实体');
      }

      if (kDebugMode) debugPrint('✅ morph动画播放检查完成');
    } catch (e) {
      if (kDebugMode) debugPrint('❌ morph动画播放启动失败: $e');
    }
  }

  // 🎭 安全的统一动画播放 - 避免几何体冲突
  Future<void> _playUnifiedAnimationSafe() async {
    if (_asset == null) return;

    try {
      setState(() => _status = '🎭 安全启动统一动画系统...');

      if (kDebugMode) {
        debugPrint('🎭 安全动画流程：先停止→设置morph→启动身体动画');
      }

      // 🛑 步骤1：先停止所有现有动画，避免冲突
      try {
        for (int i = 0; i < _animations.length; i++) {
          await _asset!.stopGltfAnimation(i);
        }
        if (kDebugMode) debugPrint('✅ 所有身体动画已停止');
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ 停止动画失败: $e');
      }

      // 🔄 步骤2：检查是否需要清除现有morph数据
      // 如果之前已经设置了正确的数据，就不要清除
      if (kDebugMode) debugPrint('🎯 跳过清除morph数据，保持已设置的动画轨道');

      // 🎯 步骤3：设置新的morph数据（使用我们的分离分配策略）
      if (!_isMorphAnimationConfigured) {
        await _assignBsJsonToAnimationTrack();
        _isMorphAnimationConfigured = true;
        if (kDebugMode) debugPrint('✅ morph动画轨道已配置，后续播放将重用');
      } else {
        if (kDebugMode) debugPrint('🎯 重用已配置的morph动画轨道');
      }

      // ⏱️ 步骤4：等待一帧，确保morph数据设置完成
      await Future.delayed(const Duration(milliseconds: 50));

      // 🎭 步骤5：暂时注释掉身体动画，专注测试口型
      // if (_selectedTalkAnimation >= 0 &&
      //     _selectedTalkAnimation < _animations.length) {
      //   await _asset!.playGltfAnimation(_selectedTalkAnimation, loop: true);
      //   _isPlaying = true;
      //   _currentAnimationIndex = _selectedTalkAnimation;

      //   if (kDebugMode) {
      //     debugPrint('✅ 身体动画已安全启动：${_animations[_selectedTalkAnimation]}');
      //     debugPrint('   morph数据已预先设置，避免冲突');
      //   }
      // }

      if (kDebugMode) {
        debugPrint('🎯 身体动画已暂时禁用，专注测试口型动画');
      }

      setState(() => _status = '🎯 纯口型动画测试模式');

      if (kDebugMode) {
        debugPrint('🎉 纯口型测试模式已启动！');
        debugPrint('   ✓ 身体动画：已禁用');
        debugPrint('   ✓ 面部表情：由bs.json动画轨道控制');
        debugPrint('   ✓ 专注测试：F.jawOpen + T.jawOpen 双重驱动');
        debugPrint('   ✓ 预期效果：清晰的嘴部开合动作');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 安全统一动画播放失败: $e');
      }
      setState(() => _status = '❌ 安全统一动画失败: $e');
    }
  }

  // ===== 动画管理系统 =====

  // ===== 简化测试：移除复杂的动画更新循环 =====

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

      // 🎭 启动统一动画系统（修复版：先停止动画再设置morph数据）
      await _playUnifiedAnimationSafe();

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

      // 🎯 暂时移除可能导致崩溃的更新循环，让Thermion自动处理
      // _startAnimationUpdateLoop();

      // 🎯 触发widget重建，确保morph动画与音频同步启动
      setState(() => _status = '🎵 音频播放中，口型同步激活...');

      if (kDebugMode) debugPrint('✅ 音频播放已启动，morph动画应自动同步');

      // 🎯 分离分配策略已完成，无需额外测试

      if (kDebugMode) {
        debugPrint('✅ 纯口型同步测试已启动！');
        debugPrint('   🎭 身体动画：已禁用（纯口型测试模式）');
        debugPrint('   👄 面部动画：由bs.json轨道驱动');
        debugPrint('   🎵 音频播放：已开始');
        debugPrint('   🎯 测试重点：F.jawOpen + T.jawOpen 双重驱动');
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

      // 🛑 简化测试：无需手动停止动画更新循环

      // 停止音频
      await _audioPlayer.stop();

      // 取消监听
      _positionSubscription?.cancel();
      _completeSubscription?.cancel();

      // 🔄 暂时注释清除morph动画轨道数据，保持Mouth_Mod动画状态
      // if (_asset != null) {
      //   final childEntities = await _asset!.getChildEntities();
      //   for (int i = 0; i < childEntities.length; i++) {
      //     try {
      //       await _asset!.clearMorphAnimationData(childEntities[i]);
      //     } catch (_) {
      //       // 忽略清理错误
      //     }
      //   }
      // }

      if (kDebugMode) debugPrint('🎯 保持morph动画轨道数据，不清除Mouth_Mod状态');

      // 🎭 纯口型测试模式：不恢复idle动画
      // await _resumeIdleAnimation();
      if (kDebugMode) debugPrint('🎯 纯口型测试模式：保持静止状态');

      setState(() {}); // 更新 UI 状态

      if (kDebugMode) {
        debugPrint('⏹️ 纯口型测试系统已停止');
        debugPrint('   ✓ 音频播放已停止');
        debugPrint('   ✓ morph动画轨道已保持（未清除）');
        debugPrint('   ✓ 保持静止状态（身体动画已禁用）');
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

  // ===== 相机预设系统 =====

  /// 安全地应用相机预设，避免渲染状态冲突
  Future<void> _applyCameraPresetSafe(CameraPreset preset) async {
    if (_viewer == null) return;

    try {
      final camera = await _viewer!.getActiveCamera();

      // 根据预设直接设置相机位置，不暂停渲染
      Vector3 position;
      Vector3 target;

      switch (preset) {
        case CameraPreset.soloCloseUp:
          // 全身视角 - 调整为更合适的观看距离
          position = Vector3(0.0, 1.0, 2.5); // 从5.0拉近到3.2，更好的全身视角
          target = Vector3(0.0, 1.0, 0.0);
          break;
        case CameraPreset.halfBody:
          // 半身视角
          position = Vector3(0.0, 1.2, 3.0); // 调整为原始尺寸
          target = Vector3(0.0, 1.0, 0.0);
          break;
        case CameraPreset.bustCloseUp:
          // 脸部特写 - 专门观察口型变化
          position = Vector3(0.0, 1.6, 1.0); // 更近距离，专注口部区域
          target = Vector3(0.0, 1.5, 0.0); // 目标稍微向上，聚焦面部
          break;
        // case CameraPreset.thirdPersonOts:
        //   // 越肩第三人称视角
        //   position = Vector3(-3.0, 1.2, -4.0);
        //   target = Vector3(0.5, 0.8, 2.0);
        //   break;
      }

      // 直接设置相机位置，避免复杂的渲染状态管理
      await camera.lookAt(position, focus: target, up: Vector3(0, 1, 0));

      if (kDebugMode) {
        debugPrint('📷 相机预设已安全应用: $preset');
        debugPrint(
          '   位置: ${position.x.toStringAsFixed(2)}, ${position.y.toStringAsFixed(2)}, ${position.z.toStringAsFixed(2)}',
        );
        debugPrint(
          '   目标: ${target.x.toStringAsFixed(2)}, ${target.y.toStringAsFixed(2)}, ${target.z.toStringAsFixed(2)}',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 安全相机预设应用失败: $e');
      }
    }
  }

  // ===== UI构建系统 =====
  /// 构建主界面，包含3D视图和控制面板
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('写实数字人测试'),
        actions: [
          // 🎥 相机预设选择菜单
          PopupMenuButton<CameraPreset>(
            tooltip: '切换视角',
            icon: const Icon(Icons.camera_outdoor),
            onSelected: (preset) async {
              setState(() => _cameraPreset = preset);
              if (_viewer != null && _isInitialized) {
                try {
                  await _applyCameraPresetSafe(preset);
                  if (kDebugMode) debugPrint('✅ 相机预设已切换: $preset');
                } catch (e) {
                  if (kDebugMode) debugPrint('❌ 相机预设切换失败: $e');
                }
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: CameraPreset.soloCloseUp,
                child: Text('全身视角'),
              ),
              const PopupMenuItem(
                value: CameraPreset.halfBody,
                child: Text('半身视角'),
              ),
              const PopupMenuItem(
                value: CameraPreset.bustCloseUp,
                child: Text('脸部特写'),
              ),
            ],
          ),
        ],
      ),
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
                  onPressed: !_isLipSyncPlaying && _isBlendshapeLoaded
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
          const SizedBox(height: 8),

          // 添加实体检查按钮
          Center(
            child: ElevatedButton.icon(
              onPressed: _asset != null ? _checkAllEntities : null,
              icon: const Icon(Icons.info, size: 14),
              label: const Text('检查GLB实体信息', style: TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // 手动滑块控制两个实体的jawOpen - 更好的位置
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
              color: Colors.white,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '手动控制jawOpen',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),

                // Head_Mod F.jawOpen 滑块
                Row(
                  children: [
                    const SizedBox(
                      width: 85,
                      child: Text('Head_Mod:', style: TextStyle(fontSize: 13)),
                    ),
                    Expanded(
                      child: Slider(
                        value: _headJawOpenValue,
                        min: 0.0,
                        max: 1.0,
                        divisions: 100,
                        label: _headJawOpenValue.toStringAsFixed(2),
                        onChanged: _asset != null
                            ? (value) => _setHeadJawOpen(value)
                            : null,
                      ),
                    ),
                    SizedBox(
                      width: 45,
                      child: Text(
                        _headJawOpenValue.toStringAsFixed(2),
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),

                // Mouth_Mod T.jawOpen 滑块
                Row(
                  children: [
                    const SizedBox(
                      width: 85,
                      child: Text('Mouth_Mod:', style: TextStyle(fontSize: 13)),
                    ),
                    Expanded(
                      child: Slider(
                        value: _mouthJawOpenValue,
                        min: 0.0,
                        max: 1.0,
                        divisions: 100,
                        label: _mouthJawOpenValue.toStringAsFixed(2),
                        onChanged: _asset != null
                            ? (value) => _setMouthJawOpen(value)
                            : null,
                      ),
                    ),
                    SizedBox(
                      width: 45,
                      child: Text(
                        _mouthJawOpenValue.toStringAsFixed(2),
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

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
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButton<int>(
                        value: _selectedTalkAnimation,
                        isExpanded: true,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black87,
                        ),
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
                        onChanged: _isLipSyncPlaying
                            ? null
                            : (value) {
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

    // 🛑 简化测试：无需清理动画更新循环

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
