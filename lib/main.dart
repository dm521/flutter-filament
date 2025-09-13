import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:thermion_flutter/thermion_flutter.dart';
import 'package:vector_math/vector_math_64.dart' as v;
import 'dart:async';

// 稳定的 ViewerWidget 包装器，避免重建问题
class StableViewerWidget extends StatefulWidget {
  final Future<void> Function(ThermionViewer) onViewerAvailable;
  
  const StableViewerWidget({
    super.key,
    required this.onViewerAvailable,
  });

  @override
  State<StableViewerWidget> createState() => _StableViewerWidgetState();
}

class _StableViewerWidgetState extends State<StableViewerWidget> {
  @override
  Widget build(BuildContext context) {
    return ViewerWidget(
      assetPath: 'assets/models/2D_Girl.glb',
      iblPath: 'assets/environments/default_env_ibl.ktx',
      skyboxPath: 'assets/environments/default_env_skybox.ktx',
      transformToUnitCube: true,
      manipulatorType: ManipulatorType.NONE,
      background: const Color(0xFF404040),
      initialCameraPosition: v.Vector3(0.0, 1.2, 3.0),
      onViewerAvailable: widget.onViewerAvailable,
    );
  }
}

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ThermionDemo(),
    );
  }
}

class ThermionDemo extends StatefulWidget {
  const ThermionDemo({super.key});

  @override
  State<ThermionDemo> createState() => _ThermionDemoState();
}

