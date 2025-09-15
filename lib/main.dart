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
  
  // 相机动画控制
  bool _isCameraAnimating = false;
  
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
  
  // HDR 环境控制 - 配合天空HDR优化
  double _iblIntensity = 30000.0;  // 可调节IBL强度
  
  // 画质预设系统
  String _currentQuality = 'high';  // high/medium/low
  


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
    
    // 🧹 完善资源清理
    _cleanupResources();
    
    super.dispose();
  }
  
  // 🧹 资源清理方法
  Future<void> _cleanupResources() async {
    try {
      if (_viewer != null) {
        debugPrint('🧹 开始清理3D资源...');
        
        // 停止渲染
        await _viewer!.setRendering(false);
        
        // 清理所有光照
        await _viewer!.destroyLights();
        
        debugPrint('✅ 3D资源清理完成');
      }
    } catch (e) {
      debugPrint('❌ 资源清理失败: $e');
    }
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

  // 🎬 带动画的球坐标相机更新
  Future<void> _updateSphericalCamera({bool animate = false}) async {
    if (_viewer == null || _isCameraAnimating) return;
    
    try {
      // 将球坐标转换为笛卡尔坐标
      final double thetaRad = _cameraTheta * (math.pi / 180.0);
      final double phiRad = _cameraPhi * (math.pi / 180.0);

      final double x = _cameraRadius * math.sin(phiRad) * math.cos(thetaRad);
      final double y = _cameraRadius * math.cos(phiRad);
      final double z = _cameraRadius * math.sin(phiRad) * math.sin(thetaRad);

      final v.Vector3 targetPos = v.Vector3(x, y, z);
      final v.Vector3 focusPoint = v.Vector3(0.0, _focusY, 0.0);
      final v.Vector3 upVector = v.Vector3(0.0, 1.0, 0.0);

      debugPrint('📍 球坐标相机: R=${_cameraRadius.toStringAsFixed(1)}m, θ=${_cameraTheta.toStringAsFixed(0)}°, φ=${_cameraPhi.toStringAsFixed(0)}°');

      final camera = await _viewer!.getActiveCamera();
      
      if (animate) {
        // 🎬 250ms 插值动画
        _isCameraAnimating = true;
        
        // 获取当前位置
        final currentPos = await camera.getPosition();
        
        // 创建插值动画参数
        const steps = 10;
        const stepDuration = Duration(milliseconds: 25);
        
        for (int i = 1; i <= steps; i++) {
          final t = i / steps;
          // 使用 easeInOut 缓动函数
          final easedT = t * t * (3.0 - 2.0 * t);
          
          final interpolatedPos = v.Vector3(
            currentPos.x + (targetPos.x - currentPos.x) * easedT,
            currentPos.y + (targetPos.y - currentPos.y) * easedT,
            currentPos.z + (targetPos.z - currentPos.z) * easedT,
          );
          
          await camera.lookAt(interpolatedPos, focus: focusPoint, up: upVector);
          await Future.delayed(stepDuration);
        }
        
        _isCameraAnimating = false;
      } else {
        // 直接切换
        await camera.lookAt(targetPos, focus: focusPoint, up: upVector);
      }
      
    } catch (e) {
      debugPrint('❌ 球坐标相机更新失败: $e');
      _isCameraAnimating = false;
    }
  }

  // HDR 环境控制方法
  Future<void> _updateIblIntensity() async {
    if (_viewer == null) return;
    
    try {
      debugPrint('🔄 更新 IBL 强度: ${(_iblIntensity/1000).toStringAsFixed(0)}K');
      
      // 🛡️ 安全的 IBL 加载 - 优先使用天空HDR，回退到默认
      String iblPath = 'assets/environments/sky_output_2048_ibl.ktx';
      
      try {
        await _viewer!.loadIbl(
          iblPath,
          intensity: _iblIntensity,
          destroyExisting: true
        );
        debugPrint('✅ 天空HDR加载成功');
      } catch (skyError) {
        debugPrint('⚠️ 天空HDR加载失败，回退到默认: $skyError');
        // 回退到默认环境
        await _viewer!.loadIbl(
          'assets/environments/default_env_ibl.ktx',
          intensity: _iblIntensity,
          destroyExisting: true
        );
        debugPrint('✅ 默认HDR加载成功');
      }
      
    } catch (e) {
      debugPrint('❌ IBL 强度更新完全失败: $e');
    }
  }

  // 光照系统初始化
  Future<void> _initializeLighting() async {
    if (_viewer == null) return;
    
    try {
      // 清除现有光照
      await _viewer!.destroyLights();
      
      // 🌟 精简高质量光照系统 - 仅2盏灯
      
      // 1. 主光源 - 唯一投影光源，模拟太阳光
      await _viewer!.addDirectLight(DirectLight.sun(
        color: 3600.0,  // 温暖的黄光
        intensity: 55000.0,  // 提高强度补偿减少的灯光
        direction: v.Vector3(0.4, -0.8, -0.3).normalized(),  // 优化角度
        castShadows: true,  // 唯一投影光源
        sunAngularRadius: 2.0,  // 增加柔和度
      ));

      // 2. 补光 - 柔和填充光，模拟天空漫反射
      await _viewer!.addDirectLight(DirectLight.sun(
        color: 4200.0,  // 稍冷的补光平衡色温
        intensity: 15000.0,  // 适中强度
        direction: v.Vector3(-0.5, -0.2, 0.7).normalized(),  // 从侧后方补光
        castShadows: false,  // 不投影，避免多重阴影
        sunAngularRadius: 3.0,  // 很柔和的补光
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

  // 🎮 画质预设系统
  Future<void> _setQuality(String quality) async {
    if (_viewer == null) return;
    
    setState(() {
      _currentQuality = quality;
    });
    
    try {
      switch (quality) {
        case 'high':
          await _viewer!.setShadowType(ShadowType.PCSS);
          await _viewer!.setSoftShadowOptions(2.5, 0.4);
          _iblIntensity = 35000.0;
          debugPrint('🔥 高画质模式: PCSS阴影 + 高强度IBL');
          break;
        case 'medium':
          await _viewer!.setShadowType(ShadowType.DPCF);
          await _viewer!.setSoftShadowOptions(2.0, 0.5);
          _iblIntensity = 25000.0;
          debugPrint('⚡ 中画质模式: DPCF阴影 + 中强度IBL');
          break;
        case 'low':
          await _viewer!.setShadowType(ShadowType.PCF);
          await _viewer!.setSoftShadowOptions(1.5, 0.6);
          _iblIntensity = 20000.0;
          debugPrint('📱 低画质模式: PCF阴影 + 低强度IBL');
          break;
      }
      
      // 🔄 重新加载IBL应用新强度（仅在初始化后）
      if (_viewer != null) {
        await _updateIblIntensity();
      }
      
    } catch (e) {
      debugPrint('❌ 画质设置失败: $e');
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
                          _updateSphericalCamera(animate: true);  // 启用动画
                        },
                      ),
                      _buildControlButton(
                        label: '右侧',
                        color: Colors.cyan,
                        isActive: _cameraTheta == 180,
                        onPressed: () {
                          setState(() { _cameraTheta = 180; });
                          _updateSphericalCamera(animate: true);
                        },
                      ),
                      _buildControlButton(
                        label: '背面',
                        color: Colors.orange,
                        isActive: _cameraTheta == 270,
                        onPressed: () {
                          setState(() { _cameraTheta = 270; });
                          _updateSphericalCamera(animate: true);
                        },
                      ),
                      _buildControlButton(
                        label: '左侧',
                        color: Colors.purple,
                        isActive: _cameraTheta == 0,
                        onPressed: () {
                          setState(() { _cameraTheta = 0; });
                          _updateSphericalCamera(animate: true);
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
                  
                  // 画质设置组
                  const Text(
                    '画质设置',
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildControlButton(
                        label: '🔥 高',
                        color: Colors.red,
                        isActive: _currentQuality == 'high',
                        onPressed: () => _setQuality('high'),
                      ),
                      _buildControlButton(
                        label: '⚡ 中',
                        color: Colors.orange,
                        isActive: _currentQuality == 'medium',
                        onPressed: () => _setQuality('medium'),
                      ),
                      _buildControlButton(
                        label: '📱 低',
                        color: Colors.green,
                        isActive: _currentQuality == 'low',
                        onPressed: () => _setQuality('low'),
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
                          _updateSphericalCamera(animate: true);
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
                          _updateSphericalCamera(animate: true);
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
            iblPath: 'assets/environments/sky_output_2048_ibl.ktx',
            skyboxPath: 'assets/environments/sky_output_2048_skybox.ktx',
            transformToUnitCube: true,
            manipulatorType: ManipulatorType.NONE,
            //background: const Color(0xFF404040),
            onViewerAvailable: (viewer) async {
              _viewer = viewer;
              debugPrint('🚀 Thermion 3D 渲染系统初始化...');
              debugPrint('📱 设备信息: ${MediaQuery.of(context).size}');

              // 🚀 分阶段初始化，确保稳定性
              
              // 阶段1: 等待基础初始化
              await Future.delayed(const Duration(milliseconds: 500));
              
              // 阶段2: 启用渲染设置
              await viewer.setPostProcessing(true);
              await viewer.setShadowsEnabled(true);
              
              // 阶段3: 设置画质（包含IBL）
              await _setQuality('high');
              
              // 阶段4: 等待渲染管线稳定
              await Future.delayed(const Duration(milliseconds: 200));
              
              // 阶段5: 初始化光照
              await _initializeLighting();
              
              // 阶段6: 设置相机
              await _updateSphericalCamera();

              // 阶段7: 启用渲染
              await viewer.setRendering(true);

              
              debugPrint('✅ Thermion 3D 渲染系统设置完成');
              debugPrint('📊 HDR 环境坐标系统: θ=0°(+Z正面), θ=180°(-Z背面)');
              debugPrint('📊 当前相机角度: θ=$_cameraTheta° (${_cameraTheta == 0 ? "看向HDR正面" : _cameraTheta == 180 ? "看向HDR背面" : "侧面视角"})');
              debugPrint('🎮 当前画质: $_currentQuality');
              debugPrint('💡 IBL强度: ${(_iblIntensity/1000).toStringAsFixed(0)}K');
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