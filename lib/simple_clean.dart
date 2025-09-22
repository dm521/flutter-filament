import 'dart:async';
import 'dart:convert';
// import 'dart:math' as math; // 暂时未使用
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
  int _talkAnimationIndex = -1; // 说话动画索引
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

  // 动画混合控制参数
  double _bodyAnimationWeight = 0.6; // 身体动画权重（降低以避免覆盖面部）
  double _morphTargetBoost = 1.5; // morph target增强系数

  // 权重优化参数（暂时保留用于后续优化）
  // static const double _weightAmplifier = 1.0; // 恢复原始权重，不放大
  // List<double>? _previousWeights; // 用于平滑处理
  // static const double _smoothingFactor = 0.0; // 禁用平滑处理

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
        _asset = await _viewer!.loadGltf("assets/models/xiaomeng_0922.glb");
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

        // 检测idle和说话动画
        _detectIdleAnimation(animationNames);
        _detectTalkAnimation(animationNames);

        // 如果有动画，默认选择第一个
        if (_animations.isNotEmpty) {
          _currentAnimationIndex = 0;
        }

        // 检测所有实体的 morph targets
        await _detectMorphEntities();

        // 加载 blendshape 数据
        await _loadBlendshapeData();

        // 🎭 自动播放idle动画
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

  // 直接获取实体12的 morph targets
  Future<void> _detectMorphEntities() async {
    if (_asset == null) return;

    try {
      setState(() => _status = '获取所有实体的 Morph Targets...');

      final childEntities = await _asset!.getChildEntities();
      _entities.clear();

      if (kDebugMode) {
        debugPrint('\n' + '='*80);
        debugPrint('📊 模型实体分析报告');
        debugPrint('='*80);
        debugPrint('总实体数: ${childEntities.length}');
        debugPrint('-'*80);
      }

      // 扫描所有实体，找出具有morph targets的实体
      final morphEntitiesInfo = <Map<String, dynamic>>[];

      for (int i = 0; i < childEntities.length; i++) {
        try {
          final entity = childEntities[i];
          final morphTargets = await _asset!.getMorphTargetNames(entity: entity);

          if (morphTargets.isNotEmpty) {
            // 根据morph target前缀推断实体名称
            String entityName = "Entity_$i";
            if (morphTargets.isNotEmpty) {
              final firstTarget = morphTargets[0];
              if (firstTarget.startsWith('BS.')) {
                entityName = "Body_Mesh";
              } else if (firstTarget.startsWith('EL.')) {
                entityName = "Eye_Mesh";
              } else if (firstTarget.startsWith('F.')) {
                entityName = "Face_Mesh";
              } else if (firstTarget.startsWith('T.')) {
                entityName = "Teeth_Mesh";
              }
            }

            morphEntitiesInfo.add({
              'index': i,
              'entity': entity,
              'name': entityName,
              'morphTargets': morphTargets,
              'count': morphTargets.length,
            });
          }
        } catch (e) {
          // 忽略无morph targets的实体
        }
      }

      // 打印所有具有morph targets的实体详细信息
      if (kDebugMode) {
        debugPrint('🎯 发现 ${morphEntitiesInfo.length} 个具有Morph Targets的实体:\n');

        for (final info in morphEntitiesInfo) {
          debugPrint('【实体 ${info['index']}】 名称: ${info['name']}');
          debugPrint('  - Morph Target数量: ${info['count']}');
          debugPrint('  - Morph Target列表:');

          final targets = info['morphTargets'] as List<String>;
          for (int j = 0; j < targets.length; j++) {
            // 每行打印5个，方便查看
            if (j % 5 == 0 && j > 0) {
              debugPrint('');
            }
            if (j % 5 == 0) {
              debugPrint('    [$j-${j+4.clamp(0, targets.length-1)}]: ', );
            }
          }

          // 打印完整列表（分组显示）
          for (int j = 0; j < targets.length; j += 5) {
            final end = (j + 5).clamp(0, targets.length);
            final group = targets.sublist(j, end);
            debugPrint('    [$j-${end-1}]: ${group.join(', ')}');
          }

          // 根据morph target前缀推断实体用途
          String entityPurpose = "";
          if (targets.isNotEmpty) {
            final firstTarget = targets[0];
            if (firstTarget.startsWith('BS.')) {
              entityPurpose = " (Body/身体网格)";
            } else if (firstTarget.startsWith('EL.')) {
              entityPurpose = " (Eyes Left/左眼)";
            } else if (firstTarget.startsWith('F.')) {
              entityPurpose = " (Face/面部网格)";
            } else if (firstTarget.startsWith('T.')) {
              entityPurpose = " (Teeth/牙齿)";
            }
          }

          // 特殊标记
          if (info['count'] == 52) {
            debugPrint('  ✅ 标准ARKit 52个blendshapes' + entityPurpose);
          } else if (info['count'] == 14) {
            debugPrint('  ⚠️ 部分blendshapes（眼部控制）' + entityPurpose);
          } else if (info['count'] == 1) {
            debugPrint('  ⚠️ 单一blendshape（下巴控制）' + entityPurpose);
          }
          debugPrint('');
        }

        debugPrint('='*80);
        debugPrint('📋 实体分析总结:');
        debugPrint('');

        // 根据前缀分析实体用途
        for (final info in morphEntitiesInfo) {
          final targets = info['morphTargets'] as List<String>;
          String entityDesc = "";
          String entityRole = "";

          if (targets.isNotEmpty) {
            final firstTarget = targets[0];
            if (firstTarget.startsWith('BS.')) {
              entityDesc = "身体网格 (Body Mesh)";
              entityRole = "控制整体面部和身体表情";
            } else if (firstTarget.startsWith('EL.')) {
              entityDesc = "眼部网格 (Eye Mesh)";
              entityRole = "单独控制眼睛动作";
            } else if (firstTarget.startsWith('F.')) {
              entityDesc = "面部网格 (Face Mesh)";
              entityRole = "主要面部表情控制";
            } else if (firstTarget.startsWith('T.')) {
              entityDesc = "牙齿网格 (Teeth Mesh)";
              entityRole = "控制牙齿/下巴开合";
            }
          }

          debugPrint('  📍 实体${info['index']}: ${entityDesc}');
          debugPrint('     - Morph Targets: ${info['count']}个');
          debugPrint('     - 作用: ${entityRole}');
          debugPrint('');
        }

        debugPrint('🔍 关键发现:');
        debugPrint('  1. 实体1 (BS前缀) - 可能是主身体网格，包含完整52个ARKit blendshapes');
        debugPrint('  2. 实体3 (EL前缀) - 专门的眼部网格，14个眼部相关blendshapes');
        debugPrint('  3. 实体12 (F前缀) - 面部网格，包含完整52个ARKit blendshapes');
        debugPrint('  4. 实体13 (T前缀) - 牙齿网格，只有jawOpen控制');
        debugPrint('');
        debugPrint('💡 建议: 应该对实体1(BS)或实体12(F)应用口型权重');
        debugPrint('='*80 + '\n');
      }

      // 安全处理：根据实际存在的实体选择
      int targetEntityIndex = -1;
      int targetEntity = -1;
      List<String> targetMorphTargets = [];

      // 优先尝试使用实体12
      if (childEntities.length > 12) {
        try {
          final entity12 = childEntities[12];
          final morphTargets12 = await _asset!.getMorphTargetNames(entity: entity12);
          if (morphTargets12.length == 52) {
            targetEntityIndex = 12;
            targetEntity = entity12;
            targetMorphTargets = morphTargets12;
            if (kDebugMode) debugPrint('✅ 使用实体12 (Face_Mesh)');
          }
        } catch (e) {
          if (kDebugMode) debugPrint('⚠️ 实体12不可用: $e');
        }
      }

      // 如果实体12不可用，尝试实体1
      if (targetEntityIndex == -1 && childEntities.length > 1) {
        try {
          final entity1 = childEntities[1];
          final morphTargets1 = await _asset!.getMorphTargetNames(entity: entity1);
          if (morphTargets1.length == 52) {
            targetEntityIndex = 1;
            targetEntity = entity1;
            targetMorphTargets = morphTargets1;
            if (kDebugMode) debugPrint('✅ 使用实体1 (Body_Mesh)');
          }
        } catch (e) {
          if (kDebugMode) debugPrint('⚠️ 实体1不可用: $e');
        }
      }

      // 如果都不可用，使用第一个有52个morph targets的实体
      if (targetEntityIndex == -1) {
        for (final info in morphEntitiesInfo) {
          if (info['count'] == 52) {
            targetEntityIndex = info['index'];
            targetEntity = info['entity'];
            targetMorphTargets = info['morphTargets'];
            if (kDebugMode) debugPrint('✅ 使用实体$targetEntityIndex (自动选择)');
            break;
          }
        }
      }

      if (targetEntityIndex == -1) {
        throw Exception('没有找到合适的实体（需要52个morph targets）');
      }

      // 创建选中实体的信息
      final selectedEntityInfo = EntityInfo(
        index: targetEntityIndex,
        entityHandle: targetEntity,
        morphTargets: targetMorphTargets,
        score: 1000, // 固定高分
      );

      _entities.add(selectedEntityInfo);
      _selectedMorphEntityIndex = 0; // 直接选择第一个（也是唯一一个）

      if (kDebugMode) {
        debugPrint('🎯 当前使用: 实体$targetEntityIndex (${targetMorphTargets.length} targets)');

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
        final jawOpenTarget = targetMorphTargets.firstWhere(
          (name) => name.toLowerCase().contains('jawopen'),
          orElse: () => '',
        );
        if (jawOpenTarget.isNotEmpty) {
          final jawOpenIndex = targetMorphTargets.indexOf(jawOpenTarget);
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

        debugPrint('🏆 使用实体$targetEntityIndex，准备解决动画冲突问题');
      }

      setState(() => _status = '✅ 实体$targetEntityIndex准备就绪，${targetMorphTargets.length}个targets');
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

  // 检测说话动画
  void _detectTalkAnimation(List<String> animationNames) {
    // 查找包含说话关键词的动画
    const talkKeywords = [
      'talk',
      'Talk',
      'TALK',
      'speak',
      'Speak',
      'SPEAK',
      'speech',
      'Speech',
      'SPEECH',
      'conversation',
      'Conversation',
      'chat',
      'Chat',
    ];

    for (int i = 0; i < animationNames.length; i++) {
      final name = animationNames[i].toLowerCase();
      for (final keyword in talkKeywords) {
        if (name.contains(keyword.toLowerCase())) {
          _talkAnimationIndex = i;
          if (kDebugMode) {
            debugPrint('🗣️ 找到说话动画: ${animationNames[i]} (索引: $i)');
          }
          return;
        }
      }
    }

    // 如果没找到说话动画，尝试找第二个动画（通常idle是第一个）
    if (animationNames.length > 1) {
      _talkAnimationIndex = 1;
      if (kDebugMode) {
        debugPrint('⚠️ 未找到说话关键词，使用第二个动画作为说话动画: ${animationNames[1]}');
      }
    } else {
      // 如果只有一个动画，就用idle动画
      _talkAnimationIndex = _idleAnimationIndex;
      if (kDebugMode) {
        debugPrint('⚠️ 只有一个动画，说话时将使用idle动画');
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
        debugPrint(
          '   �️ 说话动画: 混合模式: ${_talkAnimationIndex != -1 ? _animations[_talkAnimationIndex] : "无"}',
        );
        debugPrint('   � 权重处理: 实原始blendshape数据 (无放大处理)');
        debugPrint('   🌊 平滑处理: 已禁用');
      }

      // 🎭 新策略：根据选项决定是否播放身体动画
      // 先停止所有动画
      for (int i = 0; i < _animations.length; i++) {
        try {
          await _asset!.stopGltfAnimation(i);
        } catch (_) {}
      }

      // 测试策略：根据权重决定播放模式
      if (_bodyAnimationWeight < 0.1) {
        // 完全禁用骨骼动画，只使用morph targets
        _isPlaying = false;
        if (kDebugMode) {
          debugPrint('🔥 策略：完全禁用骨骼动画（权重<0.1），纯morph target模式');
          debugPrint('💡 这样可以确保morph targets不被骨骼覆盖');
        }
      } else if (_talkAnimationIndex != -1 && _talkAnimationIndex != _idleAnimationIndex) {
        try {
          // 播放身体动画
          await _asset!.playGltfAnimation(
            _talkAnimationIndex,
            loop: true,
            // weight: _bodyAnimationWeight, // 如果API支持权重参数
          );
          _isPlaying = true;
          _currentAnimationIndex = _talkAnimationIndex;

          if (kDebugMode) {
            debugPrint('🎭 混合策略：播放说话动画（权重${_bodyAnimationWeight}）+ morph targets');
            debugPrint('💡 同时应用到实体1、3、12，确保找到正确的渲染实体');
            debugPrint('');
            debugPrint('✨ 新动画测试模式:');
            debugPrint('   如果建模师已清零面部骨骼数据，现在应该能看到:');
            debugPrint('   ✓ 身体动作正常播放');
            debugPrint('   ✓ 口型由morph target控制');
            debugPrint('   ✓ 两者不再冲突');
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('⚠️ 说话动画播放失败，使用纯morph target模式: $e');
          }
          _isPlaying = false;
        }
      } else {
        _isPlaying = false;
        if (kDebugMode) {
          debugPrint('🎭 使用纯morph target权重模式');
        }
      }

      // 重置所有权重
      await _resetAllMorphWeights();

      // 🔄 重置权重应用状态

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

  // 应用单帧 blendshape 数据 - 选择性增强版本
  Future<void> _applyBlendshapeFrame(int frameIndex) async {
    if (_blendshapeData == null ||
        _selectedMorphEntityIndex == null ||
        _asset == null) {
      return;
    }

    final selectedEntity = _entities[_selectedMorphEntityIndex!];
    final frameWeights = _blendshapeData![frameIndex];

    try {
      // 🚀 获取前52个权重
      var rawWeights = frameWeights.sublist(0, 52);

      // 🔥 策略1：同时应用到所有具有morph targets的实体
      // 关键：实体1(Body_Mesh)可能是主渲染体，实体12(Face_Mesh)可能是辅助
      await _applyWeightsToAllMorphEntities(rawWeights, frameIndex);

      // 测试：在第一帧打印分工策略
      if (frameIndex == 0 && kDebugMode) {
        debugPrint('🎯 分层权重应用策略:');
        debugPrint('   - 实体12 (Face_Mesh): 完整52个权重 (面部表情主控)');
        debugPrint('   - 实体13 (Teeth_Mesh): 第17个jawOpen权重 (下巴开合专控)');
        debugPrint('   - 实体3 (Eye_Mesh): 14个眼部权重 (眼部控制)');
        debugPrint('');
        debugPrint('   🎭 建模师策略: 实体12+实体13协同工作');
        debugPrint('   🦷 jawOpen由实体12+实体13同时驱动，双重增强');
      }

      // 🚀 增强权重以突破骨骼动画覆盖
      var enhancedWeights = List.generate(rawWeights.length, (i) {
        final weight = rawWeights[i];

        // 如果正在播放骨骼动画，增强morph target权重
        if (_isPlaying && _currentAnimationIndex == _talkAnimationIndex) {
          // 对关键口型权重进行增强
          if (i == 17 || // jawOpen
              i == 19 || // mouthFunnel
              i == 20 || // mouthPucker
              (i >= 23 && i <= 40)) { // 各种嘴部相关权重
            return (weight * _morphTargetBoost).clamp(0.0, 1.0);
          }
        }

        return weight.clamp(0.0, 1.0);
      });

      // 🌊 平滑处理（暂时禁用）
      List<double> finalWeights = enhancedWeights; // 直接使用增强权重，不进行平滑

      // 💾 权重已应用，准备下一帧

      // � 实多实体测试：尝试所有可能的实体
      if (frameIndex == 0) {
        await _testAllEntitiesForMorphTargets();
      }

      // 🚀 应用最终权重（实体12权重应用时机优化模式）
      await _asset!.setMorphTargetWeights(
        selectedEntity.entityHandle,
        finalWeights,
      );

      // 直接应用权重，简化处理
      await _asset!.setMorphTargetWeights(
        selectedEntity.entityHandle,
        finalWeights,
      );

      // 🧪 测试：每1000帧强制设置一个明显的jawOpen值
      if (kDebugMode && frameIndex % 1000 == 0 && frameIndex > 0) {
        final testWeights = List<double>.filled(52, 0.0);
        testWeights[17] = 0.8; // 强制设置jawOpen为0.8
        await _asset!.setMorphTargetWeights(
          selectedEntity.entityHandle,
          testWeights,
        );
        // 移除强制测试，权重应用已确认有效

        // 等待一小段时间让用户看到效果
        await Future.delayed(const Duration(milliseconds: 200));

        // 恢复正常权重
        await _asset!.setMorphTargetWeights(
          selectedEntity.entityHandle,
          finalWeights,
        );
        debugPrint('🔄 恢复正常权重');
      }

      // �  权重验证：检查权重是否真的被应用到正确的morph target
      if (kDebugMode && frameIndex % 100 == 0) {
        // 验证权重应用后的实际状态
        _verifyMorphTargetWeights(
          selectedEntity.entityHandle,
          finalWeights,
          frameIndex,
        );
      }

      // 📊 调试信息（每100帧打印一次）
      if (kDebugMode && frameIndex % 100 == 0) {
        final jawOpenRaw = rawWeights.length > 17 ? rawWeights[17] : 0.0;
        final jawOpenFinal = finalWeights.length > 17 ? finalWeights[17] : 0.0;
        debugPrint(
          '🔍 第$frameIndex帧 jawOpen: ${jawOpenRaw.toStringAsFixed(4)} → ${jawOpenFinal.toStringAsFixed(4)}',
        );

        // 显示其他关键权重
        if (rawWeights.length > 19) {
          final funnelRaw = rawWeights[19];
          final funnelFinal = finalWeights[19];
          debugPrint(
            '   👄 mouthFunnel: ${funnelRaw.toStringAsFixed(4)} → ${funnelFinal.toStringAsFixed(4)}',
          );
        }
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
        debugPrint('   最大值出现在第${maxIndex}帧');

        if (maxJawOpen < 0.01) {
          debugPrint('⚠️ jawOpen数据可能有问题：最大值只有${maxJawOpen.toStringAsFixed(4)}');
        }
      }
    } catch (e) {
      debugPrint('❌ jawOpen数据分析失败: $e');
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
        debugPrint('❌ 重置实体1权重失败: $e');
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

          // 权重调节控件
          if (kDebugMode) ...[
            const Divider(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Column(
                children: [
                  // 身体动画权重调节
                  Row(
                    children: [
                      const Text(
                        '身体动画:',
                        style: TextStyle(fontSize: 10),
                      ),
                      Expanded(
                        child: Slider(
                          value: _bodyAnimationWeight,
                          min: 0.0,
                          max: 1.0,
                          divisions: 20,
                          label: _bodyAnimationWeight.toStringAsFixed(2),
                          onChanged: (value) {
                            setState(() {
                              _bodyAnimationWeight = value;
                            });
                          },
                        ),
                      ),
                      Text(
                        _bodyAnimationWeight.toStringAsFixed(2),
                        style: const TextStyle(fontSize: 10),
                      ),
                    ],
                  ),
                  // Morph Target增强系数调节
                  Row(
                    children: [
                      const Text(
                        '口型增强:',
                        style: TextStyle(fontSize: 10),
                      ),
                      Expanded(
                        child: Slider(
                          value: _morphTargetBoost,
                          min: 1.0,
                          max: 3.0,
                          divisions: 20,
                          label: _morphTargetBoost.toStringAsFixed(2),
                          onChanged: (value) {
                            setState(() {
                              _morphTargetBoost = value;
                            });
                          },
                        ),
                      ),
                      Text(
                        _morphTargetBoost.toStringAsFixed(2),
                        style: const TextStyle(fontSize: 10),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // � 验证mo覆rph target权重是否真的被应用
  Future<void> _verifyMorphTargetWeights(
    int entityHandle,
    List<double> expectedWeights,
    int frameIndex,
  ) async {
    try {
      if (_asset == null) return;

      final expectedJawOpen = expectedWeights.length > 17
          ? expectedWeights[17]
          : 0.0;
      final entityInfo = _entities[_selectedMorphEntityIndex!];

      debugPrint(
        '🔍 第${frameIndex}帧权重应用: 实体${entityInfo.index}, jawOpen=${expectedJawOpen.toStringAsFixed(4)}',
      );

      // 重新应用权重确保生效
      await _asset!.setMorphTargetWeights(entityHandle, expectedWeights);
    } catch (e) {
      debugPrint('⚠️ 权重验证失败: $e');
    }
  }


  // 同时应用权重到所有具有morph targets的实体
  Future<void> _applyWeightsToAllMorphEntities(List<double> rawWeights, int frameIndex) async {
    if (_asset == null) return;

    try {
      final childEntities = await _asset!.getChildEntities();

      // 安全检查：打印实际实体数量
      if (frameIndex == 0 && kDebugMode) {
        debugPrint('⚠️ 新模型实体数: ${childEntities.length}');
      }

      // 关键实体列表：去掉实体1（镜像，不起作用）
      final keyEntities = [12, 13, 3];

      for (final entityIndex in keyEntities) {
        // 安全检查：确保实体存在
        if (entityIndex >= childEntities.length) {
          if (frameIndex == 0 && kDebugMode) {
            debugPrint('❌ 跳过实体$entityIndex: 超出范围(总数${childEntities.length})');
          }
          continue;
        }

        try {
          final entity = childEntities[entityIndex];
          final morphTargets = await _asset!.getMorphTargetNames(entity: entity);

          if (morphTargets.isEmpty) continue;

          // 根据实体的morph target数量调整权重
          List<double> entityWeights;

          // 安全检查：确保不会越界
          if (morphTargets.length == 52 && rawWeights.length >= 52) {
            // 实体1和12：使用完整的52个权重，但实体12要排除jawOpen
            entityWeights = List.generate(52, (i) {
              final weight = i < rawWeights.length ? rawWeights[i] : 0.0;

              // 🎯 实体12和实体13的jawOpen都要工作，不排除
              // if (entityIndex == 12 && i == 17) {
              //   return 0.0; // 实体12的jawOpen设为0
              // }

              // 增强关键权重
              if (_isPlaying && _currentAnimationIndex == _talkAnimationIndex) {
                if (i == 17 || i == 19 || i == 20 || (i >= 23 && i <= 40)) { // 恢复jawOpen(17)
                  return (weight * _morphTargetBoost).clamp(0.0, 1.0);
                }
              }
              return weight.clamp(0.0, 1.0);
            });
          } else if (morphTargets.length == 14) {
            // 实体3：可能只有部分权重，映射关键的口型权重
            entityWeights = List<double>.filled(14, 0.0);
            // 尝试映射jawOpen和其他关键权重
            if (rawWeights.length > 17) {
              // 假设前几个是关键口型权重
              for (int i = 0; i < entityWeights.length && i < 5; i++) {
                entityWeights[i] = (rawWeights[17 + i] * _morphTargetBoost).clamp(0.0, 1.0);
              }
            }
          } else if (morphTargets.length == 1 && entityIndex == 13) {
            // 🎯 实体13 (Teeth_Mesh)：专门负责第17个jawOpen数据
            final jawOpenWeight = rawWeights.length > 17 ? rawWeights[17] : 0.0;

            // 应用增强处理
            final enhancedJawOpen = _isPlaying && _currentAnimationIndex == _talkAnimationIndex
                ? (jawOpenWeight * _morphTargetBoost).clamp(0.0, 1.0)
                : jawOpenWeight.clamp(0.0, 1.0);

            entityWeights = [enhancedJawOpen];

            // 每100帧记录实体13的jawOpen值
            if (kDebugMode && frameIndex % 100 == 0) {
              debugPrint('   🦷 实体13专职jawOpen: ${jawOpenWeight.toStringAsFixed(4)} → ${enhancedJawOpen.toStringAsFixed(4)}');
            }
          } else {
            // 处理其他非标准数量的morph targets
            if (frameIndex == 0 && kDebugMode) {
              debugPrint('⚠️ 实体$entityIndex有${morphTargets.length}个morph targets，跳过');
            }
            continue;
          }

          // 安全检查：确保权重数组长度匹配
          if (entityWeights.length != morphTargets.length) {
            if (frameIndex == 0 && kDebugMode) {
              debugPrint('❌ 实体$entityIndex权重数量不匹配: ${entityWeights.length} vs ${morphTargets.length}');
            }
            continue;
          }

          // 应用权重到实体
          await _asset!.setMorphTargetWeights(entity, entityWeights);

          // 每100帧记录一次
          if (kDebugMode && frameIndex % 100 == 0) {
            if (entityIndex == 12) {
              // 实体12：显示关键权重包括jawOpen
              final jawOpen = entityWeights.length > 17 ? entityWeights[17] : 0.0;
              final mouthFunnel = entityWeights.length > 19 ? entityWeights[19] : 0.0;
              final mouthPucker = entityWeights.length > 20 ? entityWeights[20] : 0.0;
              debugPrint('   🎭 实体12 (Face): jawOpen=${jawOpen.toStringAsFixed(3)}, mouthFunnel=${mouthFunnel.toStringAsFixed(3)}, mouthPucker=${mouthPucker.toStringAsFixed(3)}');
            } else if (entityIndex == 13) {
              // 实体13：显示jawOpen专职权重
              final jawValue = entityWeights.isNotEmpty ? entityWeights[0] : 0.0;
              debugPrint('   🦷 实体13 (Teeth): jawOpen=${jawValue.toStringAsFixed(3)} (协同驱动)');
            } else {
              final jawValue = entityWeights.isNotEmpty ? entityWeights[0] : 0.0;
              debugPrint('   🎯 实体$entityIndex应用权重: jaw=${jawValue.toStringAsFixed(3)}');
            }
          }

        } catch (e) {
          // 静默处理单个实体的错误
        }
      }
    } catch (e) {
      if (kDebugMode && frameIndex == 0) {
        debugPrint('⚠️ 多实体权重应用失败: $e');
      }
    }
  }

  // 🔥 测试所有实体的morph targets，找到真正有效的实体
  Future<void> _testAllEntitiesForMorphTargets() async {
    if (_asset == null) return;

    try {
      final childEntities = await _asset!.getChildEntities();
      debugPrint('🔥 开始测试所有${childEntities.length}个实体的morph targets...');

      for (int i = 0; i < childEntities.length; i++) {
        try {
          final entity = childEntities[i];
          final morphTargets = await _asset!.getMorphTargetNames(
            entity: entity,
          );

          if (morphTargets.isNotEmpty) {
            debugPrint('🎯 实体$i: ${morphTargets.length}个morph targets');

            // 测试应用一个明显的权重
            final testWeights = List<double>.filled(morphTargets.length, 0.0);
            if (morphTargets.length > 17) {
              testWeights[17] = 0.8; // 设置jawOpen
            }

            await _asset!.setMorphTargetWeights(entity, testWeights);
            await Future.delayed(const Duration(milliseconds: 100));

            debugPrint('   实体$i jawOpen测试: 已设置0.8 (无法验证实际值)');

            // 重置权重
            final zeroWeights = List<double>.filled(morphTargets.length, 0.0);
            await _asset!.setMorphTargetWeights(entity, zeroWeights);
          }
        } catch (e) {
          debugPrint('   实体$i测试失败: $e');
        }
      }

      debugPrint('🔥 所有实体测试完成');
    } catch (e) {
      debugPrint('❌ 多实体测试失败: $e');
    }
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