class _ThermionDemoState extends State<ThermionDemo>
    with TickerProviderStateMixin {
  
  // FPS 监控
  double _fps = 0.0;
  int _frameCount = 0;
  DateTime _lastTime = DateTime.now();
  Timer? _fpsTimer;
  bool _showFpsOverlay = true;
  
  // 相机控制
  ThermionViewer? _viewer;
  double _cameraX = 0.0;
  double _cameraY = 1.20;
  double _cameraZ = 2.5;
  double _focusX = 0.0;
  double _focusY = 0.6;
  double _focusZ = 0.0;
  
  // 阴影控制
  ShadowType _currentShadowType = ShadowType.PCSS;
  bool _shadowsEnabled = true;
  double _penumbraScale = 2.0;
  double _penumbraRatioScale = 0.4;
  
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

  // 相机控制方法
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

  void _applyPreset(String name, double cx, double cy, double cz, double fx, double fy, double fz) {
    setState(() {
      _cameraX = cx;
      _cameraY = cy;
      _cameraZ = cz;
      _focusX = fx;
      _focusY = fy;
      _focusZ = fz;
    });
    _updateCamera();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已应用 $name 预设')),
    );
  }

  // 重置到初始视角
  void _resetCamera() {
    setState(() {
      _cameraX = 0.0;
      _cameraY = 1.2;
      _cameraZ = 2.5;
      _focusX = 0.0;
      _focusY = 0.6;
      _focusZ = 0.0;
    });
    _updateCamera();
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已重置到初始视角')),
    );
  }

  // 阴影控制方法
  Future<void> _updateShadowType(ShadowType type) async {
    if (_viewer == null) return;
    
    setState(() {
      _currentShadowType = type;
    });
    
    try {
      await _viewer!.setShadowType(type);
      await _viewer!.setSoftShadowOptions(_penumbraScale, _penumbraRatioScale);
    } catch (e) {
      debugPrint('❌ 更新阴影类型失败: $e');
    }
  }

  Future<void> _toggleShadows() async {
    if (_viewer == null) return;
    
    setState(() {
      _shadowsEnabled = !_shadowsEnabled;
    });
    
    try {
      await _viewer!.setShadowsEnabled(_shadowsEnabled);
    } catch (e) {
      debugPrint('❌ 切换阴影失败: $e');
    }
  }

  Future<void> _updateShadowIntensity(double penumbraScale, double penumbraRatioScale) async {
    if (_viewer == null) return;
    
    setState(() {
      _penumbraScale = penumbraScale;
      _penumbraRatioScale = penumbraRatioScale;
    });
    
    try {
      await _viewer!.setSoftShadowOptions(_penumbraScale, _penumbraRatioScale);
    } catch (e) {
      debugPrint('❌ 更新阴影强度失败: $e');
    }
  }

  // UI 构建方法
  Widget _buildControlPanel() {
    return Container(
      color: Colors.grey[50],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 相机控制折叠面板
          _buildCameraControls(),
          
          // 阴影控制折叠面板
          _buildShadowControls(),
        ],
      ),
    );
  }

  Widget _buildCameraControls() {
    return ExpansionTile(
      title: const Row(
        children: [
          Icon(Icons.camera_alt, size: 20, color: Colors.blue),
          SizedBox(width: 8),
          Text('相机控制', style: TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
      subtitle: Text('位置: (${_cameraX.toStringAsFixed(1)}, ${_cameraY.toStringAsFixed(1)}, ${_cameraZ.toStringAsFixed(1)}) | 焦点: (${_focusX.toStringAsFixed(1)}, ${_focusY.toStringAsFixed(1)}, ${_focusZ.toStringAsFixed(1)})'),
      initiallyExpanded: false,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // 快速预设
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.bookmark, size: 18),
                          SizedBox(width: 8),
                          Text('快速预设', style: TextStyle(fontWeight: FontWeight.w500)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildPresetButton('正面', Icons.person, () => _applyPreset('正面', 0, 1.2, 2.5, 0, 0.6, 0)),
                          _buildPresetButton('侧面', Icons.person_outline, () => _applyPreset('侧面', 3.0, 1.2, 1.0, 0, 0.8, 0)),
                          _buildPresetButton('俯视', Icons.keyboard_arrow_down, () => _applyPreset('俯视', 0, 3.0, 2.0, 0, 0.8, 0)),
                          _buildPresetButton('全身', Icons.accessibility, () => _applyPreset('全身', 0, 1.5, 4.0, 0, 1.0, 0)),
                          _buildPresetButton('重置', Icons.refresh, _resetCamera),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              
              // 精细调节
              ExpansionTile(
                title: const Text('精细调节', style: TextStyle(fontSize: 14)),
                initiallyExpanded: false,
                children: [
                  _buildSlider('相机 X', _cameraX, -5.0, 5.0, (value) {
                    setState(() => _cameraX = value);
                    _updateCamera();
                  }),
                  _buildSlider('相机 Y', _cameraY, -2.0, 5.0, (value) {
                    setState(() => _cameraY = value);
                    _updateCamera();
                  }),
                  _buildSlider('相机 Z', _cameraZ, 0.5, 8.0, (value) {
                    setState(() => _cameraZ = value);
                    _updateCamera();
                  }),
                  _buildSlider('焦点 X', _focusX, -2.0, 2.0, (value) {
                    setState(() => _focusX = value);
                    _updateCamera();
                  }),
                  _buildSlider('焦点 Y', _focusY, -1.0, 3.0, (value) {
                    setState(() => _focusY = value);
                    _updateCamera();
                  }),
                  _buildSlider('焦点 Z', _focusZ, -2.0, 2.0, (value) {
                    setState(() => _focusZ = value);
                    _updateCamera();
                  }),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildShadowControls() {
    return ExpansionTile(
      title: Row(
        children: [
          const Icon(Icons.wb_sunny_outlined, size: 20, color: Colors.orange),
          const SizedBox(width: 8),
          const Text('阴影控制', style: TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          Switch(
            value: _shadowsEnabled,
            onChanged: (value) => _toggleShadows(),
          ),
        ],
      ),
      subtitle: Text('${_getShadowTypeName(_currentShadowType)} | 强度: ${_penumbraScale.toStringAsFixed(1)} | 比例: ${_penumbraRatioScale.toStringAsFixed(2)}'),
      initiallyExpanded: false,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // 阴影类型选择
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.layers, size: 18),
                          SizedBox(width: 8),
                          Text('阴影类型', style: TextStyle(fontWeight: FontWeight.w500)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: ShadowType.values.map((type) {
                          final isSelected = type == _currentShadowType;
                          return FilterChip(
                            label: Text(_getShadowTypeName(type)),
                            selected: isSelected,
                            onSelected: _shadowsEnabled ? (selected) {
                              if (selected) _updateShadowType(type);
                            } : null,
                            selectedColor: Colors.orange.withValues(alpha: 0.3),
                            backgroundColor: Colors.grey[100],
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              
              // 阴影参数
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.tune, size: 18),
                          SizedBox(width: 8),
                          Text('阴影参数', style: TextStyle(fontWeight: FontWeight.w500)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      
                      _buildSlider('阴影强度', _penumbraScale, 0.5, 5.0, (value) {
                        _updateShadowIntensity(value, _penumbraRatioScale);
                      }),
                      _buildSlider('阴影比例', _penumbraRatioScale, 0.1, 1.0, (value) {
                        _updateShadowIntensity(_penumbraScale, value);
                      }),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSlider(String label, double value, double min, double max, Function(double) onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 14)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  value.toStringAsFixed(2),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: ((max - min) * 20).round(),
            onChanged: onChanged,
            activeColor: Colors.blue,
          ),
        ],
      ),
    );
  }

  Widget _buildPresetButton(String label, IconData icon, void Function() onPressed) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }

  String _getShadowTypeName(ShadowType type) {
    switch (type) {
      case ShadowType.PCF:
        return 'PCF (基础)';
      case ShadowType.VSM:
        return 'VSM (方差)';
      case ShadowType.DPCF:
        return 'DPCF (硬化)';
      case ShadowType.PCSS:
        return 'PCSS (软阴影)';
    }
  }

  Color _getFpsColor(double fps) {
    if (fps >= 55) return Colors.green;
    if (fps >= 45) return Colors.yellow;
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
      body: Column(
        children: [
          // 折叠控制面板
          _buildControlPanel(),
          
          // 3D 视图 - 占据剩余空间
          Expanded(
            child: Stack(
              children: [
                StableViewerWidget(
                  onViewerAvailable: (viewer) async {
                    _viewer = viewer;
                    debugPrint('🚀 Thermion 3D 渲染系统初始化...');

                    // 设置相机到当前位置
                    await _updateCamera();

                    // 启用后处理和阴影
                    await viewer.setPostProcessing(true);
                    await viewer.setShadowsEnabled(_shadowsEnabled);
                    await viewer.setShadowType(_currentShadowType);
                    await viewer.setSoftShadowOptions(_penumbraScale, _penumbraRatioScale);

                    // 清除默认光照
                    await viewer.destroyLights();

                    // 专业三点光照系统
                    await viewer.addDirectLight(DirectLight.sun(
                      color: 5800.0,
                      intensity: 100000.0,
                      direction: v.Vector3(0.6, -0.9, -0.5).normalized(),
                      castShadows: true,
                      sunAngularRadius: 0.8,
                    ));

                    await viewer.addDirectLight(DirectLight.sun(
                      color: 6200.0,
                      intensity: 20000.0,
                      direction: v.Vector3(-0.6, -0.3, -0.8).normalized(),
                      castShadows: false,
                    ));

                    await viewer.addDirectLight(DirectLight.sun(
                      color: 7000.0,
                      intensity: 25000.0,
                      direction: v.Vector3(-0.2, 0.1, 0.9).normalized(),
                      castShadows: false,
                    ));

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
              ],
            ),
          ),
        ],
      ),
    );
  }
}