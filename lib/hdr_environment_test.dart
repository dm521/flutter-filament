import 'package:flutter/material.dart';
import 'package:thermion_flutter/thermion_flutter.dart';
import 'package:vector_math/vector_math_64.dart' as v;
import 'dart:math' as math;

class HDREnvironmentTest extends StatefulWidget {
  const HDREnvironmentTest({super.key});

  @override
  State<HDREnvironmentTest> createState() => _HDREnvironmentTestState();
}

class _HDREnvironmentTestState extends State<HDREnvironmentTest> {
  ThermionViewer? _viewer;
  bool _viewerInitialized = false;
  bool _showSkybox = true;
  double _iblIntensity = 50000.0;  // IBL强度：50K - 理想光照效果

  // 存储加载的模型资产，用于位置调整
  dynamic _modelAsset;

  // 相机控制参数 - 根据理想效果设置
  double _cameraRadius = 3.0;  // 相机距离：3.0m - 完美观看距离
  double _cameraTheta = 90.0;  // 水平角度：90° - 侧面视角
  double _cameraPhi = 90.0;    // 垂直角度：90° - 水平视角

  // 模型位置控制参数
  double _modelYOffset = -0.80; // 模型Y轴偏移量：-0.80m - 完美站在地面

  Future<void> _onViewerAvailable(ThermionViewer viewer) async {
    _viewer = viewer;

    try {
      debugPrint('🚀 HDR 环境测试初始化...');

      // 等待初始化
      await Future.delayed(const Duration(milliseconds: 500));

      // 加载 HDR 环境
      debugPrint('🔄 加载 HDR IBL...');
      await viewer.loadIbl(
        'assets/environments/studio_small_03_1024_ibl.ktx',
        intensity: _iblIntensity,
        destroyExisting: true
      );

      if (_showSkybox) {
        debugPrint('🔄 加载 HDR Skybox...');
        await viewer.loadSkybox('assets/environments/studio_small_03_1024_skybox.ktx');
      }

      // 等待一下再设置相机，确保环境加载完成
      await Future.delayed(const Duration(milliseconds: 200));

      // 先获取并诊断当前相机状态
      await _diagnoseCameraState();

      // 加载模型并调整位置，使其站在地面上
      debugPrint('🔄 加载模型并调整位置...');
      await _loadAndAdjustModel();

      // 设置相机到环境内部，模拟人的视角
      debugPrint('🔄 开始设置初始相机位置...');
      await _updateCameraPosition();

      setState(() {
        _viewerInitialized = true;
      });

      debugPrint('✅ HDR 环境加载完成');
    } catch (e, stackTrace) {
      debugPrint('❌ HDR 环境加载失败: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  Future<void> _diagnoseCameraState() async {
    if (_viewer == null) return;

    try {
      debugPrint('🔍 相机诊断开始...');
      await _viewer!.getActiveCamera();
      debugPrint('📊 相机对象获取成功');
      debugPrint('🔍 相机诊断完成');
    } catch (e) {
      debugPrint('❌ 相机诊断失败: $e');
    }
  }

  Future<void> _loadAndAdjustModel() async {
    if (_viewer == null) return;

    try {
      debugPrint('👤 加载数字人模型...');

      // 加载GLB模型
      _modelAsset = await _viewer!.loadGltf('assets/models/2D_Girl.glb');

      debugPrint('✅ 模型加载成功');

      // 等待一下让模型完全加载
      await Future.delayed(const Duration(milliseconds: 300));

      debugPrint('🔧 调整模型位置，让人物站在地面上...');

      // 创建向下移动的变换矩阵，使用可调整的偏移量
      await _updateModelPosition();

      debugPrint('📍 模型位置已调整: Y轴偏移${_modelYOffset.toStringAsFixed(1)}单位');
      debugPrint('👣 人物现在应该站在地面上了');

    } catch (e, stackTrace) {
      debugPrint('❌ 模型加载或位置调整失败: $e');
      debugPrint('Stack trace: $stackTrace');

      // 如果失败，记录但不阻塞后续流程
      debugPrint('💡 将使用ViewerWidget默认加载的模型');
    }
  }

  Future<void> _updateModelPosition() async {
    if (_modelAsset == null) {
      debugPrint('⚠️ 模型资产未加载，无法调整位置');
      return;
    }

    try {
      // 创建变换矩阵，Y轴使用可调整的偏移量
      final transform = v.Matrix4.translation(v.Vector3(0, _modelYOffset, 0));

      // 应用变换到模型
      await _modelAsset.setTransform(transform);

      debugPrint('📍 模型Y轴位置更新: ${_modelYOffset.toStringAsFixed(2)}');
    } catch (e) {
      debugPrint('❌ 模型位置更新失败: $e');
    }
  }


  Future<void> _updateCameraPosition() async {
    if (_viewer == null || !_viewerInitialized) return;

    try {
      // 将球坐标转换为笛卡尔坐标
      final double thetaRad = _cameraTheta * (math.pi / 180.0);
      final double phiRad = _cameraPhi * (math.pi / 180.0);

      final double x = _cameraRadius * math.sin(phiRad) * math.cos(thetaRad);
      final double y = _cameraRadius * math.cos(phiRad);
      final double z = _cameraRadius * math.sin(phiRad) * math.sin(thetaRad);

      final v.Vector3 cameraPos = v.Vector3(x, y, z);
      final v.Vector3 focusPoint = v.Vector3(0.0, 0.0, 0.0);
      final v.Vector3 upVector = v.Vector3(0.0, 1.0, 0.0);

      debugPrint('📍 设置相机位置: (${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)}, ${z.toStringAsFixed(3)})');
      debugPrint('📍 距离: ${_cameraRadius.toStringAsFixed(3)}m, 角度: θ=${_cameraTheta.toStringAsFixed(1)}°, φ=${_cameraPhi.toStringAsFixed(1)}°');

      final camera = await _viewer!.getActiveCamera();

      // 使用正确的 Thermion API - lookAt 方法
      await camera.lookAt(
        cameraPos,         // 相机位置
        focus: focusPoint, // 目标点（原点）
        up: upVector,      // 上方向
      );

      // 验证相机位置是否正确设置
      try {
        final actualPosition = await camera.getPosition();
        final actualDistance = actualPosition.length;

        debugPrint('📏 实际相机位置: (${actualPosition.x.toStringAsFixed(3)}, ${actualPosition.y.toStringAsFixed(3)}, ${actualPosition.z.toStringAsFixed(3)})');
        debugPrint('📏 实际距离: ${actualDistance.toStringAsFixed(3)}m vs 目标距离: ${_cameraRadius.toStringAsFixed(3)}m');

        final distanceDiff = (actualDistance - _cameraRadius).abs();
        if (distanceDiff > 0.01) {
          debugPrint('⚠️ 距离偏差: ${distanceDiff.toStringAsFixed(3)}m');
        } else {
          debugPrint('✅ 相机距离设置正确');
        }
      } catch (positionError) {
        debugPrint('⚠️ 无法获取相机位置进行验证: $positionError');
      }

      debugPrint('✅ 相机更新完成');
    } catch (e, stackTrace) {
      debugPrint('❌ 相机位置更新失败: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  Future<void> _toggleSkybox() async {
    if (_viewer == null || !_viewerInitialized) return;

    setState(() {
      _showSkybox = !_showSkybox;
    });

    try {
      if (_showSkybox) {
        await _viewer!.loadSkybox('assets/environments/studio_small_03_1024_skybox.ktx');
      } else {
        await _viewer!.removeSkybox();
      }
      debugPrint('🔄 Skybox 切换: ${_showSkybox ? "开启" : "关闭"}');
    } catch (e) {
      debugPrint('❌ Skybox 切换失败: $e');
    }
  }

  Future<void> _updateIbl() async {
    if (_viewer == null) {
      debugPrint('⚠️ Viewer 未初始化，跳过IBL更新');
      return;
    }

    try {
      debugPrint('🔄 IBL 强度更新: ${(_iblIntensity/1000).toStringAsFixed(0)}K');
      await _viewer!.loadIbl(
        'assets/environments/studio_small_03_1024_ibl.ktx',
        intensity: _iblIntensity,
        destroyExisting: true
      );
      debugPrint('✅ IBL 更新成功');
    } catch (e, stackTrace) {
      debugPrint('❌ IBL 更新失败: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HDR 环境全景测试'),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_showSkybox ? Icons.panorama : Icons.panorama_wide_angle_outlined),
            onPressed: _toggleSkybox,
            tooltip: 'Skybox 开关',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showControlDialog,
            tooltip: '相机控制',
          ),
        ],
      ),
      body: Stack(
        children: [
          // HDR 环境视图 (带一个小模型作为距离参考)
          ViewerWidget(
            // 不在这里加载模型，我们手动加载并调整位置
            skyboxPath: 'assets/environments/studio_small_03_1024_skybox.ktx',
            iblPath: 'assets/environments/studio_small_03_1024_ibl.ktx',
            manipulatorType: ManipulatorType.NONE, // 禁用默认控制，使用自定义控制
            background: const Color(0xFF000000),
            // 设置初始相机位置：对应θ=90°, φ=90°, R=3.0的坐标
            initialCameraPosition: v.Vector3(0.0, 0.0, 3.0), // 相机位置：正面3米距离
            onViewerAvailable: _onViewerAvailable,
          ),

          // 加载指示器
          if (!_viewerInitialized)
            const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    '加载 HDR 环境...',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),


          // 状态信息
          Positioned(
            right: 16,
            top: 16,
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
                    'Status: ${_viewerInitialized ? "Ready" : "Loading"}',
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                  Text(
                    'Skybox: ${_showSkybox ? "ON" : "OFF"}',
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                  Text(
                    'R=${_cameraRadius.toStringAsFixed(1)}m θ=${_cameraTheta.toStringAsFixed(0)}° φ=${_cameraPhi.toStringAsFixed(0)}°',
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                  Text(
                    'XYZ=(${(_cameraRadius * math.sin(_cameraPhi * math.pi / 180) * math.cos(_cameraTheta * math.pi / 180)).toStringAsFixed(2)}, ${(_cameraRadius * math.cos(_cameraPhi * math.pi / 180)).toStringAsFixed(2)}, ${(_cameraRadius * math.sin(_cameraPhi * math.pi / 180) * math.sin(_cameraTheta * math.pi / 180)).toStringAsFixed(2)})',
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ],
              ),
            ),
          ),

          // 操作提示
          const Positioned(
            bottom: 16,
            right: 16,
            child: Text(
              '💡 可以直接拖拽屏幕旋转视角',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }


  void _showControlDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: Colors.black87,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Row(
                children: [
                  Icon(Icons.threed_rotation, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    '360° 全景控制',
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: double.maxFinite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 相机距离
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '相机距离: ${_cameraRadius.toStringAsFixed(1)}m',
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                          ),
                          Slider(
                            value: _cameraRadius,
                            min: 0.1,  // 最近距离 - 接近模型
                            max: 8.0,  // 最远距离 - 环境边缘，不需要太远
                            divisions: 79,
                            onChanged: (value) {
                              setState(() {
                                _cameraRadius = value;
                              });
                              this.setState(() {});
                              _updateCameraPosition();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // 水平旋转 (Theta)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '水平角度: ${_cameraTheta.toStringAsFixed(0)}°',
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                          ),
                          Slider(
                            value: _cameraTheta,
                            min: 0.0,
                            max: 360.0,
                            divisions: 72,
                            onChanged: (value) {
                              setState(() {
                                _cameraTheta = value;
                              });
                              this.setState(() {});
                              _updateCameraPosition();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // 垂直角度 (Phi)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '垂直角度: ${_cameraPhi.toStringAsFixed(0)}°',
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                          ),
                          Slider(
                            value: _cameraPhi,
                            min: 10.0,
                            max: 170.0,
                            divisions: 32,
                            onChanged: (value) {
                              setState(() {
                                _cameraPhi = value;
                              });
                              this.setState(() {});
                              _updateCameraPosition();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // IBL 强度
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'IBL 强度: ${(_iblIntensity / 1000).toStringAsFixed(0)}K',
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                          ),
                          Slider(
                            value: _iblIntensity,
                            min: 10000.0,
                            max: 100000.0,
                            divisions: 45,
                            onChanged: (value) {
                              setState(() {
                                _iblIntensity = value;
                              });
                              this.setState(() {});
                              _updateIbl();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // 模型高度调整
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '模型高度: ${_modelYOffset.toStringAsFixed(2)}m',
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                          ),
                          Slider(
                            value: _modelYOffset,
                            min: -3.0,  // 最多向下移动3个单位
                            max: 1.0,   // 最多向上移动1个单位
                            divisions: 40,
                            onChanged: (value) {
                              setState(() {
                                _modelYOffset = value;
                              });
                              this.setState(() {});
                              _updateModelPosition();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // 预设距离按钮
                      const Text(
                        '快速距离预设:',
                        style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildDialogButton('极近', 0.2, Colors.orange, () {
                            setState(() {
                              _cameraRadius = 0.2;
                            });
                            this.setState(() {});
                            _updateCameraPosition();
                          }),
                          _buildDialogButton('近景', 0.8, Colors.orange, () {
                            setState(() {
                              _cameraRadius = 0.8;
                            });
                            this.setState(() {});
                            _updateCameraPosition();
                          }),
                          _buildDialogButton('中景', 1.5, Colors.orange, () {
                            setState(() {
                              _cameraRadius = 1.5;
                            });
                            this.setState(() {});
                            _updateCameraPosition();
                          }),
                          _buildDialogButton('远景', 3.0, Colors.orange, () {
                            setState(() {
                              _cameraRadius = 3.0;
                            });
                            this.setState(() {});
                            _updateCameraPosition();
                          }),
                          _buildDialogButton('环境边缘', 6.0, Colors.orange, () {
                            setState(() {
                              _cameraRadius = 6.0;
                            });
                            this.setState(() {});
                            _updateCameraPosition();
                          }),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // 预设角度按钮
                      const Text(
                        '快速角度预设:',
                        style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildDialogButton('正面', null, Colors.blue, () {
                            setState(() {
                              _cameraTheta = 0;
                              _cameraPhi = 90;
                            });
                            this.setState(() {});
                            _updateCameraPosition();
                          }),
                          _buildDialogButton('右侧', null, Colors.blue, () {
                            setState(() {
                              _cameraTheta = 90;
                              _cameraPhi = 90;
                            });
                            this.setState(() {});
                            _updateCameraPosition();
                          }),
                          _buildDialogButton('背面', null, Colors.blue, () {
                            setState(() {
                              _cameraTheta = 180;
                              _cameraPhi = 90;
                            });
                            this.setState(() {});
                            _updateCameraPosition();
                          }),
                          _buildDialogButton('左侧', null, Colors.blue, () {
                            setState(() {
                              _cameraTheta = 270;
                              _cameraPhi = 90;
                            });
                            this.setState(() {});
                            _updateCameraPosition();
                          }),
                          _buildDialogButton('俯视', null, Colors.blue, () {
                            setState(() {
                              _cameraTheta = 0;
                              _cameraPhi = 30;
                            });
                            this.setState(() {});
                            _updateCameraPosition();
                          }),
                          _buildDialogButton('仰视', null, Colors.blue, () {
                            setState(() {
                              _cameraTheta = 0;
                              _cameraPhi = 150;
                            });
                            this.setState(() {});
                            _updateCameraPosition();
                          }),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    '关闭',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDialogButton(String label, double? value, Color color, void Function() onPressed) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withValues(alpha: 0.8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, color: Colors.white),
      ),
    );
  }
}