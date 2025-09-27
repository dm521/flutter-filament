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
import 'blink_animation_controller.dart';
import 'blink_config.dart';
import 'blink_test.dart';

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
  final bool _enableOptimization = false; // 默认关闭，因为原始数据已经比较自然

  // 眨眼权重控制
  double _leftEyeBlinkWeight = 0.0;
  double _rightEyeBlinkWeight = 0.0;
  ThermionEntity? _headEntity;

  // 防抖动控制
  Timer? _blinkWeightTimer;
  bool _isSettingWeights = false;

  // 自动眨眼动画控制器
  BlinkAnimationController? _blinkController;
  bool _autoBlinkEnabled = true;
  String _currentBlinkPreset = '自然';

  // 人物旋转控制
  double _rotationAngle = 0.0; // 0=正面, 90=右侧, 180=背面, 270=左侧

  // 动画系统
  final List<String> _animations = [];
  int _idleAnimationIndex = -1;
  bool _isIdlePlaying = false;
  int _selectedAnimationIndex = -1;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _completeSubscription?.cancel();
    _audioPlayer.dispose();
    _blinkWeightTimer?.cancel();
    _blinkController?.dispose();
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
      _asset = await _viewer!.loadGltf("assets/models/xiaomeng_0927.glb");

      // 检测和设置动画
      await _loadAnimations();

      // 设置相机预设
      await _applyCameraPreset(_currentCameraPreset);

      setState(() => _status = '加载口型数据...');

      // 加载BS数据
      await _loadBlendshapeData();

      // 初始化眨眼控制
      await _initializeBlinkControl();

      // 初始化自动眨眼控制器
      _initializeBlinkController();

      // 运行眨眼动画测试（仅在调试模式下）
      if (kDebugMode) {
        BlinkAnimationTest.runAllTests();
      }

      // 直接启动自动眨眼（不依赖idle动画）
      if (_autoBlinkEnabled && _blinkController != null) {
        _blinkController!.startAutoBlink();
        if (kDebugMode) debugPrint('🎯 独立启动自动眨眼动画');
      }

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
        _status = '🎬 播放中...';
      });

      // 暂停当前动画，避免冲突
      await _pauseCurrentAnimations();

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

        // 恢复之前的动画状态
        await _resumePreviousAnimation();
      });
    } catch (e) {
      setState(() {
        _isPlaying = false;
        _status = '❌ 播放失败: $e';
      });
      if (kDebugMode) debugPrint('播放失败: $e');

      // 发生错误时也要恢复之前的动画状态
      await _resumePreviousAnimation();
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

      // 恢复之前的动画状态
      await _resumePreviousAnimation();
    } catch (e) {
      setState(() => _status = '❌ 停止失败: $e');
      if (kDebugMode) debugPrint('停止失败: $e');

      // 即使停止失败也要尝试恢复之前的动画状态
      await _resumePreviousAnimation();
    }
  }

  // 暂停当前动画（不清除状态）
  Future<void> _pauseCurrentAnimations() async {
    if (_asset == null) return;
    try {
      // 停止所有glTF动画
      for (int i = 0; i < _animations.length; i++) {
        try {
          await _asset!.stopGltfAnimation(i);
        } catch (e) {
          if (kDebugMode) debugPrint('⚠️ 停止动画$i失败: $e');
        }
      }
      
      // 暂停自动眨眼（播放口型动画时）
      if (_blinkController != null) {
        _blinkController!.stopAutoBlink();
      }
      
    } catch (e) {
      if (kDebugMode) debugPrint('暂停动画失败: $e');
    }
  }

  // 恢复之前的动画状态
  Future<void> _resumePreviousAnimation() async {
    if (_selectedAnimationIndex >= 0) {
      await _playSelectedAnimation(_selectedAnimationIndex);
    } else {
      await _resumeIdleAnimation();
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

  String _getRotationDescription(double angle) {
    const descriptions = ['正面', '右前', '右侧', '右后', '背面', '左后', '左侧', '左前'];
    final index = ((angle + 202.5) % 360 / 45).floor() % 8;
    return descriptions[index];
  }

  Future<void> _initializeBlinkControl() async {
    if (_asset == null) return;
    try {
      final entities = await _asset!.getChildEntities();
      _headEntity = entities.firstWhere(
        (e) => FilamentApp.instance!.getNameForEntity(e) == "Head_Mod",
        orElse: () => throw Exception('Head_Mod not found'),
      );
      if (kDebugMode) debugPrint('✅ 找到Head_Mod实体');
    } catch (e) {
      if (kDebugMode) debugPrint('❌ 初始化眨眼控制失败: $e');
    }
  }

  /// 初始化自动眨眼控制器
  void _initializeBlinkController() {
    _blinkController = BlinkAnimationController(
      onBlinkWeightChanged: (leftWeight, rightWeight) {
        // 只有在自动眨眼启用时才更新权重
        if (_autoBlinkEnabled) {
          if (kDebugMode && (leftWeight > 0.01 || rightWeight > 0.01)) {
            debugPrint('👁️ 眨眼权重更新: 左=${leftWeight.toStringAsFixed(3)}, 右=${rightWeight.toStringAsFixed(3)}');
          }
          setState(() {
            _leftEyeBlinkWeight = leftWeight;
            _rightEyeBlinkWeight = rightWeight;
          });
          _setBlinkWeightsImmediate();
        }
      },
    );

    if (kDebugMode) {
      debugPrint('✅ 自动眨眼控制器已初始化');
    }
  }

  /// 切换自动眨眼
  void _toggleAutoBlink() {
    if (_blinkController == null) return;

    setState(() {
      _autoBlinkEnabled = !_autoBlinkEnabled;
    });

    if (_autoBlinkEnabled) {
      _blinkController!.startAutoBlink();
      if (kDebugMode) debugPrint('👁️ 自动眨眼已启用');
    } else {
      _blinkController!.stopAutoBlink();
      // 重置眨眼权重
      setState(() {
        _leftEyeBlinkWeight = 0.0;
        _rightEyeBlinkWeight = 0.0;
      });
      _setBlinkWeightsImmediate();
      if (kDebugMode) debugPrint('👁️ 自动眨眼已禁用');
    }
  }

  /// 手动触发眨眼
  void _triggerManualBlink() {
    if (_blinkController == null) {
      if (kDebugMode) debugPrint('⚠️ 眨眼控制器未初始化');
      return;
    }
    
    if (!_autoBlinkEnabled) {
      if (kDebugMode) debugPrint('⚠️ 自动眨眼未启用，无法手动触发');
      return;
    }
    
    if (kDebugMode) debugPrint('🎯 手动触发眨眼');
    _blinkController!.triggerBlink();
  }

  /// 测试眨眼功能（直接设置权重）
  void _testBlinkWeights() {
    if (kDebugMode) debugPrint('🧪 测试眨眼权重设置');
    
    // 测试闭眼
    setState(() {
      _leftEyeBlinkWeight = 1.0;
      _rightEyeBlinkWeight = 1.0;
    });
    _setBlinkWeightsImmediate();
    
    // 2秒后睁眼
    Timer(Duration(seconds: 2), () {
      setState(() {
        _leftEyeBlinkWeight = 0.0;
        _rightEyeBlinkWeight = 0.0;
      });
      _setBlinkWeightsImmediate();
      if (kDebugMode) debugPrint('🧪 眨眼权重测试完成');
    });
  }

  /// 切换眨眼预设
  void _changeBlinkPreset(String presetName) {
    if (_blinkController == null) return;

    final presets = BlinkPresets.getAllPresets();
    final config = presets[presetName];
    
    if (config != null) {
      _blinkController!.updateConfig(config);
      setState(() {
        _currentBlinkPreset = presetName;
      });
      
      if (kDebugMode) {
        debugPrint('👁️ 眨眼预设已切换为: $presetName');
      }
    }
  }

  void _setBlinkWeights() {
    _blinkWeightTimer?.cancel();
    _blinkWeightTimer = Timer(Duration(milliseconds: 100), _setBlinkWeightsImmediate);
  }

  Future<void> _setBlinkWeightsImmediate() async {
    if (_asset == null || _headEntity == null || _isSettingWeights) return;
    _isSettingWeights = true;
    try {
      final morphTargets = await _asset!.getMorphTargetNames(entity: _headEntity!);
      if (morphTargets.isEmpty) {
        if (kDebugMode) debugPrint('⚠️ Head_Mod没有morph targets');
        return;
      }
      
      final weights = List<double>.filled(morphTargets.length, 0.0);
      final blinkTargets = {'F.eyeBlinkLeft': _leftEyeBlinkWeight, 'F.eyeBlinkRight': _rightEyeBlinkWeight};
      
      bool hasBlinkTargets = false;
      blinkTargets.forEach((name, weight) {
        final index = morphTargets.indexOf(name);
        if (index >= 0) {
          weights[index] = weight.clamp(0.0, 1.0);
          hasBlinkTargets = true;
          if (kDebugMode && weight > 0.01) {
            debugPrint('👁️ 设置 $name = ${weight.toStringAsFixed(3)}');
          }
        }
      });
      
      if (!hasBlinkTargets && kDebugMode) {
        debugPrint('⚠️ 未找到眨眼相关的morph targets: F.eyeBlinkLeft, F.eyeBlinkRight');
        debugPrint('   可用的morph targets: ${morphTargets.take(10).join(", ")}${morphTargets.length > 10 ? "..." : ""}');
      }
      
      await _asset!.setMorphTargetWeights(_headEntity!, weights);
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

  void _findIdleAnimation(List<String> animationNames) {
    const idleKeywords = ['idle', 'wait', 'stand', 'breathing'];
    _idleAnimationIndex = animationNames.indexWhere(
      (name) => idleKeywords.any((keyword) => name.toLowerCase().contains(keyword))
    );
    if (_idleAnimationIndex == -1 && animationNames.isNotEmpty) {
      _idleAnimationIndex = 0;
    }
    if (kDebugMode && _idleAnimationIndex >= 0) {
      debugPrint('✅ 找到idle动画: ${animationNames[_idleAnimationIndex]} (索引: $_idleAnimationIndex)');
    }
  }

  Future<void> _startIdleAnimation() async {
    if (kDebugMode) {
      debugPrint('🎭 尝试启动idle动画...');
      debugPrint('   _asset: ${_asset != null ? "已加载" : "未加载"}');
      debugPrint('   _idleAnimationIndex: $_idleAnimationIndex');
    }
    
    if (_asset == null || _idleAnimationIndex == -1) {
      if (kDebugMode) debugPrint('❌ 无法启动idle动画：资源或索引无效');
      return;
    }
    
    try {
      await _asset!.playGltfAnimation(_idleAnimationIndex, loop: true);
      _isIdlePlaying = true;
      
      if (kDebugMode) debugPrint('✅ Idle动画已启动');
      
      // 启动自动眨眼（如果启用）
      if (kDebugMode) {
        debugPrint('🔍 检查眨眼启动条件:');
        debugPrint('   _autoBlinkEnabled: $_autoBlinkEnabled');
        debugPrint('   _blinkController: ${_blinkController != null ? "已初始化" : "未初始化"}');
      }
      
      if (_autoBlinkEnabled && _blinkController != null) {
        _blinkController!.startAutoBlink();
        if (kDebugMode) debugPrint('✅ 自动眨眼已启动');
      } else {
        if (kDebugMode) debugPrint('⚠️ 自动眨眼未启动：条件不满足');
      }
      
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Idle动画播放失败: $e');
    }
  }

  Future<void> _resumeIdleAnimation() async {
    if (!_isIdlePlaying && _selectedAnimationIndex == -1) {
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

  Future<void> _playSelectedAnimation(int animationIndex) async {
    if (_asset == null || animationIndex < 0 || animationIndex >= _animations.length) return;
    try {
      await _pauseCurrentAnimations();
      await _asset!.playGltfAnimation(animationIndex, loop: true);
      setState(() {
        _selectedAnimationIndex = animationIndex;
        _isIdlePlaying = false;
      });
      
      // 选择动画时也启动自动眨眼
      if (_autoBlinkEnabled && _blinkController != null) {
        _blinkController!.startAutoBlink();
      }
      
      if (kDebugMode) debugPrint('🎬 播放动画: ${_animations[animationIndex]}');
    } catch (e) {
      if (kDebugMode) debugPrint('❌ 播放动画失败: $e');
    }
  }

  Future<void> _resetToIdle() async {
    await _pauseCurrentAnimations();
    setState(() => _selectedAnimationIndex = -1);
    await _startIdleAnimation();
  }

  void _analyzeBSDataRange() {
    if (_blendshapeData == null || _blendshapeData!.isEmpty || !kDebugMode) return;
    const mouthIndices = {17: 'jawOpen', 18: 'mouthClose', 19: 'mouthFunnel', 20: 'mouthPucker'};
    debugPrint('📊 BS数据分析 (关键口型):');
    
    mouthIndices.forEach((index, name) {
      final values = _blendshapeData!.where((frame) => index < frame.length).map((frame) => frame[index]);
      if (values.isNotEmpty) {
        final min = values.reduce(math.min);
        final max = values.reduce(math.max);
        final avg = values.reduce((a, b) => a + b) / values.length;
        debugPrint('   $name: min=${min.toStringAsFixed(3)}, max=${max.toStringAsFixed(3)}, avg=${avg.toStringAsFixed(3)}');
      }
    });
  }

  double _optimizeWeight(String morphName, double originalWeight) {
    const morphScaleFactors = {
      'F.jawOpen': 2.0, 'F.mouthClose': 1.5, 'F.mouthFunnel': 2.5, 'F.mouthPucker': 2.0,
      'F.mouthLeft': 1.8, 'F.mouthRight': 1.8, 'F.mouthSmileLeft': 1.3, 'F.mouthSmileRight': 1.3,
      'F.browInnerUp': 1.2, 'F.browDownLeft': 1.2, 'F.browDownRight': 1.2,
    };
    return (originalWeight * (morphScaleFactors[morphName] ?? 1.0)).clamp(0.0, 1.5);
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

            // 动作控制区
            _buildActionControlSection(),

            const SizedBox(height: 8),

            // 眨眼控制区
            _buildBlinkControlSection(),

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

  // 🎭 动作控制区域
  Widget _buildActionControlSection() {
    // 总是显示动作控制区域，即使动画列表为空

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
          // 标题和状态
          Row(
            children: [
              const Icon(Icons.directions_run, size: 16, color: Colors.purple),
              const SizedBox(width: 4),
              const Text('动作', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _selectedAnimationIndex >= 0 ? Colors.purple[50] : Colors.blue[50],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _selectedAnimationIndex >= 0 ? _getActionName(_selectedAnimationIndex) : 'Idle',
                  style: TextStyle(
                    fontSize: 10,
                    color: _selectedAnimationIndex >= 0 ? Colors.purple : Colors.blue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 动作按钮
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildActionButton('Idle', -1, _selectedAnimationIndex == -1 && _isIdlePlaying),
              if (_animations.isNotEmpty)
                ..._getTalkAnimations().map((entry) => 
                  _buildActionButton(entry.key, entry.value, _selectedAnimationIndex == entry.value)
                )
              else
                _buildActionButton('加载中...', -2, false),
            ],
          ),
        ],
      ),
    );
  }

  // 获取Talk动画列表
  List<MapEntry<String, int>> _getTalkAnimations() {
    final talkAnimations = <MapEntry<String, int>>[];
    for (int i = 1; i < _animations.length && i <= 4; i++) {
      talkAnimations.add(MapEntry('Talk${i.toString().padLeft(2, '0')}', i));
    }
    return talkAnimations;
  }

  // 获取动作名称
  String _getActionName(int index) {
    if (index >= 1 && index <= 4) return 'Talk${index.toString().padLeft(2, '0')}';
    return 'Talk${index.toString().padLeft(2, '0')}';
  }

  // 构建动作按钮
  Widget _buildActionButton(String label, int actionIndex, bool isSelected) {
    return InkWell(
      onTap: _isInitialized && !_isPlaying
          ? () => actionIndex == -1 ? _resetToIdle() : _playSelectedAnimation(actionIndex)
          : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: const BoxConstraints(minWidth: 60),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.purple : Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.purple : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isSelected ? Colors.white : Colors.grey[700],
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
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
          // 标题和自动眨眼开关
          Row(
            children: [
              const Icon(Icons.visibility, size: 16, color: Colors.orange),
              const SizedBox(width: 8),
              const Text(
                '眨眼控制',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              // 自动眨眼状态指示
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _autoBlinkEnabled ? Colors.green[50] : Colors.grey[100],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _autoBlinkEnabled ? '自动' : '手动',
                  style: TextStyle(
                    fontSize: 10,
                    color: _autoBlinkEnabled ? Colors.green[700] : Colors.grey[600],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // 自动眨眼控制行
          Row(
            children: [
              const Text(
                '自动眨眼',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              widgets.Transform.scale(
                scale: 0.8,
                child: Switch(
                  value: _autoBlinkEnabled,
                  onChanged: _isInitialized ? (value) => _toggleAutoBlink() : null,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  activeTrackColor: Colors.orange,
                ),
              ),
              const SizedBox(width: 8),
              // 手动触发眨眼按钮
              ElevatedButton(
                onPressed: _isInitialized && _autoBlinkEnabled ? _triggerManualBlink : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange[400],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: const Size(50, 28),
                ),
                child: const Text('眨眼', style: TextStyle(fontSize: 10)),
              ),
              const SizedBox(width: 4),
              // 测试眨眼权重按钮
              ElevatedButton(
                onPressed: _isInitialized ? _testBlinkWeights : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[400],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: const Size(50, 28),
                ),
                child: const Text('测试', style: TextStyle(fontSize: 10)),
              ),
            ],
          ),

          // 眨眼预设选择（仅在自动模式下显示）
          if (_autoBlinkEnabled) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Text(
                  '预设',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: widgets.Axis.horizontal,
                    child: Row(
                      children: BlinkPresets.getAllPresets().keys.map((presetName) {
                        final isSelected = _currentBlinkPreset == presetName;
                        return Container(
                          margin: const EdgeInsets.only(right: 6),
                          child: InkWell(
                            onTap: _isInitialized ? () => _changeBlinkPreset(presetName) : null,
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isSelected ? Colors.orange : Colors.grey[200],
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                presetName,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isSelected ? Colors.white : Colors.grey[700],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ],

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
                onChanged: _isInitialized && !_autoBlinkEnabled
                    ? (value) {
                        setState(() {
                          _leftEyeBlinkWeight = value;
                        });
                        _setBlinkWeights();
                      }
                    : null,
                activeColor: _autoBlinkEnabled ? Colors.grey[400] : Colors.blue[400],
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
                onChanged: _isInitialized && !_autoBlinkEnabled
                    ? (value) {
                        setState(() {
                          _rightEyeBlinkWeight = value;
                        });
                        _setBlinkWeights();
                      }
                    : null,
                activeColor: _autoBlinkEnabled ? Colors.grey[400] : Colors.green[400],
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
                  onPressed: _isInitialized && !_autoBlinkEnabled
                      ? () {
                          setState(() {
                            _leftEyeBlinkWeight = 0.0;
                            _rightEyeBlinkWeight = 0.0;
                          });
                          _setBlinkWeights();
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _autoBlinkEnabled ? Colors.grey[300] : Colors.grey[400],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                  child: const Text('睁眼', style: TextStyle(fontSize: 11)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isInitialized && !_autoBlinkEnabled
                      ? () {
                          setState(() {
                            _leftEyeBlinkWeight = 1.0;
                            _rightEyeBlinkWeight = 1.0;
                          });
                          _setBlinkWeights();
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _autoBlinkEnabled ? Colors.grey[300] : Colors.orange[400],
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


}
