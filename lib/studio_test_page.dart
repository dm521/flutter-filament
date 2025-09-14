import 'package:flutter/material.dart';
import 'package:thermion_flutter/thermion_flutter.dart';
import 'package:vector_math/vector_math_64.dart' as v;

class StudioTestPage extends StatefulWidget {
  const StudioTestPage({super.key});

  @override
  State<StudioTestPage> createState() => _StudioTestPageState();
}

class _StudioTestPageState extends State<StudioTestPage> {
  ThermionViewer? _viewer;
  bool _viewerInitialized = false;
  bool _showSkybox = true;
  double _cameraDistance = 5.0;
  double _cameraHeight = 0.0;
  double _iblIntensity = 30000.0;

  Future<void> _onViewerAvailable(ThermionViewer viewer) async {
    _viewer = viewer;

    try {
      debugPrint('🚀 Studio 测试页面初始化...');

      // 等待一下确保 viewer 完全初始化
      await Future.delayed(const Duration(milliseconds: 500));

      // 检查 viewer 是否有效
      if (_viewer == null) {
        debugPrint('❌ Viewer 为空');
        return;
      }

      // 设置相机位置
      debugPrint('🔄 设置相机位置...');
      final camera = await viewer.getActiveCamera();
      await camera.lookAt(
        v.Vector3(0.0, _cameraHeight, _cameraDistance),
        focus: v.Vector3(0.0, 0.0, 0.0),
        up: v.Vector3(0, 1, 0),
      );

      // 加载 Studio IBL
      debugPrint('🔄 加载 Studio IBL...');
      await viewer.loadIbl(
        'assets/environments/studio_small_03_output_ibl.ktx',
        intensity: _iblIntensity,
        destroyExisting: true
      );
      debugPrint('✅ IBL 加载成功');

      // 加载 Studio Skybox
      if (_showSkybox) {
        debugPrint('🔄 加载 Studio Skybox...');
        await viewer.loadSkybox('assets/environments/studio_small_03_output_skybox.ktx');
        debugPrint('✅ Skybox 加载成功');
      }

      // 启用阴影
      debugPrint('🔄 设置阴影...');
      await viewer.setShadowsEnabled(true);
      await viewer.setShadowType(ShadowType.PCF);

      setState(() {
        _viewerInitialized = true;
      });

      debugPrint('✅ Studio 场景加载完成');
    } catch (e, stackTrace) {
      debugPrint('❌ Studio 场景加载失败: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  Future<void> _toggleSkybox() async {
    if (_viewer == null) return;

    setState(() {
      _showSkybox = !_showSkybox;
    });

    try {
      if (_showSkybox) {
        debugPrint('🔄 启用 Studio Skybox');
        await _viewer!.loadSkybox('assets/environments/studio_small_03_output_skybox.ktx');
      } else {
        debugPrint('🔄 禁用 Skybox');
        await _viewer!.removeSkybox();
      }
    } catch (e) {
      debugPrint('❌ Skybox 切换失败: $e');
    }
  }

  Future<void> _updateCamera() async {
    if (_viewer == null || !_viewerInitialized) return;

    try {
      final camera = await _viewer!.getActiveCamera();
      await camera.lookAt(
        v.Vector3(0.0, _cameraHeight, _cameraDistance),
        focus: v.Vector3(0.0, 0.0, 0.0),
        up: v.Vector3(0, 1, 0),
      );
    } catch (e) {
      debugPrint('❌ 相机更新失败: $e');
    }
  }

  Future<void> _updateIbl() async {
    if (_viewer == null || !_viewerInitialized) return;

    try {
      debugPrint('🔄 更新 IBL 强度: $_iblIntensity');
      await _viewer!.loadIbl(
        'assets/environments/studio_small_03_output_ibl.ktx',
        intensity: _iblIntensity,
        destroyExisting: true
      );
    } catch (e) {
      debugPrint('❌ IBL 更新失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Studio 场景测试'),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_showSkybox ? Icons.visibility : Icons.visibility_off),
            onPressed: _toggleSkybox,
            tooltip: 'Skybox 开关',
          ),
        ],
      ),
      body: Stack(
        children: [
          // 3D 视图
          ViewerWidget(
            assetPath: 'assets/models/2D_Girl.glb',
            iblPath: 'assets/environments/studio_small_03_output_ibl.ktx',
            skyboxPath: 'assets/environments/studio_small_03_output_skybox.ktx',
            transformToUnitCube: true,
            manipulatorType: ManipulatorType.NONE,
            background: const Color(0xFF202020),
            initialCameraPosition: v.Vector3(0.0, 0.0, 5.0),
            onViewerAvailable: _onViewerAvailable,
          ),

          // 状态指示器
          if (!_viewerInitialized)
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),

          // 控制面板
          Positioned(
            left: 16,
            bottom: 100,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Studio 场景控制',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Skybox 开关
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Skybox: ', style: TextStyle(color: Colors.white)),
                      Switch(
                        value: _showSkybox,
                        onChanged: (value) => _toggleSkybox(),
                        activeThumbColor: Colors.green,
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // 相机距离
                  SizedBox(
                    width: 200,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '相机距离: ${_cameraDistance.toStringAsFixed(1)}',
                          style: const TextStyle(color: Colors.white),
                        ),
                        Slider(
                          value: _cameraDistance,
                          min: 2.0,
                          max: 10.0,
                          divisions: 40,
                          onChanged: (value) {
                            setState(() {
                              _cameraDistance = value;
                            });
                            _updateCamera();
                          },
                        ),
                      ],
                    ),
                  ),

                  // 相机高度
                  SizedBox(
                    width: 200,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '相机高度: ${_cameraHeight.toStringAsFixed(1)}',
                          style: const TextStyle(color: Colors.white),
                        ),
                        Slider(
                          value: _cameraHeight,
                          min: -3.0,
                          max: 3.0,
                          divisions: 30,
                          onChanged: (value) {
                            setState(() {
                              _cameraHeight = value;
                            });
                            _updateCamera();
                          },
                        ),
                      ],
                    ),
                  ),

                  // IBL 强度
                  SizedBox(
                    width: 200,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'IBL 强度: ${(_iblIntensity / 1000).toStringAsFixed(0)}K',
                          style: const TextStyle(color: Colors.white),
                        ),
                        Slider(
                          value: _iblIntensity,
                          min: 10000.0,
                          max: 80000.0,
                          divisions: 35,
                          onChanged: (value) {
                            setState(() {
                              _iblIntensity = value;
                            });
                            _updateIbl();
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 调试信息
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
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    'Skybox: ${_showSkybox ? "ON" : "OFF"}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    'IBL: ${(_iblIntensity / 1000).toStringAsFixed(0)}K',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
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