import 'package:flutter/material.dart';
import 'package:thermion_flutter/thermion_flutter.dart';

class ModelViewer extends StatelessWidget {
  final String modelPath;
  final String? skyboxPath;
  final String? iblPath;

  const ModelViewer({
    Key? key,
    required this.modelPath,
    this.skyboxPath,
    this.iblPath,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('3D模型查看器'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ViewerWidget(
        assetPath: modelPath,
        skyboxPath: skyboxPath,
        iblPath: iblPath,
        initialCameraPosition: Vector3(0, 3.0, 3),
        manipulatorType: ManipulatorType.ORBIT,
        showFpsCounter: true,
        background: Colors.grey[200],
        postProcessing: true,
        transformToUnitCube: true,
        onViewerAvailable: (viewer) async {
          debugPrint('3D查看器已准备就绪!');
        },
      ),
    );
  }
}
