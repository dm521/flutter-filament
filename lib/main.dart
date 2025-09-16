import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide View;
import 'package:flutter/scheduler.dart';
import 'package:thermion_flutter/thermion_flutter.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

// 🎭 动画状态枚举
enum AnimState { none, idle, talk }

void main() {
  runApp(const MyApp());
}


// Future<void> applyLightsFromSpec(ThermionViewer viewer) async {
//   // 清旧灯，避免叠加
//   try { await viewer.destroyLights(); } catch (_) {}

//   // 你的对焦点（只用于算方向，不改相机）
//   final Vector3 focus = Vector3(0.0, 1.10, 0.0);

//   Vector3 _dirFromPosToFocus(Vector3 pos, Vector3 target) {
//     final d = target - pos; d.normalize(); return d;
//   }

//   Future<void> _sun({
//     required double kelvin,      // Filament: 色温 double
//     required double intensity,
//     required Vector3 dir,
//     bool shadows = false,
//   }) async {
//     await viewer.addDirectLight(DirectLight.sun(
//       color: kelvin,
//       intensity: intensity,
//       castShadows: shadows,
//       direction: dir,
//     ));
//   }

//   // 统一增益（整体亮度旋钮）：IBL 仍在，所以把方向光提到主导层级
//   const double kScale = 20000.0;   // 觉得还亮不够就 22000 / 24000

//   // 1) “环境兜底” —— 极弱顶部中性光（有 IBL 就更轻）
//   await _sun(
//     kelvin: 6500.0,
//     intensity: 1200.0,                 // 原来 1500 → 更弱，只抹死黑
//     dir: Vector3(0.0, -1.0, -0.20),
//     shadows: false,
//   );

//   // 2) 暖色补光（由 PointLight 近似）
//   final Vector3 pointPos = Vector3(0.316, 0.896, -0.172);
//   await _sun(
//     kelvin: 5600.0,                    // 略暖
//     intensity: 1.60 * kScale,          // 原来 1.35*kScale → 1.60*kScale
//     dir: _dirFromPosToFocus(pointPos, focus),
//     shadows: false,
//   );

//   // 3) 主光（Directional）—— 开阴影，方向更“擦面”
//   final Vector3 dirPos = Vector3(-2.248, 2.00, 2.806);   // y 再低一点更擦面
//   await _sun(
//     kelvin: 6200.0,                    // 中性略冷
//     intensity: 3.60 * kScale,          // 原来 3.20*kScale → 3.60*kScale
//     dir: _dirFromPosToFocus(dirPos, focus),
//     shadows: true,
//   );

//   // 4) 冷色轮廓光（新增，提升发丝/肩线的立体感；不投影）
//   final Vector3 rimPos = Vector3(0.9, 1.8, -2.2);        // 右后上
//   await _sun(
//     kelvin: 8200.0,                    // 偏冷
//     intensity: 1.20 * kScale,          // 适中，主要勾边
//     dir: _dirFromPosToFocus(rimPos, focus),
//     shadows: false,
//   );

//   try { await viewer.setRendering(true); } catch (_) {}
// }


