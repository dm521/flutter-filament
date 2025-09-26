import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart' as widgets;
import 'package:flutter/services.dart';
import 'package:thermion_flutter/thermion_flutter.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:animation_tools_dart/animation_tools_dart.dart';

enum CameraPreset {
  soloCloseUp,   // 单人演播（当前较远，接近全身）
  halfBody,      // 半身像（腰部以上）
  bustCloseUp    // 胸像/肩部以上特写
}

void main() {
  runApp(const LipSyncApp());
}

class LipSyncApp extends StatelessWidget {
  const LipSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '全特科技写实数字人测试',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const LipSyncPlayer(),
    );
  }
}

class LipSyncPlayer extends StatefulWidget {
  const LipSyncPlayer({super.key});

  @override
  State<LipSyncPlayer> createState() => _LipSyncPlayerState();
}

class _LipSyncPlayerState extends State<LipSyncPlayer> {
  // 核心组件
  ThermionViewer? _viewer;
  ThermionAsset? _asset;
  String _status = '初始化中...';
  bool _isInitialized = false;

  // 音频和数据
  List<List<double>>? _blendshapeData;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;

  StreamSubscription<void>? _completeSubscription;

  // 相机预设
  CameraPreset _currentCameraPreset = CameraPreset.soloCloseUp;

  // 优化控制
  bool _enableOptimization = false; // 默认关闭，因为原始数据已经比较自然

  // 眨眼权重控制
  double _leftEyeBlinkWeight = 0.0;
  double _rightEyeBlinkWeight = 0.0;
  ThermionEntity? _headEntity;

  // 防抖动控制
  Timer? _blinkWeightTimer;
  bool _isSettingWeights = false;

  // 手动停止标志
  bool _isManuallyStopped = false;

  // 人物旋转控制
  double _rotationAngle = 0.0; // 0=正面, 90=右侧, 180=背面, 270=左侧

  // 动画系统
  final List<String> _animations = [];
  int _idleAnimationIndex = -1;
  bool _isIdlePlaying = false;
  int _selectedAnimationIndex = -1;
  bool _isCustomAnimationPlaying = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _completeSubscription?.cancel();
    _audioPlayer.dispose();
    _blinkWeightTimer?.cancel(); // 清理眨眼权重定时器
    // 停止所有动画
    if (_asset != null) {
      _stopAllAnimations();
    }
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      setState(() => _status = '创建3D场景...');

      // 创建3D查看器
      _viewer = await ThermionFlutterPlugin.createViewer();
      await Future.delayed(Duration(milliseconds: 300));
      await _viewer!.setRendering(true);

      // 🖼️ 设置背景图片（替代 skybox）
      try {
        await _viewer!.setBackgroundImage(
          'assets/images/background.png',
          fillHeight: true,
        );
        if (kDebugMode) debugPrint('🖼️ 背景图片已加载');
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ 背景图片加载失败，使用默认背景: $e');
      }

      // 设置环境光照（IBL）
      await _viewer!.loadIbl(
        "assets/environments/studio_small_env_ibl.ktx",
        intensity: 15600.0,
      );

      // 应用 IBL 旋转（基于 settings.json 中的 iblRotation 参数）
      try {
        var rotationMatrix = Matrix3.identity();
        Matrix4.rotationY(
          0.558505,
        ).copyRotation(rotationMatrix); // settings.json 中的角度
        await _viewer!.rotateIbl(rotationMatrix);
        if (kDebugMode) {
          debugPrint('🔄 IBL 旋转已应用: 0.558505 弧度');
        }
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ IBL 旋转设置失败: $e');
      }

      // 设置专业灯光系统（基于 main.dart 的配置）
      try {
        await _viewer!.destroyLights();
      } catch (_) {}

      // 主太阳光 - 基于 settings.json 参数
      await _viewer!.addDirectLight(
        DirectLight.sun(
          color: 5400.0, // 暖白色温
          intensity: 75000.0, // settings.json 的 sunlightIntensity
          castShadows: true, // 启用阴影
          direction: Vector3(
            0.366695,
            -0.357967,
            -0.858717,
          ), // settings.json 的最新方向
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

      // 🎨 应用后处理效果（基于 main.dart）
      await _viewer!.setPostProcessing(true);

      // 🌑 启用阴影系统
      try {
        await _viewer!.setShadowsEnabled(true);
        if (kDebugMode) debugPrint('🌑 阴影系统已启用');
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ 阴影系统启用失败: $e');
      }

      // Tone Mapping - ACES
      await _viewer!.setToneMapping(ToneMapper.ACES);

      // Bloom 效果
      await _viewer!.setBloom(
        true,
        0.348,
      ); // enabled, strength from settings.json

      // 抗锯齿 (MSAA, FXAA, TAA)
      await _viewer!.setAntiAliasing(true, true, true);

      // 🔆 调整曝光度以提升整体亮度（基于 settings.json 的相机参数）
      try {
        final camera = await _viewer!.getActiveCamera();
        await camera.setExposure(
          16.0,
          1.0 / 125.0,
          100.0,
        ); // f/16, 1/125s, ISO100
        if (kDebugMode) debugPrint('📷 相机曝光已设置: f/16, 1/125s, ISO100');
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ 相机曝光设置失败: $e');
      }

      setState(() => _status = '加载角色模型...');

      // 加载模型
      _asset = await _viewer!.loadGltf("assets/models/xiaomeng_0926.glb");

      // 检测和设置动画
      await _loadAnimations();

      // 设置相机预设
      await _applyCameraPreset(_currentCameraPreset);

      setState(() => _status = '加载口型数据...');

      // 加载BS数据
      await _loadBlendshapeData();

      // 初始化眨眼控制
      await _initializeBlinkControl();

      _isInitialized = true;
      setState(() => _status = '✅ 准备就绪');
    } catch (e) {
      setState(() => _status = '❌ 初始化失败: $e');
      if (kDebugMode) debugPrint('初始化失败: $e');
    }
  }

