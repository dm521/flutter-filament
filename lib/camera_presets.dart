import 'package:thermion_flutter/thermion_flutter.dart';

enum CameraPreset {
  soloCloseUp,   // 单人演播（当前较远，接近全身）
  halfBody,      // 半身像（腰部以上）
  bustCloseUp,   // 胸像/肩部以上特写
  thirdPersonOts // 越肩第三人称
}

class CameraRigConfig {
  final double fovDegrees;
  final Vector3 eyeOffset; // 相对角色中心偏移
  final Vector3 centerOffset; // 视点相对角色中心偏移

  CameraRigConfig({
    required this.fovDegrees,
    required this.eyeOffset,
    required this.centerOffset,
  });
}

CameraRigConfig _configFor(CameraPreset preset) {
  switch (preset) {
    case CameraPreset.soloCloseUp:
      // 全身视角 - 基于 format.json 的相机参数优化
      return CameraRigConfig(
        fovDegrees: 45,  // 稍微增大视野，更自然
        eyeOffset: Vector3(0.0, 0.5, 2.8),  // 略微抬高视角，拉远距离
        centerOffset: Vector3(0.0, 0.5, 0.0),  // 看向模型中心
      );
    case CameraPreset.halfBody:
      return CameraRigConfig(
        fovDegrees: 40,
        eyeOffset: Vector3(0.0, 0.8, 2.2),  // 调整高度和距离
        centerOffset: Vector3(0.0, 0.7, 0.0),
      );
    case CameraPreset.bustCloseUp:
      return CameraRigConfig(
        fovDegrees: 35,
        eyeOffset: Vector3(0.0, 0.8, 1.5),  // 胸像特写
        centerOffset: Vector3(0.0, 0.8, 0.0),
      );
    case CameraPreset.thirdPersonOts:
      return CameraRigConfig(
        fovDegrees: 50,
        eyeOffset: Vector3(-1.5, 1.2, -2.5),  // 越肩视角
        centerOffset: Vector3(0.0, 0.8, 0.0),
      );
  }
}

/// 应用相机预设到当前活动相机。
/// [characterCenter] 通常为角色的世界中心（或头部/胸口位置）。
Future<void> applyCameraPreset(
  ThermionViewer viewer, {
  required CameraPreset preset,
  Vector3? characterCenter,
}) async {
  final cfg = _configFor(preset);
  final cam = await viewer.getActiveCamera();

  // 计算绝对 eye/center
  final centerBase = characterCenter ?? Vector3(0, 0, 0);
  final eye = centerBase + cfg.eyeOffset;

  // 简化：Thermion 暴露的 Camera 常用方法中未提供 FOV/独立 target 设置，保持与现有用法一致
  await cam.lookAt(eye);
}