Future<void> applyLightsFromSpec(ThermionViewer viewer) async {
  try { await viewer.destroyLights(); } catch (_) {}

  final Vector3 focus = Vector3(0.0, 1.10, 0.0);
  Vector3 _dir(Vector3 pos) { final d = focus - pos; d.normalize(); return d; }

  Future<void> _sun({
    required double k, required double it, required Vector3 dir, bool shadow=false
  }) async {
    await viewer.addDirectLight(DirectLight.sun(
      color: k, intensity: it, castShadows: shadow, direction: dir,
    ));
  }

  // 全局增益：整体还暗就 23000–24000；过亮就 20000
  const double kScale = 22000.0;

  // A) 顶部中性兜底（极弱，只抹死黑）
  await _sun(k: 6500.0, it: 800.0, dir: Vector3(0.0, -1.0, -0.15));

  // B) 主光（左前上 → 更“擦面”，强度降，开阴影；避免正怼脸）
  final Vector3 keyPos = Vector3(-1.10, 1.45, 1.90);
  await _sun(k: 6000.0, it: 1.95 * kScale, dir: _dir(keyPos), shadow: true);

  // C) 顶部柔补（明显抬胸腹/眼下阴影）
  final Vector3 fillTopPos = Vector3(0.0, 2.60, 1.00);
  await _sun(k: 6000.0, it: 1.90 * kScale, dir: _dir(fillTopPos));

  // D) 右前暖补（更靠前更贴脸，吃掉右脸/躯干硬阴影）
  final Vector3 warmPos = Vector3(0.70, 1.10, 0.10);
  await _sun(k: 5400.0, it: 2.10 * kScale, dir: _dir(warmPos));

  // E) 左侧微补（小功率，只填左臂死黑）
  final Vector3 leftFillPos = Vector3(-0.90, 1.10, 0.40);
  await _sun(k: 5900.0, it: 0.55 * kScale, dir: _dir(leftFillPos));

  // F) 冷轮廓（更轻，只勾发丝/肩线）
  final Vector3 rimPos = Vector3(1.10, 1.90, -2.20);
  await _sun(k: 8200.0, it: 0.45 * kScale, dir: _dir(rimPos));

  // G) 反天光（偏暖、加量：腿/鞋不再死白，裙褶回细节）
  final Vector3 bouncePos = Vector3(0.0, -1.05, 0.55);
  await _sun(k: 5000.0, it: 1.30 * kScale, dir: _dir(bouncePos));

  // H) 正面柔光（很弱，从镜头方向两盏，均匀抹面部阴影）
  final Vector3 camSoft1 = Vector3(0.10, 1.30, 3.0);
  final Vector3 camSoft2 = Vector3(-0.10, 1.30, 3.0);
  await _sun(k: 5800.0, it: 0.45 * kScale, dir: _dir(camSoft1));
  await _sun(k: 5800.0, it: 0.45 * kScale, dir: _dir(camSoft2));

    // 1) 胸腹/上臂：正面柔填（很弱，尽量不碰脸）
    final Vector3 torsoFillPos = Vector3(0.20, 1.20, 1.60);   // 镜头略下、正前方
    await _sun(
    k: 5600.0,                       // 略暖，让皮肤不灰
    it: 0.90 * kScale,               // 小功率，只抬中段
    dir: _dir(torsoFillPos),
    // shadows: false  // 默认 false
    );

    // 2) 鞋/裙摆：地面反天光（比原先更暖更有量）
    final Vector3 shoeBouncePos = Vector3(0.0, -0.40, 0.90);  // 脚前偏低位，向上托
    await _sun(
    k: 5000.0,                       // 偏暖，减少“病白”
    it: 1.20 * kScale,               // 比你现有 bounce 稍强
    dir: _dir(shoeBouncePos)
    );

    // 3) 裙褶 kicker：低右前侧光，提裙摆细节，不影响上半身
    final Vector3 skirtKickerPos = Vector3(0.80, -0.20, 0.60);
    await _sun(
    k: 5200.0,                       // 微暖
    it: 0.70 * kScale,               // 中等，小范围提折线
    dir: _dir(skirtKickerPos)
    );

  try { await viewer.setRendering(true); } catch (_) {}
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
  late DelegateInputHandler _inputHandler;
  ThermionViewer? _thermionViewer;

  ThermionAsset? _asset;
  
  // 🎭 测试用的角色模型路径
  final _characterUri = "assets/models/erciyuan.glb";

  // 动画相关
  final gltfAnimations = <String>[];
  final gltfDurations = <double>[];
  int selectedGltfAnimation = -1;
  bool isPlaying = false;
  
  // 🎭 动画状态机
  AnimState _currentState = AnimState.none;
  int _idleAnimIndex = -1;
  int _talkAnimIndex = -1;
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
  bool _isMicPressed = false;

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
    
    for (int i = 0; i < animations.length; i++) {
      final animName = animations[i].toLowerCase();
      
      // 匹配 idle 动画
      if (_idleAnimIndex == -1 && 
          (animName.contains('idle') || 
           animName.contains('wait') || 
           animName.contains('stand'))) {
        _idleAnimIndex = i;
        if (kDebugMode) {
          debugPrint('✅ 找到 Idle 动画: $i (${animations[i]})');
        }
      }
      
      // 匹配 talk 动画
      if (_talkAnimIndex == -1 && 
          (animName.contains('talk') || 
           animName.contains('speak') || 
           animName.contains('speech'))) {
        _talkAnimIndex = i;
        if (kDebugMode) {
          debugPrint('✅ 找到 Talk 动画: $i (${animations[i]})');
        }
      }
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

      

      // 🎥 设置相机位置
      final camera = await _thermionViewer!.getActiveCamera();
      await camera.lookAt(Vector3(0.5, 1.0, 3.5));

      // 🌅 加载官方默认环境
      await _thermionViewer!.loadSkybox("assets/default_env_skybox.ktx");
      await _thermionViewer!.loadIbl("assets/default_env_ibl.ktx");

      // 没有 setIblIntensity，就直接把 IBL 移除，仅留 skybox
      //try { await _thermionViewer!.removeIbl(); } catch (_) {}

      // 👉👉👉 新增：按三盏灯的规格添加（放在 IBL 之后、渲染之前）
      await applyLightsFromSpec(_thermionViewer!);
      
      // 🎨 启用后处理和渲染
      await _thermionViewer!.setPostProcessing(true);
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
        appBar: AppBar(title: Text(widget.title)),
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
      body: Stack(
        children: [
          // 3D 视图 - 全屏显示
          Positioned.fill(
            child: ThermionListenerWidget(
              inputHandler: _inputHandler,
              child: ThermionWidget(
                viewer: _thermionViewer!,
              ),
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
                FloatingActionButton(
                  heroTag: "reload",
                  mini: true,
                  onPressed: () => _loadCharacter(_characterUri),
                  backgroundColor: Colors.blue.withValues(alpha: 0.9),
                  child: const Icon(Icons.refresh, color: Colors.white, size: 20),
                ),
                const SizedBox(height: 12),
                
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
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTapDown: (_) {
                  if (kDebugMode) {
                    debugPrint('🎤 麦克风按钮按下');
                  }
                  setState(() {
                    _isMicPressed = true;
                  });
                  // 按下时开始播放 talk
                  if (_talkAnimIndex >= 0) {
                    startTalkLoop();
                  }
                },
                onTapUp: (_) {
                  if (kDebugMode) {
                    debugPrint('🎤 麦克风按钮松开');
                  }
                  setState(() {
                    _isMicPressed = false;
                  });
                  // 松开时回到 idle
                  startIdleLoop();
                },
                onTapCancel: () {
                  if (kDebugMode) {
                    debugPrint('🎤 麦克风按钮取消');
                  }
                  setState(() {
                    _isMicPressed = false;
                  });
                  // 取消时也回到 idle
                  startIdleLoop();
                },
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: _isMicPressed || _currentState == AnimState.talk 
                        ? Colors.orange.withValues(alpha: 0.9)
                        : Colors.blue.withValues(alpha: 0.9),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Icon(
                    _isMicPressed || _currentState == AnimState.talk 
                        ? Icons.record_voice_over 
                        : Icons.mic,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
              ),
            ),
          ),
          
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