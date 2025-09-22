import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:thermion_flutter/thermion_flutter.dart';
import 'package:audioplayers/audioplayers.dart';

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

// 实体信息类
class EntityInfo {
  final int index;
  final int entityHandle;
  final List<String> morphTargets;
  final int score;

  EntityInfo({
    required this.index,
    required this.entityHandle,
    required this.morphTargets,
    required this.score,
  });

  @override
  String toString() {
    return 'Entity $index: ${morphTargets.length} targets (score: $score)';
  }
}

class SimpleThermionTest extends StatefulWidget {
  const SimpleThermionTest({super.key});

  @override
  State<SimpleThermionTest> createState() => _SimpleThermionTestState();
}

class _SimpleThermionTestState extends State<SimpleThermionTest>
    with WidgetsBindingObserver {
  ThermionViewer? _viewer;
  String _status = '初始化中...';
  DelegateInputHandler? _inputHandler;
  bool _isInitialized = false;
  bool _isDisposed = false;

  // 动画相关
  ThermionAsset? _asset;
  List<String> _animations = [];
  int _currentAnimationIndex = -1;
  int _idleAnimationIndex = -1; // idle动画索引
  bool _isPlaying = false;

  // 口型同步相关
  List<EntityInfo> _entities = [];
  int? _selectedMorphEntityIndex;

  // blendshape 数据
  List<List<double>>? _blendshapeData;
  bool _isBlendshapeLoaded = false;

  // 音频同步播放
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isLipSyncPlaying = false;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<void>? _completeSubscription;
  int _lastAppliedFrame = -1;

  // 权重优化参数
  static const double _weightAmplifier = 1.0; // 恢复原始权重，不放大
  List<double>? _previousWeights; // 用于平滑处理
  static const double _smoothingFactor = 0.3; // 平滑系数 (0-1)

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
      await Future.delayed(const Duration(milliseconds: 100));
      await _viewer!.setRendering(true);

      // 如果有 idle 动画，重新启动
      if (_isInitialized && _idleAnimationIndex != -1 && !_isLipSyncPlaying) {
        await _resumeIdleAnimation();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ 恢复渲染失败: $e');
    }
  }

  Future<void> _initializeSimpleViewer() async {
    try {
      setState(() => _status = '创建 Viewer...');

      _viewer = await ThermionFlutterPlugin.createViewer();

      setState(() => _status = '等待 Surface 准备...');
      await Future.delayed(const Duration(milliseconds: 300));

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
          intensity: 15600.0,
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
          color: 6400.0, // 暖白色温
          intensity: 75000.0, // 更新为 settings.json 的 sunlightIntensity
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

        // 如果有动画，默认选择第一个
        if (_animations.isNotEmpty) {
          _currentAnimationIndex = 0;
        }

        // 检测所有实体的 morph targets
        await _detectMorphEntities();

        // 加载 blendshape 数据
        await _loadBlendshapeData();

        // 🎭 自动播放idle动画
        // await _startIdleAnimation();

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

  // 直接获取实体12的 morph targets
  Future<void> _detectMorphEntities() async {
    if (_asset == null) return;

    try {
      setState(() => _status = '获取实体12的 Morph Targets...');

      final childEntities = await _asset!.getChildEntities();
      _entities.clear();

      if (kDebugMode) {
        debugPrint('🎯 直接获取实体12的 morph targets...');
      }

      // 确保实体12存在
      if (childEntities.length <= 12) {
        throw Exception('实体12不存在，总实体数: ${childEntities.length}');
      }

      // 直接获取实体12
      final entity12 = childEntities[12];
      final morphTargets = await _asset!.getMorphTargetNames(entity: entity12);

      if (morphTargets.isEmpty) {
        throw Exception('实体12没有 morph targets');
      }

      // 创建实体12信息
      final entity12Info = EntityInfo(
        index: 12,
        entityHandle: entity12,
        morphTargets: morphTargets,
        score: 1000, // 固定高分
      );

      _entities.add(entity12Info);
      _selectedMorphEntityIndex = 0; // 直接选择第一个（也是唯一一个）

      if (kDebugMode) {
        debugPrint('✅ 实体12: ${morphTargets.length} targets');

        // 🔍 打印实体12的完整morph target列表
        // debugPrint('📋 实体12完整morph target列表:');
        // for (int i = 0; i < morphTargets.length; i++) {
        //   debugPrint('   [$i] ${morphTargets[i]}');
        // }

        // 🆚 ARKit标准顺序对比
        // const arkitStandard = [
        //   "eyeBlinkLeft", "eyeLookDownLeft", "eyeLookInLeft", "eyeLookOutLeft", "eyeLookUpLeft",
        //   "eyeSquintLeft", "eyeWideLeft", "eyeBlinkRight", "eyeLookDownRight", "eyeLookInRight",
        //   "eyeLookOutRight", "eyeLookUpRight", "eyeSquintRight", "eyeWideRight", "jawForward",
        //   "jawLeft", "jawRight", "jawOpen", "mouthClose", "mouthFunnel",
        //   "mouthPucker", "mouthLeft", "mouthRight", "mouthSmileLeft", "mouthSmileRight",
        //   "mouthFrownLeft", "mouthFrownRight", "mouthDimpleLeft", "mouthDimpleRight", "mouthStretchLeft",
        //   "mouthStretchRight", "mouthRollLower", "mouthRollUpper", "mouthShrugLower", "mouthShrugUpper",
        //   "mouthPressLeft", "mouthPressRight", "mouthLowerDownLeft", "mouthLowerDownRight", "mouthUpperUpLeft",
        //   "mouthUpperUpRight", "browDownLeft", "browDownRight", "browInnerUp", "browOuterUpLeft",
        //   "browOuterUpRight", "cheekPuff", "cheekSquintLeft", "cheekSquintRight", "noseSneerLeft",
        //   "noseSneerRight", "tongueOut"
        // ];

        // debugPrint('🆚 与ARKit标准顺序对比:');
        // bool orderMatches = true;
        // for (int i = 0; i < morphTargets.length && i < arkitStandard.length; i++) {
        //   final entity12Name = morphTargets[i].replaceFirst('F.', ''); // 移除F.前缀
        //   final arkitName = arkitStandard[i];
        //   final matches = entity12Name.toLowerCase() == arkitName.toLowerCase();

        //   if (!matches) {
        //     orderMatches = false;
        //     debugPrint('   ❌ [$i] ${morphTargets[i]} ≠ $arkitName');
        //   } else {
        //     debugPrint('   ✅ [$i] ${morphTargets[i]} = $arkitName');
        //   }
        // }

        // if (orderMatches) {
        //   debugPrint('🎉 实体12的morph target顺序与ARKit标准完全匹配！');
        // } else {
        //   debugPrint('⚠️ 实体12的morph target顺序与ARKit标准不匹配，需要重新映射');
        // }

        // 检查是否包含关键的 jawOpen
        final jawOpenTarget = morphTargets.firstWhere(
          (name) => name.toLowerCase().contains('jawopen'),
          orElse: () => '',
        );
        if (jawOpenTarget.isNotEmpty) {
          final jawOpenIndex = morphTargets.indexOf(jawOpenTarget);
          debugPrint(
            '   🦷 找到 jawOpen target: $jawOpenTarget (索引: $jawOpenIndex)',
          );
          debugPrint('   🆚 ARKit标准中jawOpen索引: 17');
          if (jawOpenIndex == 17) {
            debugPrint('   ✅ jawOpen位置匹配ARKit标准');
          } else {
            debugPrint('   ❌ jawOpen位置不匹配，需要重新映射');
          }
        }

        debugPrint('🏆 直接使用实体12作为口型驱动实体');
      }

      setState(() => _status = '✅ 实体12准备就绪，${morphTargets.length}个targets');
    } catch (e) {
      setState(() => _status = '❌ 获取实体12失败: $e');
      if (kDebugMode) {
        debugPrint('❌ 获取实体12 morph targets 失败: $e');
      }
    }
  }

  // 加载 blendshape 数据
  Future<void> _loadBlendshapeData() async {
    try {
      setState(() => _status = '加载 blendshape 数据...');

      if (kDebugMode) {
        debugPrint('📊 开始加载 blendshape 数据...');
      }

      final jsonString = await rootBundle.loadString('assets/wav/bs_7.json');
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

  // 开始播放idle动画
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

  // 播放音频与 blendshape 同步
  Future<void> _playLipSync() async {
    if (!_isBlendshapeLoaded ||
        _blendshapeData == null ||
        _selectedMorphEntityIndex == null) {
      if (kDebugMode) {
        debugPrint(
          '⚠️ 数据未准备好：blendshape=${_isBlendshapeLoaded}, entity=${_selectedMorphEntityIndex}',
        );
      }
      return;
    }

    if (_isLipSyncPlaying) {
      await _stopLipSync();
    }

    final selectedEntity = _entities[_selectedMorphEntityIndex!];

    try {
      _isLipSyncPlaying = true;
      _lastAppliedFrame = -1;

      if (kDebugMode) {
        debugPrint('🎤 开始音频与 blendshape 同步播放...');
        debugPrint('   使用实体: ${selectedEntity.index}');
        debugPrint('   总帧数: ${_blendshapeData!.length}');
        debugPrint('   音频文件: wav/output.wav');
        debugPrint('   🔧 权重处理: 原始权重 (${_weightAmplifier}x)');
        debugPrint('   🌊 平滑系数: $_smoothingFactor');
      }

      // 停止所有动画，避免冲突（包括idle动画）
      for (int i = 0; i < _animations.length; i++) {
        try {
          await _asset!.stopGltfAnimation(i);
        } catch (_) {}
      }
      _isPlaying = false;

      // 重置所有权重
      await _resetAllMorphWeights();

      // 🔄 重置平滑处理状态
      _previousWeights = null;

      // 🔥 关键修复：禁用可能冲突的实体13
      await _disableEntity13();

      setState(() {}); // 更新 UI 状态

      // 设置音频播放完成监听
      _completeSubscription?.cancel();
      _completeSubscription = _audioPlayer.onPlayerComplete.listen((_) async {
        if (kDebugMode) {
          debugPrint('🎵 音频播放完成');
        }
        await _stopLipSync();
      });

      // 设置音频进度监听，驱动 blendshape 同步
      _positionSubscription?.cancel();
      _positionSubscription = _audioPlayer.onPositionChanged.listen((
        position,
      ) async {
        if (!_isLipSyncPlaying || _blendshapeData == null) return;

        // 计算当前应该播放的帧
        final positionMs = position.inMilliseconds;
        final totalDurationMs = 59160; // 根据日志，音频约59.16秒
        final frameRate =
            _blendshapeData!.length / (totalDurationMs / 1000.0); // 计算实际帧率

        final currentFrame = ((positionMs / 1000.0) * frameRate).round();
        final clampedFrame = currentFrame.clamp(0, _blendshapeData!.length - 1);

        // 避免重复应用同一帧
        if (clampedFrame != _lastAppliedFrame) {
          _lastAppliedFrame = clampedFrame;
          await _applyBlendshapeFrame(clampedFrame);

          // 移除进度日志，减少日志输出
        }
      });

      // 开始播放音频
      await _audioPlayer.play(AssetSource('wav/output.wav'));

      if (kDebugMode) {
        debugPrint('✅ 音频播放已开始，blendshape 同步已启动');
      }
    } catch (e) {
      _isLipSyncPlaying = false;
      setState(() {});
      if (kDebugMode) {
        debugPrint('❌ 音频同步播放失败: $e');
      }
    }
  }

  // 停止音频与 blendshape 同步
  Future<void> _stopLipSync() async {
    try {
      _isLipSyncPlaying = false;

      // 停止音频
      await _audioPlayer.stop();

      // 取消监听
      _positionSubscription?.cancel();
      _completeSubscription?.cancel();

      // 重置所有 morph 权重
      await _resetAllMorphWeights();

      // 🎭 恢复idle动画
      await _resumeIdleAnimation();

      setState(() {}); // 更新 UI 状态

      if (kDebugMode) {
        debugPrint('⏹️ 音频同步播放已停止');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 停止音频同步失败: $e');
      }
    }
  }

  // 应用单帧 blendshape 数据 - 优化版本（权重放大+平滑）
  Future<void> _applyBlendshapeFrame(int frameIndex) async {
    if (_blendshapeData == null ||
        _selectedMorphEntityIndex == null ||
        _asset == null)
      return;

    final selectedEntity = _entities[_selectedMorphEntityIndex!];
    final frameWeights = _blendshapeData![frameIndex];

    try {
      // 🚀 获取前52个权重
      var rawWeights = frameWeights.sublist(0, 52);

      // 📈 权重放大处理（保守2倍放大）
      var amplifiedWeights = rawWeights
          .map((w) => w * _weightAmplifier)
          .toList();

      // 🎯 权重限制（确保不超过1.0）
      var clampedWeights = amplifiedWeights
          .map((w) => w.clamp(0.0, 1.0))
          .toList();

      // 🌊 平滑处理（减少突变）
      List<double> finalWeights;
      if (_previousWeights != null &&
          _previousWeights!.length == clampedWeights.length) {
        // 线性插值平滑
        finalWeights = List.generate(clampedWeights.length, (i) {
          final current = clampedWeights[i];
          final previous = _previousWeights![i];
          return previous + (current - previous) * _smoothingFactor;
        });
      } else {
        // 第一帧直接使用
        finalWeights = clampedWeights;
      }

      // 💾 保存当前权重用于下一帧平滑
      _previousWeights = List.from(finalWeights);

      // 🎭 应用最终权重
      await _asset!.setMorphTargetWeights(
        selectedEntity.entityHandle,
        finalWeights,
      );

      // 📊 调试信息（每500帧打印一次）
      if (kDebugMode && frameIndex % 500 == 0) {
        final jawOpenRaw = rawWeights.length > 17 ? rawWeights[17] : 0.0;
        final jawOpenFinal = finalWeights.length > 17 ? finalWeights[17] : 0.0;
        debugPrint(
          '🦷 第$frameIndex帧 jawOpen: ${jawOpenRaw.toStringAsFixed(4)} → ${jawOpenFinal.toStringAsFixed(4)} (原始权重+平滑)',
        );
      }
    } catch (e) {
      // 静默处理帧应用错误，避免日志干扰
    }
  }

  // 禁用实体13，防止与实体12冲突
  Future<void> _disableEntity13() async {
    if (_asset == null) return;

    try {
      final childEntities = await _asset!.getChildEntities();

      // 确保实体13存在
      if (childEntities.length <= 13) {
        if (kDebugMode) debugPrint('⚠️ 实体13不存在，跳过禁用');
        return;
      }

      // 直接获取实体13
      final entity13 = childEntities[13];
      final morphTargets = await _asset!.getMorphTargetNames(entity: entity13);

      if (morphTargets.isNotEmpty) {
        // 将实体13的所有权重设为0
        final zeroWeights = List<double>.filled(morphTargets.length, 0.0);

        await _asset!.setMorphTargetWeights(entity13, zeroWeights);

        if (kDebugMode) {
          debugPrint('🚫 实体13已被禁用（${morphTargets.length}个targets），防止与实体12冲突');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ 禁用实体13失败: $e');
      }
    }
  }

  // 重置实体12的 morph 权重
  Future<void> _resetAllMorphWeights() async {
    if (_asset == null || _entities.isEmpty) return;

    try {
      // 只重置实体12
      final entity12Info = _entities.first; // 现在只有实体12
      final zeroWeights = List<double>.filled(
        entity12Info.morphTargets.length,
        0.0,
      );
      await _asset!.setMorphTargetWeights(
        entity12Info.entityHandle,
        zeroWeights,
      );

      if (kDebugMode) {
        debugPrint('🔄 已重置实体12的 morph 权重');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 重置实体12权重失败: $e');
      }
    }
  }

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
              minHeight: 80, // 最小高度，允许内容适应
              maxHeight: 100, // 最大高度，防止过度扩展
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

    return Column(
      mainAxisSize: MainAxisSize.min, // 使用最小空间
      mainAxisAlignment: MainAxisAlignment.center, // 居中对齐
      children: [
        // 播放控制按钮 - 紧凑布局
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Flexible(
              child: ElevatedButton.icon(
                onPressed:
                    !_isLipSyncPlaying && _selectedMorphEntityIndex != null
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
        // 🔧 修复：紧凑的状态指示器
        SizedBox(
          height: 18, // 稍微增加高度适应内容
          child: _isLipSyncPlaying
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
              : const SizedBox.shrink(), // 播放停止时显示空白但保持高度
        ),
      ],
    );
  }

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
