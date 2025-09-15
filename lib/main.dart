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

class _ThermionDemoState extends State<ThermionDemo> with TickerProviderStateMixin {
  
  // 核心变量
  ThermionViewer? _viewer;
  double _fps = 0.0;
  int _frameCount = 0;
  DateTime _lastTime = DateTime.now();
  Timer? _fpsTimer;
  bool _showFpsOverlay = true;
  
  // 悬浮按钮控制
  bool _isControlPanelOpen = false;
  late AnimationController _animationController;
  
  // 相机控制
  final double _cameraX = 0.0;
  final double _cameraY = 1.5; // 修正为与旋转一致
  final double _cameraZ = 3.2;
  final double _focusX = 0.0;
  double _focusY = 0.60;       // 焦点Y坐标 - 可调节，用于球坐标相机
  final double _focusZ = 0.0;
  

  
  // 球坐标相机控制 - 基于最佳全身照角度优化
  double _cameraRadius = 3.2;  // 🎯 最佳距离 - 完美全身照构图
  double _cameraTheta = 90.0;  // 🎯 最佳水平角度 - 人物正面
  double _cameraPhi = 75.0;   // 🎯 最佳垂直角度 - 理想俯视角度
  final bool _useSphericalCamera = true; // 使用球坐标控制
  
  // HDR 环境控制
  final double _iblIntensity = 50000.0;
  
  // 光照控制
  final bool _warmLightEnabled = true;
  final double _faceWarmIntensity = 35000.0;
  final double _legWarmIntensity = 25000.0;
  final double _warmColorTemp = 4800.0;

