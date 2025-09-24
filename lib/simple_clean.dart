import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:thermion_flutter/thermion_flutter.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:animation_tools_dart/animation_tools_dart.dart';
import 'camera_presets.dart';

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

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _completeSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      setState(() => _status = '创建3D场景...');

      // 创建3D查看器
      _viewer = await ThermionFlutterPlugin.createViewer();
      await Future.delayed(Duration(milliseconds: 300));
      await _viewer!.setRendering(true);

      // 设置环境
      await _viewer!.loadSkybox(
        "assets/environments/studio_small_env_skybox.ktx",
      );
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
        if (kDebugMode) {
          debugPrint('⚠️ IBL 旋转失败: $e');
        }
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
      _asset = await _viewer!.loadGltf("assets/models/xiaomeng_0923_3.glb");

      // 设置相机预设
      await _applyCameraPreset(_currentCameraPreset);

      setState(() => _status = '加载口型数据...');

      // 加载BS数据
      await _loadBlendshapeData();

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
      _completeSubscription = _audioPlayer.onPlayerComplete.listen((_) {
        setState(() {
          _isPlaying = false;
          _status = '✅ 播放完成';
        });
      });
    } catch (e) {
      setState(() {
        _isPlaying = false;
        _status = '❌ 播放失败: $e';
      });
      if (kDebugMode) debugPrint('播放失败: $e');
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
            // 直接使用 bs.json 中的原始数据，不做任何限制或优化
            flatData[baseIndex + i] = weight;
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

      // 重置所有morph targets到默认状态
      if (_asset != null) {
        try {
          final childEntities = await _asset!.getChildEntities();
          for (int i = 0; i < childEntities.length; i++) {
            final entity = childEntities[i];
            final entityName = FilamentApp.instance!.getNameForEntity(entity);
            if (entityName == "Head_Mod") {
              final morphTargets = await _asset!.getMorphTargetNames(
                entity: entity,
              );
              final resetWeights = List<double>.filled(
                morphTargets.length,
                0.0,
              );
              await _asset!.setMorphTargetWeights(entity, resetWeights);
              break;
            }
          }
          if (kDebugMode) debugPrint('✅ Morph targets已重置');
        } catch (e) {
          if (kDebugMode) debugPrint('⚠️ Morph targets重置失败: $e');
        }
      }

      setState(() => _status = '✅ 已停止');
    } catch (e) {
      setState(() => _status = '❌ 停止失败: $e');
      if (kDebugMode) debugPrint('停止失败: $e');
    }
  }

  // 相机预设切换 - 自定义实现，针对xiaomeng模型优化
  Future<void> _applyCameraPreset(CameraPreset preset) async {
    if (_viewer == null) return;

    try {
      final camera = await _viewer!.getActiveCamera();

      // 根据预设设置不同的相机位置 - 针对xiaomeng模型调整高度
      Vector3 position;
      Vector3 target;

      switch (preset) {
        case CameraPreset.soloCloseUp: // 全身
          position = Vector3(0.0, 1.5, 2.2); // 平视，合理距离
          target = Vector3(0.0, 1.0, 0.0); // 看向模型中心
          break;
        case CameraPreset.halfBody: // 半身
          position = Vector3(0.0, 1.6, 1.6); // 提高相机高度，拉近距离
          target = Vector3(0.0, 1.5, 0.0); // 看向胸部中心
          break;
        case CameraPreset.bustCloseUp: // 特写
          position = Vector3(0.0, 1.7, 0.6); // 特写距离
          target = Vector3(0.0, 1.7, 0.0); // 看向肩部/颈部
          break;
      }

      // 应用相机设置
      await camera.lookAt(position, focus: target, up: Vector3(0, 1, 0));

      setState(() {
        _currentCameraPreset = preset;
      });

      if (kDebugMode) {
        debugPrint('✅ 相机预设已切换: $preset');
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

  String _getCameraPresetName(CameraPreset preset) {
    switch (preset) {
      case CameraPreset.soloCloseUp:
        return '全身';
      case CameraPreset.halfBody:
        return '半身';
      case CameraPreset.bustCloseUp:
        return '特写';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('全特科技写实数字人测试'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          // 3D视图
          Expanded(
            child: _viewer != null
                ? ThermionWidget(viewer: _viewer!)
                : const Center(child: CircularProgressIndicator()),
          ),

          // 控制面板
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // 状态显示
                Text(
                  _status,
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 16),

                // 播放控制
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _isInitialized && !_isPlaying
                          ? _playLipSync
                          : null,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('播放'),
                    ),
                    ElevatedButton.icon(
                      onPressed: _isPlaying ? _stopLipSync : null,
                      icon: const Icon(Icons.stop),
                      label: const Text('停止'),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // 相机视角切换
                const Text(
                  '相机视角',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildCameraButton(CameraPreset.soloCloseUp),
                    _buildCameraButton(CameraPreset.halfBody),
                    _buildCameraButton(CameraPreset.bustCloseUp),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraButton(CameraPreset preset) {
    final isSelected = _currentCameraPreset == preset;
    return ElevatedButton(
      onPressed: _isInitialized ? () => _applyCameraPreset(preset) : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? Theme.of(context).primaryColor : null,
        foregroundColor: isSelected ? Colors.white : null,
      ),
      child: Text(_getCameraPresetName(preset)),
    );
  }
}
