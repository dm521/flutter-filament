import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
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
  List<List<double>>? _testBlendshapeData;
  bool _isTestDataLoaded = false;
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

  /// 🛑 强制停止所有动画和音频
  Future<void> _forceStopAll() async {
    try {
      if (kDebugMode) debugPrint('🛑 强制停止所有动画...');

      // 1. 强制停止音频
      await _audioPlayer.stop();

      // 2. 停止所有GLTF动画
      if (_asset != null && _animations.isNotEmpty) {
        for (int i = 0; i < _animations.length; i++) {
          try {
            await _asset!.stopGltfAnimation(i);
          } catch (e) {
            if (kDebugMode) debugPrint('⚠️ 停止动画$i失败: $e');
          }
        }
      }

      // 3. 🎯 强制停止morph动画（使用正确的API！）
      if (_asset != null && _headEntity != null) {
        try {
          // 使用Thermion的官方API清除morph动画
          await _asset!.clearMorphAnimationData(_headEntity!);
          if (kDebugMode) debugPrint('🛑 强制清除morph动画完成');
        } catch (e) {
          if (kDebugMode) debugPrint('⚠️ 强制清除morph动画失败: $e');
        }
      }

      // 4. 重置状态
      _isLipSyncPlaying = false;
      _completeSubscription?.cancel();

      // 5. 重置morph targets
      await _resetAllMorphTargets();

      setState(() => _status = '🛑 强制停止完成');
      if (kDebugMode) debugPrint('🛑 强制停止完成');
    } catch (e) {
      if (kDebugMode) debugPrint('❌ 强制停止失败: $e');
    }
  }

  /// 🔍 诊断形变问题 - 专门分析形变原因
  Future<void> _diagnoseDeformationIssues() async {
    if (_headEntity == null || _blendshapeData == null) return;

    try {
      setState(() => _status = '🔍 诊断形变问题...');

      final headMorphNames = await _asset!.getMorphTargetNames(
        entity: _headEntity!,
      );
      final bsToHeadMapping = _createBSMapping(headMorphNames);

      if (kDebugMode) {
        debugPrint('🔍 ===== 形变问题诊断报告 =====');

        // 1. 检查数据范围异常
        debugPrint('📊 数据范围分析:');
        final problematicMorphs = <String, Map<String, dynamic>>{};

        for (final entry in bsToHeadMapping.entries) {
          final morphName = entry.key;
          final bsIndex = entry.value;

          double maxValue = 0.0;
          double minValue = 0.0;
          int extremeFrames = 0; // 超过1.0的帧数
          int negativeFrames = 0; // 负值帧数

          for (final frame in _blendshapeData!) {
            if (bsIndex < frame.length) {
              final value = frame[bsIndex];
              if (value > maxValue) maxValue = value;
              if (value < minValue) minValue = value;
              if (value > 1.0) extremeFrames++;
              if (value < 0.0) negativeFrames++;
            }
          }

          // 标记问题数据
          if (maxValue > 1.0 || minValue < -0.1 || extremeFrames > 0) {
            problematicMorphs[morphName] = {
              'maxValue': maxValue,
              'minValue': minValue,
              'extremeFrames': extremeFrames,
              'negativeFrames': negativeFrames,
              'bsIndex': bsIndex,
            };
          }
        }

        if (problematicMorphs.isNotEmpty) {
          debugPrint('⚠️  发现${problematicMorphs.length}个异常morph targets:');
          for (final entry in problematicMorphs.entries) {
            final name = entry.key;
            final data = entry.value;
            debugPrint('   🔥 $name (索引${data['bsIndex']}):');
            debugPrint(
              '      范围: ${data['minValue'].toStringAsFixed(3)} ~ ${data['maxValue'].toStringAsFixed(3)}',
            );
            if (data['extremeFrames'] > 0) {
              debugPrint('      ⚠️  超过1.0的帧数: ${data['extremeFrames']}');
            }
            if (data['negativeFrames'] > 0) {
              debugPrint('      ⚠️  负值帧数: ${data['negativeFrames']}');
            }
          }
        } else {
          debugPrint('✅ 所有morph targets数据范围正常');
        }

        // 2. 检查增强系数是否过度
        debugPrint('\n🎛️  当前增强系数分析:');
        debugPrint('   张嘴增强系数: $_jawOpenEnhanceFactor (建议: 1.0-1.3)');
        debugPrint('   嘴型增强系数: $_mouthShapeEnhanceFactor (建议: 1.0-1.2)');
        debugPrint('   平滑系数: $_smoothingFactor (建议: 0.1-0.3)');
        debugPrint('   最大权重限制: $_maxMorphWeight (建议: 0.8-1.0)');

        if (_jawOpenEnhanceFactor > 1.5) {
          debugPrint('   ⚠️  张嘴增强过度，可能导致下颌形变');
        }
        if (_mouthShapeEnhanceFactor > 1.3) {
          debugPrint('   ⚠️  嘴型增强过度，可能导致嘴部形变');
        }

        // 3. 检查关键帧的权重分布
        debugPrint('\n📈 关键帧权重分布分析:');
        final keyIndices = [
          17,
          19,
          20,
          23,
          24,
        ]; // jawOpen, mouthFunnel, mouthPucker, smileLeft, smileRight
        final keyNames = [
          'jawOpen',
          'mouthFunnel',
          'mouthPucker',
          'smileLeft',
          'smileRight',
        ];

        for (int i = 0; i < keyIndices.length; i++) {
          final index = keyIndices[i];
          final name = keyNames[i];

          if (index < _blendshapeData!.first.length) {
            final values = _blendshapeData!
                .map((frame) => frame[index])
                .toList();
            values.sort();

            final p25 = values[(values.length * 0.25).floor()];
            final p50 = values[(values.length * 0.5).floor()];
            final p75 = values[(values.length * 0.75).floor()];
            final p95 = values[(values.length * 0.95).floor()];

            debugPrint(
              '   📊 $name: P25=${p25.toStringAsFixed(3)}, P50=${p50.toStringAsFixed(3)}, P75=${p75.toStringAsFixed(3)}, P95=${p95.toStringAsFixed(3)}',
            );

            if (p95 > 1.2) {
              debugPrint('      🔥 95%分位数过高，可能导致极端形变');
            }
            if (p75 > 0.8) {
              debugPrint('      ⚠️  75%分位数偏高，整体权重可能过大');
            }
          }
        }

        // 4. 提供修复建议
        debugPrint('\n💡 形变问题修复建议:');
        debugPrint('   1. 数据预处理:');
        debugPrint('      - 将所有权重限制在0.0-0.8范围内');
        debugPrint('      - 对超过1.0的值进行截断处理');
        debugPrint('      - 增加数据平滑处理');

        debugPrint('   2. 增强系数调整:');
        debugPrint('      - 降低jawOpenEnhanceFactor到1.2');
        debugPrint('      - 降低mouthShapeEnhanceFactor到1.1');
        debugPrint('      - 增加smoothingFactor到0.25');

        debugPrint('   3. 特定morph targets处理:');
        if (problematicMorphs.containsKey('F.mouthSmileLeft') ||
            problematicMorphs.containsKey('F.mouthSmileRight')) {
          debugPrint('      - 微笑表情权重过高，建议限制在0.6以内');
        }
        if (problematicMorphs.containsKey('F.jawOpen')) {
          debugPrint('      - 张嘴权重异常，检查BS数据源');
        }

        debugPrint('🔍 ===== 诊断完成 =====');
      }

      setState(() => _status = '✅ 形变诊断完成');
    } catch (e) {
      setState(() => _status = '❌ 诊断失败: $e');
      if (kDebugMode) debugPrint('❌ 形变诊断失败: $e');
    }
  }

  /// 🔍 检查数据对齐 - 专门的诊断函数
  Future<void> _checkDataAlignment() async {
    if (_headEntity == null || _blendshapeData == null) return;

    try {
      setState(() => _status = '🔍 检查数据对齐...');

      final headMorphNames = await _asset!.getMorphTargetNames(
        entity: _headEntity!,
      );
      final bsToHeadMapping = _createBSMapping(headMorphNames);

      if (kDebugMode) {
        debugPrint('🔍 ===== 数据对齐诊断报告 =====');
        debugPrint('模型信息:');
        debugPrint('   Head_Mod morph targets: ${headMorphNames.length}个');
        debugPrint('   成功映射: ${bsToHeadMapping.length}个');

        debugPrint('BS数据信息:');
        debugPrint('   数据长度: ${_blendshapeData!.first.length}个');
        debugPrint('   总帧数: ${_blendshapeData!.length}帧');

        // 检查关键morph targets是否存在
        const keyMorphs = [
          'F.jawOpen',
          'F.mouthFunnel',
          'F.mouthPucker',
          'F.mouthSmileLeft',
          'F.mouthSmileRight',
        ];

        debugPrint('关键morph targets检查:');
        for (final morph in keyMorphs) {
          if (headMorphNames.contains(morph)) {
            final bsIndex = bsToHeadMapping[morph];
            debugPrint('   ✅ $morph -> BS索引$bsIndex');
          } else {
            debugPrint('   ❌ $morph -> 模型中不存在');
          }
        }

        // 分析BS数据中最活跃的索引
        _findMostActiveIndices();

        // 如果数据长度不匹配，给出建议
        if (_blendshapeData!.first.length != 52) {
          debugPrint('⚠️  数据长度建议:');
          debugPrint('   当前: ${_blendshapeData!.first.length}个');
          debugPrint('   标准: 52个');
          if (_blendshapeData!.first.length == 55) {
            debugPrint('   建议: 可能需要忽略前3个或后3个数据');
          }
        }

        debugPrint('🔍 ===== 诊断报告结束 =====');
      }

      setState(() => _status = '✅ 数据对齐检查完成');
    } catch (e) {
      setState(() => _status = '❌ 检查失败: $e');
      if (kDebugMode) debugPrint('❌ 数据对齐检查失败: $e');
    }
  }

  /// 🔍 找出最活跃的BS数据索引
  void _findMostActiveIndices() {
    if (_blendshapeData == null) return;

    final activityMap = <int, double>{};
    final dataLength = _blendshapeData!.first.length;

    // 计算每个索引的活跃度
    for (int index = 0; index < dataLength; index++) {
      double totalActivity = 0.0;
      for (final frame in _blendshapeData!) {
        totalActivity += frame[index].abs();
      }
      activityMap[index] = totalActivity;
    }

    // 排序找出最活跃的索引
    final sortedIndices = activityMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (kDebugMode) {
      debugPrint('📊 最活跃的BS数据索引 (前10个):');
      for (int i = 0; i < 10 && i < sortedIndices.length; i++) {
        final entry = sortedIndices[i];
        debugPrint('   索引${entry.key}: 活跃度${entry.value.toStringAsFixed(2)}');
      }

      // 特别检查关键口型索引的活跃度
      const keyIndices = [
        25,
        27,
        28,
        31,
        32,
      ]; // jawOpen, mouthFunnel, mouthPucker, mouthSmileLeft, mouthSmileRight
      const keyNames = [
        'jawOpen',
        'mouthFunnel',
        'mouthPucker',
        'mouthSmileLeft',
        'mouthSmileRight',
      ];

      debugPrint('🔍 关键口型索引活跃度:');
      for (int i = 0; i < keyIndices.length; i++) {
        final index = keyIndices[i];
        final name = keyNames[i];
        if (index < dataLength) {
          final activity = activityMap[index] ?? 0.0;
          debugPrint('   $name(索引$index): 活跃度${activity.toStringAsFixed(2)}');
        } else {
          debugPrint('   $name(索引$index): 超出数据范围');
        }
      }
    }
  }

  /// 🧪 全面测试所有morph targets的数据对齐和质量
  Future<void> _testMapping() async {
    if (_headEntity == null || _blendshapeData == null) return;

    try {
      setState(() => _status = '🧪 全面测试映射...');

      final headMorphNames = await _asset!.getMorphTargetNames(
        entity: _headEntity!,
      );
      final bsToHeadMapping = _createBSMapping(headMorphNames);

      if (kDebugMode) {
        debugPrint('🧪 ===== 完整数据对齐分析 =====');
        debugPrint('📊 基础信息:');
        debugPrint('   模型morph targets: ${headMorphNames.length}个');
        debugPrint('   BS数据长度: ${_blendshapeData!.first.length}个');
        debugPrint('   成功映射: ${bsToHeadMapping.length}个');
        debugPrint('   总帧数: ${_blendshapeData!.length}帧');

        // 分析所有映射的morph targets
        final sortedMorphs = bsToHeadMapping.entries.toList()
          ..sort((a, b) => a.value.compareTo(b.value));

        debugPrint('\n📋 完整映射分析 (按BS索引排序):');

        // 统计数据
        int normalCount = 0;
        int lowActivityCount = 0;
        int highValueCount = 0;
        int suspiciousCount = 0;

        for (final entry in sortedMorphs) {
          final morphName = entry.key;
          final bsIndex = entry.value;

          // 分析这个morph target的数据
          double maxValue = 0.0;
          double minValue = double.infinity;
          double avgValue = 0.0;
          int activeFrames = 0;
          double totalValue = 0.0;

          for (final frame in _blendshapeData!) {
            if (bsIndex < frame.length) {
              final value = frame[bsIndex];
              if (value > maxValue) maxValue = value;
              if (value < minValue) minValue = value;
              totalValue += value;
              if (value > 0.05) activeFrames++;
            }
          }

          avgValue = totalValue / _blendshapeData!.length;
          final activityRate = (activeFrames / _blendshapeData!.length * 100);

          // 分类统计
          if (maxValue > 1.0) highValueCount++;
          if (activityRate < 5.0) lowActivityCount++;
          if (maxValue > 1.5 || activityRate > 95.0)
            suspiciousCount++;
          else
            normalCount++;

          // 标记异常数据
          String status = '✅';
          if (maxValue > 1.2) status = '⚠️ 高值';
          if (maxValue > 1.5) status = '🔥 异常高';
          if (activityRate < 2.0) status = '💤 低活跃';
          if (activityRate > 98.0) status = '🔄 过活跃';

          debugPrint('   [$bsIndex] $morphName:');
          debugPrint(
            '      最大值: ${maxValue.toStringAsFixed(3)} | 平均值: ${avgValue.toStringAsFixed(3)}',
          );
          debugPrint(
            '      活跃率: ${activityRate.toStringAsFixed(1)}% (${activeFrames}帧) $status',
          );
        }

        debugPrint('\n📊 数据质量统计:');
        debugPrint('   ✅ 正常数据: $normalCount个');
        debugPrint('   💤 低活跃度: $lowActivityCount个');
        debugPrint('   ⚠️  高数值: $highValueCount个');
        debugPrint('   🔥 可疑数据: $suspiciousCount个');

        // 重点分析口型相关的morph targets
        debugPrint('\n🎯 口型关键分析:');
        const keyMorphs = [
          'F.jawOpen',
          'F.mouthFunnel',
          'F.mouthPucker',
          'F.mouthSmileLeft',
          'F.mouthSmileRight',
          'F.mouthClose',
          'F.mouthLeft',
          'F.mouthRight',
        ];

        for (final morphName in keyMorphs) {
          if (bsToHeadMapping.containsKey(morphName)) {
            final bsIndex = bsToHeadMapping[morphName]!;
            double maxValue = 0.0;
            int activeFrames = 0;

            for (final frame in _blendshapeData!) {
              if (bsIndex < frame.length) {
                final value = frame[bsIndex];
                if (value > maxValue) maxValue = value;
                if (value > 0.05) activeFrames++;
              }
            }

            final activityRate = (activeFrames / _blendshapeData!.length * 100);
            String recommendation = '';

            if (morphName == 'F.jawOpen' && maxValue < 0.5) {
              recommendation = ' → 建议增强张嘴幅度';
            } else if (morphName.contains('Smile') && maxValue > 0.8) {
              recommendation = ' → 建议降低微笑强度，避免过度表情';
            } else if (activityRate > 90) {
              recommendation = ' → 活跃度过高，可能导致不自然';
            } else if (activityRate < 10) {
              recommendation = ' → 活跃度过低，口型变化不明显';
            }

            debugPrint(
              '   🎯 $morphName: 最大${maxValue.toStringAsFixed(3)}, 活跃${activityRate.toStringAsFixed(1)}%$recommendation',
            );
          }
        }

        debugPrint('🧪 ===== 分析完成 =====');
      }

      setState(() => _status = '✅ 全面测试完成');
    } catch (e) {
      setState(() => _status = '❌ 测试失败: $e');
      if (kDebugMode) debugPrint('❌ 映射测试失败: $e');
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

  /// 分析测试数据的分布
  void _analyzeTestData() {
    if (_testBlendshapeData == null) return;

    if (kDebugMode) {
      debugPrint('🔍 ===== 测试数据分析 =====');

      // 统计每个索引的数据情况
      final dataLength = _testBlendshapeData!.first.length;
      final totalFrames = _testBlendshapeData!.length;

      for (int index = 0; index < dataLength; index++) {
        double maxValue = 0.0;
        double minValue = double.infinity;
        int nonZeroFrames = 0;
        Set<double> uniqueValues = {};

        for (int frame = 0; frame < totalFrames; frame++) {
          final value = _testBlendshapeData![frame][index];
          if (value > 0.001) {
            nonZeroFrames++;
            uniqueValues.add(value);
          }
          if (value > maxValue) maxValue = value;
          if (value < minValue) minValue = value;
        }

        if (nonZeroFrames > 0) {
          debugPrint(
            '📊 索引$index: 非零帧$nonZeroFrames/$totalFrames, 最大值${maxValue.toStringAsFixed(3)}, 唯一值${uniqueValues.length}个',
          );
          if (uniqueValues.length <= 5) {
            debugPrint(
              '   值: ${uniqueValues.map((v) => v.toStringAsFixed(3)).join(', ')}',
            );
          }
        }
      }

      debugPrint('🔍 ===== 分析完成 =====');
    }
  }

  /// 加载测试BS数据
  Future<void> _loadTestBlendshapeData() async {
    try {
      setState(() => _status = '加载测试数据...');

      final jsonString = await rootBundle.loadString('assets/wav/bs.json');
      final Map<String, dynamic> jsonData = json.decode(jsonString);

      final int numFrames = jsonData['numFrames'];
      final List<dynamic> weightMat = jsonData['weightMat'];

      _testBlendshapeData = weightMat
          .map(
            (frame) =>
                List<double>.from(frame.map((value) => value.toDouble())),
          )
          .toList();

      _isTestDataLoaded = true;

      if (kDebugMode) {
        debugPrint('✅ 测试数据加载成功: ${_testBlendshapeData!.length}帧');
        debugPrint('   预期帧数: $numFrames');
        debugPrint('   实际帧数: ${_testBlendshapeData!.length}');
        debugPrint('   每帧数据长度: ${_testBlendshapeData!.first.length}');

        // 分析数据分布
        _analyzeTestData();
      }

      setState(() => _status = '✅ 测试数据加载完成');
    } catch (e) {
      _isTestDataLoaded = false;
      setState(() => _status = '❌ 测试数据加载失败: $e');
      if (kDebugMode) {
        debugPrint('❌ 加载测试数据失败: $e');
      }
    }
  }

  /// 播放口型同步 - 优化版本（改进同步）
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

      // 预加载音频以获取时长
      await _audioPlayer.setSource(audioSource);
      final audioDuration = await _audioPlayer.getDuration();

      if (audioDuration == null) {
        throw Exception('无法获取音频时长');
      }

      final actualAudioLengthMs = audioDuration.inMilliseconds.toDouble();

      if (kDebugMode) {
        debugPrint('🎵 音频同步信息:');
        debugPrint(
          '   音频实际长度: ${actualAudioLengthMs}ms (${(actualAudioLengthMs / 1000).toStringAsFixed(2)}秒)',
        );
        debugPrint('   BS数据帧数: ${_blendshapeData!.length}');
        debugPrint(
          '   计算帧率: ${(_blendshapeData!.length * 1000 / actualAudioLengthMs).toStringAsFixed(2)}fps',
        );
      }

      // 🎯 使用实际音频长度设置动画数据
      await _setupMorphAnimationWithDuration(actualAudioLengthMs);

      // 设置音频播放完成监听
      _completeSubscription?.cancel();
      _completeSubscription = _audioPlayer.onPlayerComplete.listen((_) async {
        await _stopLipSync();
      });

      // 🎯 同步启动：先启动动画，立即播放音频
      if (_talk01AnimationIndex >= 0) {
        await _asset!.playGltfAnimation(_talk01AnimationIndex);
        if (kDebugMode) debugPrint('🎭 启动talk_01动画');
      }

      // 立即播放音频，减少延迟
      await _audioPlayer.play(audioSource);
      setState(() => _status = '🎬 正在播放 (同步优化)...');

      if (kDebugMode) {
        debugPrint('✅ 音频和口型动画已同步启动');
      }
    } catch (e) {
      _isLipSyncPlaying = false;
      setState(() => _status = '❌ 播放失败: $e');
      if (kDebugMode) {
        debugPrint('❌ 播放失败: $e');
      }
    }
  }

  /// 播放测试JSON数据 - 纯BS数据测试
  Future<void> _playTestData() async {
    if (!_isTestDataLoaded || _testBlendshapeData == null) {
      // 如果测试数据未加载，先加载
      await _loadTestBlendshapeData();
      if (!_isTestDataLoaded) return;
    }

    if (_isLipSyncPlaying) {
      await _stopLipSync();
    }

    try {
      setState(() => _status = '🧪 播放测试数据...');
      _isLipSyncPlaying = true;

      // 设置测试动画数据
      await _setupTestMorphAnimation();

      // 🎭 启动talk_01动画
      if (_talk01AnimationIndex >= 0) {
        await _asset!.playGltfAnimation(_talk01AnimationIndex);
        if (kDebugMode) {
          debugPrint('🎭 启动talk_01动画');
        }
      }

      // 不播放音频，只播放morph动画
      setState(
        () => _status = '🧪 测试数据播放中 (${_testBlendshapeData!.length}帧)...',
      );

      // 计算播放时长并设置定时器
      final totalDurationMs = _testBlendshapeData!.length * 33.0; // 30fps
      final durationSeconds = (totalDurationMs / 1000).toStringAsFixed(1);

      if (kDebugMode) {
        debugPrint('🧪 开始播放测试数据:');
        debugPrint('   总帧数: ${_testBlendshapeData!.length}');
        debugPrint('   播放时长: ${durationSeconds}秒');
        debugPrint('   帧率: 30fps');
      }

      Timer(Duration(milliseconds: totalDurationMs.toInt()), () async {
        if (_isLipSyncPlaying) {
          await _stopLipSync();
          if (kDebugMode) debugPrint('🧪 测试数据播放完成');
        }
      });
    } catch (e) {
      _isLipSyncPlaying = false;
      setState(() => _status = '❌ 测试播放失败: $e');
      if (kDebugMode) {
        debugPrint('❌ 测试播放失败: $e');
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

  /// 停止口型同步 - 完整版本
  Future<void> _stopLipSync() async {
    try {
      _isLipSyncPlaying = false;
      setState(() => _status = '⏹️ 停止播放...');

      // 1. 停止音频
      await _audioPlayer.stop();
      if (kDebugMode) debugPrint('🔇 音频已停止');

      // 2. 🎭 停止talk_01动画
      if (_talk01AnimationIndex >= 0) {
        await _asset!.stopGltfAnimation(_talk01AnimationIndex);
        if (kDebugMode) {
          debugPrint('🎭 停止talk_01动画');
        }
      }

      // 3. 🎯 停止morph动画（使用正确的API！）
      try {
        if (_asset != null && _headEntity != null) {
          // 使用Thermion的官方API清除morph动画
          await _asset!.clearMorphAnimationData(_headEntity!);
          if (kDebugMode) debugPrint('🎯 已清除morph动画数据');
        }
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ 清除morph动画失败: $e');
      }

      // 4. 取消监听
      _completeSubscription?.cancel();

      // 5. 重置所有morph targets到默认状态
      await _resetAllMorphTargets();

      setState(() => _status = '✅ 已完全停止');
      if (kDebugMode) debugPrint('✅ 口型同步完全停止');
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

      // 检查数据长度匹配
      final dataLength = _blendshapeData!.first.length;
      if (kDebugMode) {
        debugPrint('🔍 原始播放数据检查:');
        debugPrint('   BS数据长度: $dataLength');
        debugPrint('   映射的morph数量: ${mappedMorphNames.length}');
        if (bsToHeadMapping.isNotEmpty) {
          debugPrint(
            '   最大BS索引: ${bsToHeadMapping.values.reduce((a, b) => a > b ? a : b)}',
          );
        }
      }

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
          } else {
            // 索引超出范围，记录警告
            if (kDebugMode && frame == 0) {
              debugPrint('⚠️  $morphName 的索引$bsIndex 超出数据长度$dataLength');
            }
            flatData[baseIndex + i] = 0.0;
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

  /// 设置测试Morph动画数据 - 完全按照test_0924.json还原
  Future<void> _setupTestMorphAnimation() async {
    if (_asset == null || _testBlendshapeData == null) return;

    try {
      final totalFrames = _testBlendshapeData!.length;
      final frameLengthMs = 33.0; // 30fps

      // 获取Head_Mod的所有morph targets
      final headMorphNames = await _asset!.getMorphTargetNames(
        entity: _headEntity!,
      );

      if (kDebugMode) {
        debugPrint('🧪 测试数据完全还原设置:');
        debugPrint('   Head_Mod morph targets: ${headMorphNames.length}个');
        debugPrint('   JSON数据长度: ${_testBlendshapeData!.first.length}个');
        debugPrint('   总帧数: $totalFrames');
        debugPrint('   帧长度: ${frameLengthMs}ms');
      }

      // 确保数据长度匹配
      final jsonDataLength = _testBlendshapeData!.first.length;
      final modelMorphCount = headMorphNames.length;

      if (jsonDataLength != modelMorphCount) {
        if (kDebugMode) {
          debugPrint(
            '⚠️ 数据长度不匹配: JSON($jsonDataLength) vs 模型($modelMorphCount)',
          );
          debugPrint('   将使用较小的长度进行映射');
        }
      }

      // 使用实际可用的长度
      final actualMorphCount = math.min(jsonDataLength, modelMorphCount);
      final flatData = Float32List(totalFrames * actualMorphCount);

      // 统计非零数据并按帧分组显示
      int totalNonZeroValues = 0;
      Map<int, int> nonZeroCountPerIndex = {};
      Map<int, List<String>> frameData = {}; // 按帧存储非零数据

      for (int frame = 0; frame < totalFrames; frame++) {
        final frameWeights = _testBlendshapeData![frame];
        final baseIndex = frame * actualMorphCount;
        List<String> currentFrameData = [];

        for (int morphIndex = 0; morphIndex < actualMorphCount; morphIndex++) {
          // 🎯 完全按照JSON数据还原，不做任何修改
          double value = frameWeights[morphIndex];

          // 只做基本的安全检查，保持原始数据
          if (value.isNaN || value.isInfinite) {
            value = 0.0;
          }

          flatData[baseIndex + morphIndex] = value;

          // 收集非零值
          if (value.abs() > 0.001) {
            totalNonZeroValues++;
            nonZeroCountPerIndex[morphIndex] =
                (nonZeroCountPerIndex[morphIndex] ?? 0) + 1;
            currentFrameData.add(
              '索引$morphIndex(${headMorphNames[morphIndex]})=$value',
            );
          }
        }

        // 如果当前帧有数据，存储起来
        if (currentFrameData.isNotEmpty) {
          frameData[frame] = currentFrameData;
        }
      }

      // 简化日志输出
      if (kDebugMode && frameData.isNotEmpty) {
        debugPrint('📋 检测到${frameData.length}帧有BS数据');
      }

      // 创建morph动画数据
      final morphData = MorphAnimationData(
        flatData,
        headMorphNames.take(actualMorphCount).toList(), // 只使用实际映射的morph names
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
        debugPrint(
          '✅ 测试数据完全还原完成: $actualMorphCount个morph targets, ${nonZeroCountPerIndex.keys.length}个活跃索引',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 设置测试Morph动画失败: $e');
      }
    }
  }

  /// 设置优化的Morph动画数据 - 使用实际音频长度
  Future<void> _setupMorphAnimationWithDuration(double audioLengthMs) async {
    if (_asset == null || _blendshapeData == null) return;

    try {
      final totalFrames = _blendshapeData!.length;
      final frameLengthMs = audioLengthMs / totalFrames; // 使用实际音频长度

      if (kDebugMode) {
        debugPrint('🎯 动画同步设置:');
        debugPrint('   总帧数: $totalFrames');
        debugPrint('   音频长度: ${audioLengthMs}ms');
        debugPrint('   每帧时长: ${frameLengthMs.toStringAsFixed(2)}ms');
      }

      // 获取Head_Mod的所有morph targets
      final headMorphNames = await _asset!.getMorphTargetNames(
        entity: _headEntity!,
      );

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
          for (int i = 0; i < totalMorphTargets; i++) {
            flatData[baseIndex + i] = currentFrameWeights[i];
          }
        }

        _previousFrameWeights = List.from(currentFrameWeights);
      }

      final morphData = MorphAnimationData(
        flatData,
        mappedMorphNames,
        frameLengthInMs: frameLengthMs, // 使用实际计算的帧长度
      );

      // 确保animation component已激活
      await _asset!.addAnimationComponent();

      // 设置动画数据
      await _asset!.setMorphAnimationData(
        morphData,
        targetMeshNames: ["Head_Mod"],
      );

      if (kDebugMode) {
        debugPrint('✅ 同步优化的BS动画设置完成: ${mappedMorphNames.length}个morph targets');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 设置同步Morph动画失败: $e');
      }
    }
  }

  /// 设置优化的Morph动画数据 - 智能增强和平滑处理（兼容旧版本）
  Future<void> _setupMorphAnimation() async {
    if (_asset == null || _blendshapeData == null) return;

    try {
      final totalFrames = _blendshapeData!.length;
      final frameLengthMs = 59160.0 / totalFrames; // 音频总长度/帧数（硬编码版本）

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

  /// 🔍 分析BS数据特征 - 增强版本，检查数据对齐
  void _analyzeBSData() {
    if (_blendshapeData == null || _blendshapeData!.isEmpty) return;

    // 首先检查数据长度
    final firstFrameLength = _blendshapeData!.first.length;
    if (kDebugMode) {
      debugPrint('🔍 BS数据详细分析:');
      debugPrint('   总帧数: ${_blendshapeData!.length}');
      debugPrint('   每帧数据长度: $firstFrameLength');
      debugPrint('   预期长度: 52 (ARKit标准)');

      if (firstFrameLength != 52) {
        debugPrint('⚠️  数据长度不匹配！实际${firstFrameLength}个，预期52个');
        debugPrint('   这可能导致数据映射错误');
      }
    }

    // 分析前几帧的数据分布，查看是否有明显的活跃值
    _analyzeDataDistribution();

    const jawOpenIndex = 25; // ARKit jawOpen索引
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
      debugPrint('📊 张嘴数据分析:');
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

  /// 🔍 分析数据分布，查看活跃的索引
  void _analyzeDataDistribution() {
    if (_blendshapeData == null || _blendshapeData!.isEmpty) return;

    final firstFrame = _blendshapeData!.first;
    final midFrame = _blendshapeData![_blendshapeData!.length ~/ 2];

    if (kDebugMode) {
      debugPrint('🔍 数据分布分析:');

      // 找出第一帧中有值的索引
      final activeIndicesFirst = <int>[];
      for (int i = 0; i < firstFrame.length; i++) {
        if (firstFrame[i].abs() > 0.01) {
          activeIndicesFirst.add(i);
        }
      }

      // 找出中间帧中有值的索引
      final activeIndicesMid = <int>[];
      for (int i = 0; i < midFrame.length; i++) {
        if (midFrame[i].abs() > 0.01) {
          activeIndicesMid.add(i);
        }
      }

      debugPrint('   第一帧活跃索引: $activeIndicesFirst');
      debugPrint('   中间帧活跃索引: $activeIndicesMid');

      // 显示前10个值
      final first10 = firstFrame.take(10).toList();
      debugPrint(
        '   第一帧前10个值: ${first10.map((v) => v.toStringAsFixed(3)).join(", ")}',
      );

      final mid10 = midFrame.take(10).toList();
      debugPrint(
        '   中间帧前10个值: ${mid10.map((v) => v.toStringAsFixed(3)).join(", ")}',
      );
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

  /// 创建BS数据到Head_Mod的映射关系 - 正确版本
  Map<String, int> _createBSMapping(List<String> headMorphNames) {
    final mapping = <String, int>{};

    // 🎯 正确的映射：模型morph targets顺序 = BS.json数据顺序
    // 模型中的顺序和BS.json完全一致！
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
      "F.jawOpen": 17, // 🔥 正确！
      "F.mouthClose": 18,
      "F.mouthFunnel": 19, // 🔥 正确！
      "F.mouthPucker": 20, // 🔥 正确！
      "F.mouthLeft": 21,
      "F.mouthRight": 22,
      "F.mouthSmileLeft": 23, // 🔥 正确！
      "F.mouthSmileRight": 24, // 🔥 正确！
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

    if (kDebugMode) {
      debugPrint('🗺️ 模型中的morph targets (${headMorphNames.length}个):');
      for (int i = 0; i < headMorphNames.length; i++) {
        debugPrint('   [$i] ${headMorphNames[i]}');
      }

      debugPrint('🗺️ BS映射结果 (正确版本):');
      debugPrint('   成功映射: ${mapping.length}个');

      // 显示关键映射
      const keyMorphs = [
        "F.jawOpen",
        "F.mouthFunnel",
        "F.mouthPucker",
        "F.mouthSmileLeft",
        "F.mouthSmileRight",
      ];
      debugPrint('🔍 关键映射检查 (正确版本):');
      for (final keyMorph in keyMorphs) {
        if (mapping.containsKey(keyMorph)) {
          debugPrint('   ✅ $keyMorph -> BS索引${mapping[keyMorph]}');
        } else {
          debugPrint('   ❌ $keyMorph -> 未找到');
        }
      }

      // 检查BS数据长度
      if (_blendshapeData != null && _blendshapeData!.isNotEmpty) {
        final dataLength = _blendshapeData!.first.length;
        debugPrint('📊 BS数据信息:');
        debugPrint('   数据长度: $dataLength');
        debugPrint('   标准长度: 52');
        if (dataLength == 55) {
          debugPrint('   ⚠️  额外的3个值将被忽略 (索引52-54)');
        }
      }
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

                      const SizedBox(height: 16),

                      // 播放状态指示
                      if (_isLipSyncPlaying) ...[
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.blue[200]!),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.blue[600]!,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                '正在播放口型同步...',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.blue,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ],

                    // 数据状态显示
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _isBlendshapeLoaded
                            ? Colors.green[50]
                            : Colors.orange[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _isBlendshapeLoaded
                              ? Colors.green[200]!
                              : Colors.orange[200]!,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _isBlendshapeLoaded
                                    ? Icons.check_circle
                                    : Icons.hourglass_empty,
                                size: 16,
                                color: _isBlendshapeLoaded
                                    ? Colors.green[600]
                                    : Colors.orange[600],
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '数据状态',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: _isBlendshapeLoaded
                                      ? Colors.green[800]
                                      : Colors.orange[800],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_isBlendshapeLoaded) ...[
                            Text(
                              'BS数据: ${_blendshapeData?.length ?? 0}帧',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.green[700],
                              ),
                            ),
                            Text(
                              '动画: ${_animations.length}个',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.green[700],
                              ),
                            ),
                            if (_isTestDataLoaded)
                              Text(
                                '测试数据: ${_testBlendshapeData?.length ?? 0}帧',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.green[700],
                                ),
                              ),
                          ] else ...[
                            Text(
                              '数据加载中...',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.orange[700],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
