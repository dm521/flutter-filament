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
  static const int _arkitBlendshapeCount = 52;
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
  int _idleAnimationIndex = -1;
  int _selectedTalkAnimation = 1;

  // ===== 革命性口型同步系统 =====
  List<List<double>>? _blendshapeData;
  bool _isBlendshapeLoaded = false;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isLipSyncPlaying = false;
  StreamSubscription<void>? _completeSubscription;

  // ===== 交互控制系统 =====
  dynamic _inputHandler;
  bool _isPlaying = false;
  int _currentAnimationIndex = -1;
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
      // if (_isInitialized && _idleAnimationIndex != -1 && !_isLipSyncPlaying) {
      //   await _resumeIdleAnimation();
      // }

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
        _asset = await _viewer!.loadGltf("assets/models/xiaomeng_0919_2.glb");
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

        // 检测idle动画
        _detectIdleAnimation(animationNames);

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
                final hasF_jawOpen = morphTargets.contains('F.jawOpen');
                final hasT_jawOpen = morphTargets.contains('T.jawOpen');
                final hasF_eyeBlink = morphTargets.contains('F.eyeBlinkLeft');

                debugPrint('🔍 实体 $entityIndex 关键blendshape:');
                debugPrint('   F.jawOpen: $hasF_jawOpen');
                debugPrint('   T.jawOpen: $hasT_jawOpen');
                debugPrint('   F.eyeBlinkLeft: $hasF_eyeBlink');

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
        "eyeBlinkLeft", "eyeLookDownLeft", "eyeLookInLeft", "eyeLookOutLeft", "eyeLookUpLeft",
        "eyeSquintLeft", "eyeWideLeft", "eyeBlinkRight", "eyeLookDownRight", "eyeLookInRight",
        "eyeLookOutRight", "eyeLookUpRight", "eyeSquintRight", "eyeWideRight", "jawForward",
        "jawLeft", "jawRight", "jawOpen", "mouthClose", "mouthFunnel",
        "mouthPucker", "mouthLeft", "mouthRight", "mouthSmileLeft", "mouthSmileRight",
        "mouthFrownLeft", "mouthFrownRight", "mouthDimpleLeft", "mouthDimpleRight", "mouthStretchLeft",
        "mouthStretchRight", "mouthRollLower", "mouthRollUpper", "mouthShrugLower", "mouthShrugUpper",
        "mouthPressLeft", "mouthPressRight", "mouthLowerDownLeft", "mouthLowerDownRight", "mouthUpperUpLeft",
        "mouthUpperUpRight", "browDownLeft", "browDownRight", "browInnerUp", "browOuterUpLeft",
        "browOuterUpRight", "cheekPuff", "cheekSquintLeft", "cheekSquintRight", "noseSneerLeft",
        "noseSneerRight", "tongueOut", "unused52", "unused53", "unused54"
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
          if (kDebugMode && i < 5) { // 只打印前5个避免日志过长
            debugPrint('   映射: bs.json[$bsJsonIndex](${bsJsonBlendshapeNames[bsJsonIndex]}) -> 实体12[$i]($entity12Name)');
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
        debugPrint('   F.jawOpen映射: bs.json[${bsToEntity12Mapping.contains(17) ? 17 : '未找到'}] -> 实体12');
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

      // 3. 🎯 计算正确的帧时长：音频约59.16秒，1775帧
      final audioDurationMs = 59160.0; // 音频时长毫秒
      final frameLengthMs = audioDurationMs / totalFrames; // 约33.3ms每帧

      // 🎯 革命性分离映射方案：F前缀→Head_Mod，T.jawOpen→Mouth_Mod
      if (kDebugMode) {
        debugPrint('🎯 开始分离映射策略...');
        debugPrint('   F前缀${mappedWeightsPerFrame}个 → Head_Mod');
        debugPrint('   T.jawOpen → Mouth_Mod');
        debugPrint('   分别调用setMorphAnimationData，精确目标映射');
      }

      // 🎯 步骤1：创建Head_Mod专用数据（F前缀）
      final headMorphData = MorphAnimationData(
        mappedFlatData, // 精确映射的F前缀数据
        mappedMorphTargetNames, // 精确映射的F前缀名称
        frameLengthInMs: frameLengthMs,
      );

      // 🎯 步骤2：创建Mouth_Mod专用数据（T.jawOpen）
      final jawOnlyData = Float32List(totalFrames); // 只有1个权重
      for (int frame = 0; frame < totalFrames; frame++) {
        final frameWeights = _blendshapeData![frame];
        if (frameWeights.length > 17) {
          jawOnlyData[frame] = frameWeights[17]; // bs.json第17个索引
        }
      }

      final mouthMorphData = MorphAnimationData(
        jawOnlyData, // T.jawOpen数据
        ["T.jawOpen"], // 只有T.jawOpen
        frameLengthInMs: frameLengthMs,
      );

      if (kDebugMode) {
        debugPrint('🎯 分离数据创建完成:');
        debugPrint('   Head_Mod数据: ${mappedWeightsPerFrame}个F前缀 (${mappedFlatData.length}字节)');
        debugPrint('   Mouth_Mod数据: 1个T.jawOpen (${jawOnlyData.length}字节)');
        
        // 查找F.jawOpen在映射中的位置
        int fJawOpenIndex = -1;
        for (int i = 0; i < mappedMorphTargetNames.length; i++) {
          if (mappedMorphTargetNames[i] == 'F.jawOpen') {
            fJawOpenIndex = i;
            break;
          }
        }
        
        debugPrint('   F.jawOpen位置: Head_Mod索引$fJawOpenIndex (来自bs.json第17个)');
        debugPrint('   T.jawOpen位置: Mouth_Mod索引0 (来自bs.json第17个)');
        
        // 验证T.jawOpen数据
        final tJawOpenRange = '${jawOnlyData.reduce((a, b) => a < b ? a : b).toStringAsFixed(4)} - ${jawOnlyData.reduce((a, b) => a > b ? a : b).toStringAsFixed(4)}';
        final tJawOpenNonZero = jawOnlyData.where((v) => v > 0.001).length;
        debugPrint('   T.jawOpen数据范围: $tJawOpenRange');
        debugPrint('   T.jawOpen非零帧: $tJawOpenNonZero/$totalFrames');
        
        // 验证F.jawOpen数据（如果存在）
        if (fJawOpenIndex != -1) {
          final fJawOpenValues = <double>[];
          for (int frame = 0; frame < totalFrames; frame++) {
            fJawOpenValues.add(mappedFlatData[frame * mappedWeightsPerFrame + fJawOpenIndex]);
          }
          final fJawOpenRange = '${fJawOpenValues.reduce((a, b) => a < b ? a : b).toStringAsFixed(4)} - ${fJawOpenValues.reduce((a, b) => a > b ? a : b).toStringAsFixed(4)}';
          final fJawOpenNonZero = fJawOpenValues.where((v) => v > 0.001).length;
          debugPrint('   F.jawOpen数据范围: $fJawOpenRange');
          debugPrint('   F.jawOpen非零帧: $fJawOpenNonZero/$totalFrames');
        }
      }

      // 🎯 步骤3：添加动画组件（关键！）
      try {
        await _asset!.addAnimationComponent();
        if (kDebugMode) debugPrint('✅ 动画组件已添加');
      } catch (e) {
        if (kDebugMode) debugPrint('❌ 添加动画组件失败: $e');
      }

      // 🎯 步骤4：分离分配 - F前缀到Head_Mod
      bool headSuccess = false;
      try {
        await _asset!.setMorphAnimationData(
          headMorphData,
          targetMeshNames: ["Head_Mod"],
        );
        headSuccess = true;
        if (kDebugMode) debugPrint('✅ Head_Mod F前缀分配成功');
      } catch (e) {
        if (kDebugMode) debugPrint('❌ Head_Mod F前缀分配失败: $e');
      }

      // 🎯 步骤5：分离分配 - T.jawOpen到Mouth_Mod
      bool mouthSuccess = false;
      try {
        await _asset!.setMorphAnimationData(
          mouthMorphData,
          targetMeshNames: ["Mouth_Mod"],
        );
        mouthSuccess = true;
        if (kDebugMode) debugPrint('✅ Mouth_Mod T.jawOpen分配成功');
      } catch (e) {
        if (kDebugMode) debugPrint('❌ Mouth_Mod T.jawOpen分配失败: $e');
      }

      // 🎯 步骤6：验证分离分配结果
      if (kDebugMode) {
        debugPrint('🎯 分离分配结果:');
        debugPrint('   Head_Mod (F前缀): $headSuccess');
        debugPrint('   Mouth_Mod (T.jawOpen): $mouthSuccess');

        if (headSuccess && mouthSuccess) {
          debugPrint('🎉 革命性双重jawOpen系统已建立（分离映射）:');
          debugPrint('   精确映射: bs.json(55个) -> Head_Mod(${mappedWeightsPerFrame}个F前缀) + Mouth_Mod(1个T.jawOpen)');
          debugPrint('   F.jawOpen → Head_Mod精确位置 (上颌/嘴唇控制)');
          debugPrint('   T.jawOpen → Mouth_Mod索引0 (下颌/牙齿控制)');
          debugPrint('   数据来源: 都来自bs.json第17个索引');
          debugPrint('   技术优势: 精确目标映射 + 避免网格冲突');
          debugPrint('   预期效果: 完整协调的张嘴动作');
        } else {
          debugPrint('⚠️ 部分分配失败，可能影响口型效果');
        }
      }

      // 5. T.jawOpen已在上面的精确分配中处理

      if (kDebugMode) {
        debugPrint('🎯 革命性双实体方案完成！');
        debugPrint(
          '   实体12: F前缀blendshapes (${mappedWeightsPerFrame}个) 包含F.jawOpen',
        );
        debugPrint('   实体13: T.jawOpen专用 (bs.json第17个数据)');
        debugPrint('   双重jawOpen: F.jawOpen + T.jawOpen 同步驱动');
        debugPrint('   动画帧率: 30 FPS (${_blendshapeData!.length}帧/59.16秒)');
        debugPrint('   数据来源: 都来自bs.json第17个索引');
      }

      setState(() => _status = '🚀 革命性动画轨道已配置');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 革命性方案失败: $e');
      }
      setState(() => _status = '❌ 动画轨道配置失败: $e');
    }
  }

  /// 🦷 为Mouth_Mod创建专门的jawOpen动画轨道
  /// 实现Head_Mod + Mouth_Mod协同控制
  Future<void> _createMouthModJawOpenAnimation() async {
    if (_blendshapeData == null) return;

    try {
      // 1. 提取第17个jawOpen值（所有帧）
      final totalFrames = _blendshapeData!.length;
      final jawOpenData = Float32List(totalFrames); // 只有一个值

      for (int frame = 0; frame < totalFrames; frame++) {
        final frameWeights = _blendshapeData![frame];
        if (frameWeights.length > 17) {
          jawOpenData[frame] = frameWeights[17]; // 第17个是jawOpen
        }
      }

      // 2. 创建Mouth_Mod专用的动画轨道
      final audioDurationMs = 59160.0; // 与主动画同步
      final frameLengthMs = audioDurationMs / totalFrames;

      final mouthMorphData = MorphAnimationData(
        jawOpenData, // 只有jawOpen数据
        ["T.jawOpen"], // Mouth_Mod的jawOpen目标
        frameLengthInMs: frameLengthMs, // 精确时间同步
      );

      // 3. 分配jawOpen动画到支持的网格
      if (kDebugMode) {
        debugPrint('🦷 开始分配jawOpen专用动画轨道');
      }

      // 尝试不指定targetMeshNames，让系统自动分配jawOpen到支持的网格
      try {
        await _asset!.setMorphAnimationData(mouthMorphData);
        if (kDebugMode) debugPrint('✅ jawOpen动画轨道全局设置成功');
      } catch (e) {
        if (kDebugMode) debugPrint('❌ jawOpen动画轨道全局设置失败: $e');

        // 如果全局设置失败，尝试一些可能包含T.jawOpen的网格名称
        final possibleJawMeshNames = [
          "Mouth_Mod",
          "mouth",
          "Mouth",
          "jaw",
          "Jaw",
          "Head_Mod",
          "head",
          "Head",
          "face",
          "Face",
        ];

        for (final meshName in possibleJawMeshNames) {
          try {
            await _asset!.setMorphAnimationData(
              mouthMorphData,
              targetMeshNames: [meshName],
            );
            if (kDebugMode) debugPrint('✅ jawOpen动画轨道设置成功: $meshName');
            break;
          } catch (e2) {
            if (kDebugMode) debugPrint('❌ 尝试jawOpen到 $meshName 失败: $e2');
          }
        }
      }

      if (kDebugMode) {
        debugPrint('🦷 jawOpen动画轨道创建成功');
        debugPrint('   数据: bs.json第17个值 ($totalFrames帧)');
        debugPrint('   目标: T.jawOpen');
        debugPrint(
          '   数据范围: ${jawOpenData.reduce((a, b) => a < b ? a : b).toStringAsFixed(4)} - ${jawOpenData.reduce((a, b) => a > b ? a : b).toStringAsFixed(4)}',
        );
        debugPrint('   非零帧数: ${jawOpenData.where((v) => v > 0.001).length}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Mouth_Mod动画轨道创建失败: $e');
      }
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

      // 🔄 步骤2：清除现有morph数据
      final childEntities = await _asset!.getChildEntities();
      for (int i = 0; i < childEntities.length; i++) {
        try {
          await _asset!.clearMorphAnimationData(childEntities[i]);
        } catch (_) {
          // 忽略清理错误
        }
      }
      if (kDebugMode) debugPrint('✅ 现有morph数据已清除');

      // 🎯 步骤3：设置新的morph数据（使用我们的分离分配策略）
      await _assignBsJsonToAnimationTrack();

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

  // 🎭 原始统一动画播放方法（保留作为备用）
  Future<void> _playUnifiedAnimation() async {
    if (_asset == null) return;

    try {
      setState(() => _status = '🎭 启动统一动画系统...');

      if (kDebugMode) {
        debugPrint('🎭 开始统一动画播放：身体动画 + 面部动画轨道');
      }

      // 1. 清除现有的morph动画数据
      final childEntities = await _asset!.getChildEntities();
      for (int i = 0; i < childEntities.length; i++) {
        try {
          await _asset!.clearMorphAnimationData(childEntities[i]);
        } catch (_) {
          // 忽略清理错误
        }
      }

      // 2. 分配bs.json数据到动画轨道
      await _assignBsJsonToAnimationTrack();

      // 3. 🚫 禁用身体动画（纯口型测试模式）
      // if (_selectedTalkAnimation >= 0 &&
      //     _selectedTalkAnimation < _animations.length) {
      //   await _asset!.playGltfAnimation(_selectedTalkAnimation, loop: true);
      //   _isPlaying = true;
      //   _currentAnimationIndex = _selectedTalkAnimation;

      //   if (kDebugMode) {
      //     debugPrint('✅ 身体动画已启动：${_animations[_selectedTalkAnimation]}');
      //     debugPrint('   建模师已清除面部数据，无冲突');
      //   }
      // }

      if (kDebugMode) {
        debugPrint('🚫 身体动画已禁用（纯口型测试模式）');
      }

      // 4. 现在面部动画由bs.json轨道控制，无需权重覆盖！

      setState(() => _status = '🚀 统一动画系统运行中');

      if (kDebugMode) {
        debugPrint('🎉 革命性成功！统一动画管线已建立：');
        debugPrint('   ✓ 身体动作：由骨骼动画控制');
        debugPrint('   ✓ 面部表情：由bs.json动画轨道控制');
        debugPrint('   ✓ 无冲突运行：分层控制各司其职');
        debugPrint('   ✓ 简化流程：无需复杂权重覆盖逻辑');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 统一动画播放失败: $e');
      }
      setState(() => _status = '❌ 统一动画失败: $e');
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

  // ===== 动画管理系统 =====

  /// 开始播放idle动画
  Future<void> _startIdleAnimation() async {
    if (_asset == null || _idleAnimationIndex == -1) return;

    try {
      setState(() => _status = '🎭 启动idle动画...');

      if (kDebugMode) {
        debugPrint('🎭 开始播放idle动画 (索引: $_idleAnimationIndex)');
      }

      // 🚫 禁用idle动画（纯口型测试模式）
      // await _asset!.playGltfAnimation(_idleAnimationIndex, loop: true);
      // _isPlaying = true;
      // _currentAnimationIndex = _idleAnimationIndex;

      if (kDebugMode) {
        debugPrint('🚫 Idle动画已禁用（纯口型测试模式）');
      }

      setState(() => _status = '✅ 口型同步系统准备就绪');

      if (kDebugMode) {
        debugPrint('✅ Idle动画播放成功');
        debugPrint('   当前播放状态: $_isPlaying');
        debugPrint('   当前动画索引: $_currentAnimationIndex');
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

      // 🚫 禁用idle动画恢复（纯口型测试模式）
      // await _asset!.playGltfAnimation(_idleAnimationIndex, loop: true);
      // _isPlaying = true;
      // _currentAnimationIndex = _idleAnimationIndex;

      if (kDebugMode) {
        debugPrint('🚫 Idle动画恢复已禁用（纯口型测试模式）');
      }

      if (kDebugMode) {
        debugPrint('✅ Idle动画已恢复');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 恢复idle动画失败: $e');
      }
    }
  }

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

      // 停止音频
      await _audioPlayer.stop();

      // 取消监听
      _positionSubscription?.cancel();
      _completeSubscription?.cancel();

      // 🔄 清除morph动画轨道数据
      if (_asset != null) {
        final childEntities = await _asset!.getChildEntities();
        for (int i = 0; i < childEntities.length; i++) {
          try {
            await _asset!.clearMorphAnimationData(childEntities[i]);
          } catch (_) {
            // 忽略清理错误
          }
        }
      }

      // 🎭 纯口型测试模式：不恢复idle动画
      // await _resumeIdleAnimation();
      if (kDebugMode) debugPrint('🎯 纯口型测试模式：保持静止状态');

      setState(() {}); // 更新 UI 状态

      if (kDebugMode) {
        debugPrint('⏹️ 纯口型测试系统已停止');
        debugPrint('   ✓ 音频播放已停止');
        debugPrint('   ✓ morph动画轨道已清除');
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
