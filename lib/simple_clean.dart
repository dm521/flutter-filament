import 'dart:async';
import 'dart:convert';
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
      title: '口型同步测试',
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

class _SimpleThermionTestState extends State<SimpleThermionTest> {
  ThermionViewer? _viewer;
  String _status = '初始化中...';
  DelegateInputHandler? _inputHandler;

  // 动画相关
  ThermionAsset? _asset;
  List<String> _animations = [];
  int _currentAnimationIndex = -1;
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

  @override
  void initState() {
    super.initState();
    _initializeSimpleViewer();
  }

  Future<void> _initializeSimpleViewer() async {
    try {
      setState(() => _status = '创建 Viewer...');

      _viewer = await ThermionFlutterPlugin.createViewer();

      setState(() => _status = '等待 Surface 准备...');
      await Future.delayed(const Duration(milliseconds: 300));

      setState(() => _status = '启用渲染...');
      await _viewer!.setRendering(true);

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

      // 主太阳光 - 基于专业配置
      await _viewer!.addDirectLight(
        DirectLight.sun(
          color: 5400.0, // 暖白色温
          intensity: 75000.0, // 主光强度
          castShadows: true, // 启用阴影
          direction: Vector3(0.366695, -0.357967, -0.858717), // 专业角度
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

        // 如果有动画，默认选择第一个
        if (_animations.isNotEmpty) {
          _currentAnimationIndex = 0;
        }

        // 检测所有实体的 morph targets
        await _detectMorphEntities();

        // 加载 blendshape 数据
        await _loadBlendshapeData();
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

  // 检测所有实体的 morph targets
  Future<void> _detectMorphEntities() async {
    if (_asset == null) return;

    try {
      setState(() => _status = '检测 Morph Targets...');

      final childEntities = await _asset!.getChildEntities();
      _entities.clear();

      if (kDebugMode) {
        debugPrint('🔍 开始检测 ${childEntities.length} 个实体的 morph targets...');
      }

      // 嘴部相关关键词，用于评分
      const mouthKeywords = [
        'mouth',
        'jaw',
        'lip',
        'viseme',
        'aa',
        'ih',
        'ou',
        'bs.',
        'blendshape',
      ];

      for (int i = 0; i < childEntities.length; i++) {
        try {
          final entity = childEntities[i];
          final morphTargets = await _asset!.getMorphTargetNames(
            entity: entity,
          );

          if (morphTargets.isNotEmpty) {
            // 计算实体评分（优先选择包含嘴部关键词的实体）
            int score = morphTargets.fold<int>(0, (acc, name) {
              final lowerName = name.toLowerCase();
              int nameScore = 1; // 基础分

              // 嘴部关键词加分
              for (final keyword in mouthKeywords) {
                if (lowerName.contains(keyword)) {
                  nameScore += 3; // 嘴部相关加3分
                  break;
                }
              }

              return acc + nameScore;
            });

            // 特殊处理：52个targets的实体（标准ARKit数量）
            if (morphTargets.length == 52) {
              score += 100; // 给52个targets的实体极高优先级
            }

            // 特殊处理：实体12或13（根据main.dart的经验）
            if (i == 12 || i == 13) {
              score += 50; // 给实体12和13额外加分
            }

            final entityInfo = EntityInfo(
              index: i,
              entityHandle: entity,
              morphTargets: morphTargets,
              score: score,
            );

            _entities.add(entityInfo);

            if (kDebugMode) {
              debugPrint(
                '✅ 实体 $i: ${morphTargets.length} targets, score=$score',
              );

              // 显示前5个 morph target 名称
              final preview = morphTargets.take(5).join(', ');
              debugPrint(
                '   预览: $preview${morphTargets.length > 5 ? '...' : ''}',
              );

              // 检查是否包含关键的 jawOpen
              final hasJawOpen = morphTargets.any(
                (name) =>
                    name.toLowerCase().contains('jawopen') ||
                    name.toLowerCase().contains('jaw_open'),
              );
              if (hasJawOpen) {
                debugPrint('   🦷 包含 jawOpen 相关 target');
              }
            }
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('❌ 实体 $i 检测失败: $e');
          }
        }
      }

      // 按评分排序，选择最佳实体
      _entities.sort((a, b) => b.score.compareTo(a.score));

      if (_entities.isNotEmpty) {
        // 优先选择实体12（真正的工作实体）
        int preferredIndex = -1;
        for (int i = 0; i < _entities.length; i++) {
          if (_entities[i].index == 12) {
            preferredIndex = i;
            break;
          }
        }
        _selectedMorphEntityIndex = preferredIndex >= 0 ? preferredIndex : 0;

        if (kDebugMode) {
          debugPrint('🎯 实体检测完成，找到 ${_entities.length} 个有效实体:');
          for (int i = 0; i < _entities.length && i < 5; i++) {
            final entity = _entities[i];
            debugPrint('   ${i + 1}. ${entity.toString()}');
          }
          debugPrint(
            '🏆 选择实体 ${_entities[_selectedMorphEntityIndex!].index} 作为主要口型实体',
          );
        }

        setState(
          () => _status =
              '✅ 检测到 ${_entities.length} 个实体，已选择实体 ${_entities[_selectedMorphEntityIndex!].index}',
        );
      } else {
        setState(() => _status = '⚠️ 未找到包含 morph targets 的实体');
        if (kDebugMode) {
          debugPrint('⚠️ 所有实体都没有 morph targets');
        }
      }
    } catch (e) {
      setState(() => _status = '❌ 实体检测失败: $e');
      if (kDebugMode) {
        debugPrint('❌ 检测 morph targets 失败: $e');
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
      }

      // 停止所有动画，避免冲突
      for (int i = 0; i < _animations.length; i++) {
        try {
          await _asset!.stopGltfAnimation(i);
        } catch (_) {}
      }

      // 重置所有权重
      await _resetAllMorphWeights();

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

          // 每100帧打印一次进度
          if (clampedFrame % 100 == 0 && kDebugMode) {
            debugPrint(
              '🎬 播放进度: $clampedFrame/${_blendshapeData!.length} (${(clampedFrame / _blendshapeData!.length * 100).toStringAsFixed(1)}%)',
            );
          }
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

  // 应用单帧 blendshape 数据
  Future<void> _applyBlendshapeFrame(int frameIndex) async {
    if (_blendshapeData == null ||
        _selectedMorphEntityIndex == null ||
        _asset == null)
      return;

    final selectedEntity = _entities[_selectedMorphEntityIndex!];
    final frameWeights = _blendshapeData![frameIndex];

    try {
      // 准备实体12的权重（主要面部表情）
      final entity12Weights = List<double>.filled(
        selectedEntity.morphTargets.length,
        0.0,
      );
      final copyLength = frameWeights.length < entity12Weights.length
          ? frameWeights.length
          : entity12Weights.length;

      for (int i = 0; i < copyLength; i++) {
        entity12Weights[i] = frameWeights[i];
      }

      // 🔥 修改策略：保持实体12的 jawOpen，让实体12和实体13同时工作
      // 不再禁用实体12的 jawOpen，使用原始数据

      // 应用实体12的权重
      await _asset!.setMorphTargetWeights(
        selectedEntity.entityHandle,
        entity12Weights,
      );

      // 🦷 同时处理实体13的专门 jawOpen 控制
      await _applyEntity13JawOpen(frameWeights);

      // 每200帧打印一次详细信息
      if (kDebugMode && frameIndex % 200 == 0) {
        final significantWeights = <String>[];
        for (
          int i = 0;
          i < frameWeights.length && i < selectedEntity.morphTargets.length;
          i++
        ) {
          if (frameWeights[i] > 0.01) {
            final targetName = i < selectedEntity.morphTargets.length
                ? selectedEntity.morphTargets[i]
                : 'Unknown';
            significantWeights.add(
              '$targetName=${frameWeights[i].toStringAsFixed(3)}',
            );
          }
        }

        if (significantWeights.isNotEmpty) {
          debugPrint(
            '🎭 第 $frameIndex 帧主要权重: ${significantWeights.take(3).join(', ')}...',
          );
        }

        // 特别显示 jawOpen 值和实际应用情况
        if (frameWeights.length > 17) {
          final jawOpenValue = frameWeights[17];
          debugPrint(
            '   🦷 原始 jawOpen [17] = ${jawOpenValue.toStringAsFixed(4)}',
          );
          debugPrint(
            '   🦷 实体12 F.jawOpen = ${jawOpenValue.toStringAsFixed(4)} (保持原值)',
          );
        }
      }
    } catch (e) {
      if (kDebugMode && frameIndex % 500 == 0) {
        // 减少错误日志频率
        debugPrint('❌ 应用第 $frameIndex 帧失败: $e');
      }
    }
  }

  // 应用实体13的 jawOpen 控制
  Future<void> _applyEntity13JawOpen(List<double> frameWeights) async {
    if (_asset == null) return;

    try {
      // 查找实体13
      final entity13Info = _entities.firstWhere(
        (e) => e.index == 13,
        orElse: () => throw Exception('实体13未找到'),
      );

      // 获取 jawOpen 权重（索引17），使用原始数据，不放大
      final jawOpenValue = frameWeights.length > 17 ? frameWeights[17] : 0.0;

      // 应用到实体13，使用原始权重值
      final entity13Weights = List<double>.filled(
        entity13Info.morphTargets.length,
        0.0,
      );
      if (entity13Weights.isNotEmpty) {
        entity13Weights[0] = jawOpenValue.clamp(0.0, 1.0); // T.jawOpen 使用原始值
      }

      await _asset!.setMorphTargetWeights(
        entity13Info.entityHandle,
        entity13Weights,
      );

      // 增加调试日志，显示实际应用的权重
      if (kDebugMode && jawOpenValue > 0.01) {
        debugPrint(
          '   🦷 实体13 T.jawOpen = ${jawOpenValue.toStringAsFixed(4)} (原始值)',
        );
      }
    } catch (e) {
      // 静默处理实体13错误，不影响主要播放
    }
  }

  // 重置所有 morph 权重
  Future<void> _resetAllMorphWeights() async {
    if (_asset == null) return;

    try {
      // 重置所有检测到的实体
      for (final entityInfo in _entities) {
        final zeroWeights = List<double>.filled(
          entityInfo.morphTargets.length,
          0.0,
        );
        await _asset!.setMorphTargetWeights(
          entityInfo.entityHandle,
          zeroWeights,
        );
      }

      if (kDebugMode) {
        debugPrint('🔄 已重置所有实体的 morph 权重');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 重置 morph 权重失败: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('口型同步测试')),
      body: Column(
        children: [
          // 扩大 3D 视图区域
          Expanded(
            flex: 4, // 占据更多空间
            child: _viewer != null
                ? ThermionWidget(viewer: _viewer!)
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

          // 简化的控制面板 - 使用 Flexible 避免溢出
          Container(
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
      children: [
        // 播放控制按钮
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ElevatedButton.icon(
              onPressed: !_isLipSyncPlaying && _selectedMorphEntityIndex != null
                  ? _playLipSync
                  : null,
              icon: const Icon(Icons.play_arrow, size: 16),
              label: const Text('播放', style: TextStyle(fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                minimumSize: const Size(70, 28),
              ),
            ),
            ElevatedButton.icon(
              onPressed: _isLipSyncPlaying ? _stopLipSync : null,
              icon: const Icon(Icons.stop, size: 16),
              label: const Text('停止', style: TextStyle(fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                minimumSize: const Size(70, 28),
              ),
            ),
          ],
        ),
        // 播放状态指示器（如果正在播放）
        if (_isLipSyncPlaying) ...[
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(strokeWidth: 1),
              ),
              const SizedBox(width: 4),
              Text(
                '播放中...',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
              ),
            ],
          ),
        ],
      ],
    );
  }

  @override
  void dispose() {
    // 清理音频资源
    _positionSubscription?.cancel();
    _completeSubscription?.cancel();
    _audioPlayer.dispose();

    _viewer?.setRendering(false);
    super.dispose();
  }
}
