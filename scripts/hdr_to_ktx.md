# HDR 转 KTX 格式指南

## 方法1：使用 Filament 工具链

### 安装 Filament Tools
```bash
# 下载 Filament 工具
# https://github.com/google/filament/releases

# 使用 cmgen 转换
cmgen -x . --format=ktx --size=1024 your_environment.hdr
```

### 生成的文件
- `your_environment_ibl.ktx` - IBL 光照贴图
- `your_environment_skybox.ktx` - 天空盒贴图

## 方法2：使用在线转换器

### HDR to KTX 在线工具
- **Khronos KTX Tools** - 官方工具
- **Texture Tools** - 支持多种格式转换

## 方法3：使用 Flutter/Dart 工具

### 安装依赖
```yaml
dev_dependencies:
  image: ^4.0.0
```

### 转换脚本
```dart
import 'dart:io';
import 'package:image/image.dart';

Future<void> convertHdrToKtx(String hdrPath, String ktxPath) async {
  // 读取 HDR 文件
  final bytes = await File(hdrPath).readAsBytes();
  final image = decodeHdr(bytes);
  
  if (image != null) {
    // 转换为 KTX 格式
    final ktxBytes = encodeKtx(image);
    await File(ktxPath).writeAsBytes(ktxBytes);
    print('转换完成: $ktxPath');
  }
}
```

## 集成到应用

1. 将生成的 KTX 文件放到 `assets/environments/`
2. 更新 `pubspec.yaml`
3. 在代码中添加新环境配置