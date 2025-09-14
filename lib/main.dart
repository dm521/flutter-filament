import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:thermion_flutter/thermion_flutter.dart';
import 'package:vector_math/vector_math_64.dart' as v;
import 'dart:async';
import 'dart:math' as math;

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const ThermionDemo(),
    );
  }
}

class ThermionDemo extends StatefulWidget {
  const ThermionDemo({super.key});

  @override
  State<ThermionDemo> createState() => _ThermionDemoState();
}

class _ThermionDemoState extends State<ThermionDemo> {
  
  // 核心变量
  ThermionViewer? _viewer;
  double _fps = 0.0;
  int _frameCount = 0;
  DateTime _lastTime = DateTime.now();
  Timer? _fpsTimer;
  bool _showFpsOverlay = true;
  
  // 相机控制
  double _cameraX = 0.0;
  double _cameraY = 0.6; // 修正为与旋转一致
  double _cameraZ = 3.0;
  double _focusX = 0.0;
  double _focusY = 0.6;
  double _focusZ = 0.0;
  
  // 水平旋转控制
  double _horizontalRotation = 0.0;
  
  // 光照控制
  bool _warmLightEnabled = true;
  double _faceWarmIntensity = 35000.0;
  double _legWarmIntensity = 25000.0;
  double _warmColorTemp = 4800.0;

  @override
  void initState() {
    super.initState();
    _startFpsMonitoring();
  }

  @override
  void dispose() {
    _fpsTimer?.cancel();
    super.dispose();
  }

  void _startFpsMonitoring() {
    SchedulerBinding.instance.addPostFrameCallback(_onFrame);
    _fpsTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        // FPS 更新逻辑
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

  // 相机更新方法
  Future<void> _updateCamera() async {
    if (_viewer == null) return;
    
    try {
      final camera = await _viewer!.getActiveCamera();
      await camera.lookAt(
        v.Vector3(_cameraX, _cameraY, _cameraZ),
        focus: v.Vector3(_focusX, _focusY, _focusZ),
        up: v.Vector3(0, 1, 0),
      );
    } catch (e) {
      debugPrint('❌ 相机更新失败: $e');
    }
  }

  // 水平旋转控制
  void _updateHorizontalRotation(double angle) {
    setState(() {
      _horizontalRotation = angle;
      
      // 计算圆形轨道上的相机位置
      final radius = 3.0;
      final radians = angle * (math.pi / 180);
      
      _cameraX = radius * math.sin(radians);
      _cameraZ = radius * math.cos(radians);
      _cameraY = 0.6;
    });
    
    _updateCamera();
  }

  // 光照系统初始化
  Future<void> _initializeLighting() async {
    if (_viewer == null) return;
    
    try {
      // 清除现有光照
      await _viewer!.destroyLights();
      
      // 1. 主光源
      await _viewer!.addDirectLight(DirectLight.sun(
        color: 5600.0,
        intensity: 70000.0,
        direction: v.Vector3(0.5, -0.8, -0.6).normalized(),
        castShadows: true,
        sunAngularRadius: 1.2,
      ));

      // 2. 脸部暖光
      if (_warmLightEnabled) {
        await _viewer!.addDirectLight(DirectLight.point(
          color: _warmColorTemp,
          intensity: _faceWarmIntensity,
          position: v.Vector3(0.0, 1.4, 2.2),
          falloffRadius: 4.5,
        ));

        // 3. 腿部补光
        await _viewer!.addDirectLight(DirectLight.point(
          color: _warmColorTemp + 200,
          intensity: _legWarmIntensity,
          position: v.Vector3(0.0, 0.6, 1.9),
          falloffRadius: 3.8,
        ));
      }

      // 4. 填充光
      await _viewer!.addDirectLight(DirectLight.sun(
        color: 5800.0,
        intensity: 16000.0,
        direction: v.Vector3(-0.6, -0.2, -0.8).normalized(),
        castShadows: false,
      ));

      // 5. 轮廓光
      await _viewer!.addDirectLight(DirectLight.sun(
        color: 6800.0,
        intensity: 22000.0,
        direction: v.Vector3(-0.2, 0.1, 0.9).normalized(),
        castShadows: false,
      ));
      
    } catch (e) {
      debugPrint('❌ 光照系统初始化失败: $e');
    }
  }

  Color _getFpsColor(double fps) {
    if (fps >= 50) return Colors.green;
    if (fps >= 30) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thermion 3D 渲染'),
        backgroundColor: Colors.blueGrey[800],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_showFpsOverlay ? Icons.visibility : Icons.visibility_off),
            onPressed: () {
              setState(() {
                _showFpsOverlay = !_showFpsOverlay;
              });
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // 3D 视图
          ViewerWidget(
            assetPath: 'assets/models/2D_Girl.glb',
            iblPath: 'assets/environments/studio_small_03_1024_ibl.ktx',
            skyboxPath: 'assets/environments/studio_small_03_1024_skybox.ktx',
            transformToUnitCube: true,
            manipulatorType: ManipulatorType.NONE,
            //background: const Color(0xFF404040),
            onViewerAvailable: (viewer) async {
              _viewer = viewer;
              debugPrint('🚀 Thermion 3D 渲染系统初始化...');

              // 设置相机
              await _updateCamera();

              // 启用基本设置
              await viewer.setPostProcessing(true);
              await viewer.setShadowsEnabled(true);
              await viewer.setShadowType(ShadowType.PCSS);

              // 初始化光照
              await _initializeLighting();

              await viewer.setRendering(true);
              
              debugPrint('✅ Thermion 3D 渲染系统设置完成');
            },
          ),
          
          // FPS 显示
          if (_showFpsOverlay)
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'FPS: ${_fps.toStringAsFixed(1)}',
                  style: TextStyle(
                    color: _getFpsColor(_fps),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          
          // 底部水平旋转控制条
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(25),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.rotate_right,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '水平旋转',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${_horizontalRotation.toStringAsFixed(0)}°',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: Colors.blue,
                      inactiveTrackColor: Colors.grey[600],
                      thumbColor: Colors.blue,
                      overlayColor: Colors.blue.withValues(alpha: 0.2),
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                    ),
                    child: Slider(
                      value: _horizontalRotation,
                      min: 0,
                      max: 360,
                      divisions: 72,
                      onChanged: _updateHorizontalRotation,
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