  @override
  void initState() {
    super.initState();
    _startFpsMonitoring();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _fpsTimer?.cancel();
    _animationController.dispose();
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

  // 球坐标相机更新（从 HDR 环境测试迁移）
  Future<void> _updateSphericalCamera() async {
    if (_viewer == null) return;
    
    try {
      // 将球坐标转换为笛卡尔坐标
      final double thetaRad = _cameraTheta * (math.pi / 180.0);
      final double phiRad = _cameraPhi * (math.pi / 180.0);

      final double x = _cameraRadius * math.sin(phiRad) * math.cos(thetaRad);
      final double y = _cameraRadius * math.cos(phiRad);
      final double z = _cameraRadius * math.sin(phiRad) * math.sin(thetaRad);

      final v.Vector3 cameraPos = v.Vector3(x, y, z);
      final v.Vector3 focusPoint = v.Vector3(0.0, _focusY, 0.0); // 使用可调节的焦点Y坐标
      final v.Vector3 upVector = v.Vector3(0.0, 1.0, 0.0);

      debugPrint('📍 球坐标相机: R=${_cameraRadius.toStringAsFixed(1)}m, θ=${_cameraTheta.toStringAsFixed(0)}°, φ=${_cameraPhi.toStringAsFixed(0)}°');
      debugPrint('📍 笛卡尔坐标: (${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)}, ${z.toStringAsFixed(2)})');

      final camera = await _viewer!.getActiveCamera();
      await camera.lookAt(
        cameraPos,
        focus: focusPoint,
        up: upVector,
      );
    } catch (e) {
      debugPrint('❌ 球坐标相机更新失败: $e');
    }
  }

  // HDR 环境控制方法
  Future<void> _updateIblIntensity() async {
    if (_viewer == null) return;
    
    try {
      debugPrint('🔄 更新 IBL 强度: ${(_iblIntensity/1000).toStringAsFixed(0)}K');
      await _viewer!.loadIbl(
        'assets/environments/default_env_ibl.ktx',
        intensity: _iblIntensity,
        destroyExisting: true
      );
    } catch (e) {
      debugPrint('❌ IBL 强度更新失败: $e');
    }
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

  String _getViewAngleDescription(double theta) {
    // 根据实际人物朝向重新定义角度描述
    if (theta == 90) return '正面视角';  // 90度是人物正面
    if (theta == 180) return '右侧视角';
    if (theta == 270) return '背面视角';
    if (theta == 0 || theta == 360) return '左侧视角';
    
    if (theta > 90 && theta < 180) return '右前方';
    if (theta > 180 && theta < 270) return '右后方';
    if (theta > 270 && theta < 360) return '左后方';
    if (theta > 0 && theta < 90) return '左前方';
    
    return '自定义角度';
  }

  Color _getViewAngleColor(double theta) {
    if (theta == 90) return Colors.green;   // 正面 - 绿色
    if (theta == 180) return Colors.cyan;   // 右侧 - 青色
    if (theta == 270) return Colors.orange; // 背面 - 橙色
    if (theta == 0 || theta == 360) return Colors.purple; // 左侧 - 紫色
    return Colors.blue;
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

  Widget _buildControlButton({
    required String label,
    required void Function() onPressed,
    required Color color,
    bool isActive = false,
  }) {
    return Container(
      margin: const EdgeInsets.all(4),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isActive ? color : color.withValues(alpha: 0.7),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
          elevation: isActive ? 8 : 4,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
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
              margin: const EdgeInsets.only(bottom: 80),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 15,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 角度控制组
                  const Text(
                    '视角控制',
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildControlButton(
                        label: '正面',
                        color: Colors.green,
                        isActive: _cameraTheta == 90,
                        onPressed: () {
                          setState(() { _cameraTheta = 90; });
                          _updateSphericalCamera();
                        },
                      ),
                      _buildControlButton(
                        label: '右侧',
                        color: Colors.cyan,
                        isActive: _cameraTheta == 180,
                        onPressed: () {
                          setState(() { _cameraTheta = 180; });
                          _updateSphericalCamera();
                        },
                      ),
                      _buildControlButton(
                        label: '背面',
                        color: Colors.orange,
                        isActive: _cameraTheta == 270,
                        onPressed: () {
                          setState(() { _cameraTheta = 270; });
                          _updateSphericalCamera();
                        },
                      ),
                      _buildControlButton(
                        label: '左侧',
                        color: Colors.purple,
                        isActive: _cameraTheta == 0,
                        onPressed: () {
                          setState(() { _cameraTheta = 0; });
                          _updateSphericalCamera();
                        },
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // 距离和焦点控制组
                  const Text(
                    '距离调节',
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildControlButton(
                        label: '近',
                        color: Colors.teal,
                        onPressed: () {
                          setState(() {
                            _cameraRadius = _cameraRadius > 2.0 ? _cameraRadius - 0.2 : 1.8;
                          });
                          _updateSphericalCamera();
                        },
                      ),
                      _buildControlButton(
                        label: '远',
                        color: Colors.teal,
                        onPressed: () {
                          setState(() {
                            _cameraRadius = _cameraRadius < 4.2 ? _cameraRadius + 0.2 : 4.5;
                          });
                          _updateSphericalCamera();
                        },
                      ),
                      _buildControlButton(
                        label: '上',
                        color: Colors.amber,
                        onPressed: () {
                          setState(() {
                            _focusY = _focusY < 0.9 ? _focusY + 0.05 : 1.0;
                          });
                          _updateSphericalCamera();
                        },
                      ),
                      _buildControlButton(
                        label: '下',
                        color: Colors.amber,
                        onPressed: () {
                          setState(() {
                            _focusY = _focusY > 0.1 ? _focusY - 0.05 : 0.0;
                          });
                          _updateSphericalCamera();
                        },
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // 构图预设组
                  const Text(
                    '构图预设',
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildControlButton(
                        label: '🎯 最佳',
                        color: Colors.green,
                        isActive: _cameraRadius == 3.2 && _cameraPhi == 75.0,
                        onPressed: () {
                          setState(() {
                            _cameraRadius = 3.2;
                            _cameraPhi = 75.0;
                            _focusY = 0.6;
                          });
                          _updateSphericalCamera();
                        },
                      ),
                      _buildControlButton(
                        label: '全身',
                        color: Colors.indigo,
                        onPressed: () {
                          setState(() {
                            _cameraRadius = 3.8;
                            _cameraPhi = 78.0;
                          });
                          _updateSphericalCamera();
                        },
                      ),
                      _buildControlButton(
                        label: '半身',
                        color: Colors.indigo,
                        onPressed: () {
                          setState(() {
                            _cameraRadius = 2.2;
                            _cameraPhi = 72.0;
                          });
                          _updateSphericalCamera();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
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
            iblPath: 'assets/environments/default_env_ibl.ktx',
            skyboxPath: 'assets/environments/default_env_skybox.ktx',
            transformToUnitCube: true,
            manipulatorType: ManipulatorType.NONE,
            //background: const Color(0xFF404040),
            onViewerAvailable: (viewer) async {
              _viewer = viewer;
              debugPrint('🚀 Thermion 3D 渲染系统初始化...');

              // 等待初始化
              await Future.delayed(const Duration(milliseconds: 300));

              // 设置相机（使用球坐标）
              if (_useSphericalCamera) {
                await _updateSphericalCamera();
              } else {
                await _updateCamera();
              }

              // 启用基本设置
              await viewer.setPostProcessing(true);
              await viewer.setShadowsEnabled(true);
              await viewer.setShadowType(ShadowType.PCSS);

              // 更新 HDR 环境
              await _updateIblIntensity();

              // 初始化光照
              await _initializeLighting();

              await viewer.setRendering(true);
              
              debugPrint('✅ Thermion 3D 渲染系统设置完成');
              debugPrint('📊 HDR 环境坐标系统: θ=0°(+Z正面), θ=180°(-Z背面)');
              debugPrint('📊 当前相机角度: θ=$_cameraTheta° (${_cameraTheta == 0 ? "看向HDR正面" : _cameraTheta == 180 ? "看向HDR背面" : "侧面视角"})');
            },
          ),
          
          // 调试信息显示
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'FPS: ${_fps.toStringAsFixed(1)}',
                      style: TextStyle(
                        color: _getFpsColor(_fps),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_useSphericalCamera) ...[
                      const SizedBox(height: 4),
                      Text(
                        'R=${_cameraRadius.toStringAsFixed(1)}m θ=${_cameraTheta.toStringAsFixed(0)}°',
                        style: const TextStyle(color: Colors.white, fontSize: 10),
                      ),
                      Text(
                        'φ=${_cameraPhi.toStringAsFixed(0)}° Focus=${_focusY.toStringAsFixed(1)}',
                        style: const TextStyle(color: Colors.white, fontSize: 10),
                      ),
                      Text(
                        'IBL=${(_iblIntensity/1000).toStringAsFixed(0)}K',
                        style: const TextStyle(color: Colors.white, fontSize: 10),
                      ),
                      Text(
                        _getViewAngleDescription(_cameraTheta),
                        style: TextStyle(
                          color: _getViewAngleColor(_cameraTheta),
                          fontSize: 10,
                        ),
                      ),
                    ],
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
          
          // 主悬浮按钮
          Positioned(
            bottom: 20,
            right: 20,
            child: FloatingActionButton(
              onPressed: _toggleControlPanel,
              backgroundColor: Colors.blue.withValues(alpha: 0.9),
              child: AnimatedRotation(
                turns: _isControlPanelOpen ? 0.125 : 0,
                duration: const Duration(milliseconds: 300),
                child: Icon(
                  _isControlPanelOpen ? Icons.close : Icons.camera_alt,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}