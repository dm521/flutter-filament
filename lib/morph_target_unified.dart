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
  runApp(const MorphTargetUnifiedApp());
}

class MorphTargetUnifiedApp extends StatelessWidget {
  const MorphTargetUnifiedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '口型同步播放',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MorphTargetUnified(),
    );
  }
}

/// 🎯 Morph Target 统一控制系统
///
/// 核心功能：
/// - 一个滑块同时控制 Head_Mod F.jawOpen 和 Mouth_Mod T.jawOpen
/// - 确保完全同步，无任何延迟
class MorphTargetUnified extends StatefulWidget {
  const MorphTargetUnified({super.key});

  @override
  State<MorphTargetUnified> createState() => _MorphTargetUnifiedState();
}

class _MorphTargetUnifiedState extends State<MorphTargetUnified>
    with WidgetsBindingObserver {
  // ===== 核心组件 =====
  ThermionViewer? _viewer;
  ThermionAsset? _asset;
  String _status = '初始化中...';
  bool _isInitialized = false;
  bool _isDisposed = false;

  // ===== 统一控制 =====

  // 实体引用
  ThermionEntity? _headEntity;
  int _headJawOpenIndex = -1;

  // ===== 音频和BS数据系统 =====
  List<List<double>>? _blendshapeData;
  bool _isBlendshapeLoaded = false;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isLipSyncPlaying = false;
  StreamSubscription<void>? _completeSubscription;

  // ===== 动画系统 =====
  final List<String> _animations = [];
  int _talk01AnimationIndex = -1;

  // ===== BS数据优化系数 - 修复面部形变 =====
  static const double _jawOpenEnhanceFactor = 1.5; // 降低张嘴幅度增强 (从2.2降到1.5)
  static const double _mouthShapeEnhanceFactor = 1.2; // 降低嘴型细节增强 (从1.8降到1.2)
  static const double _smoothingFactor = 0.2; // 增加平滑过渡系数 (从0.15增到0.2)
  static const double _maxMorphWeight = 0.8; // 最大morph权重限制，防止过度形变

  // 上一帧的权重值，用于平滑过渡
  List<double>? _previousFrameWeights;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeSystem();
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _completeSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (_viewer == null || _isDisposed) return;

    switch (state) {
      case AppLifecycleState.paused:
        _viewer?.setRendering(false);
        break;
      case AppLifecycleState.resumed:
        _resumeRendering();
        break;
      default:
        break;
    }
  }

  Future<void> _resumeRendering() async {
    if (_viewer == null || _isDisposed) return;
    try {
      await Future.delayed(Duration(milliseconds: 100));
      await _viewer!.setRendering(true);
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ 恢复渲染失败: $e');
    }
  }

  /// 初始化系统
  Future<void> _initializeSystem() async {
    try {
      setState(() => _status = '创建 Viewer...');
      _viewer = await ThermionFlutterPlugin.createViewer();

      setState(() => _status = '等待准备...');
      await Future.delayed(Duration(milliseconds: 300));

      await _enableRendering();
      await _setupEnvironment();
      await _loadModel();
      await _setupCamera();
      await _analyzeModel();
      await _loadAnimations();
      await _loadBlendshapeData();

      setState(() {
        _status = '✅ 系统准备就绪';
        _isInitialized = true;
      });
    } catch (e) {
      setState(() => _status = '❌ 初始化失败: $e');
      if (kDebugMode) debugPrint('❌ 初始化失败: $e');
    }
  }

  /// 启用渲染
  Future<void> _enableRendering() async {
    setState(() => _status = '启用渲染...');
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        await _viewer!.setRendering(true);
        return;
      } catch (e) {
        if (attempt < 2) {
          await Future.delayed(Duration(milliseconds: 200 * (attempt + 1)));
        }
      }
    }
    throw Exception('无法启用渲染');
  }

  /// 设置环境
  Future<void> _setupEnvironment() async {
    setState(() => _status = '设置环境...');

    try {
      // 加载环境
      await _viewer!.loadSkybox(
        "assets/environments/studio_small_env_skybox.ktx",
      );
      await _viewer!.loadIbl(
        "assets/environments/studio_small_env_ibl.ktx",
        intensity: 15600.0,
      );

      // 设置灯光
      await _viewer!.destroyLights();
      await _viewer!.addDirectLight(
        DirectLight.sun(
          color: 6400.0,
          intensity: 75000.0,
          castShadows: true,
          direction: Vector3(0.366695, -0.357967, -0.858717),
        ),
      );

      // 设置渲染效果
      await _viewer!.setPostProcessing(true);
      await _viewer!.setShadowsEnabled(true);
      await _viewer!.setToneMapping(ToneMapper.ACES);
      await _viewer!.setBloom(true, 0.348);
      await _viewer!.setAntiAliasing(true, true, true);

      // 设置相机曝光
      final camera = await _viewer!.getActiveCamera();
      await camera.setExposure(16.0, 1.0 / 125.0, 100.0);
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ 环境设置失败: $e');
    }
  }

  /// 加载模型
  Future<void> _loadModel() async {
    const modelPath = 'assets/models/xiaomeng_0923_3.glb';
    setState(() => _status = '加载模型...');

    try {
      _asset = await _viewer!.loadGltf(modelPath);
      if (kDebugMode) debugPrint('✅ 模型加载成功: $modelPath');
    } catch (e) {
      throw Exception('模型加载失败: $e');
    }
  }

  /// 设置相机
  Future<void> _setupCamera() async {
    setState(() => _status = '设置相机...');

    try {
      final camera = await _viewer!.getActiveCamera();
      await camera.lookAt(
        Vector3(0.0, 1.65, 0.6), // 面部特写位置
        focus: Vector3(0.0, 1.65, 0.0),
        up: Vector3(0.0, 1.0, 0.0),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ 相机设置失败: $e');
    }
  }

  /// 分析模型结构
  Future<void> _analyzeModel() async {
    setState(() => _status = '分析模型...');

    try {
      final childEntities = await _asset!.getChildEntities();

      for (int i = 0; i < childEntities.length; i++) {
        final entity = childEntities[i];
        final entityName = FilamentApp.instance!.getNameForEntity(entity);
        final morphTargets = await _asset!.getMorphTargetNames(entity: entity);

        if (morphTargets.isNotEmpty && entityName == "Head_Mod") {
          _headEntity = entity;
          _headJawOpenIndex = morphTargets.indexOf("F.jawOpen");
          if (kDebugMode) {
            debugPrint('✅ 找到 Head_Mod，F.jawOpen 索引: $_headJawOpenIndex');
          }
        }
      }

      if (_headEntity != null && _headJawOpenIndex >= 0) {
        if (kDebugMode) debugPrint('🎯 ✅ 完美！可以控制统一的 F.jawOpen (嘴唇+牙齿)');
      } else {
        if (kDebugMode) debugPrint('⚠️ 未找到 Head_Mod 或 F.jawOpen');
      }
    } catch (e) {
      throw Exception('模型分析失败: $e');
    }
  }

  /// 🎯 统一的JawOpen控制 (嘴唇+牙齿)
  Future<void> _setUnifiedJawOpen(double value) async {
    if (_headEntity == null || _headJawOpenIndex < 0) return;

    try {
      final headMorphNames = await _asset!.getMorphTargetNames(
        entity: _headEntity!,
      );

      // 🎯 只需要设置Head_Mod的F.jawOpen，包含完整的张嘴效果
      final headWeights = List<double>.filled(headMorphNames.length, 0.0);
      headWeights[_headJawOpenIndex] = value.clamp(0.0, _maxMorphWeight);

      // 🎯 简单直接的设置
      await _asset!.setMorphTargetWeights(_headEntity!, headWeights);
    } catch (e) {
      if (kDebugMode) debugPrint('❌ 统一控制失败: $e');
    }
  }

  /// 🔄 重置所有morph targets到默认状态
  Future<void> _resetAllMorphTargets() async {
    if (_headEntity == null) return;

    try {
      final headMorphNames = await _asset!.getMorphTargetNames(
        entity: _headEntity!,
      );

      // 将所有权重设置为0
      final headWeights = List<double>.filled(headMorphNames.length, 0.0);
      await _asset!.setMorphTargetWeights(_headEntity!, headWeights);

      if (kDebugMode) {
        debugPrint('🔄 已重置所有morph targets');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ 重置失败: $e');
    }
  }

  /// 加载动画列表
  Future<void> _loadAnimations() async {
    try {
      setState(() => _status = '检测动画...');

      final animationNames = await _asset!.getGltfAnimationNames();

      _animations.clear();
      for (int i = 0; i < animationNames.length; i++) {
        final name = animationNames[i].isEmpty
            ? "动画_${i + 1}"
            : animationNames[i];
        _animations.add(name);

        // 查找talk_01动画
        if (name.toLowerCase().contains('talk_01') ||
            name.toLowerCase().contains('talk01')) {
          _talk01AnimationIndex = i;
          if (kDebugMode) {
            debugPrint('✅ 找到talk_01动画: $name (索引: $i)');
          }
        }
      }

      if (kDebugMode) {
        debugPrint('🎭 发现 ${_animations.length} 个动画');
        if (_talk01AnimationIndex >= 0) {
          debugPrint('🎯 talk_01动画索引: $_talk01AnimationIndex');
        } else {
          debugPrint('⚠️ 未找到talk_01动画');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 加载动画失败: $e');
      }
    }
  }

  /// 加载BS数据
  Future<void> _loadBlendshapeData() async {
    try {
      setState(() => _status = '加载 BS 数据...');

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
        debugPrint('✅ BS数据加载成功: ${_blendshapeData!.length}帧');
        _analyzeBSData(); // 分析BS数据特征
      }

      setState(() => _status = '✅ BS数据加载完成');
    } catch (e) {
      _isBlendshapeLoaded = false;
      setState(() => _status = '❌ BS数据加载失败: $e');
      if (kDebugMode) {
        debugPrint('❌ 加载 blendshape 数据失败: $e');
      }
    }
  }

  /// 播放口型同步 - 优化版本
  Future<void> _playLipSync() async {
    if (!_isBlendshapeLoaded || _blendshapeData == null) {
      return;
    }

    if (_isLipSyncPlaying) {
      await _stopLipSync();
    }

    try {
      setState(() => _status = '🎬 准备播放(优化版)...');
      _isLipSyncPlaying = true;

      // 设置动画数据
      await _setupMorphAnimation();

      // 🎭 启动talk_01动画
      if (_talk01AnimationIndex >= 0) {
        await _asset!.playGltfAnimation(_talk01AnimationIndex);
        if (kDebugMode) {
          debugPrint('🎭 启动talk_01动画');
        }
      }

      // 设置音频播放完成监听
      _completeSubscription?.cancel();
      _completeSubscription = _audioPlayer.onPlayerComplete.listen((_) async {
        await _stopLipSync();
      });

      // 开始播放音频
      await _audioPlayer.play(AssetSource('wav/output.wav'));
      setState(() => _status = '🎬 正在播放(优化版)...');
    } catch (e) {
      _isLipSyncPlaying = false;
      setState(() => _status = '❌ 播放失败: $e');
      if (kDebugMode) {
        debugPrint('❌ 播放失败: $e');
      }
    }
  }

  /// 播放原始BS数据 - 无任何修饰
  Future<void> _playRawLipSync() async {
    if (!_isBlendshapeLoaded || _blendshapeData == null) {
      return;
    }

    if (_isLipSyncPlaying) {
      await _stopLipSync();
    }

    try {
      setState(() => _status = '🎬 准备播放(原始版)...');
      _isLipSyncPlaying = true;

      // 设置原始动画数据
      await _setupRawMorphAnimation();

      // 🎭 启动talk_01动画
      if (_talk01AnimationIndex >= 0) {
        await _asset!.playGltfAnimation(_talk01AnimationIndex);
        if (kDebugMode) {
          debugPrint('🎭 启动talk_01动画');
        }
      }

      // 设置音频播放完成监听
      _completeSubscription?.cancel();
      _completeSubscription = _audioPlayer.onPlayerComplete.listen((_) async {
        await _stopLipSync();
      });

      // 开始播放音频
      await _audioPlayer.play(AssetSource('wav/output.wav'));
      setState(() => _status = '🎬 正在播放(原始版)...');
    } catch (e) {
      _isLipSyncPlaying = false;
      setState(() => _status = '❌ 播放失败: $e');
      if (kDebugMode) {
        debugPrint('❌ 播放失败: $e');
      }
    }
  }

  /// 停止口型同步
  Future<void> _stopLipSync() async {
    try {
      _isLipSyncPlaying = false;
      setState(() => _status = '⏹️ 停止播放...');

      // 停止音频
      await _audioPlayer.stop();

      // 🎭 停止talk_01动画
      if (_talk01AnimationIndex >= 0) {
        await _asset!.stopGltfAnimation(_talk01AnimationIndex);
        if (kDebugMode) {
          debugPrint('🎭 停止talk_01动画');
        }
      }

      // 取消监听
      _completeSubscription?.cancel();

      // 重置所有morph targets到默认状态
      await _resetAllMorphTargets();

      setState(() => _status = '✅ 已停止');
    } catch (e) {
      setState(() => _status = '❌ 停止失败: $e');
      if (kDebugMode) {
        debugPrint('❌ 停止失败: $e');
      }
    }
  }

  /// 设置原始Morph动画数据 - 完全无修饰版本
  Future<void> _setupRawMorphAnimation() async {
    if (_asset == null || _blendshapeData == null) return;

    try {
      final totalFrames = _blendshapeData!.length;
      final frameLengthMs = 59160.0 / totalFrames; // 音频总长度/帧数

      // 获取Head_Mod的所有morph targets
      final headMorphNames = await _asset!.getMorphTargetNames(
        entity: _headEntity!,
      );

      if (kDebugMode) {
        debugPrint('🎯 Head_Mod有${headMorphNames.length}个morph targets');
        debugPrint('🎯 BS数据有${_blendshapeData!.first.length}个权重');
      }

      // 创建完整的BS映射
      final bsToHeadMapping = _createBSMapping(headMorphNames);

      if (bsToHeadMapping.isEmpty) {
        if (kDebugMode) debugPrint('❌ 无法创建BS映射');
        return;
      }

      // 创建完整的动画数据 - 使用原始数据，无任何处理
      final mappedMorphNames = bsToHeadMapping.keys.toList();
      final totalMorphTargets = mappedMorphNames.length;
      final flatData = Float32List(totalFrames * totalMorphTargets);

      for (int frame = 0; frame < totalFrames; frame++) {
        final frameWeights = _blendshapeData![frame]; // 直接使用原始数据
        final baseIndex = frame * totalMorphTargets;

        for (int i = 0; i < mappedMorphNames.length; i++) {
          final morphName = mappedMorphNames[i];
          final bsIndex = bsToHeadMapping[morphName]!;

          if (bsIndex < frameWeights.length) {
            // 完全原始的值，不做任何修改
            double value = frameWeights[bsIndex];

            // 只做基本的范围限制，防止异常值
            value = value.clamp(0.0, 1.0);

            flatData[baseIndex + i] = value;
          }
        }
      }

      final morphData = MorphAnimationData(
        flatData,
        mappedMorphNames,
        frameLengthInMs: frameLengthMs,
      );

      // 确保animation component已激活
      await _asset!.addAnimationComponent();

      // 设置动画数据
      await _asset!.setMorphAnimationData(
        morphData,
        targetMeshNames: ["Head_Mod"],
      );

      if (kDebugMode) {
        debugPrint('✅ 原始BS映射设置完成: ${mappedMorphNames.length}个morph targets');
        debugPrint('🎯 使用完全原始数据，无任何增强或平滑');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 设置原始Morph动画失败: $e');
      }
    }
  }

  /// 设置优化的Morph动画数据 - 智能增强和平滑处理
  Future<void> _setupMorphAnimation() async {
    if (_asset == null || _blendshapeData == null) return;

    try {
      final totalFrames = _blendshapeData!.length;
      final frameLengthMs = 59160.0 / totalFrames; // 音频总长度/帧数

      // 获取Head_Mod的所有morph targets
      final headMorphNames = await _asset!.getMorphTargetNames(
        entity: _headEntity!,
      );

      if (kDebugMode) {
        debugPrint('🎯 Head_Mod有${headMorphNames.length}个morph targets');
        debugPrint('🎯 BS数据有${_blendshapeData!.first.length}个权重');
      }

      // 创建完整的BS映射
      final bsToHeadMapping = _createBSMapping(headMorphNames);

      if (bsToHeadMapping.isEmpty) {
        if (kDebugMode) debugPrint('❌ 无法创建BS映射');
        return;
      }

      // 预处理：优化BS数据
      final optimizedData = _optimizeBlendshapeData(_blendshapeData!);

      // 创建完整的动画数据
      final mappedMorphNames = bsToHeadMapping.keys.toList();
      final totalMorphTargets = mappedMorphNames.length;
      final flatData = Float32List(totalFrames * totalMorphTargets);

      _previousFrameWeights = null; // 重置平滑数据

      for (int frame = 0; frame < totalFrames; frame++) {
        final frameWeights = optimizedData[frame];
        final baseIndex = frame * totalMorphTargets;
        final currentFrameWeights = List<double>.filled(totalMorphTargets, 0.0);

        // 第一步：应用原始权重和增强
        for (int i = 0; i < mappedMorphNames.length; i++) {
          final morphName = mappedMorphNames[i];
          final bsIndex = bsToHeadMapping[morphName]!;

          if (bsIndex < frameWeights.length) {
            double value = frameWeights[bsIndex];

            // 智能增强不同类型的morph targets
            value = _enhanceMorphValue(morphName, value);

            currentFrameWeights[i] = value;
          }
        }

        // 第二步：应用平滑过渡
        if (_previousFrameWeights != null) {
          for (int i = 0; i < totalMorphTargets; i++) {
            final smoothedValue = _applySmoothTransition(
              _previousFrameWeights![i],
              currentFrameWeights[i],
              mappedMorphNames[i],
            );
            flatData[baseIndex + i] = smoothedValue;
          }
        } else {
          // 第一帧直接使用
          for (int i = 0; i < totalMorphTargets; i++) {
            flatData[baseIndex + i] = currentFrameWeights[i];
          }
        }

        _previousFrameWeights = List.from(currentFrameWeights);
      }

      final morphData = MorphAnimationData(
        flatData,
        mappedMorphNames,
        frameLengthInMs: frameLengthMs,
      );

      // 确保animation component已激活
      await _asset!.addAnimationComponent();

      // 设置动画数据
      await _asset!.setMorphAnimationData(
        morphData,
        targetMeshNames: ["Head_Mod"],
      );

      if (kDebugMode) {
        debugPrint('✅ 优化BS映射设置完成: ${mappedMorphNames.length}个morph targets');
        debugPrint('🎯 应用了智能增强和平滑过渡');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 设置Morph动画失败: $e');
      }
    }
  }

  /// 🎯 优化BS数据 - 修复版本，防止形变
  List<List<double>> _optimizeBlendshapeData(List<List<double>> rawData) {
    final optimizedData = <List<double>>[];

    for (int frame = 0; frame < rawData.length; frame++) {
      final currentFrame = List<double>.from(rawData[frame]);

      // 1. 去除微小噪声 (< 0.02的值设为0，提高阈值)
      for (int i = 0; i < currentFrame.length; i++) {
        if (currentFrame[i].abs() < 0.02) {
          currentFrame[i] = 0.0;
        }
        // 限制最大值，防止异常数据
        currentFrame[i] = currentFrame[i].clamp(0.0, 1.0);
      }

      // 2. 温和增强关键口型权重
      _enhanceKeyMouthShapesConservative(currentFrame);

      // 3. 应用更强的时间域平滑
      if (frame >= 1 && frame < rawData.length - 1) {
        final prevFrame = rawData[frame - 1];
        final nextFrame = rawData[frame + 1];

        for (int i = 0; i < currentFrame.length; i++) {
          // 对快速变化的权重应用更强的平滑
          final variance =
              (currentFrame[i] - prevFrame[i]).abs() +
              (currentFrame[i] - nextFrame[i]).abs();

          if (variance > 0.2) {
            // 降低阈值，更早触发平滑
            // 使用加权平均，当前帧权重更高
            currentFrame[i] =
                (prevFrame[i] * 0.2 +
                currentFrame[i] * 0.6 +
                nextFrame[i] * 0.2);
          }
        }
      }

      // 4. 最终安全检查
      for (int i = 0; i < currentFrame.length; i++) {
        currentFrame[i] = currentFrame[i].clamp(0.0, _maxMorphWeight);
      }

      optimizedData.add(currentFrame);
    }

    if (kDebugMode) {
      debugPrint('🎯 BS数据优化完成: ${optimizedData.length}帧 (修复版本)');
    }

    return optimizedData;
  }

  /// 🎯 保守增强关键口型形状 - 修复版本
  void _enhanceKeyMouthShapesConservative(List<double> frameWeights) {
    if (frameWeights.length < 52) return;

    // ARKit blendshape索引
    const jawOpenIndex = 25;
    const mouthFunnelIndex = 27;
    const mouthPuckerIndex = 28;
    const mouthSmileLeftIndex = 31;
    const mouthSmileRightIndex = 32;

    // 检测并温和增强主要口型
    final jawOpen = frameWeights[jawOpenIndex];

    if (jawOpen > 0.15) {
      // 提高阈值，减少误触发
      // 张嘴时，温和增强相关的嘴型
      if (frameWeights[mouthFunnelIndex] > 0.08) {
        frameWeights[mouthFunnelIndex] = (frameWeights[mouthFunnelIndex] * 1.15)
            .clamp(0.0, _maxMorphWeight);
      }
      if (frameWeights[mouthPuckerIndex] > 0.08) {
        frameWeights[mouthPuckerIndex] = (frameWeights[mouthPuckerIndex] * 1.1)
            .clamp(0.0, _maxMorphWeight);
      }
    }

    // 温和增强微笑表情的对称性
    final smileLeft = frameWeights[mouthSmileLeftIndex];
    final smileRight = frameWeights[mouthSmileRightIndex];
    if (smileLeft > 0.15 || smileRight > 0.15) {
      final avgSmile = (smileLeft + smileRight) / 2.0;
      frameWeights[mouthSmileLeftIndex] = (avgSmile * 1.05).clamp(
        0.0,
        _maxMorphWeight,
      );
      frameWeights[mouthSmileRightIndex] = (avgSmile * 1.05).clamp(
        0.0,
        _maxMorphWeight,
      );
    }
  }

  /// 🎯 智能增强morph值 - 修复版本，防止过度形变
  double _enhanceMorphValue(String morphName, double originalValue) {
    // 首先应用基础限制，防止输入值过大
    originalValue = originalValue.clamp(0.0, 1.0);

    // 如果原始值太小，不进行增强
    if (originalValue < 0.02) return originalValue;

    double enhancedValue = originalValue;

    // 张嘴相关的增强 - 更保守的增强
    if (morphName == "F.jawOpen") {
      enhancedValue = originalValue * _jawOpenEnhanceFactor;
      // 应用渐进式增强，避免突变
      enhancedValue = _applyProgressiveEnhancement(
        originalValue,
        enhancedValue,
      );
    }
    // 嘴型细节增强 - 更温和的增强
    else if (morphName.contains("mouth") || morphName.contains("Mouth")) {
      if (originalValue > 0.05) {
        enhancedValue = originalValue * _mouthShapeEnhanceFactor;
        enhancedValue = _applyProgressiveEnhancement(
          originalValue,
          enhancedValue,
        );
      }
    }
    // 眼部表情 - 减少增强幅度
    else if (morphName.contains("eye") || morphName.contains("Eye")) {
      if (originalValue > 0.1) {
        enhancedValue = originalValue * 1.1; // 从1.2降到1.1
      }
    }
    // 眉毛表情 - 减少增强幅度
    else if (morphName.contains("brow") || morphName.contains("Brow")) {
      if (originalValue > 0.1) {
        enhancedValue = originalValue * 1.15; // 从1.3降到1.15
      }
    }

    // 应用最终限制，确保不超过安全范围
    return enhancedValue.clamp(0.0, _maxMorphWeight);
  }

  /// 🎯 渐进式增强，避免突变
  double _applyProgressiveEnhancement(double original, double enhanced) {
    // 对于小值使用更温和的增强
    if (original < 0.1) {
      return original + (enhanced - original) * 0.5; // 50%的增强
    } else if (original < 0.3) {
      return original + (enhanced - original) * 0.7; // 70%的增强
    } else {
      return enhanced; // 完整增强
    }
  }

  /// 🎯 应用S曲线增强，使过渡更自然
  double _applySCurve(double value) {
    if (value <= 0) return 0.0;
    if (value >= 1) return 1.0;

    // S曲线公式: 3x² - 2x³
    return 3 * value * value - 2 * value * value * value;
  }

  /// 🎯 应用平滑过渡
  double _applySmoothTransition(
    double previousValue,
    double currentValue,
    String morphName,
  ) {
    // 对于快速变化的morph targets应用更强的平滑
    double smoothingStrength = _smoothingFactor;

    // 张嘴动作需要更快的响应
    if (morphName == "F.jawOpen") {
      smoothingStrength *= 0.7; // 减少平滑，保持响应性
    }

    // 眼部动作需要更快的响应
    if (morphName.contains("eye") || morphName.contains("Eye")) {
      smoothingStrength *= 0.5;
    }

    // 线性插值平滑
    return previousValue +
        (currentValue - previousValue) * (1.0 - smoothingStrength);
  }

  /// 🔍 分析BS数据特征
  void _analyzeBSData() {
    if (_blendshapeData == null || _blendshapeData!.isEmpty) return;

    const jawOpenIndex = 25; // ARKit jawOpen索引
    const mouthFunnelIndex = 27;
    const mouthPuckerIndex = 28;

    double maxJawOpen = 0.0;
    double avgJawOpen = 0.0;
    int activeFrames = 0;

    for (final frame in _blendshapeData!) {
      if (frame.length > jawOpenIndex) {
        final jawValue = frame[jawOpenIndex];
        maxJawOpen = maxJawOpen > jawValue ? maxJawOpen : jawValue;
        avgJawOpen += jawValue;

        if (jawValue > 0.05) activeFrames++;
      }
    }

    avgJawOpen /= _blendshapeData!.length;

    if (kDebugMode) {
      debugPrint('📊 BS数据分析:');
      debugPrint('   最大张嘴幅度: ${maxJawOpen.toStringAsFixed(3)}');
      debugPrint('   平均张嘴幅度: ${avgJawOpen.toStringAsFixed(3)}');
      debugPrint('   活跃帧数: $activeFrames/${_blendshapeData!.length}');
      debugPrint(
        '   活跃比例: ${(activeFrames / _blendshapeData!.length * 100).toStringAsFixed(1)}%',
      );

      // 分析主要口型分布
      _analyzeMouthShapeDistribution();
    }
  }

  /// 🔍 分析嘴型分布
  void _analyzeMouthShapeDistribution() {
    if (_blendshapeData == null) return;

    const mouthShapeIndices = [
      25, // jawOpen
      27, // mouthFunnel (O音)
      28, // mouthPucker (撅嘴)
      31, // mouthSmileLeft
      32, // mouthSmileRight
    ];

    const mouthShapeNames = [
      'jawOpen',
      'mouthFunnel',
      'mouthPucker',
      'mouthSmileLeft',
      'mouthSmileRight',
    ];

    for (int i = 0; i < mouthShapeIndices.length; i++) {
      final index = mouthShapeIndices[i];
      double maxValue = 0.0;
      int activeCount = 0;

      for (final frame in _blendshapeData!) {
        if (frame.length > index) {
          final value = frame[index];
          maxValue = maxValue > value ? maxValue : value;
          if (value > 0.1) activeCount++;
        }
      }

      if (kDebugMode) {
        debugPrint(
          '   ${mouthShapeNames[i]}: 最大${maxValue.toStringAsFixed(3)}, 活跃${activeCount}帧',
        );
      }
    }
  }

  /// 创建BS数据到Head_Mod的映射关系
  Map<String, int> _createBSMapping(List<String> headMorphNames) {
    // ARKit标准blendshape名称 (52个)
    const bsNames = [
      "browDownLeft", // 0
      "browDownRight", // 1
      "browInnerUp", // 2
      "browOuterUpLeft", // 3
      "browOuterUpRight", // 4
      "cheekPuff", // 5
      "cheekSquintLeft", // 6
      "cheekSquintRight", // 7
      "eyeBlinkLeft", // 8
      "eyeBlinkRight", // 9
      "eyeLookDownLeft", // 10
      "eyeLookDownRight", // 11
      "eyeLookInLeft", // 12
      "eyeLookInRight", // 13
      "eyeLookOutLeft", // 14
      "eyeLookOutRight", // 15
      "eyeLookUpLeft", // 16
      "eyeLookUpRight", // 17
      "eyeSquintLeft", // 18
      "eyeSquintRight", // 19
      "eyeWideLeft", // 20
      "eyeWideRight", // 21
      "jawForward", // 22
      "jawLeft", // 23
      "jawRight", // 24
      "jawOpen", // 25
      "mouthClose", // 26
      "mouthFunnel", // 27
      "mouthPucker", // 28
      "mouthLeft", // 29
      "mouthRight", // 30
      "mouthSmileLeft", // 31
      "mouthSmileRight", // 32
      "mouthFrownLeft", // 33
      "mouthFrownRight", // 34
      "mouthDimpleLeft", // 35
      "mouthDimpleRight", // 36
      "mouthStretchLeft", // 37
      "mouthStretchRight", // 38
      "mouthRollLower", // 39
      "mouthRollUpper", // 40
      "mouthShrugLower", // 41
      "mouthShrugUpper", // 42
      "mouthPressLeft", // 43
      "mouthPressRight", // 44
      "mouthLowerDownLeft", // 45
      "mouthLowerDownRight", // 46
      "mouthUpperUpLeft", // 47
      "mouthUpperUpRight", // 48
      "noseSneerLeft", // 49
      "noseSneerRight", // 50
      "tongueOut", // 51
    ];

    final mapping = <String, int>{};

    for (int i = 0; i < bsNames.length; i++) {
      final bsName = bsNames[i];
      final headMorphName = "F.$bsName";

      // 检查Head_Mod是否有对应的morph target
      if (headMorphNames.contains(headMorphName)) {
        mapping[headMorphName] = i;
      }
    }

    if (kDebugMode) {
      debugPrint('🗺️ 创建了${mapping.length}个BS映射');
      debugPrint('   映射的morph targets: ${mapping.keys.toList()}');
    }

    return mapping;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('口型同步播放'),
      ),
      body: Column(
        children: [
          // 3D 视图
          Expanded(
            flex: 3,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              margin: const EdgeInsets.all(8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _viewer != null
                    ? ThermionWidget(viewer: _viewer!)
                    : const Center(child: CircularProgressIndicator()),
              ),
            ),
          ),

          // 控制面板
          Container(
            height: 180, // 增加高度以适应两行按钮
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 状态显示
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '状态: $_status',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // 🎯 口型同步播放控制
                  Text(
                    '口型同步播放',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.purple,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    '对比测试: 优化版(增强+平滑) vs 原始版(无修饰)',
                    style: const TextStyle(color: Colors.grey, fontSize: 10),
                  ),

                  const SizedBox(height: 12),

                  // 播放控制按钮 - 第一行
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        onPressed:
                            !_isLipSyncPlaying &&
                                _isBlendshapeLoaded &&
                                _isInitialized
                            ? _playLipSync
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[100],
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        icon: const Icon(Icons.play_arrow, size: 14),
                        label: const Text(
                          '优化播放',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed:
                            !_isLipSyncPlaying &&
                                _isBlendshapeLoaded &&
                                _isInitialized
                            ? _playRawLipSync
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue[100],
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        icon: const Icon(Icons.play_circle_outline, size: 14),
                        label: const Text(
                          '原始播放',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 6),

                  // 控制按钮 - 第二行
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _isLipSyncPlaying ? _stopLipSync : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red[100],
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        icon: const Icon(Icons.stop, size: 14),
                        label: const Text('停止', style: TextStyle(fontSize: 11)),
                      ),
                      ElevatedButton.icon(
                        onPressed: _isInitialized
                            ? _resetAllMorphTargets
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange[100],
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        icon: const Icon(Icons.refresh, size: 14),
                        label: const Text('重置', style: TextStyle(fontSize: 11)),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  const SizedBox(height: 8),

                  // 数据状态显示
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _isBlendshapeLoaded
                          ? Colors.green[50]
                          : Colors.orange[50],
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: _isBlendshapeLoaded
                            ? Colors.green
                            : Colors.orange,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isBlendshapeLoaded
                              ? Icons.check_circle
                              : Icons.hourglass_empty,
                          size: 12,
                          color: _isBlendshapeLoaded
                              ? Colors.green
                              : Colors.orange,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _isBlendshapeLoaded
                                ? 'BS数据: ${_blendshapeData?.length ?? 0}帧 | 动画: ${_animations.length}个 | 优化: 去噪+增强+平滑'
                                : '数据加载中...',
                            style: TextStyle(
                              fontSize: 10,
                              color: _isBlendshapeLoaded
                                  ? Colors.green[800]
                                  : Colors.orange[800],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