  Future<void> _loadBlendshapeData() async {
    try {
      final jsonString = await rootBundle.loadString('assets/wav/bs.json');
      final List<dynamic> rawData = json.decode(jsonString);

      _blendshapeData = rawData
          .map(
            (frame) =>
                List<double>.from(frame.map((value) => value.toDouble())),
          )
          .toList();

      if (kDebugMode) {
        debugPrint('✅ BS数据加载成功: ${_blendshapeData!.length} 帧');

        // 🔍 分析BS数据的权重范围
        _analyzeBSDataRange();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ BS数据加载失败: $e');
    }
  }

  Future<void> _playLipSync() async {
    if (!_isInitialized || _asset == null || _blendshapeData == null) return;

    try {
      setState(() {
        _isPlaying = true;
        _isManuallyStopped = false; // 重置手动停止标志
        _status = '🎬 播放中...';
      });

      // 🛑 暂停所有动画，避免冲突
      await _stopAllAnimations();

      // 🎯 先设置音频源，然后获取实际时长（确保同步）
      final audioSource = AssetSource('wav/output.wav');
      await _audioPlayer.setSource(audioSource);

      final duration = await _audioPlayer.getDuration();
      if (duration == null) {
        throw Exception('无法获取音频时长');
      }

      final audioDurationMs = duration.inMilliseconds.toDouble();

      if (kDebugMode) {
        debugPrint('🎵 音频长度: ${(audioDurationMs / 1000).toStringAsFixed(2)}秒');
        debugPrint('   BS帧数: ${_blendshapeData!.length}');
        debugPrint(
          '   计算帧率: ${(_blendshapeData!.length * 1000 / audioDurationMs).toStringAsFixed(1)} FPS',
        );
      }

      // 设置morph动画（必须在播放音频之前完成）
      await _setupMorphAnimation(audioDurationMs);

      // 同步启动音频播放
      await _audioPlayer.play(audioSource);

      // 监听播放完成
      _completeSubscription = _audioPlayer.onPlayerComplete.listen((_) async {
        setState(() {
          _isPlaying = false;
          _status = '✅ 播放完成';
        });

        // 🔄 恢复之前的动画状态
        if (_selectedAnimationIndex >= 0) {
          await _playSelectedAnimation(_selectedAnimationIndex);
        } else {
          await _resumeIdleAnimation();
        }
      });
    } catch (e) {
      setState(() {
        _isPlaying = false;
        _status = '❌ 播放失败: $e';
      });
      if (kDebugMode) debugPrint('播放失败: $e');

      // 发生错误时也要恢复之前的动画状态
      if (_selectedAnimationIndex >= 0) {
        await _playSelectedAnimation(_selectedAnimationIndex);
      } else {
        await _resumeIdleAnimation();
      }
    }
  }

  Future<void> _setupMorphAnimation(double audioDurationMs) async {
    if (_asset == null || _blendshapeData == null) return;

    try {
      final totalFrames = _blendshapeData!.length;
      final frameLengthMs = audioDurationMs / totalFrames;

      if (kDebugMode) {
        debugPrint('🎬 动画同步参数:');
        debugPrint('   总帧数: $totalFrames');
        debugPrint('   每帧时长: ${frameLengthMs.toStringAsFixed(2)}ms');
        debugPrint('   总动画时长: ${audioDurationMs.toStringAsFixed(0)}ms');
      }

      // 使用完整的52个ARKit blendshape映射（与morph_target_unified.dart一致）
      const bsMapping = {
        "F.eyeBlinkLeft": 0,
        "F.eyeLookDownLeft": 1,
        "F.eyeLookInLeft": 2,
        "F.eyeLookOutLeft": 3,
        "F.eyeLookUpLeft": 4,
        "F.eyeSquintLeft": 5,
        "F.eyeWideLeft": 6,
        "F.eyeBlinkRight": 7,
        "F.eyeLookDownRight": 8,
        "F.eyeLookInRight": 9,
        "F.eyeLookOutRight": 10,
        "F.eyeLookUpRight": 11,
        "F.eyeSquintRight": 12,
        "F.eyeWideRight": 13,
        "F.jawForward": 14,
        "F.jawLeft": 15,
        "F.jawRight": 16,
        "F.jawOpen": 17,
        "F.mouthClose": 18,
        "F.mouthFunnel": 19,
        "F.mouthPucker": 20,
        "F.mouthLeft": 21,
        "F.mouthRight": 22,
        "F.mouthSmileLeft": 23,
        "F.mouthSmileRight": 24,
        "F.mouthFrownLeft": 25,
        "F.mouthFrownRight": 26,
        "F.mouthDimpleLeft": 27,
        "F.mouthDimpleRight": 28,
        "F.mouthStretchLeft": 29,
        "F.mouthStretchRight": 30,
        "F.mouthRollLower": 31,
        "F.mouthRollUpper": 32,
        "F.mouthShrugLower": 33,
        "F.mouthShrugUpper": 34,
        "F.mouthPressLeft": 35,
        "F.mouthPressRight": 36,
        "F.mouthLowerDownLeft": 37,
        "F.mouthLowerDownRight": 38,
        "F.mouthUpperUpLeft": 39,
        "F.mouthUpperUpRight": 40,
        "F.browDownLeft": 41,
        "F.browDownRight": 42,
        "F.browInnerUp": 43,
        "F.browOuterUpLeft": 44,
        "F.browOuterUpRight": 45,
        "F.cheekPuff": 46,
        "F.cheekSquintLeft": 47,
        "F.cheekSquintRight": 48,
        "F.noseSneerLeft": 49,
        "F.noseSneerRight": 50,
        "F.tongueOut": 51,
      };

      // 获取Head_Mod的实际morph targets并创建映射
      final childEntities = await _asset!.getChildEntities();
      ThermionEntity? headEntity;

      for (int i = 0; i < childEntities.length; i++) {
        final entity = childEntities[i];
        final entityName = FilamentApp.instance!.getNameForEntity(entity);
        if (entityName == "Head_Mod") {
          headEntity = entity;
          break;
        }
      }

      if (headEntity == null) {
        throw Exception('未找到Head_Mod实体');
      }

      final headMorphNames = await _asset!.getMorphTargetNames(
        entity: headEntity,
      );
      final mappedMorphNames = <String>[];

      // 只包含Head_Mod中实际存在的morph targets
      for (final morphName in headMorphNames) {
        if (bsMapping.containsKey(morphName)) {
          mappedMorphNames.add(morphName);
        }
      }

      if (mappedMorphNames.isEmpty) {
        throw Exception('Head_Mod中没有找到匹配的morph targets');
      }

      if (kDebugMode) {
        debugPrint('✅ 找到${mappedMorphNames.length}个匹配的morph targets');
      }

      // 创建动画数据
      final flatData = Float32List(totalFrames * mappedMorphNames.length);

      for (int frame = 0; frame < totalFrames; frame++) {
        final frameWeights = _blendshapeData![frame];
        final baseIndex = frame * mappedMorphNames.length;

        for (int i = 0; i < mappedMorphNames.length; i++) {
          final morphName = mappedMorphNames[i];
          final bsIndex = bsMapping[morphName]!;

          if (bsIndex < frameWeights.length) {
            double weight = frameWeights[bsIndex];
            // 🎯 根据开关决定是否应用优化
            double finalWeight = _enableOptimization
                ? _optimizeWeight(morphName, weight)
                : weight;
            flatData[baseIndex + i] = finalWeight;
          }
        }
      }

      final morphData = MorphAnimationData(
        flatData,
        mappedMorphNames,
        frameLengthInMs: frameLengthMs,
      );

      await _asset!.addAnimationComponent();
      // 只使用 Head_Mod，因为它包含 F. 开头的面部 morph targets
      await _asset!.setMorphAnimationData(
        morphData,
        targetMeshNames: ["Head_Mod"],
      );

      // 🎯 确保动画数据完全设置完成后再返回
      await Future.delayed(Duration(milliseconds: 50));

      if (kDebugMode) debugPrint('✅ Morph动画设置完成，准备同步播放');
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Morph动画设置失败: $e');
    }
  }

  Future<void> _stopLipSync() async {
    try {
      setState(() {
        _isPlaying = false;
        _status = '⏹️ 停止中...';
      });

      // 🎯 同步停止音频和动画
      await _audioPlayer.stop();

      // 取消播放完成监听
      _completeSubscription?.cancel();

      // 🎯 停止morph动画（参考morph_target_unified.dart的实现）
      if (_asset != null) {
        try {
          // 找到Head_Mod实体
          final childEntities = await _asset!.getChildEntities();
          ThermionEntity? headEntity;

          for (int i = 0; i < childEntities.length; i++) {
            final entity = childEntities[i];
            final entityName = FilamentApp.instance!.getNameForEntity(entity);
            if (entityName == "Head_Mod") {
              headEntity = entity;
              break;
            }
          }

          if (headEntity != null) {
            // 🔑 关键：清除morph动画数据（这会停止动画播放）
            await _asset!.clearMorphAnimationData(headEntity);
            if (kDebugMode) debugPrint('✅ Morph动画数据已清除');

            // 然后重置所有morph targets到默认状态
            final morphTargets = await _asset!.getMorphTargetNames(
              entity: headEntity,
            );
            final resetWeights = List<double>.filled(morphTargets.length, 0.0);
            await _asset!.setMorphTargetWeights(headEntity, resetWeights);
            if (kDebugMode) debugPrint('✅ Morph targets已重置');
          }
        } catch (e) {
          if (kDebugMode) debugPrint('⚠️ Morph动画停止失败: $e');
        }
      }

      setState(() => _status = '✅ 已停止');

      // 🔄 恢复之前的动画状态
      if (_selectedAnimationIndex >= 0) {
        await _playSelectedAnimation(_selectedAnimationIndex);
      } else {
        await _resumeIdleAnimation();
      }
    } catch (e) {
      setState(() => _status = '❌ 停止失败: $e');
      if (kDebugMode) debugPrint('停止失败: $e');

      // 即使停止失败也要尝试恢复之前的动画状态
      if (_selectedAnimationIndex >= 0) {
        await _playSelectedAnimation(_selectedAnimationIndex);
      } else {
        await _resumeIdleAnimation();
      }
    }
  }

  // 🛑 停止所有动画
  Future<void> _stopAllAnimations() async {
    if (kDebugMode) debugPrint('🛑 停止按钮被点击，开始停止所有动画...');

    try {
      setState(() => _status = '⏹️ 停止所有动画...');

      // 停止音频
      await _audioPlayer.stop();
      _completeSubscription?.cancel();

      // 停止所有glTF动画
      if (_asset != null) {
        for (int i = 0; i < _animations.length; i++) {
          try {
            await _asset!.stopGltfAnimation(i);
          } catch (e) {
            if (kDebugMode) debugPrint('⚠️ 停止动画$i失败: $e');
          }
        }

        // 清除morph动画数据
        final childEntities = await _asset!.getChildEntities();
        for (final entity in childEntities) {
          try {
            await _asset!.clearMorphAnimationData(entity);
          } catch (e) {
            // 忽略清除失败的错误
          }
        }
      }

      setState(() {
        _isPlaying = false;
        _isIdlePlaying = false;
        _isCustomAnimationPlaying = false;
        _selectedAnimationIndex = -1;
        _isManuallyStopped = true; // 标记为手动停止
        _status = '✅ 所有动画已停止 - 角色静止';
      });

      if (kDebugMode) debugPrint('✅ 所有动画已停止，角色保持静止状态');
    } catch (e) {
      setState(() => _status = '❌ 停止动画失败: $e');
      if (kDebugMode) debugPrint('停止所有动画失败: $e');
    }
  }

  // 相机预设切换 - 自定义实现，针对xiaomeng模型优化
  Future<void> _applyCameraPreset(CameraPreset preset) async {
    if (_viewer == null) return;

    try {
      final camera = await _viewer!.getActiveCamera();

      // 根据预设设置不同的相机距离和高度
      double distance;
      double height;
      double targetHeight;

      switch (preset) {
        case CameraPreset.soloCloseUp: // 全身
          distance = 2.2;
          height = 1.5;
          targetHeight = 1.0;
          break;
        case CameraPreset.halfBody: // 半身
          distance = 1.6;
          height = 1.6;
          targetHeight = 1.5;
          break;
        case CameraPreset.bustCloseUp: // 特写
          distance = 0.6;
          height = 1.6;
          targetHeight = 1.8;
          break;
      }

      // 🎯 根据旋转角度计算相机位置（围绕人物旋转）
      final radians = _rotationAngle * (math.pi / 180.0);
      final x = distance * math.sin(radians);
      final z = distance * math.cos(radians);

      final position = Vector3(x, height, z);
      final target = Vector3(0.0, targetHeight, 0.0); // 始终看向人物中心

      // 应用相机设置
      await camera.lookAt(position, focus: target, up: Vector3(0, 1, 0));

      setState(() {
        _currentCameraPreset = preset;
      });

      if (kDebugMode) {
        debugPrint(
          '✅ 相机预设已切换: $preset, 旋转角度: ${_rotationAngle.toStringAsFixed(0)}°',
        );
        debugPrint(
          '   位置: ${position.x.toStringAsFixed(2)}, ${position.y.toStringAsFixed(2)}, ${position.z.toStringAsFixed(2)}',
        );
        debugPrint(
          '   目标: ${target.x.toStringAsFixed(2)}, ${target.y.toStringAsFixed(2)}, ${target.z.toStringAsFixed(2)}',
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ 相机预设切换失败: $e');
    }
  }

  // 🎯 人物旋转控制
  Future<void> _rotateCharacter(double angle) async {
    setState(() {
      _rotationAngle = angle;
    });

    // 重新应用当前相机预设，但使用新的旋转角度
    await _applyCameraPreset(_currentCameraPreset);
  }

  // 获取旋转角度的描述文字
  String _getRotationDescription(double angle) {
    if (angle >= -22.5 && angle <= 22.5) return '正面';
    if (angle > 22.5 && angle <= 67.5) return '右前';
    if (angle > 67.5 && angle <= 112.5) return '右侧';
    if (angle > 112.5 && angle <= 157.5) return '右后';
    if (angle > 157.5 || angle <= -157.5) return '背面';
    if (angle > -157.5 && angle <= -112.5) return '左后';
    if (angle > -112.5 && angle <= -67.5) return '左侧';
    if (angle > -67.5 && angle <= -22.5) return '左前';
    return '正面';
  }

  // 👁️ 初始化眨眼控制（找到Head_Mod实体）
  Future<void> _initializeBlinkControl() async {
    if (_asset == null) return;

    try {
      final childEntities = await _asset!.getChildEntities();
      for (final entity in childEntities) {
        final entityName = FilamentApp.instance!.getNameForEntity(entity);
        if (entityName == "Head_Mod") {
          _headEntity = entity;
          if (kDebugMode) {
            debugPrint('✅ 找到Head_Mod实体，眨眼控制已初始化');
          }
          break;
        }
      }

      if (_headEntity == null) {
        if (kDebugMode) debugPrint('❌ 未找到Head_Mod实体');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ 初始化眨眼控制失败: $e');
    }
  }

  // 👁️ 防抖动设置眨眼权重
  void _setBlinkWeights() {
    // 取消之前的定时器
    _blinkWeightTimer?.cancel();

    // 设置新的定时器，延迟执行
    _blinkWeightTimer = Timer(Duration(milliseconds: 100), () {
      _setBlinkWeightsImmediate();
    });
  }

  // 👁️ 立即设置眨眼权重（内部方法）
  Future<void> _setBlinkWeightsImmediate() async {
    if (_asset == null || _headEntity == null || _isSettingWeights) return;

    _isSettingWeights = true;

    try {
      final morphTargets = await _asset!.getMorphTargetNames(
        entity: _headEntity!,
      );
      final weights = List<double>.filled(morphTargets.length, 0.0);

      // 设置左眼权重 - 使用Head_Mod中的blendShape1.eyeBlinkLeft
      final leftBlinkIndex = morphTargets.indexOf('F.eyeBlinkLeft');
      if (leftBlinkIndex >= 0 && leftBlinkIndex < weights.length) {
        weights[leftBlinkIndex] = _leftEyeBlinkWeight.clamp(0.0, 1.0);
      }

      // 设置右眼权重 - 使用Head_Mod中的blendShape1.eyeBlinkRight
      final rightBlinkIndex = morphTargets.indexOf('F.eyeBlinkRight');
      if (rightBlinkIndex >= 0 && rightBlinkIndex < weights.length) {
        weights[rightBlinkIndex] = _rightEyeBlinkWeight.clamp(0.0, 1.0);
      }

      // 安全检查：确保morphTargets不为空
      if (morphTargets.isEmpty) {
        if (kDebugMode) debugPrint('⚠️ morphTargets为空，跳过权重设置');
        return;
      }

      await _asset!.setMorphTargetWeights(_headEntity!, weights);

      // 权重设置成功，不输出调试信息以保持控制台简洁
    } catch (e) {
      if (kDebugMode) debugPrint('❌ 设置眨眼权重失败: $e');
    } finally {
      _isSettingWeights = false;
    }
  }

  // 🎭 加载和管理动画
  Future<void> _loadAnimations() async {
    if (_asset == null) return;

    try {
      setState(() => _status = '检测动画...');

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

      // 查找idle动画
      _findIdleAnimation(animationNames);

      // 自动播放idle动画
      await _startIdleAnimation();

      // 🔍 分析idle动画中的眨眼数据
      await _analyzeIdleBlinkData();
    } catch (e) {
      if (kDebugMode) debugPrint('❌ 动画加载失败: $e');
    }
  }

  // 🔍 查找idle动画
  void _findIdleAnimation(List<String> animationNames) {
    _idleAnimationIndex = -1;

    // 查找包含idle关键词的动画
    for (int i = 0; i < animationNames.length; i++) {
      final animName = animationNames[i].toLowerCase();
      if (animName.contains('idle') ||
          animName.contains('wait') ||
          animName.contains('stand') ||
          animName.contains('breathing')) {
        _idleAnimationIndex = i;
        if (kDebugMode) {
          debugPrint('✅ 找到idle动画: ${animationNames[i]} (索引: $i)');
        }
        break;
      }
    }

    // 如果没找到idle动画，使用第一个动画
    if (_idleAnimationIndex == -1 && animationNames.isNotEmpty) {
      _idleAnimationIndex = 0;
      if (kDebugMode) {
        debugPrint('⚠️ 未找到idle动画，使用第一个动画: ${animationNames[0]}');
      }
    }
  }

  // 🎬 开始播放idle动画
  Future<void> _startIdleAnimation() async {
    if (_asset == null || _idleAnimationIndex == -1) return;

    try {
      if (kDebugMode) {
        debugPrint('🎬 开始播放idle动画...');
      }

      await _asset!.playGltfAnimation(_idleAnimationIndex, loop: true);
      _isIdlePlaying = true;

      if (kDebugMode) {
        debugPrint('✅ Idle动画播放中: ${_animations[_idleAnimationIndex]}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Idle动画播放失败: $e');
    }
  }

  // 🔄 恢复idle动画
  Future<void> _resumeIdleAnimation() async {
    // 如果用户手动停止了动画，不要自动恢复
    if (_isManuallyStopped) {
      if (kDebugMode) debugPrint('🛑 用户手动停止了动画，跳过自动恢复idle动画');
      return;
    }

    if (!_isIdlePlaying && !_isCustomAnimationPlaying) {
      await _startIdleAnimation();
    }
  }

  // 🔍 分析idle动画中的眨眼数据
  Future<void> _analyzeIdleBlinkData() async {
    if (_asset == null || _idleAnimationIndex == -1) return;

    try {
      if (kDebugMode) {
        debugPrint('🔍 开始分析idle动画中的眨眼数据...');
      }

      // 获取所有子实体
      final childEntities = await _asset!.getChildEntities();

      for (int i = 0; i < childEntities.length; i++) {
        final entity = childEntities[i];
        final entityName = FilamentApp.instance!.getNameForEntity(entity);

        // 重点检查Eyelashes_Mod实体（眨眼动画所在位置）
        if (entityName == "Eyelashes_Mod") {
          if (kDebugMode) {
            debugPrint('🎯 检查Eyelashes_Mod实体的眨眼动画数据...');
          }

          final morphTargets = await _asset!.getMorphTargetNames(
            entity: entity,
          );

          // 查找眨眼相关的morph targets
          final blinkTargets = <String>[];
          for (final morphName in morphTargets) {
            if (morphName.toLowerCase().contains('blink') ||
                morphName.toLowerCase().contains('eye')) {
              blinkTargets.add(morphName);
            }
          }

          if (blinkTargets.isNotEmpty) {
            if (kDebugMode) {
              debugPrint('👁️ 找到眨眼相关的morph targets:');
              for (int j = 0; j < blinkTargets.length; j++) {
                debugPrint('   [$j]: ${blinkTargets[j]}');
              }
            }

            // 尝试获取当前的morph target权重
            await _sampleBlinkWeights(entity, morphTargets, blinkTargets);
          } else {
            if (kDebugMode) {
              debugPrint('⚠️ 未找到眨眼相关的morph targets');
            }
          }
          break;
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ 分析眨眼数据失败: $e');
    }
  }

  // 👁️ 显示眨眼morph target信息
  Future<void> _sampleBlinkWeights(
    ThermionEntity entity,
    List<String> allMorphTargets,
    List<String> blinkTargets,
  ) async {
    if (kDebugMode) {
      debugPrint('👁️ Eyelashes_Mod眨眼Morph Target信息:');
      debugPrint('   📊 总共找到 ${blinkTargets.length} 个眨眼相关的morph targets:');

      for (int i = 0; i < blinkTargets.length; i++) {
        final blinkTarget = blinkTargets[i];
        final index = allMorphTargets.indexOf(blinkTarget);
        debugPrint('   [$i] $blinkTarget: 索引[$index]');
      }

      debugPrint('💡 这些morph targets会在idle动画中自动驱动眨眼效果');
      debugPrint('�️ 使用眨眼眨控制滑块可以手动调整眨眼效果');
    }
  }

  // 🎬 播放选中的动画
  Future<void> _playSelectedAnimation(int animationIndex) async {
    if (_asset == null ||
        animationIndex < 0 ||
        animationIndex >= _animations.length) {
      return;
    }

    try {
      // 停止当前播放的动画
      await _stopAllAnimations();

      // 播放选中的动画
      await _asset!.playGltfAnimation(animationIndex, loop: true);

      setState(() {
        _selectedAnimationIndex = animationIndex;
        _isCustomAnimationPlaying = true;
        _isIdlePlaying = false;
        _isManuallyStopped = false; // 重置手动停止标志
      });

      if (kDebugMode) {
        debugPrint('🎬 播放动画: ${_animations[animationIndex]}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ 播放动画失败: $e');
    }
  }

  // 🔄 重置到idle动画
  Future<void> _resetToIdle() async {
    await _stopAllAnimations();
    setState(() {
      _selectedAnimationIndex = -1;
      _isManuallyStopped = false; // 重置手动停止标志
    });
    await _startIdleAnimation();
  }

  // 🔍 分析BS数据范围，为优化提供依据
  void _analyzeBSDataRange() {
    if (_blendshapeData == null || _blendshapeData!.isEmpty) return;

    // 关键口型相关的索引
    const mouthIndices = {
      'jawOpen': 17,
      'mouthClose': 18,
      'mouthFunnel': 19,
      'mouthPucker': 20,
      'mouthLeft': 21,
      'mouthRight': 22,
      'mouthSmileLeft': 23,
      'mouthSmileRight': 24,
    };

    final stats = <String, Map<String, double>>{};

    for (final entry in mouthIndices.entries) {
      final name = entry.key;
      final index = entry.value;

      double min = double.infinity;
      double max = double.negativeInfinity;
      double sum = 0.0;
      int nonZeroCount = 0;

      for (final frame in _blendshapeData!) {
        if (index < frame.length) {
          final value = frame[index];
          min = math.min(min, value);
          max = math.max(max, value);
          sum += value;
          if (value > 0.001) nonZeroCount++;
        }
      }

      final avg = sum / _blendshapeData!.length;
      stats[name] = {
        'min': min,
        'max': max,
        'avg': avg,
        'nonZeroRatio': nonZeroCount / _blendshapeData!.length,
      };
    }

    if (kDebugMode) {
      debugPrint('📊 BS数据分析 (关键口型):');
      for (final entry in stats.entries) {
        final name = entry.key;
        final stat = entry.value;
        debugPrint(
          '   $name: min=${stat['min']!.toStringAsFixed(3)}, '
          'max=${stat['max']!.toStringAsFixed(3)}, '
          'avg=${stat['avg']!.toStringAsFixed(3)}, '
          'active=${(stat['nonZeroRatio']! * 100).toStringAsFixed(1)}%',
        );
      }
    }
  }

  // 🎯 动态权重优化函数
  double _optimizeWeight(String morphName, double originalWeight) {
    // 基于GPT-5建议的scaleFactor方案
    const morphScaleFactors = {
      // 口型相关 - 增强效果
      'F.jawOpen': 2.0, // 张嘴动作需要更明显
      'F.mouthClose': 1.5, // 闭嘴动作
      'F.mouthFunnel': 2.5, // 嘟嘴动作需要很明显
      'F.mouthPucker': 2.0, // 撅嘴动作
      'F.mouthLeft': 1.8, // 嘴部左右移动
      'F.mouthRight': 1.8,
      'F.mouthSmileLeft': 1.3, // 微笑动作适度增强
      'F.mouthSmileRight': 1.3,

      // 其他面部表情 - 保持自然
      'F.eyeBlinkLeft': 1.0, // 眨眼保持原始
      'F.eyeBlinkRight': 1.0,
      'F.browInnerUp': 1.2, // 眉毛动作轻微增强
      'F.browDownLeft': 1.2,
      'F.browDownRight': 1.2,
    };

    final scaleFactor = morphScaleFactors[morphName] ?? 1.0;
    final optimizedWeight = originalWeight * scaleFactor;

    // 限制在合理范围内，避免过度变形
    return optimizedWeight.clamp(0.0, 1.5);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: _buildAppBar(context), body: _buildBody());
  }

  // 🎯 应用栏
  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      title: const Text('全特科技写实数字人测试'),
      backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      elevation: 0,
    );
  }

  // 🏗️ 主体布局
  Widget _buildBody() {
    return Column(
      children: [_build3DViewSection(), _buildControlPanelSection()],
    );
  }

  // 🎬 3D视图区域
  Widget _build3DViewSection() {
    return Expanded(
      flex: 7, // 占70%空间
      child: Container(
        margin: const EdgeInsets.all(8),
        decoration: _build3DViewDecoration(),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: _build3DViewContent(),
        ),
      ),
    );
  }

  // 🎨 3D视图装饰
  BoxDecoration _build3DViewDecoration() {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.1),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  // 📺 3D视图内容
  Widget _build3DViewContent() {
    if (_viewer != null) {
      return ThermionWidget(viewer: _viewer!);
    }

    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(
            '正在初始化3D场景...',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // 🎛️ 控制面板区域
  Widget _buildControlPanelSection() {
    return Expanded(
      flex: 3, // 占30%空间
      child: Container(
        decoration: _buildControlPanelDecoration(),
        child: _buildControlPanelContent(),
      ),
    );
  }

  // 🎨 控制面板装饰
  BoxDecoration _buildControlPanelDecoration() {
    return BoxDecoration(
      color: Colors.grey[50],
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(20),
        topRight: Radius.circular(20),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 10,
          offset: const Offset(0, -2),
        ),
      ],
    );
  }

  // 📋 控制面板内容
  Widget _buildControlPanelContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部指示器
            _buildPanelIndicator(),

            const SizedBox(height: 8),

            // 播放控制区
            _buildPlayControlSection(),

            const SizedBox(height: 12),

            // 视角控制区
            _buildViewControlSection(),

            const SizedBox(height: 8),

            // 眨眼控制区
            _buildBlinkControlSection(),

            const SizedBox(height: 8),

            // 设置区
            _buildSettingsSection(),

            // 底部安全区域
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // 📍 面板指示器
  Widget _buildPanelIndicator() {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildRotationButton(String label, double angle) {
    final isSelected = (_rotationAngle - angle).abs() < 5.0; // 5度容差
    return ElevatedButton(
      onPressed: _isInitialized ? () => _rotateCharacter(angle) : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? Colors.orange : null,
        foregroundColor: isSelected ? Colors.white : null,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: const Size(50, 32),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }

  // 🎮 播放控制区域
  Widget _buildPlayControlSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // 状态显示
          Column(
            children: [
              Text(
                _status,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              if (_isIdlePlaying && _idleAnimationIndex >= 0)
                Text(
                  '🎭 ${_animations.isNotEmpty ? _animations[_idleAnimationIndex] : "Idle动画"}',
                  style: const TextStyle(fontSize: 11, color: Colors.blue),
                  textAlign: TextAlign.center,
                ),
            ],
          ),

          const SizedBox(height: 8),

          // 播放控制按钮
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isInitialized && !_isPlaying
                      ? _playLipSync
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[400],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('播放', style: TextStyle(fontSize: 13)),
                ),
              ),

              const SizedBox(width: 8),

              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isPlaying ? _stopLipSync : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[400],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  icon: const Icon(Icons.stop, size: 18),
                  label: const Text('停止', style: TextStyle(fontSize: 13)),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // 停止动画按钮
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed:
                      (_isInitialized &&
                          (_isPlaying ||
                              _isIdlePlaying ||
                              _isCustomAnimationPlaying))
                      ? () {
                          if (kDebugMode) debugPrint('🛑 停止动画按钮被点击');
                          _stopAllAnimations();
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[600],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  icon: const Icon(Icons.pause, size: 18),
                  label: const Text('停止动画', style: TextStyle(fontSize: 13)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 🎥 视角控制区域
  Widget _buildViewControlSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 相机视角
          Row(
            children: [
              const Icon(Icons.camera_alt, size: 16, color: Colors.blue),
              const SizedBox(width: 4),
              const Text(
                '视角',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              // 紧凑的相机按钮
              ..._buildCompactCameraButtons(),
            ],
          ),

          const SizedBox(height: 8),

          // 人物旋转
          Row(
            children: [
              const Icon(Icons.rotate_right, size: 16, color: Colors.orange),
              const SizedBox(width: 4),
              const Text(
                '旋转',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                _getRotationDescription(_rotationAngle),
                style: const TextStyle(fontSize: 12, color: Colors.orange),
              ),
            ],
          ),

          const SizedBox(height: 4),

          // 紧凑的旋转滑块
          SizedBox(
            height: 30,
            child: Slider(
              value: _rotationAngle,
              min: -180.0,
              max: 180.0,
              divisions: 36, // 减少刻度，每10度一个
              onChanged: _isInitialized ? _rotateCharacter : null,
              activeColor: Colors.orange,
            ),
          ),

          // 快捷旋转按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildRotationButton('左', -90.0),
              _buildRotationButton('前', 0.0),
              _buildRotationButton('右', 90.0),
              _buildRotationButton('后', 180.0),
            ],
          ),

          const SizedBox(height: 12),

          // 🎭 动画选择区域
          _buildAnimationSection(),
        ],
      ),
    );
  }

  // 紧凑的相机按钮
  List<Widget> _buildCompactCameraButtons() {
    final presets = [
      (CameraPreset.soloCloseUp, '全'),
      (CameraPreset.halfBody, '半'),
      (CameraPreset.bustCloseUp, '特'),
    ];

    return presets.map((preset) {
      final isSelected = _currentCameraPreset == preset.$1;
      return Container(
        margin: const EdgeInsets.only(left: 4),
        child: InkWell(
          onTap: _isInitialized ? () => _applyCameraPreset(preset.$1) : null,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isSelected ? Colors.blue : Colors.grey[200],
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              preset.$2,
              style: TextStyle(
                fontSize: 11,
                color: isSelected ? Colors.white : Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  // 🎭 动画选择区域
  Widget _buildAnimationSection() {
    if (_animations.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 动画标题和状态
        Row(
          children: [
            const Icon(Icons.animation, size: 16, color: Colors.purple),
            const SizedBox(width: 4),
            const Text(
              '动画',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            // 🎯 固定宽度的状态显示，避免布局跳动
            SizedBox(
              width: 50, // 固定宽度
              child: Text(
                _selectedAnimationIndex >= 0
                    ? _getCustomAnimationName(_selectedAnimationIndex)
                    : _isIdlePlaying
                    ? 'Idle00'
                    : '',
                style: TextStyle(
                  fontSize: 11,
                  color: _selectedAnimationIndex >= 0
                      ? Colors.purple
                      : Colors.blue,
                ),
                textAlign: TextAlign.end, // 右对齐
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),

        // 动画选择按钮 - 从第二个动画开始显示（第一个是默认idle）
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _animations.length > 1
              ? _animations.asMap().entries.skip(1).map((entry) {
                  final index = entry.key;
                  final customName = _getCustomAnimationName(index);
                  final isSelected = _selectedAnimationIndex == index;

                  return _buildAnimationButton(customName, index, isSelected);
                }).toList()
              : [],
        ),
      ],
    );
  }

  // 🎬 构建动画按钮
  Widget _buildAnimationButton(
    String label,
    int animationIndex,
    bool isSelected,
  ) {
    return InkWell(
      onTap: _isInitialized && !_isPlaying
          ? () {
              if (animationIndex == -1) {
                _resetToIdle();
              } else {
                _playSelectedAnimation(animationIndex);
              }
            }
          : null,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        constraints: const BoxConstraints(minWidth: 45), // 🎯 设置最小宽度，保持一致性
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? Colors.purple : Colors.grey[200],
          borderRadius: BorderRadius.circular(6),
          border: isSelected
              ? Border.all(color: Colors.purple, width: 1)
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isSelected ? Colors.white : Colors.grey[700],
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
          textAlign: TextAlign.center, // 🎯 居中对齐
        ),
      ),
    );
  }

  // 📝 获取简短的动画名称
  // 📝 获取自定义动画名称
  String _getCustomAnimationName(int index) {
    // 根据索引位置返回自定义名称
    switch (index) {
      case 1:
        return 'Talk01'; // 修正：第二个动画是Talk01
      case 2:
        return 'Talk02';
      case 3:
        return 'Talk03';
      case 4:
        return 'Talk04';
      default:
        // 如果有更多动画，继续编号
        if (index > 4) {
          return 'Talk${(index - 3).toString().padLeft(2, '0')}';
        }
        return 'Anim$index';
    }
  }

  // 👁️ 眨眼控制区域
  Widget _buildBlinkControlSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Row(
            children: [
              const Icon(Icons.visibility, size: 16, color: Colors.orange),
              const SizedBox(width: 8),
              const Text(
                '眨眼控制',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                '范围: 0.0 ~ 1.0',
                style: TextStyle(fontSize: 10, color: Colors.grey[600]),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // 左眼滑块
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    '左眼',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  const Spacer(),
                  Text(
                    _leftEyeBlinkWeight.toStringAsFixed(2),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.blue[700],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Slider(
                value: _leftEyeBlinkWeight,
                min: 0.0,
                max: 1.0,
                divisions: 20, // 0.05 精度
                onChanged: _isInitialized
                    ? (value) {
                        setState(() {
                          _leftEyeBlinkWeight = value;
                        });
                        _setBlinkWeights();
                      }
                    : null,
                activeColor: Colors.blue[400],
                inactiveColor: Colors.grey[300],
              ),
            ],
          ),

          const SizedBox(height: 8),

          // 右眼滑块
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    '右眼',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  const Spacer(),
                  Text(
                    _rightEyeBlinkWeight.toStringAsFixed(2),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.green[700],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Slider(
                value: _rightEyeBlinkWeight,
                min: 0.0,
                max: 1.0,
                divisions: 20, // 0.05 精度
                onChanged: _isInitialized
                    ? (value) {
                        setState(() {
                          _rightEyeBlinkWeight = value;
                        });
                        _setBlinkWeights();
                      }
                    : null,
                activeColor: Colors.green[400],
                inactiveColor: Colors.grey[300],
              ),
            ],
          ),

          const SizedBox(height: 8),

          // 快捷按钮
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _isInitialized
                      ? () {
                          setState(() {
                            _leftEyeBlinkWeight = 0.0;
                            _rightEyeBlinkWeight = 0.0;
                          });
                          _setBlinkWeights();
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[400],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                  child: const Text('睁眼', style: TextStyle(fontSize: 11)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isInitialized
                      ? () {
                          setState(() {
                            _leftEyeBlinkWeight = 1.0;
                            _rightEyeBlinkWeight = 1.0;
                          });
                          _setBlinkWeights();
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange[400],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                  child: const Text('闭眼', style: TextStyle(fontSize: 11)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ⚙️ 设置区域
  Widget _buildSettingsSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Row(
            children: [
              const Icon(Icons.settings, size: 16, color: Colors.grey),
              const SizedBox(width: 8),
              const Text(
                '设置',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // 口型优化开关
          Row(
            children: [
              const Icon(Icons.tune, size: 14, color: Colors.grey),
              const SizedBox(width: 8),
              const Text(
                '口型优化',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              widgets.Transform.scale(
                scale: 0.8,
                child: Switch(
                  value: _enableOptimization,
                  onChanged: (value) {
                    setState(() {
                      _enableOptimization = value;
                    });
                  },
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
