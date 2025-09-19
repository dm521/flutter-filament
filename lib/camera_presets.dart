import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:thermion_flutter/thermion_flutter.dart';

enum CameraPreset {
  soloCloseUp,   // 单人演播（当前较远，接近全身）
  halfBody,      // 半身像（腰部以上）
  bustCloseUp,   // 胸像/肩部以上特写
  thirdPersonOts // 越肩第三人称
}

class CameraRigConfig {
  final Vector3 position;      // 相机绝对位置
  final Vector3 target;        // 目标点（角色身体部位）
  final Vector3 up;           // 上方向向量
  final double near;          // 近裁剪面
  final double far;           // 远裁剪面

  CameraRigConfig({
    required this.position,
    required this.target,
    Vector3? up,
    this.near = 0.1,
    this.far = 100.0,
  }) : up = up ?? Vector3(0, 1, 0);
}

CameraRigConfig _configFor(CameraPreset preset) {
  switch (preset) {
    case CameraPreset.soloCloseUp:
      // 全身视角 - 使用默认透视，避免变形
      return CameraRigConfig(
        position: Vector3(0.0, 0.5, 2.6), // 平视，合理距离
        target: Vector3(0.0, 0.0, 0.0),   // 看向模型中心
      );
    case CameraPreset.halfBody:
      // 半身像 - 提高相机，看向上半身
      return CameraRigConfig(
        position: Vector3(0.0, 0.6, 1.6), // 提高相机高度，拉近距离
        target: Vector3(0.0, 0.5, 0.0),   // 看向胸部中心
      );
    case CameraPreset.bustCloseUp:
      // 脸部特写 - 更近距离
      return CameraRigConfig(
        position: Vector3(0.0, 0.75, 0.8), // 特写距离
        target: Vector3(0.0, 0.7, 0.0),   // 看向肩部/颈部
      );
    case CameraPreset.thirdPersonOts:
      // 越肩第三人称视角
      return CameraRigConfig(
        position: Vector3(-1.8, 0.6, -2.5), // 左后方位置
        target: Vector3(0.3, 0.4, 1.5),     // 看向角色前方
      );
  }
}

/// 应用相机预设到当前活动相机，使用标准 Filament 方法
/// [characterCenter] 角色的世界中心位置偏移
Future<void> applyCameraPreset(
  ThermionViewer viewer, {
  required CameraPreset preset,
  Vector3? characterCenter,
}) async {
  final cfg = _configFor(preset);

  // 计算最终的相机位置和目标点（考虑角色中心偏移）
  final centerOffset = characterCenter ?? Vector3.zero();
  final finalPosition = cfg.position + centerOffset;
  final finalTarget = cfg.target + centerOffset;

  try {
    // 暂停渲染以避免并发问题
    await viewer.setRendering(false);

    // 获取相机（在暂停渲染后）
    final cam = await viewer.getActiveCamera();

    // 等待一帧确保状态稳定
    await Future.delayed(const Duration(milliseconds: 16));

    // 1. 先设置简单的 lookAt（避免复杂的透视设置导致崩溃）
    await cam.lookAt(finalPosition);

    // 2. 等待设置生效
    await Future.delayed(const Duration(milliseconds: 16));

    // 3. 跳过透视投影设置，避免变形
    // setLensProjection 会导致人物变形，使用默认透视设置效果最佳
    if (kDebugMode) {
      debugPrint('📐 使用默认透视投影，避免变形');
    }

    // 4. 再次设置精确的 lookAt（包含焦点和上方向）
    try {
      await cam.lookAt(
        finalPosition,
        focus: finalTarget,
        up: cfg.up,
      );
    } catch (lookAtError) {
      if (kDebugMode) {
        debugPrint('⚠️ 精确 lookAt 设置失败，使用简化版本: $lookAtError');
      }
      // 回退到简单版本
      await cam.lookAt(finalPosition);
    }

    // 等待设置完成
    await Future.delayed(const Duration(milliseconds: 16));

    // 重新启用渲染
    await viewer.setRendering(true);

    if (kDebugMode) {
      debugPrint('📷 相机预设已应用: $preset');
      debugPrint('   位置: ${finalPosition.x.toStringAsFixed(2)}, ${finalPosition.y.toStringAsFixed(2)}, ${finalPosition.z.toStringAsFixed(2)}');
      debugPrint('   目标: ${finalTarget.x.toStringAsFixed(2)}, ${finalTarget.y.toStringAsFixed(2)}, ${finalTarget.z.toStringAsFixed(2)}');
    }
  } catch (e) {
    if (kDebugMode) {
      debugPrint('❌ 应用相机预设失败: $e');
    }
    // 确保重新启用渲染
    try {
      await viewer.setRendering(true);
    } catch (_) {}
  }
}
