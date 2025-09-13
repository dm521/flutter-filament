import 'package:flutter/material.dart';
import 'package:thermion_flutter/thermion_flutter.dart';
import 'package:vector_math/vector_math_64.dart' as v;

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ThermionAnimeDemo(),
    );
  }
}

class ThermionAnimeDemo extends StatelessWidget {
  const ThermionAnimeDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Thermion Demo')),
      body: ViewerWidget(
        // 你的 GLB（确保已在 pubspec.yaml 的 assets 中声明）
        assetPath: 'assets/models/2D_Girl.glb',

        // 统一缩放并居中，保证不同模型相机参数可复用
        transformToUnitCube: true,

        // 手势轨道操作，方便近距离检查
        manipulatorType: ManipulatorType.ORBIT,

        // 背景：中性灰，接近建模师参考
        background: const Color(0xFFBDBDBD),

        // 相机：保持你现在的半身近景
        initialCameraPosition: v.Vector3(0, 1.30, 3.0),

        onViewerAvailable: (viewer) async {
          // —— 相机保持不变 ——
          final camera = await viewer.getActiveCamera();
          await camera.lookAt(
            v.Vector3(0, 1.30, 3.0),   // 不改
            focus: v.Vector3(0, 0.65, 0), // 不改
            up: v.Vector3(0, 1, 0),
          );

          // —— 建议关闭或不加载 IBL，避免“灰雾感” ——（有就移除，没加载就忽略）
          try { await viewer.removeIbl(); } catch (_) {}
          try { await viewer.removeSkybox(); } catch (_) {}

          // —— 阴影：只给主光开阴影（如果你的版本默认支持就会生效）——
          try { await viewer.setShadowsEnabled(true); } catch (_) {}
          // 如果你的 SDK 有这些接口，可解开进一步柔化阴影：
          // try { await viewer.setShadowType(ShadowType.PCSS); } catch (_) {}
          // try { await viewer.setShadowMapSize(2048); } catch (_) {}

          // =========================
          //   “二次元棚拍”四盏方向光
          // =========================
          //
          // 色温(K)：Key 6500（中性偏冷） / FillSide 5600（微暖）
          //          FillTop 6000（中性） / Rim 8200（冷，勾边）
          // 强度起步（可按比例整体调亮/调暗）：
          //    Key 26000 ~ 30000（先 28000）
          //    FillSide  9000 ~ 12000（先 10000）
          //    FillTop  11000 ~ 15000（先 13000）
          //    Rim      15000 ~ 19000（先 17000）
          //
          // 方向向量：均为“从灯指向人物”的方向（世界坐标）
          // - Key：左上前 → 模特（斜擦面，避免正怼）
          // - FillSide：右前 → 模特（抬起阴影面）
          // - FillTop：上方略前 → 模特（柔化眼下&鼻影）
          // - Rim：右后上 → 模特（勾发丝与肩线）

          // 1) 主光 Key（日光中性偏冷，开阴影）
          await viewer.addDirectLight(DirectLight.sun(
            color: 6500,
            intensity: 28000,
            castShadows: true,
            direction: v.Vector3(-0.50, -0.70, -0.25), // 左上前 → 人物
          ));

          // 2) 侧向补光 FillSide（室内反暖，无阴影）
          await viewer.addDirectLight(DirectLight.sun(
            color: 5600,
            intensity: 10000,
            castShadows: false,
            direction: v.Vector3(0.85, -0.30, -0.10),  // 右前 → 人物
          ));

          // 3) 顶部柔光 FillTop（上方柔化面部阴影，无阴影）
          await viewer.addDirectLight(DirectLight.sun(
            color: 6000,
            intensity: 13000,
            castShadows: false,
            direction: v.Vector3(0.00, -1.00, -0.25),  // 上方略前 → 人物
          ));

          // 4) 右后轮廓 Rim（冷边，无阴影）
          await viewer.addDirectLight(DirectLight.sun(
            color: 8200,
            intensity: 17000,
            castShadows: false,
            direction: v.Vector3(-0.15, -0.25, 0.95),  // 右后上 → 人物
          ));

          try { await viewer.setRendering(true); } catch (_) {}
        },
      ),
    );
  }
}
