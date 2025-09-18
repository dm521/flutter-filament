import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide View;
import 'package:flutter/scheduler.dart';
import 'package:thermion_flutter/thermion_flutter.dart';
// vector_math types are re-exported by thermion_flutter
import 'lip_sync_controller.dart';
import 'camera_presets.dart';

// 🎭 动画状态枚举
enum AnimState { none, idle, talk }

void main() {
  runApp(const MyApp());
}

//


// 基于最新 settings.json 的专业灯光配置
Future<void> applyLightsFromSpec(ThermionViewer viewer) async {
  try {
    await viewer.destroyLights();
  } catch (_) {}

  // 主太阳光 - 基于新 settings.json 参数
  // sunlightColor: [0.955105, 0.827571, 0.767769] 对应暖白色
  // 通过色温近似: ~5400K (暖白)
  await viewer.addDirectLight(DirectLight.sun(
    color: 5400.0,                    // 暖白色温
    intensity: 75000.0,               // 更新为 settings.json 的 sunlightIntensity
    castShadows: true,                 // 启用阴影
    direction: Vector3(0.366695, -0.357967, -0.858717), // 更新为 settings.json 的最新方向
  ));

  // 正面补光 - 增强正面填充
  await viewer.addDirectLight(DirectLight.sun(
    color: 5600.0,                    // 稍暖的补光
    intensity: 30000.0,               // 增强正面补光
    castShadows: false,
    direction: Vector3(0.1, -0.4, -0.9).normalized(),
  ));

  // 背面环境光 - 解决背面全黑问题
  await viewer.addDirectLight(DirectLight.sun(
    color: 5800.0,                    // 中性暖光
    intensity: 25000.0,               // 中等强度背光
    castShadows: false,
    direction: Vector3(-0.2, -0.3, 0.9).normalized(), // 从背面照射
  ));

  // 左侧补光 - 减少侧面阴影
  await viewer.addDirectLight(DirectLight.sun(
    color: 5700.0,                    // 中性光
    intensity: 18000.0,               // 适中强度
    castShadows: false,
    direction: Vector3(-0.8, -0.2, -0.3).normalized(), // 从左侧照射
  ));

  // 右侧轮廓光 - 保持立体感
  await viewer.addDirectLight(DirectLight.sun(
    color: 6200.0,                    // 稍冷的轮廓光
    intensity: 15000.0,               // 适度轮廓光
    castShadows: false,
    direction: Vector3(0.8, -0.1, 0.5).normalized(), // 从右侧照射
  ));

  try {
    await viewer.setRendering(true);
  } catch (_) {}
}


