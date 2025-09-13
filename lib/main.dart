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
          // 相机：半身偏近景（教室日系感）
          final camera = await viewer.getActiveCamera();
          await camera.lookAt(
            v.Vector3(0, 1.30, 3.0),          // position：半身偏近景
            focus: v.Vector3(0, 0.65, 0),     // focus：看向胸口上方
            up: v.Vector3(0, 1, 0),
          );

          // 阴影设置：PCSS软阴影，≥2048分辨率
          await viewer.setShadowsEnabled(true);
          await viewer.setShadowType(ShadowType.PCSS);

          // —— 二次元角色专用布光方案 ——

          // 1) 主光（正面偏上）：确保面部充分照明
          await viewer.addDirectLight(
            DirectLight.sun(
              color: 6000,                      // 中性偏冷，保持清晰
              intensity: 45000,                 // 提升主光亮度
              castShadows: true,                // 保持阴影但要柔和
              direction: v.Vector3(-0.3, -0.8, -0.5),    // 正面偏左上
            ),
          );

          // 2) 右侧补光：均匀照亮右脸，减少阴影对比
          await viewer.addDirectLight(
            DirectLight.sun(
              color: 5800,                      // 略暖，平衡冷光
              intensity: 25000,                 // 大幅提升补光强度
              castShadows: false,               // 补光不投阴影
              direction: v.Vector3(0.6, -0.4, -0.6),     // 右前上方
            ),
          );

          // 3) 背部轮廓光：突出人物轮廓，与背景分离  
          await viewer.addDirectLight(
            DirectLight.sun(
              color: 7500,                      // 偏冷轮廓
              intensity: 20000,                 // 适中轮廓光
              castShadows: false,               // 无阴影
              direction: v.Vector3(-0.2, -0.3, 0.9),     // 后方偏上
            ),
          );

          // 4) 眼部高光：专门照亮眼部区域，突出二次元特色
          await viewer.addDirectLight(
            DirectLight.sun(
              color: 6500,                      // 清冷，突出眼神
              intensity: 15000,                 // 中等强度
              castShadows: false,               // 无阴影
              direction: v.Vector3(0.1, -0.7, -0.7),     // 稍微偏右的正面光
            ),
          );

          await viewer.setRendering(true);
          debugPrint('3D查看器已准备就绪! 教室日系感布光完成');
        },
      ),
    );
  }
}
