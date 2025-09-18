import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:thermion_flutter/thermion_flutter.dart';
import 'package:vector_math/vector_math_64.dart';

class SceneDemoPage extends StatefulWidget {
  const SceneDemoPage({super.key});

  @override
  State<SceneDemoPage> createState() => _SceneDemoPageState();
}

class _SceneDemoPageState extends State<SceneDemoPage> {
  ThermionViewer? _viewer;
  ThermionAsset? _asset;
  DelegateInputHandler? _input;
  bool _ready = false;

  // Demo assets (can be changed to your own)
  static const String kModel = 'assets/models/erciyuan_fix.glb';
  static const String kSkybox = 'assets/environments/default_env_skybox.ktx';
  static const String kIbl = 'assets/environments/default_env_ibl.ktx';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      if (kDebugMode) debugPrint('🚀 SceneDemo init');
      _viewer = await ThermionFlutterPlugin.createViewer();
      _input = DelegateInputHandler.fixedOrbit(_viewer!);
      setState(() {});

      // Camera framing
      final cam = await _viewer!.getActiveCamera();
      await cam.lookAt(Vector3(0.0, 1.2, 3.0));

      // Environment
      await _viewer!.loadSkybox(kSkybox);
      await _viewer!.loadIbl(kIbl);

      // A simple key light
      await _viewer!.addDirectLight(DirectLight.sun(
        color: 6000, intensity: 18000, castShadows: true, direction: Vector3(-0.7, -1.0, -0.5),
      ));

      // Load model
      _asset = await _viewer!.loadGltf(kModel);
      await _asset!.transformToUnitCube();

      // Post processing
      await _viewer!.setPostProcessing(true);

      // Ensure rendering starts after widget is in the tree
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await _viewer!.setRendering(true);
        } catch (_) {}
      });

      setState(() => _ready = true);
      if (kDebugMode) debugPrint('✅ SceneDemo ready');
    } catch (e) {
      if (kDebugMode) debugPrint('❌ SceneDemo init failed: $e');
    }
  }

  Future<void> _recenterCamera() async {
    if (_viewer == null || _asset == null) return;
    try {
      final cam = await _viewer!.getActiveCamera();
      await cam.lookAt(Vector3(0.0, 1.2, 3.0));
    } catch (_) {}
  }

  @override
  void dispose() {
    () async {
      try {
        if (_viewer != null) {
          await _viewer!.setRendering(false);
        }
        if (_asset != null && _viewer != null) {
          await _viewer!.destroyAsset(_asset!);
          _asset = null;
        }
      } catch (_) {}
    }();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thermion 场景示例'),
        actions: [
          IconButton(
            icon: const Icon(Icons.center_focus_strong),
            onPressed: _recenterCamera,
            tooltip: '重置相机',
          ),
        ],
      ),
      body: _viewer == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Positioned.fill(
                  child: ThermionListenerWidget(
                    inputHandler: _input!,
                    child: ThermionWidget(viewer: _viewer!),
                  ),
                ),
                if (!_ready) const Center(child: CircularProgressIndicator()),
              ],
            ),
    );
  }
}