class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Thermion 角色动画测试',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: '角色动画测试'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with TickerProviderStateMixin {
  DelegateInputHandler? _inputHandler;
  ThermionViewer? _thermionViewer;

  ThermionAsset? _asset;
  
  // 🎭 测试用的角色模型路径
  final _characterUri = "assets/models/xiaomeng_ani_0918_2.glb";

  // 动画相关
  final gltfAnimations = <String>[];
  final gltfDurations = <double>[];
  int selectedGltfAnimation = -1;
  bool isPlaying = false;
  
  // 🎭 动画状态机
  AnimState _currentState = AnimState.none;
  int _idleAnimIndex = -1;
  int _talkAnimIndex = -1;
  // ignore: unused_field
  int _lastPlayingIndex = -1;
  Timer? _talkTimer;
  
  // 悬浮控制面板
  bool _isControlPanelOpen = false;
  late AnimationController _animationController;
  
  // FPS 监控
  double _fps = 0.0;
  int _frameCount = 0;
  DateTime _lastTime = DateTime.now();
  Timer? _fpsTimer;
  bool _showFpsOverlay = true;
  
  // 按钮按下状态
  // ignore: unused_field
  bool _isMicPressed = false;
  
  // 🎤 口型同步控制器
  LipSyncController? _lipSyncController;
  // 相机预设（默认胸像/全身默认）
  // ignore: unused_field
  CameraPreset _cameraPreset = CameraPreset.soloCloseUp;

  // 口型参数（UI）
  bool _lipSmooth = true;
  double _lipPhaseMs = 0.0; // -300..+300

  Future _loadCharacter(String? uri) async {
    if (_asset != null) {
      await _thermionViewer!.destroyAsset(_asset!);
      _asset = null;
    }

    // 加载指定的角色模型
    if (uri != null) {
      try {
        if (kDebugMode) {
          debugPrint('🎭 开始加载角色: $uri');
        }
        
        _asset = await _thermionViewer!.loadGltf(uri);
        
        // 🎯 获取模型边界信息
        final bounds = await _asset!.getBoundingBox();
        final size = bounds.max - bounds.min;
        if (kDebugMode) {
          debugPrint('📏 模型尺寸: ${size.x.toStringAsFixed(2)} x ${size.y.toStringAsFixed(2)} x ${size.z.toStringAsFixed(2)}');
        }
        
        // 🎯 应用单位立方体变换（官方推荐）
        await _asset!.transformToUnitCube();
        if (kDebugMode) {
          debugPrint('✅ 已应用 transformToUnitCube');
        }
        
        // 🎭 获取动画数据
        final animations = await _asset!.getGltfAnimationNames();
        final durations = await Future.wait(
          List.generate(animations.length, (i) => _asset!.getGltfAnimationDuration(i))
        );

        if (kDebugMode) {
          debugPrint('📋 发现 ${animations.length} 个动画:');
        }
        
        // 🎯 处理动画名称和时长
        gltfAnimations.clear();
        gltfDurations.clear();
        
        for (int i = 0; i < animations.length; i++) {
          final animName = animations[i].isEmpty ? "动画_${i + 1}" : animations[i];
          final duration = durations[i];
          
          gltfAnimations.add("$animName (${duration.toStringAsFixed(1)}s)");
          gltfDurations.add(duration);
          
          if (kDebugMode) {
            debugPrint('   ${i + 1}. $animName - ${duration.toStringAsFixed(1)}s');
          }
        }
        
        selectedGltfAnimation = animations.isNotEmpty ? 0 : -1;
        isPlaying = false;
        
        // 🎯 匹配 idle 和 talk 动画索引
        _matchAnimationIndices(animations);
        
        if (kDebugMode) {
          debugPrint('✅ 角色加载完成');
          debugPrint('🎭 Idle 动画索引: $_idleAnimIndex');
          debugPrint('🎭 Talk 动画索引: $_talkAnimIndex');
          
          // 检查模型的其他信息
          debugPrint('🔍 检查模型详细信息...');
          try {
            final bounds = await _asset!.getBoundingBox();
            debugPrint('🔍 模型边界: ${bounds.min} 到 ${bounds.max}');
            
            // 检查动画数量（使用已有的 gltfAnimations）
            debugPrint('🔍 动画数量: ${gltfAnimations.length}');
            
            // 检查实体详情
            final entities = await _asset!.getChildEntities();
            for (int i = 0; i < entities.length && i < 5; i++) {
              try {
                final morphTargets = await _asset!.getMorphTargetNames(entity: entities[i]);
                debugPrint('🔍 实体 $i morph targets: ${morphTargets.length}');
                if (morphTargets.isNotEmpty && i == 2) {
                  debugPrint('🔍 实体 $i 的前5个 morph targets: ${morphTargets.take(5).join(', ')}');
                }
              } catch (e) {
                debugPrint('🔍 实体 $i 无法获取 morph targets: $e');
              }
            }
          } catch (e) {
            debugPrint('🔍 检查模型信息失败: $e');
          }
        }
        
        // � 初始化始口型同步控制器
        await _initializeLipSync();
        // 同步 UI 状态到控制器
        if (_lipSyncController != null) {
          _lipSyncController!.enableSmoothing = _lipSmooth;
          _lipSyncController!.phaseOffsetMs = _lipPhaseMs;
        }
        
        // 🎬 自动开始 idle 循环
        if (_idleAnimIndex >= 0) {
          await Future.delayed(const Duration(milliseconds: 500));
          await startIdleLoop();
        } else if (animations.isNotEmpty) {
          // 兜底：播放第一个动画作为 idle
          _idleAnimIndex = 0;
          await Future.delayed(const Duration(milliseconds: 500));
          await startIdleLoop();
        }
        
      } catch (e) {
        if (kDebugMode) {
          debugPrint('❌ 角色加载失败: $e');
        }
        _asset = null;
        gltfAnimations.clear();
        gltfDurations.clear();
        selectedGltfAnimation = -1;
      }
    }
    setState(() {});
  }

  Future _playGltfAnimation() async {
    if (selectedGltfAnimation == -1 || _asset == null) {
      if (kDebugMode) {
        debugPrint('⚠️ 无法播放动画：无效的动画索引或资产');
      }
      return;
    }
    
    try {
      if (kDebugMode) {
        debugPrint('▶️ 播放动画: ${gltfAnimations[selectedGltfAnimation]}');
      }
      await _asset!.playGltfAnimation(selectedGltfAnimation, loop: true);
      setState(() {
        isPlaying = true;
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 动画播放失败: $e');
      }
    }
  }

  Future _stopGltfAnimation() async {
    if (selectedGltfAnimation == -1 || _asset == null) {
      return;
    }
    
    try {
      if (kDebugMode) {
        debugPrint('⏹️ 停止动画: ${gltfAnimations[selectedGltfAnimation]}');
      }
      await _asset!.stopGltfAnimation(selectedGltfAnimation);
      setState(() {
        isPlaying = false;
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 动画停止失败: $e');
      }
    }
  }

  // 🎯 匹配动画索引（根据名称关键词）
  void _matchAnimationIndices(List<String> animations) {
    _idleAnimIndex = -1;
    _talkAnimIndex = -1;
    
    if (kDebugMode) {
      debugPrint('🔍 开始匹配动画索引...');
      for (int i = 0; i < animations.length; i++) {
        debugPrint('   动画 $i: ${animations[i]}');
      }
    }
    
    // 优先选择干净的动画名称（不包含 skeleton 和 # 符号）
    int bestIdleIndex = -1;
    int bestTalkIndex = -1;
    
    for (int i = 0; i < animations.length; i++) {
      final animName = animations[i].toLowerCase();
      final isCleanName = !animName.contains('skeleton') && !animName.contains('#');
      
      // 匹配 idle 动画
      if ((animName.contains('idle') || 
           animName.contains('wait') || 
           animName.contains('stand'))) {
        if (bestIdleIndex == -1 || isCleanName) {
          bestIdleIndex = i;
          if (kDebugMode) {
            debugPrint('🎯 候选 Idle 动画: $i (${animations[i]}) ${isCleanName ? "[干净名称]" : "[包含特殊符号]"}');
          }
        }
      }
      
      // 匹配 talk 动画
      if ((animName.contains('talk') || 
           animName.contains('speak') || 
           animName.contains('speech'))) {
        if (bestTalkIndex == -1 || isCleanName) {
          bestTalkIndex = i;
          if (kDebugMode) {
            debugPrint('🎯 候选 Talk 动画: $i (${animations[i]}) ${isCleanName ? "[干净名称]" : "[包含特殊符号]"}');
          }
        }
      }
    }
    
    _idleAnimIndex = bestIdleIndex;
    _talkAnimIndex = bestTalkIndex;
    
    if (_idleAnimIndex >= 0 && kDebugMode) {
      debugPrint('✅ 最终选择 Idle 动画: $_idleAnimIndex (${animations[_idleAnimIndex]})');
    }
    if (_talkAnimIndex >= 0 && kDebugMode) {
      debugPrint('✅ 最终选择 Talk 动画: $_talkAnimIndex (${animations[_talkAnimIndex]})');
    }
    
    // 兜底策略 - 只设置 idle，不自动设置 talk
    if (_idleAnimIndex == -1 && animations.isNotEmpty) {
      _idleAnimIndex = 0; // 第一个动画作为 idle
      if (kDebugMode) {
        debugPrint('⚠️ 未找到 Idle 关键词，使用第一个动画作为 Idle: ${animations[0]}');
      }
    }
    
    // 如果只有一个动画，可以让 talk 也使用同一个动画
    if (_talkAnimIndex == -1 && animations.length == 1) {
      _talkAnimIndex = 0; // 使用同一个动画作为 talk
      if (kDebugMode) {
        debugPrint('💡 只有一个动画，将其同时用作 Idle 和 Talk');
      }
    } else if (_talkAnimIndex == -1) {
      if (kDebugMode) {
        debugPrint('⚠️ 未找到 Talk 动画，需要手动指定');
      }
    }
    
    if (kDebugMode) {
      debugPrint('🎭 最终匹配结果: Idle=$_idleAnimIndex, Talk=$_talkAnimIndex');
    }
  }

  // 🛑 停止所有动画
  Future<void> _stopAllAnimations() async {
    if (_asset == null) return;
    
    try {
      // 停止所有可能播放的动画
      for (int i = 0; i < gltfAnimations.length; i++) {
        try {
          await _asset!.stopGltfAnimation(i);
        } catch (e) {
          // 忽略停止失败的错误
        }
      }
      _lastPlayingIndex = -1;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 停止所有动画失败: $e');
      }
    }
  }

  // 🔄 开始 Idle 循环
  Future<void> startIdleLoop() async {
    if (_asset == null || _idleAnimIndex == -1) return;
    // 如果正在进行口型同步，则禁止进入 Idle 循环
    if (_lipSyncController?.isPlaying == true) {
      if (kDebugMode) {
        debugPrint('⏸️ 口型同步进行中，暂不进入 Idle');
      }
      return;
    }
    // 移除防重复检查，允许强制切换到 idle
    
    try {
      if (kDebugMode) {
        debugPrint('🎭 开始 Idle 循环...');
      }
      
      // 取消说话定时器
      _talkTimer?.cancel();
      
      // 停止其他动画
      await _stopAllAnimations();
      
      // 播放 idle 循环
      await _asset!.playGltfAnimation(_idleAnimIndex, loop: true);
      _lastPlayingIndex = _idleAnimIndex;
      
      setState(() {
        _currentState = AnimState.idle;
        isPlaying = true;
        selectedGltfAnimation = _idleAnimIndex;
      });
      
      if (kDebugMode) {
        debugPrint('✅ Idle 循环已开始');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Idle 循环失败: $e');
      }
    }
  }

  // 🗣️ 开始 Talk 循环
  Future<void> startTalkLoop() async {
    if (_asset == null || _talkAnimIndex == -1) {
      if (kDebugMode) {
        debugPrint('⚠️ 无法开始 Talk 循环: asset=$_asset, talkIndex=$_talkAnimIndex');
      }
      return;
    }
    
    try {
      if (kDebugMode) {
        debugPrint('🎭 开始 Talk 循环... (从 ${_currentState} 状态)');
      }
      
      // 取消之前的定时器
      _talkTimer?.cancel();
      
      // 停止其他动画
      await _stopAllAnimations();
      
      // 播放 talk 循环
      await _asset!.playGltfAnimation(_talkAnimIndex, loop: true);
      _lastPlayingIndex = _talkAnimIndex;
      
      setState(() {
        _currentState = AnimState.talk;
        isPlaying = true;
        selectedGltfAnimation = _talkAnimIndex;
      });
      
      if (kDebugMode) {
        debugPrint('✅ Talk 循环已开始');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Talk 循环失败: $e');
      }
    }
  }

  // 🎬 播放一次 Talk 然后回到 Idle
  Future<void> playTalkOnceThenIdle() async {
    if (_asset == null || _talkAnimIndex == -1) return;
    
    try {
      if (kDebugMode) {
        debugPrint('🎭 播放一次 Talk 然后回到 Idle...');
      }
      
      // 取消之前的定时器
      _talkTimer?.cancel();
      
      // 停止其他动画
      await _stopAllAnimations();
      
      // 播放 talk 单次
      await _asset!.playGltfAnimation(_talkAnimIndex, loop: false);
      _lastPlayingIndex = _talkAnimIndex;
      
      setState(() {
        _currentState = AnimState.talk;
        isPlaying = true;
        selectedGltfAnimation = _talkAnimIndex;
      });
      
      // 设置定时器，动画结束后回到 idle
      final talkDuration = _talkAnimIndex < gltfDurations.length 
          ? gltfDurations[_talkAnimIndex] 
          : 2.0; // 默认 2 秒
      
      _talkTimer = Timer(Duration(milliseconds: (talkDuration * 1000).round()), () {
        startIdleLoop();
      });
      
      if (kDebugMode) {
        debugPrint('✅ Talk 单次播放已开始，${talkDuration.toStringAsFixed(1)}秒后回到 Idle');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Talk 单次播放失败: $e');
      }
    }
  }

  // 🎤 初始化口型同步控制器
  Future<void> _initializeLipSync() async {
    if (_asset == null) return;
    
    try {
      if (kDebugMode) {
        debugPrint('🎤 初始化口型同步控制器...');
      }
      
      _lipSyncController = LipSyncController(_asset!);
      
      // 加载 blendshape 数据
      await _lipSyncController!.loadBlendshapeData('assets/wav/bs.json');
      
      // 加载 morph target 名称
      await _lipSyncController!.loadMorphTargetNames();
      // 初始化默认参数
      _lipSyncController!.enableSmoothing = _lipSmooth;
      _lipSyncController!.phaseOffsetMs = _lipPhaseMs;
      
      if (kDebugMode) {
        debugPrint('✅ 口型同步控制器初始化完成');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 口型同步控制器初始化失败: $e');
      }
    }
  }

  // 🎤 播放口型同步
  Future<void> _playLipSync() async {
    if (_lipSyncController == null) {
      if (kDebugMode) {
        debugPrint('⚠️ 口型同步控制器未初始化');
      }
      return;
    }
    
    try {
      if (kDebugMode) {
        debugPrint('🎤 开始播放口型同步...');
      }
      
      await _lipSyncController!.playLipSync(
        audioPath: 'wav/output.wav',
        frameRate: 60.0,
        attenuation: 0.8, // 降低幅度，使用更接近“默认数据”的嘴型
        // 更强：播放前停止所有动画，结束后恢复 Idle 循环
        pauseIdleAnimation: () async {
          await _stopAllAnimations();
          if (kDebugMode) debugPrint('🎤 已停止所有动画以避免与 morph 竞争');
        },
        resumeIdleAnimation: () async {
          await startIdleLoop();
          if (kDebugMode) debugPrint('🎤 已恢复 Idle 循环');
        },
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 播放口型同步失败: $e');
      }
    }
  }

  // 🎤 停止口型同步
  Future<void> _stopLipSync() async {
    if (_lipSyncController != null) {
      await _lipSyncController!.stopLipSync();
    }
  }

  // 🧪 测试 Morph Targets
  Future<void> _testMorphTargets() async {
    if (_asset == null) {
      if (kDebugMode) {
        debugPrint('⚠️ 模型未加载');
      }
      return;
    }

    try {
      if (kDebugMode) {
        debugPrint('🧪 开始全面测试 Morph Targets...');
        debugPrint('🧪 暂停所有动画以避免冲突...');
      }

      // 暂停所有动画（通过停止播放）
      if (_idleAnimIndex >= 0) {
        await _asset!.stopGltfAnimation(_idleAnimIndex);
      }
      if (_talkAnimIndex >= 0) {
        await _asset!.stopGltfAnimation(_talkAnimIndex);
      }

      final childEntities = await _asset!.getChildEntities();
      if (kDebugMode) {
        debugPrint('🧪 总共有 ${childEntities.length} 个子实体');
      }

      // 测试所有实体
      for (int entityIndex = 0; entityIndex < childEntities.length; entityIndex++) {
        try {
          final entity = childEntities[entityIndex];
          final morphTargets = await _asset!.getMorphTargetNames(entity: entity);
          
          if (morphTargets.isNotEmpty) {
            if (kDebugMode) {
              debugPrint('🧪 实体 $entityIndex 有 ${morphTargets.length} 个 morph targets');
            }
            
            // 创建测试权重：尝试不同的权重值范围
            final testWeights = List.filled(morphTargets.length, 10.0); // 尝试更大的值
            
            if (kDebugMode) {
              debugPrint('🧪 对实体 $entityIndex 应用最大权重测试...');
            }
            
            // 应用测试权重
            await _asset!.setMorphTargetWeights(entity, testWeights);
            
            if (kDebugMode) {
              debugPrint('🧪 实体 $entityIndex 权重已应用，等待2秒观察效果...');
            }
            
            // 等待2秒观察效果
            await Future.delayed(const Duration(seconds: 2));
            
            // 重置权重
            final resetWeights = List.filled(morphTargets.length, 0.0);
            await _asset!.setMorphTargetWeights(entity, resetWeights);
            
            if (kDebugMode) {
              debugPrint('🧪 实体 $entityIndex 权重已重置');
            }
            
            // 如果这是实体2，额外测试单个权重
            if (entityIndex == 2) {
              if (kDebugMode) {
                debugPrint('🧪 对实体2进行单个权重测试...');
              }
              
              // 逐个测试前10个权重，使用更大的值
              for (int i = 0; i < morphTargets.length && i < 10; i++) {
                final singleTestWeights = List.filled(morphTargets.length, 0.0);
                singleTestWeights[i] = 10.0; // 尝试更大的值
                
                if (kDebugMode) {
                  debugPrint('🧪 测试单个权重: ${morphTargets[i]} = 1.0');
                }
                
                await _asset!.setMorphTargetWeights(entity, singleTestWeights);
                await Future.delayed(const Duration(milliseconds: 500));
                
                // 重置
                await _asset!.setMorphTargetWeights(entity, resetWeights);
                await Future.delayed(const Duration(milliseconds: 200));
              }
            }
          }
        } catch (entityError) {
          if (kDebugMode) {
            debugPrint('❌ 测试实体 $entityIndex 失败: $entityError');
          }
        }
      }
      
      if (kDebugMode) {
        debugPrint('🧪 全面测试完成');
        debugPrint('🧪 恢复 idle 动画...');
      }

      // 恢复 idle 动画
      if (_idleAnimIndex >= 0) {
        await _asset!.playGltfAnimation(_idleAnimIndex, loop: true);
        _currentState = AnimState.idle;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 测试 Morph Targets 失败: $e');
      }
      
      // 确保恢复动画
      if (_idleAnimIndex >= 0) {
        await _asset!.playGltfAnimation(_idleAnimIndex, loop: true);
        _currentState = AnimState.idle;
      }
    }
  }

  // 🔄 重置所有动画
  Future _resetAllAnimations() async {
    if (_asset == null) return;
    
    try {
      if (kDebugMode) {
        debugPrint('🔄 重置所有动画...');
      }
      for (int i = 0; i < gltfAnimations.length; i++) {
        try {
          await _asset!.stopGltfAnimation(i);
        } catch (e) {
          // 忽略停止失败的错误
        }
      }
      setState(() {
        isPlaying = false;
      });
      if (kDebugMode) {
        debugPrint('✅ 所有动画已重置');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 重置动画失败: $e');
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _startFpsMonitoring();
    
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (kDebugMode) {
        debugPrint('🚀 初始化 Thermion 查看器...');
      }
      
      _thermionViewer = await ThermionFlutterPlugin.createViewer();

      

      // 🎥 设置相机视角（预设）
      await applyCameraPreset(_thermionViewer!, preset: CameraPreset.soloCloseUp, characterCenter: null);

      // 🌅 加载环境光照（基于新 settings.json 的配置）
      try {
        if (kDebugMode) {
          debugPrint('📦 开始加载 Skybox...');
        }
        await _thermionViewer!.loadSkybox("assets/environments/studio_small_env_skybox.ktx");
        if (kDebugMode) {
          debugPrint('✅ Skybox 加载完成');
        }

        // 尝试启用 skybox 显示
        try {
          // await _thermionViewer!.setSkyboxVisible(true);
          if (kDebugMode) {
            debugPrint('🌌 尝试启用 Skybox 显示');
          }
        } catch (skyboxError) {
          if (kDebugMode) {
            debugPrint('⚠️ Skybox 显示设置失败: $skyboxError');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('❌ Skybox 加载失败: $e');
        }
      }

      try {
        if (kDebugMode) {
          debugPrint('💡 开始加载 IBL...');
        }
        await _thermionViewer!.loadIbl("assets/environments/studio_small_env_ibl.ktx", intensity: 15600.0);
        if (kDebugMode) {
          debugPrint('✅ IBL 加载完成 (强度: 15600)');
        }

        // 应用 IBL 旋转（基于 settings.json 中的 iblRotation 参数）
        try {
          var rotationMatrix = Matrix3.identity();
          Matrix4.rotationY(0.558505).copyRotation(rotationMatrix); // settings.json 中的角度
          await _thermionViewer!.rotateIbl(rotationMatrix);
          if (kDebugMode) {
            debugPrint('🔄 IBL 旋转已应用: 0.558505 弧度');
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('⚠️ IBL 旋转失败: $e');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('❌ IBL 加载失败: $e');
        }
      }

      // 💡 应用专业灯光配置
      await applyLightsFromSpec(_thermionViewer!); 

      // 🏢 启用地面平面和阴影（基于 settings.json）
      // groundPlaneEnabled: true, groundShadowStrength: 0.75
      try {
        // await _thermionViewer!.enableGroundPlane(true);
        // await _thermionViewer!.setGroundShadowStrength(0.75);
        if (kDebugMode) {
          debugPrint('🏢 地面平面设置已配置');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ 地面平面设置失败: $e');
        }
      }

      // 🎨 应用后处理效果（基于 settings.json）
      await _thermionViewer!.setPostProcessing(true);

      // 🌑 启用阴影系统（基于 settings.json: enableShadows: true）
      try {
        await _thermionViewer!.setShadowsEnabled(true);
        if (kDebugMode) {
          debugPrint('🌑 阴影系统已启用');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ 阴影系统启用失败: $e');
        }
      }

      // Tone Mapping - ACES 是最接近 ACES_LEGACY 的选项
      await _thermionViewer!.setToneMapping(ToneMapper.ACES);

      // Bloom 效果
      await _thermionViewer!.setBloom(true, 0.348);  // enabled, strength from updated settings.json

      // 抗锯齿 (MSAA, FXAA, TAA)
      await _thermionViewer!.setAntiAliasing(true, true, true);  // MSAA on, FXAA on, TAA on (从 settings.json)

      // 🔆 调整曝光度以提升整体亮度（基于 settings.json 的相机参数）
      // cameraAperture: 16, cameraSpeed: 125, cameraISO: 100
      try {
        final camera = await _thermionViewer!.getActiveCamera();
        await camera.setExposure(16.0, 1.0 / 125.0, 100.0);  // aperture, shutterSpeed, ISO
        if (kDebugMode) {
          debugPrint('📷 相机曝光已设置: f/16, 1/125s, ISO100');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ 相机曝光设置失败: $e');
        }
      }

      // 启用渲染
      await _thermionViewer!.setRendering(true);

      // 🎮 设置轨道控制器
      _inputHandler = DelegateInputHandler.fixedOrbit(_thermionViewer!);
      
      // 🎭 自动加载角色
      await _loadCharacter(_characterUri);



      setState(() {});
      if (kDebugMode) {
        debugPrint('✅ Thermion 初始化完成');
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _fpsTimer?.cancel();
    _talkTimer?.cancel(); // 清理说话定时器
    _lipSyncController?.dispose(); // 清理口型同步控制器
    super.dispose();
  }

  void _startFpsMonitoring() {
    SchedulerBinding.instance.addPostFrameCallback(_onFrame);
    _fpsTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        // FPS 更新逻辑在 _onFrame 中处理
      }
    });
  }

  void _onFrame(Duration timestamp) {
    if (!mounted) return;
    
    _frameCount++;
    final now = DateTime.now();
    final elapsed = now.difference(_lastTime).inMilliseconds;
    
    if (elapsed >= 1000) {
      final fps = (_frameCount * 1000.0) / elapsed;
      setState(() {
        _fps = fps;
      });
      
      _frameCount = 0;
      _lastTime = now;
    }
    
    SchedulerBinding.instance.addPostFrameCallback(_onFrame);
  }

  Color _getFpsColor(double fps) {
    if (fps >= 50) return Colors.green;
    if (fps >= 30) return Colors.orange;
    return Colors.red;
  }

  // 🎭 状态显示辅助方法
  Color _getStateColor() {
    switch (_currentState) {
      case AnimState.idle:
        return Colors.blue;
      case AnimState.talk:
        return Colors.orange;
      case AnimState.none:
        return Colors.grey;
    }
  }

  IconData _getStateIcon() {
    switch (_currentState) {
      case AnimState.idle:
        return Icons.self_improvement;
      case AnimState.talk:
        return Icons.record_voice_over;
      case AnimState.none:
        return Icons.pause_circle;
    }
  }

  String _getStateText() {
    switch (_currentState) {
      case AnimState.idle:
        return '待机中';
      case AnimState.talk:
        return '说话中';
      case AnimState.none:
        return '无状态';
    }
  }

  void _toggleControlPanel() {
    setState(() {
      _isControlPanelOpen = !_isControlPanelOpen;
    });
    
    if (_isControlPanelOpen) {
      _animationController.forward();
    } else {
      _animationController.reverse();
    }
  }

  Widget _buildFloatingControlPanel() {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Transform.scale(
          scale: _animationController.value,
          child: Opacity(
            opacity: _animationController.value,
            child: Container(
              margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 20,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题
                  Row(
                    children: [
                      Icon(
                        _asset != null ? Icons.check_circle : Icons.error,
                        color: _asset != null ? Colors.green : Colors.red,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _asset != null ? '角色已加载' : '角色加载失败',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  if (_asset != null && gltfAnimations.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    
                    // 动画选择
                    const Text(
                      '选择动画:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.grey.shade50,
                      ),
                      child: DropdownButton<String>(
                        value: selectedGltfAnimation == -1 
                            ? null 
                            : gltfAnimations[selectedGltfAnimation],
                        hint: const Text('选择一个动画'),
                        isExpanded: true,
                        underline: Container(),
                        items: gltfAnimations.map((animation) {
                          return DropdownMenuItem<String>(
                            value: animation,
                            child: Text(
                              animation,
                              style: const TextStyle(fontSize: 14),
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              selectedGltfAnimation = gltfAnimations.indexOf(value);
                              isPlaying = false;
                            });
                            if (kDebugMode) {
                              debugPrint('🎯 选择动画: $value');
                            }
                          }
                        },
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // 状态显示
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _getStateColor().withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _getStateIcon(),
                            color: _getStateColor(),
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '当前状态: ${_getStateText()}',
                            style: TextStyle(
                              color: _getStateColor(),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // 动画状态控制按钮
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildControlButton(
                          icon: Icons.self_improvement,
                          label: 'Idle',
                          color: Colors.blue,
                          onPressed: _idleAnimIndex >= 0 ? () => startIdleLoop() : null,
                        ),
                        
                        _buildControlButton(
                          icon: Icons.record_voice_over,
                          label: 'Talk循环',
                          color: Colors.orange,
                          onPressed: _talkAnimIndex >= 0 ? () => startTalkLoop() : null,
                        ),
                        
                        _buildControlButton(
                          icon: Icons.chat_bubble,
                          label: 'Talk单次',
                          color: Colors.purple,
                          onPressed: _talkAnimIndex >= 0 ? () => playTalkOnceThenIdle() : null,
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // 传统控制按钮
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildControlButton(
                          icon: Icons.play_arrow,
                          label: '播放',
                          color: Colors.green,
                          onPressed: (selectedGltfAnimation >= 0 && !isPlaying) 
                              ? () => _playGltfAnimation()
                              : null,
                        ),
                        
                        _buildControlButton(
                          icon: Icons.stop,
                          label: '停止',
                          color: Colors.red,
                          onPressed: (selectedGltfAnimation >= 0 && isPlaying) 
                              ? () => _stopGltfAnimation()
                              : null,
                        ),
                        
                        _buildControlButton(
                          icon: Icons.refresh,
                          label: '重置',
                          color: Colors.blue,
                          onPressed: () => _resetAllAnimations(),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // 🎤 口型同步控制
                    const Text(
                      '🎤 口型同步',
                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    // 平滑插值开关
                    Row(
                      children: [
                        const Text(
                          '平滑插值',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                        const SizedBox(width: 6),
                          Switch(
                            value: _lipSmooth,
                            onChanged: (v) {
                              setState(() {
                                _lipSmooth = v;
                              });
                              _lipSyncController?.enableSmoothing = v;
                            },
                            activeThumbColor: Colors.greenAccent,
                          ),
                        const SizedBox(width: 12),
                        Text(
                          _lipSmooth ? 'ON' : 'OFF',
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        )
                      ],
                    ),
                    const SizedBox(height: 8),
                    // 相位偏移滑条
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '相位偏移: ${_lipPhaseMs.toStringAsFixed(0)} ms',
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                        Slider(
                          value: _lipPhaseMs.clamp(-300.0, 300.0),
                          min: -300,
                          max: 300,
                          divisions: 60,
                          onChanged: (v) {
                            setState(() {
                              _lipPhaseMs = v;
                            });
                            if (_lipSyncController != null) {
                              _lipSyncController!.phaseOffsetMs = v;
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildControlButton(
                          icon: Icons.record_voice_over,
                          label: '播放同步',
                          color: Colors.green,
                          onPressed: () => _playLipSync(),
                        ),
                        
                        _buildControlButton(
                          icon: Icons.stop_circle,
                          label: '停止同步',
                          color: Colors.red,
                          onPressed: () => _stopLipSync(),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // 状态指示
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isPlaying 
                            ? Colors.green.withValues(alpha: 0.1) 
                            : Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isPlaying ? Icons.play_circle : Icons.pause_circle,
                            color: isPlaying ? Colors.green : Colors.grey,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            isPlaying ? '动画播放中...' : '动画已停止',
                            style: TextStyle(
                              color: isPlaying ? Colors.green : Colors.grey,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (_asset != null) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.warning, color: Colors.orange, size: 24),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '未发现动画数据\n请检查 GLB 文件是否包含动画',
                              style: TextStyle(
                                color: Colors.orange,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required Color color,
    Function()? onPressed,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            color: onPressed != null ? color : Colors.grey,
            borderRadius: BorderRadius.circular(16),
            boxShadow: onPressed != null ? [
              BoxShadow(
                color: color.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ] : null,
          ),
          child: IconButton(
            onPressed: onPressed != null ? () => onPressed() : null,
            icon: Icon(icon, color: Colors.white),
            iconSize: 24,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: onPressed != null ? color : Colors.grey,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_thermionViewer == null) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: '切换视角',
            icon: const Icon(Icons.camera_outdoor),
            onPressed: () {},
          ),
        ],
      ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在初始化 3D 引擎...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          PopupMenuButton<CameraPreset>(
            tooltip: '切换视角',
            icon: const Icon(Icons.camera_outdoor),
            onSelected: (preset) async {
              setState(() => _cameraPreset = preset);
              if (_thermionViewer != null) {
                await applyCameraPreset(
                  _thermionViewer!,
                  preset: _cameraPreset,
                  characterCenter: null,
                );
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: CameraPreset.soloCloseUp,
                child: Text('全身/默认'),
              ),
              const PopupMenuItem(
                value: CameraPreset.halfBody,
                child: Text('半身像'),
              ),
              const PopupMenuItem(
                value: CameraPreset.bustCloseUp,
                child: Text('胸像特写'),
              ),
              const PopupMenuItem(
                value: CameraPreset.thirdPersonOts,
                child: Text('第三人称越肩'),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          // 3D 视图 - 全屏显示
          Positioned.fill(
            child: _inputHandler == null
                ? ThermionWidget(viewer: _thermionViewer!)
                : ThermionListenerWidget(
                    inputHandler: _inputHandler!,
                    child: ThermionWidget(viewer: _thermionViewer!),
                  ),
          ),
          
          // FPS 显示（左上角）
          if (_showFpsOverlay)
            Positioned(
              top: 50,
              left: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.speed,
                      color: _getFpsColor(_fps),
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'FPS: ${_fps.toStringAsFixed(1)}',
                      style: TextStyle(
                        color: _getFpsColor(_fps),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          
          // 悬浮控制面板
          if (_isControlPanelOpen)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildFloatingControlPanel(),
            ),
          
          // 主控制按钮
          Positioned(
            bottom: 20,
            right: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // FPS 切换按钮
                FloatingActionButton(
                  heroTag: "fps",
                  mini: true,
                  onPressed: () {
                    setState(() {
                      _showFpsOverlay = !_showFpsOverlay;
                    });
                  },
                  backgroundColor: Colors.teal.withValues(alpha: 0.9),
                  child: Icon(
                    _showFpsOverlay ? Icons.visibility : Icons.visibility_off,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(height: 12),
                
                // 重新加载按钮
                // FloatingActionButton(
                //   heroTag: "reload",
                //   mini: true,
                //   onPressed: () => _loadCharacter(_characterUri),
                //   backgroundColor: Colors.blue.withValues(alpha: 0.9),
                //   child: const Icon(Icons.refresh, color: Colors.white, size: 20),
                // ),
                //const SizedBox(height: 12),
                
                
                // 主控制面板按钮
                FloatingActionButton(
                  heroTag: "control",
                  mini: true,
                  onPressed: _toggleControlPanel,
                  backgroundColor: Colors.deepPurple.withValues(alpha: 0.9),
                  child: AnimatedRotation(
                    turns: _isControlPanelOpen ? 0.125 : 0,
                    duration: const Duration(milliseconds: 300),
                    child: Icon(
                      _isControlPanelOpen ? Icons.close : Icons.settings,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // 🎤 大播放按钮（中央底部）
          // Positioned(
          //   bottom: 40,
          //   left: 0,
          //   right: 0,
          //   child: Center(
          //     child: GestureDetector(
          //       onTapDown: (_) {
          //         if (kDebugMode) {
          //           debugPrint('🎤 麦克风按钮按下');
          //         }
          //         setState(() {
          //           _isMicPressed = true;
          //         });
          //         // 按下时开始播放 talk
          //         if (_talkAnimIndex >= 0) {
          //           startTalkLoop();
          //         }
          //       },
          //       onTapUp: (_) {
          //         if (kDebugMode) {
          //           debugPrint('🎤 麦克风按钮松开');
          //         }
          //         setState(() {
          //           _isMicPressed = false;
          //         });
          //         // 松开时回到 idle
          //         startIdleLoop();
          //       },
          //       onTapCancel: () {
          //         if (kDebugMode) {
          //           debugPrint('🎤 麦克风按钮取消');
          //         }
          //         setState(() {
          //           _isMicPressed = false;
          //         });
          //         // 取消时也回到 idle
          //         startIdleLoop();
          //       },
          //       child: Container(
          //         width: 80,
          //         height: 80,
          //         decoration: BoxDecoration(
          //           color: _isMicPressed || _currentState == AnimState.talk 
          //               ? Colors.orange.withValues(alpha: 0.9)
          //               : Colors.blue.withValues(alpha: 0.9),
          //           shape: BoxShape.circle,
          //           boxShadow: [
          //             BoxShadow(
          //               color: Colors.black.withValues(alpha: 0.3),
          //               blurRadius: 15,
          //               offset: const Offset(0, 5),
          //             ),
          //           ],
          //         ),
          //         child: Icon(
          //           _isMicPressed || _currentState == AnimState.talk 
          //               ? Icons.record_voice_over 
          //               : Icons.mic,
          //           color: Colors.white,
          //           size: 40,
          //         ),
          //       ),
          //     ),
          //   ),
          //),
          
          // 状态指示器（右上角）
          if (_asset != null)
            Positioned(
              top: 50,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _getStateColor().withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getStateIcon(),
                      color: Colors.white,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _getStateText(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
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
