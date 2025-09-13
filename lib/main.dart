import 'package:flutter/material.dart';
import 'package:thermion_flutter/thermion_flutter.dart';
import 'package:vector_math/vector_math_64.dart' as v;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Thermion Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Thermion Demo'),
      ),
      body: _CustomControlledViewer(),
    );
  }
}

class _CustomControlledViewer extends StatefulWidget {
  @override
  State<_CustomControlledViewer> createState() => _CustomControlledViewerState();
}

class _CustomControlledViewerState extends State<_CustomControlledViewer> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: (details) {
        // 目前禁用手势控制，保持固定视角
      },
      child: ViewerWidget(
        assetPath: 'assets/models/2D_Girl.glb',
        transformToUnitCube: true,
        manipulatorType: ManipulatorType.ORBIT,
        background: const Color(0xFFE9E4DD),
        showFpsCounter: true,
        
        // —— 环境光尽量弱（不开 IBL，最弱环境）——
        // skyboxPath: null, iblPath: null,

        onViewerAvailable: (viewer) async {
          // 相机：全身视角，稍远一点给三点光留空间
          final camera = await viewer.getActiveCamera();
          // await camera.lookAt(
          //   v.Vector3(0, 1.0, 3.0),            // 全身视角相机位
          //   focus: v.Vector3(0, 1.0, 0),       // 看向胸口附近
          //   up: v.Vector3(0, 1, 0),
          // );

          // 全身 + 垂直居中：把焦点从胸口(1.0)抬到 1.25，并略微抬高相机
          await camera.lookAt(
            v.Vector3(0, 1.0, 3.0),   // position：抬高相机 y（1.5 → 1.60）
            focus: v.Vector3(0, 0.65, 0), // focus：把“看向点”抬高（1.0 → 1.25）
            up: v.Vector3(0, 1, 0),
          );

          // （可选）开启阴影与类型：PCSS
          await viewer.setShadowsEnabled(true);
          await viewer.setShadowType(ShadowType.PCSS);

          // —— 三点光方案（专业影棚布光）—— 使用正确的0.3.3 API

          // 1) 主光（Key）：右前上 → 模型，略暖
          await viewer.addDirectLight(
            DirectLight.sun(
              color: 5200,                      // 色温K（暖）
              intensity: 50000,                 // 强
              castShadows: true,
              direction: v.Vector3(-0.35, -0.80, -0.45),  // 方向向量：从光指向模型
            ),
          );

          // 2) 左侧补光（Fill）：左前上 → 模型，略暖，较弱
          await viewer.addDirectLight(
            DirectLight.sun(
              color: 5600,
              intensity: 18000,                 // 中等/偏弱
              castShadows: false,               // 补光一般不投影更柔
              direction: v.Vector3(0.85, -0.35, -0.20),
            ),
          );

          // 3) 右后轮廓（Rim/Back）：右后上 → 模型，偏冷，勾边
          await viewer.addDirectLight(
            DirectLight.sun(
              color: 8000,                      // 偏冷
              intensity: 24000,                 // 中等略强
              castShadows: false,
              direction: v.Vector3(-0.25, -0.25, 0.95),
            ),
          );

          await viewer.setRendering(true);
          debugPrint('3D查看器已准备就绪! 三点影棚布光完成');
        },
      ),
    );
  }
}
