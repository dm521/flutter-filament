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

/// 🎯 口型同步播放系统
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

  // ===== 实体引用 =====
  ThermionEntity? _headEntity;

  // ===== 音频和BS数据系统 =====
  List<List<double>>? _blendshapeData;
  bool _isBlendshapeLoaded = false;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isLipSyncPlaying = false;
  StreamSubscription<void>? _completeSubscription;

  // ===== 动画系统 =====
  final List<String> _animations = [];
  int _talk01AnimationIndex = -1;  /
/ ===== BS数据优化系数 =====
  static const double _jawOpenEnhanceFactor = 1.5;
  static const double _mouthShapeEnhanceFactor = 1.2;
  static const double _smoothingFactor = 0.2;
  static const double _maxMorphWeight = 0.8;

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
  }  /// 初
始化系统
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
  }  //
/ 设置环境
  Future<void> _setupEnvironment() async {
    setState(() => _status = '设置环境...');

    try {
      await _viewer!.loadSkybox("assets/environments/studio_small_env_skybox.ktx");
      await _viewer!.loadIbl("assets/environments/studio_small_env_ibl.ktx", intensity: 15600.0);

      await _viewer!.destroyLights();
      await _viewer!.addDirectLight(
        DirectLight.sun(
          color: 6400.0,
          intensity: 75000.0,
          castShadows: true,
          direction: Vector3(0.366695, -0.357967, -0.858717),
        ),
      );

      await _viewer!.setPostProcessing(true);
      await _viewer!.setShadowsEnabled(true);
      await _viewer!.setToneMapping(ToneMapper.ACES);
      await _viewer!.setBloom(true, 0.348);
      await _viewer!.setAntiAliasing(true, true, true);

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
          if (kDebugMode) {
            debugPrint('✅ 找到 Head_Mod，morph targets: ${morphTargets.length}个');
          }
        }
      }

      if (_headEntity != null) {
        if (kDebugMode) debugPrint('🎯 ✅ Head_Mod 准备就绪');
      } else {
        if (kDebugMode) debugPrint('⚠️ 未找到 Head_Mod');
      }
    } catch (e) {
      throw Exception('模型分析失败: $e');
    }
  }  ///
 加载动画列表
  Future<void> _loadAnimations() async {
    try {
      setState(() => _status = '检测动画...');

      final animationNames = await _asset!.getGltfAnimationNames();

      _animations.clear();
      for (int i = 0; i < animationNames.length; i++) {
        final name = animationNames[i].isEmpty ? "动画_${i + 1}" : animationNames[i];
        _animations.add(name);

        if (name.toLowerCase().contains('talk_01') || name.toLowerCase().contains('talk01')) {
          _talk01AnimationIndex = i;
          if (kDebugMode) {
            debugPrint('✅ 找到talk_01动画: $name (索引: $i)');
          }
        }
      }

      if (kDebugMode) {
        debugPrint('🎭 发现 ${_animations.length} 个动画');
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
          .map((frame) => List<double>.from(frame.map((value) => value.toDouble())))
          .toList();

      _isBlendshapeLoaded = true;

      if (kDebugMode) {
        debugPrint('✅ BS数据加载成功: ${_blendshapeData!.length}帧');
      }

      setState(() => _status = '✅ BS数据加载完成');
    } catch (e) {
      _isBlendshapeLoaded = false;
      setState(() => _status = '❌ BS数据加载失败: $e');
      if (kDebugMode) {
        debugPrint('❌ 加载 blendshape 数据失败: $e');
      }
    }
  }  /// 播
放口型同步
  Future<void> _playLipSync() async {
    if (!_isBlendshapeLoaded || _blendshapeData == null) {
      return;
    }

    if (_isLipSyncPlaying) {
      await _stopLipSync();
    }

    try {
      setState(() => _status = '🎬 准备播放...');
      _isLipSyncPlaying = true;

      // 🎯 获取音频文件的实际长度
      final audioSource = AssetSource('wav/output.wav');
      
      await _audioPlayer.setSource(audioSource);
      final audioDuration = await _audioPlayer.getDuration();
      
      if (audioDuration == null) {
        throw Exception('无法获取音频时长');
      }
      
      final actualAudioLengthMs = audioDuration.inMilliseconds.toDouble();
      
      if (kDebugMode) {
        debugPrint('🎵 音频长度: ${(actualAudioLengthMs/1000).toStringAsFixed(2)}秒');
        debugPrint('   BS帧数: ${_blendshapeData!.length}');
      }

      // 设置同步的动画数据
      await _setupMorphAnimation(actualAudioLengthMs);

      // 设置音频播放完成监听
      _completeSubscription?.cancel();
      _completeSubscription = _audioPlayer.onPlayerComplete.listen((_) async {
        await _stopLipSync();
      });

      // 同步启动动画和音频
      if (_talk01AnimationIndex >= 0) {
        await _asset!.playGltfAnimation(_talk01AnimationIndex);
      }
      
      await _audioPlayer.play(audioSource);
      setState(() => _status = '🎬 正在播放...');
      
    } catch (e) {
      _isLipSyncPlaying = false;
      setState(() => _status = '❌ 播放失败: $e');
      if (kDebugMode) {
        debugPrint('❌ 播放失败: $e');
      }
    }
  }  /// 停止口
型同步
  Future<void> _stopLipSync() async {
    try {
      _isLipSyncPlaying = false;
      setState(() => _status = '⏹️ 停止播放...');

      // 停止音频
      await _audioPlayer.stop();

      // 停止talk_01动画
      if (_talk01AnimationIndex >= 0) {
        await _asset!.stopGltfAnimation(_talk01AnimationIndex);
      }

      // 停止morph动画
      if (_asset != null && _headEntity != null) {
        await _asset!.clearMorphAnimationData(_headEntity!);
      }

      // 取消监听
      _completeSubscription?.cancel();

      // 重置所有morph targets
      await _resetAllMorphTargets();

      setState(() => _status = '✅ 已停止');
    } catch (e) {
      setState(() => _status = '❌ 停止失败: $e');
      if (kDebugMode) {
        debugPrint('❌ 停止失败: $e');
      }
    }
  }

  /// 重置所有morph targets到默认状态
  Future<void> _resetAllMorphTargets() async {
    if (_headEntity == null) return;

    try {
      final headMorphNames = await _asset!.getMorphTargetNames(entity: _headEntity!);
      final headWeights = List<double>.filled(headMorphNames.length, 0.0);
      await _asset!.setMorphTargetWeights(_headEntity!, headWeights);
    } catch (e) {
      if (kDebugMode) debugPrint('❌ 重置失败: $e');
    }
  } 
 /// 设置Morph动画数据
  Future<void> _setupMorphAnimation(double audioLengthMs) async {
    if (_asset == null || _blendshapeData == null) return;

    try {
      final totalFrames = _blendshapeData!.length;
      final frameLengthMs = audioLengthMs / totalFrames;

      final headMorphNames = await _asset!.getMorphTargetNames(entity: _headEntity!);
      final bsToHeadMapping = _createBSMapping(headMorphNames);

      if (bsToHeadMapping.isEmpty) {
        if (kDebugMode) debugPrint('❌ 无法创建BS映射');
        return;
      }

      final mappedMorphNames = bsToHeadMapping.keys.toList();
      final totalMorphTargets = mappedMorphNames.length;
      final flatData = Float32List(totalFrames * totalMorphTargets);

      for (int frame = 0; frame < totalFrames; frame++) {
        final frameWeights = _blendshapeData![frame];
        final baseIndex = frame * totalMorphTargets;

        for (int i = 0; i < mappedMorphNames.length; i++) {
          final morphName = mappedMorphNames[i];
          final bsIndex = bsToHeadMapping[morphName]!;

          if (bsIndex < frameWeights.length) {
            double value = frameWeights[bsIndex];
            value = value.clamp(0.0, _maxMorphWeight);
            flatData[baseIndex + i] = value;
          }
        }
      }

      final morphData = MorphAnimationData(
        flatData,
        mappedMorphNames,
        frameLengthInMs: frameLengthMs,
      );

      await _asset!.addAnimationComponent();
      await _asset!.setMorphAnimationData(morphData, targetMeshNames: ["Head_Mod"]);

      if (kDebugMode) {
        debugPrint('✅ 口型动画设置完成');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 设置Morph动画失败: $e');
      }
    }
  }  
/// 创建BS数据到Head_Mod的映射关系
  Map<String, int> _createBSMapping(List<String> headMorphNames) {
    final mapping = <String, int>{};
    
    // 直接按位置对应：模型位置 = JSON索引
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
    
    // 创建映射
    for (final morphName in headMorphNames) {
      if (bsMapping.containsKey(morphName)) {
        mapping[morphName] = bsMapping[morphName]!;
      }
    }
    
    return mapping;
  }  @overr
ide
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('口型同步播放'),
      ),
      body: Column(
        children: [
          // 3D视图
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

          // 控制面板 - ScrollView
          Expanded(
            flex: 1,
            child: Container(
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 状态显示
                    Text(
                      _status,
                      style: TextStyle(
                        fontSize: 12,
                        color: _isInitialized ? Colors.green : Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 播放控制按钮
                    if (_isInitialized) ...[
                      const Text(
                        '口型同步播放控制',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(height: 12),
                      
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // 播放按钮
                          ElevatedButton.icon(
                            onPressed: !_isLipSyncPlaying && _isBlendshapeLoaded
                                ? _playLipSync
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green[100],
                              foregroundColor: Colors.green[800],
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              elevation: 2,
                            ),
                            icon: const Icon(Icons.play_arrow, size: 20),
                            label: const Text(
                              '播放',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          
                          // 停止按钮
                          ElevatedButton.icon(
                            onPressed: _isLipSyncPlaying ? _stopLipSync : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isLipSyncPlaying 
                                  ? Colors.red[400] 
                                  : Colors.red[100],
                              foregroundColor: _isLipSyncPlaying 
                                  ? Colors.white 
                                  : Colors.red[800],
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              elevation: _isLipSyncPlaying ? 4 : 2,
                            ),
                            icon: const Icon(Icons.stop, size: 20),
                            label: const Text(
                              '停止',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),