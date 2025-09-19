import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:thermion_flutter/thermion_flutter.dart';
import 'package:audioplayers/audioplayers.dart';

class LipSyncController {
  final ThermionAsset asset;
  final AudioPlayer audioPlayer = AudioPlayer();
  static bool enableLogs = true; // 开启 blendshape 详细日志用于调试
  
  List<List<double>>? _blendshapeData;
  List<String>? _morphTargetNames;
  bool _isPlaying = false;
  
  // 存储有 morph targets 的实体索引
  int? _morphTargetEntityIndex;
  // 直接缓存实体句柄与 target 数，避免每帧查询与潜在失效
  int? _morphEntity;
  int _morphTargetCount = 0;
  
  // 权重放大倍数（根据模型调节，通常 1.0 即可）
  double weightMultiplier = 1.0;  // 恢复默认倍率，使用原始数据
  
  // 帧计数器用于调试
  int _frameCounter = 0;
  
  // 音频进度驱动同步
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<void>? _completeSub;
  int _lastAppliedFrame = -1;
  double _frameRate = 60.0;
  double? _audioDurationSec; // 从播放器获取的音频总时长（秒）
  
  // 可调参数：平滑与相位
  bool enableSmoothing = true; // 线性插值两帧，减小跳变
  double phaseOffsetMs = 0.0;  // 相位校正（正值：嘴滞后，负值：嘴提前）

  // 口型/下颌等通道的额外倍率（更细粒度控制）。
  // key 为包含匹配（不区分大小写），value 为倍率（0..1）。
  final Map<String, double> channelGains = {
    'jawopen': 1.0,  // 恢复默认倍率
    'jaw': 1.0,
    'mouthfunnel': 1.0,
    'mouthpucker': 1.0,
    'mouthstretch': 1.0,
    'mouthshrug': 1.0,
    'mouthroll': 1.0,
    'mouthlowerdown': 1.0,
    'mouthupperup': 1.0,
    'mouthclose': 1.0,
    // 兜底：所有 mouth 相关
    'mouth': 1.0,
  };
  
  LipSyncController(this.asset);

  /// 加载 blendshape 数据
  Future<void> loadBlendshapeData(String jsonPath) async {
    try {
      final jsonString = await rootBundle.loadString(jsonPath);
      final List<dynamic> rawData = json.decode(jsonString);
      
      _blendshapeData = rawData.map((frame) => 
        List<double>.from(frame.map((value) => value.toDouble()))
      ).toList();
      
      if (kDebugMode && enableLogs) {
        debugPrint('🎭 加载了 ${_blendshapeData!.length} 帧 blendshape 数据');
        debugPrint('🎭 每帧包含 ${_blendshapeData!.first.length} 个 blendshape 权重');
      }
    } catch (e) {
      if (kDebugMode && enableLogs) {
        debugPrint('❌ 加载 blendshape 数据失败: $e');
      }
    }
  }

  /// 获取模型的 morph target 名称
  Future<void> loadMorphTargetNames() async {
    try {
      // 获取角色的子实体
      final childEntities = await asset.getChildEntities();
      
      if (kDebugMode && enableLogs) {
        debugPrint('🎭 找到 ${childEntities.length} 个子实体');
      }
      
      if (childEntities.isNotEmpty) {
        // 逐个实体评分，优先选择包含嘴部通道（mouth/jaw/viseme）的实体
        int? bestIndex;
        int bestScore = -1;
        List<String>? bestNames;

        const mouthKeywords = ['mouth', 'jaw', 'lip', 'viseme', 'aa', 'ih', 'ou'];

        for (int i = 0; i < childEntities.length; i++) {
          final entity = childEntities[i];
          try {
            final morphTargets = await asset.getMorphTargetNames(entity: entity);

            final score = morphTargets.fold<int>(0, (acc, name) {
              final n = name.toLowerCase();
              return acc + (mouthKeywords.any((k) => n.contains(k)) ? 2 : 0) + 1; // 有嘴部关键词加更高权重
            });

            if (kDebugMode && enableLogs) {
              debugPrint('🎭 实体 $i morph targets: ${morphTargets.length}, score=$score');
            }

            if (morphTargets.isNotEmpty && score > bestScore) {
              bestScore = score;
              bestIndex = i;
              bestNames = morphTargets;
            }

            // 🔥 特殊处理：如果发现实体12有52个targets，优先选择它
            if (i == 12 && morphTargets.length == 52) {
              bestScore = score + 1000; // 给实体12极高优先级
              bestIndex = i;
              bestNames = morphTargets;
              if (kDebugMode && enableLogs) {
                debugPrint('🎯 强制选择实体12（可能是真正的动画实体）');
              }
            }
          } catch (entityError) {
            if (kDebugMode && enableLogs) {
              debugPrint('⚠️ 实体 $i 获取 morph targets 失败: $entityError');
            }
          }
        }

        if (bestIndex != null && bestNames != null) {
          _morphTargetEntityIndex = bestIndex;
          _morphTargetNames = bestNames;
          // 缓存实体句柄与数量（一次性取）
          _morphEntity = childEntities[bestIndex];
          _morphTargetCount = bestNames.length;
          if (kDebugMode && enableLogs) {
            debugPrint('✅ 选用实体 $bestIndex 作为口型实体（score=$bestScore）');
            for (int j = 0; j < _morphTargetNames!.length; j++) {
              debugPrint('   $j: ${_morphTargetNames![j]}');
            }
          }
        }
        
        if (_morphTargetNames == null || _morphTargetNames!.isEmpty) {
          if (kDebugMode && enableLogs) {
            debugPrint('⚠️ 所有实体都没有 morph targets');
          }
        }
      } else {
        if (kDebugMode && enableLogs) {
          debugPrint('⚠️ 模型没有子实体');
        }
      }
    } catch (e) {
      if (kDebugMode && enableLogs) {
        debugPrint('❌ 获取 morph target 名称失败: $e');
      }
    }
  }

  /// 播放音频和口型同步动画
  Future<void> playLipSync({
    required String audioPath,
    double frameRate = 60.0, // 默认 60 FPS
    double attenuation = 1.0, // <1.0 可整体降低嘴型幅度
    Function? pauseIdleAnimation, // 暂停idle动画的回调
    Function? resumeIdleAnimation, // 恢复idle动画的回调
  }) async {
    // 详细的数据验证
    if (_blendshapeData == null) {
      if (kDebugMode) {
        debugPrint('❌ Blendshape 数据未加载');
      }
      return;
    }
    
    if (_morphTargetNames == null) {
      if (kDebugMode) {
        debugPrint('❌ Morph target 名称未加载');
      }
      return;
    }
    
    if (_blendshapeData!.isEmpty) {
      if (kDebugMode) {
        debugPrint('❌ Blendshape 数据为空');
      }
      return;
    }
    
    if (_morphTargetNames!.isEmpty) {
      if (kDebugMode) {
        debugPrint('❌ 模型没有 morph targets');
      }
      return;
    }

    if (_isPlaying) {
      if (kDebugMode) {
        debugPrint('⚠️ 已经在播放中，停止当前播放');
      }
      await stopLipSync();
    }

    try {
      _isPlaying = true;
      _frameCounter = 0; // 重置帧计数器
      _frameRate = frameRate;
      _lastAppliedFrame = -1;
      final double effectiveMul = (weightMultiplier * attenuation).clamp(0.0, 1.0);
      
      if (kDebugMode && enableLogs) {
        debugPrint('🎤 开始播放口型同步动画');
        debugPrint('🎵 音频文件: $audioPath');
        debugPrint('📊 帧率: ${frameRate}fps');
        debugPrint('🎭 总帧数: ${_blendshapeData!.length}');
        debugPrint('🎤 暂停 idle 动画以避免冲突...');
      }

      // 🔥 强化版动画停止（仿照强制测试的彻底方法）
      try {
        debugPrint('🛑 彻底停止所有动画...');
        final childEntities = await asset.getChildEntities();

        // 停止所有可能的动画索引
        for (int animIndex = 0; animIndex < 10; animIndex++) {
          try {
            await asset.stopGltfAnimation(animIndex);
          } catch (_) {}
        }

        // 重置所有实体的权重为0
        for (int entityIndex = 0; entityIndex < childEntities.length && entityIndex < 20; entityIndex++) {
          try {
            final entity = childEntities[entityIndex];
            final morphTargets = await asset.getMorphTargetNames(entity: entity);
            if (morphTargets.isNotEmpty) {
              final zeroWeights = List.filled(morphTargets.length, 0.0);
              await asset.setMorphTargetWeights(entity, zeroWeights);
            }
          } catch (_) {}
        }

        await Future.delayed(const Duration(milliseconds: 500)); // 等待清理完成
        debugPrint('✅ 动画清理完成');
      } catch (e) {
        debugPrint('⚠️ 动画清理失败: $e');
      }

      // 暂停 idle 动画（保留原有逻辑）
      if (pauseIdleAnimation != null) {
        await pauseIdleAnimation();
      }

      // 1) 播放音频
      await audioPlayer.stop();
      // 订阅音频总时长与完成事件
      _durSub?.cancel();
      _durSub = audioPlayer.onDurationChanged.listen((d) {
        _audioDurationSec = d.inMilliseconds > 0 ? d.inMilliseconds / 1000.0 : null;
        if (kDebugMode && enableLogs && _audioDurationSec != null) {
          debugPrint('⏱️ 音频时长: ${_audioDurationSec!.toStringAsFixed(2)}s, 帧数: ${_blendshapeData!.length}, 推导FPS≈ ${( _blendshapeData!.length / _audioDurationSec!).toStringAsFixed(2)}');
        }
      });
      _completeSub?.cancel();
      _completeSub = audioPlayer.onPlayerComplete.listen((_) async {
        // 音频真正结束，再停止口型并恢复 idle
        await stopLipSync();
        if (kDebugMode) debugPrint('🎵 音频播放完成');
      });
      await audioPlayer.play(AssetSource(audioPath));

      // 2) 用音频进度驱动帧索引，确保与音频对齐
      _posSub?.cancel();
      _posSub = audioPlayer.onPositionChanged.listen((pos) async {
        if (!_isPlaying) return;
        final int posMs = pos.inMilliseconds;
        final double t = (posMs + phaseOffsetMs) / 1000.0; // 应用相位偏移
        int frameIndex;
        if (_audioDurationSec != null && _audioDurationSec! > 0) {
          // 把整段 bs 数据映射到整段音频：支持任意时长匹配
          final double u = (t / _audioDurationSec!).clamp(0.0, 1.0);
          final double f = u * (_blendshapeData!.length - 1);
          if (enableSmoothing) {
            final int i0 = f.floor().clamp(0, _blendshapeData!.length - 1);
            final int i1 = (i0 + 1).clamp(0, _blendshapeData!.length - 1);
            final double a = (f - i0).clamp(0.0, 1.0);
            final List<double> w0 = _blendshapeData![i0];
            final List<double> w1 = _blendshapeData![i1];
            final int n = w0.length;
            final List<double> w = List<double>.filled(n, 0.0);
            for (int i = 0; i < n; i++) {
              w[i] = w0[i] * (1.0 - a) + w1[i] * a;
            }
            if (kDebugMode && enableLogs && (i0 % 100 == 0) && a < 0.02) {
              debugPrint('🎬 播放进度: $i0/${_blendshapeData!.length}');
            }
            _lastAppliedFrame = i0;
            await _applyBlendshapeFrame(w, multiplier: effectiveMul);
            return;
          } else {
            frameIndex = f.round();
          }
        } else {
          // 回退：使用设置的帧率
          final double f = t * _frameRate;
          if (enableSmoothing) {
            final int i0 = f.floor().clamp(0, _blendshapeData!.length - 1);
            final int i1 = (i0 + 1).clamp(0, _blendshapeData!.length - 1);
            final double a = (f - i0).clamp(0.0, 1.0);
            final List<double> w0 = _blendshapeData![i0];
            final List<double> w1 = _blendshapeData![i1];
            final int n = w0.length;
            final List<double> w = List<double>.filled(n, 0.0);
            for (int i = 0; i < n; i++) {
              w[i] = w0[i] * (1.0 - a) + w1[i] * a;
            }
            if (kDebugMode && enableLogs && (i0 % 100 == 0) && a < 0.02) {
              debugPrint('🎬 播放进度: $i0/${_blendshapeData!.length}');
            }
            _lastAppliedFrame = i0;
            await _applyBlendshapeFrame(w, multiplier: effectiveMul);
            return;
          } else {
            frameIndex = f.floor();
          }
        }
        if (frameIndex < 0) frameIndex = 0;
        if (frameIndex >= _blendshapeData!.length) frameIndex = _blendshapeData!.length - 1;
        if (frameIndex == _lastAppliedFrame) return;
        _lastAppliedFrame = frameIndex;
        if (kDebugMode && enableLogs && frameIndex % 100 == 0) {
          debugPrint('🎬 播放进度: $frameIndex/${_blendshapeData!.length}');
        }
        await _applyBlendshapeFrame(_blendshapeData![frameIndex], multiplier: effectiveMul);
      });

    } catch (e) {
      if (kDebugMode && enableLogs) {
        debugPrint('❌ 播放口型同步失败: $e');
      }
      
      // 确保恢复 idle 动画
      if (resumeIdleAnimation != null) {
        await resumeIdleAnimation();
      }
    }
  }

  /// 应用单帧的 blendshape 权重 - 增强版，解决动画冲突
  Future<void> _applyBlendshapeFrame(List<double> weights, {double? multiplier}) async {
    _frameCounter++;

    try {
      // 检查数据有效性
      if (_morphTargetNames == null || _morphTargetNames!.isEmpty) {
        if (kDebugMode) {
          debugPrint('⚠️ Morph target 名称未加载或为空');
        }
        return;
      }

      if (weights.isEmpty) {
        if (kDebugMode) {
          debugPrint('⚠️ 权重数组为空，跳过此帧');
        }
        return;
      }

      // 使用缓存实体，避免每帧取列表和潜在的索引漂移
      if (_morphEntity == null) {
        if (kDebugMode) {
          debugPrint('❌ 口型实体未缓存，无法应用权重');
        }
        return;
      }

      final entity = _morphEntity!;

      // 🔥 关键修复：每帧都强制停止可能的动画干扰
      if (_frameCounter % 10 == 1) { // 每10帧检查一次，避免性能影响
        try {
          // 强制停止所有可能的动画
          for (int i = 0; i < 5; i++) {
            try {
              await asset.stopGltfAnimation(i);
            } catch (_) {}
          }
        } catch (_) {}
      }
      
      // 确保权重数组长度匹配 morph targets 数量
      final maxLength = _morphTargetCount > 0 ? _morphTargetCount : _morphTargetNames!.length;
      List<double> actualWeights;

      if (weights.length >= maxLength) {
        // 如果权重数组过长，截取前面的部分
        actualWeights = weights.take(maxLength).toList();

        // 记录被截取的权重用于调试
        if (kDebugMode && enableLogs && _frameCounter == 1 && weights.length > maxLength) {
          debugPrint('⚠️ 权重数组过长，已截取: ${weights.length} -> $maxLength');
          debugPrint('   被丢弃的权重: ${weights.skip(maxLength).take(5).toList()}...');
        }
      } else {
        // 如果权重数组过短，用0填充
        actualWeights = List<double>.from(weights);
        while (actualWeights.length < maxLength) {
          actualWeights.add(0.0);
        }

        if (kDebugMode && enableLogs && _frameCounter == 1) {
          debugPrint('⚠️ 权重数组过短，已填充0: ${weights.length} -> $maxLength');
        }
      }
      
      if (actualWeights.isEmpty) {
        if (kDebugMode) {
          debugPrint('⚠️ 处理后的权重数组仍为空');
        }
        return;
      }
      
      // 每50帧打印一次详细信息
      if (kDebugMode && enableLogs && _frameCounter % 50 == 1) {
        debugPrint('🎭 应用第 $_frameCounter 帧权重:');
        debugPrint('   原始权重长度: ${weights.length}');
        debugPrint('   处理后权重长度: ${actualWeights.length}');
        debugPrint('   Morph targets 数量: ${_morphTargetNames!.length}');
        debugPrint('   使用实体索引: $_morphTargetEntityIndex');
        
        // 显示所有非零权重（包括嘴部）
        final allNonZeroWeights = <String>[];
        final mouthWeights = <String>[];
        
        for (int i = 0; i < actualWeights.length; i++) {
          if (actualWeights[i] > 0.001) {
            final weightInfo = '${_morphTargetNames![i]}: ${actualWeights[i].toStringAsFixed(3)}';
            allNonZeroWeights.add(weightInfo);
            
            // 检查是否是嘴部相关的权重
            if (_morphTargetNames![i].toLowerCase().contains('mouth') || 
                _morphTargetNames![i].toLowerCase().contains('jaw')) {
              mouthWeights.add(weightInfo);
            }
          }
        }
        
        if (allNonZeroWeights.isNotEmpty) {
          debugPrint('   所有非零权重 (${allNonZeroWeights.length}个): ${allNonZeroWeights.take(10).join(', ')}${allNonZeroWeights.length > 10 ? '...' : ''}');
        } else {
          debugPrint('   所有权重都接近0');
        }
        
        if (mouthWeights.isNotEmpty) {
          debugPrint('   🗣️ 嘴部权重: ${mouthWeights.join(', ')}');
        } else {
          debugPrint('   🤐 没有检测到嘴部权重');
        }
      }
      
      // 计算最终倍率：全局 * 通道局部（命名匹配）
      final double mul = (multiplier ?? weightMultiplier);  // 不限制在1.0，允许放大
      final List<double> scaledWeights = List<double>.filled(actualWeights.length, 0.0);
      for (int i = 0; i < actualWeights.length; i++) {
        double local = 1.0;
        final name = _morphTargetNames![i].toLowerCase();

        // 优先匹配更具体的关键词
        bool matched = false;
        for (final entry in channelGains.entries) {
          if (name.contains(entry.key)) {
            local = entry.value;  // 使用最后匹配的值，不叠乘
            matched = true;
            break;  // 找到匹配就停止
          }
        }

        // 🔥 放大嘴部和jaw相关权重以增强口型效果
        if (name.contains('jawopen')) {
          local = 3.0;  // jawOpen放大3倍
        }
        // jaw相关的其他动作也放大
        else if (name.contains('jaw')) {
          local = 2.0;  // jaw其他动作放大2倍
        }
        // mouth相关动作也放大
        else if (name.contains('mouth')) {
          local = 2.0;  // mouth动作放大2倍
        }

        final v = (actualWeights[i] * mul * local).clamp(0.0, 1.0);
        scaledWeights[i] = v;
      }

      // 🔥 关键修复：将实体1的BS.jawOpen设为0，避免与实体13的T.jawOpen冲突
      if (scaledWeights.length > 17) {
        scaledWeights[17] = 0.0; // BS.jawOpen = 0，让实体13的T.jawOpen独占控制
        if (kDebugMode && _frameCounter % 50 == 1) {
          debugPrint('🚫 已禁用实体1的BS.jawOpen，由实体13的T.jawOpen独占控制');
        }
      }

      // 🔥 关键修复：应用权重到选中的主要实体（现在应该是实体12）
      await asset.setMorphTargetWeights(entity, scaledWeights);

      if (kDebugMode && _frameCounter % 50 == 1) {
        debugPrint('🎭 主要面部权重已应用到实体$_morphTargetEntityIndex');
      }

      // 🔥 关键修复：将bs.json的jawOpen数据赋给实体13的Mouth_Mod
      try {
        final childEntities = await asset.getChildEntities();

        // 直接检查实体13
        if (childEntities.length > 13) {
          final entity13 = childEntities[13];
          final morphTargets13 = await asset.getMorphTargetNames(entity: entity13);

          if (kDebugMode && _frameCounter == 1) {
            debugPrint('🔍 实体13 morph targets: ${morphTargets13.join(', ')}');
          }

          if (morphTargets13.isNotEmpty) {
            final weights13 = List.filled(morphTargets13.length, 0.0);

            // 直接将jawOpen数据赋给实体13的第一个target（应该是Mouth_Mod）
            if (actualWeights.length > 17) {
              final jawOpenValue = actualWeights[17]; // bs.json的jawOpen数据
              final jawAmplifier = 5.0; // 🔥 jaw专用放大倍率，从2.5增加到5.0
              weights13[0] = (jawOpenValue * (multiplier ?? weightMultiplier) * jawAmplifier).clamp(0.0, 1.0);

              if (kDebugMode && _frameCounter % 50 == 1) {
                debugPrint('🦷 实体13 ${morphTargets13[0]} = ${weights13[0].toStringAsFixed(3)} (原始:${jawOpenValue.toStringAsFixed(3)} x5.0倍放大)');
              }
            }

            await asset.setMorphTargetWeights(entity13, weights13);
          }
        }
      } catch (e) {
        // 实体13应用失败不影响主流程
        if (kDebugMode && _frameCounter % 100 == 1) {
          debugPrint('⚠️ 实体13权重应用失败: $e');
        }
      }
      
      // 第一帧显示缩放后的权重
      if (kDebugMode && enableLogs && _frameCounter == 1) {
        debugPrint('🔧 应用权重倍率: x${mul.toStringAsFixed(2)}（含通道局部增益）');

        // 🔍 详细验证bs.json与模型的映射关系
        debugPrint('🗺️ blendshape映射验证:');
        final standardNames = [
          'eyeBlinkLeft', 'eyeLookDownLeft', 'eyeLookInLeft', 'eyeLookOutLeft', 'eyeLookUpLeft',
          'eyeSquintLeft', 'eyeWideLeft', 'eyeBlinkRight', 'eyeLookDownRight', 'eyeLookInRight',
          'eyeLookOutRight', 'eyeLookUpRight', 'eyeSquintRight', 'eyeWideRight', 'jawForward',
          'jawLeft', 'jawRight', 'jawOpen', 'mouthClose', 'mouthFunnel'
        ];

        for (int i = 0; i < standardNames.length && i < _morphTargetNames!.length; i++) {
          final expectedSuffix = standardNames[i];
          final actualName = _morphTargetNames![i];
          final matched = actualName.toLowerCase().contains(expectedSuffix.toLowerCase());
          final status = matched ? '✅' : '❌';
          debugPrint('   [$i] 期望包含:$expectedSuffix → 实际:$actualName $status');
        }
        debugPrint('📊 缩放后的主要口型权重:');
        for (int i = 0; i < scaledWeights.length && i < _morphTargetNames!.length; i++) {
          final name = _morphTargetNames![i].toLowerCase();
          if ((name.contains('jaw') || name.contains('mouth'))) {
            // 显示所有嘴部权重，包括原始值和缩放后的值
            debugPrint('   ${_morphTargetNames![i]}: ${actualWeights[i].toStringAsFixed(4)} -> ${scaledWeights[i].toStringAsFixed(3)}');
          }
        }

        // 特别显示jawOpen的值
        for (int i = 0; i < _morphTargetNames!.length; i++) {
          if (_morphTargetNames![i].toLowerCase().contains('jawopen')) {
            debugPrint('⚠️ 关键参数 BS.jawOpen 索引[$i]: 原始=${actualWeights[i].toStringAsFixed(4)}, 缩放后=${scaledWeights[i].toStringAsFixed(3)}');
            break;
          }
        }
      }
      
      // 第一帧显示完整的权重映射
      if (kDebugMode && enableLogs && _frameCounter == 1) {
        debugPrint('🔍 第一帧完整权重映射:');
        for (int i = 0; i < actualWeights.length; i++) {
          if (actualWeights[i] > 0.0001) {
            debugPrint('   [$i] ${_morphTargetNames![i]}: ${actualWeights[i].toStringAsFixed(6)}');
          }
        }

        // 特别检查jawOpen在不同帧的值
        debugPrint('🔬 检查jawOpen映射问题:');
        debugPrint('   模型中BS.jawOpen在索引: 17');
        debugPrint('   bs.json索引17的值: ${actualWeights.length > 17 ? actualWeights[17].toStringAsFixed(4) : "N/A"}');

        // 查找哪个索引有最大值
        double maxValue = 0;
        int maxIndex = -1;
        for (int i = 0; i < actualWeights.length; i++) {
          if (actualWeights[i] > maxValue) {
            maxValue = actualWeights[i];
            maxIndex = i;
          }
        }
        debugPrint('   第1帧最大权重: [${maxIndex}] ${maxIndex >= 0 && maxIndex < _morphTargetNames!.length ? _morphTargetNames![maxIndex] : "?"} = ${maxValue.toStringAsFixed(4)}');
      }
      
      // 每100帧确认一次应用成功
      if (kDebugMode && enableLogs && _frameCounter % 100 == 1) {
        debugPrint('✅ 第 $_frameCounter 帧权重应用成功');
      }
      
    } catch (e) {
      if (kDebugMode && enableLogs) {
        debugPrint('❌ 应用 blendshape 权重失败 (帧 $_frameCounter): $e');
        debugPrint('   权重数组长度: ${weights.length}');
        debugPrint('   Morph targets 数量: ${_morphTargetNames?.length ?? 0}');
        debugPrint('   实体索引: $_morphTargetEntityIndex');
      }
    }
  }

  /// 停止播放
  Future<void> stopLipSync() async {
    _isPlaying = false;
    
    try {
      _posSub?.cancel();
      _posSub = null;
      _durSub?.cancel();
      _durSub = null;
      _completeSub?.cancel();
      _completeSub = null;
      // 停止音频
      await audioPlayer.stop();
      
      // 重置所有 blendshape 权重为 0
      if (_morphTargetNames != null && _morphEntity != null) {
        final zeroWeights = List.filled(_morphTargetNames!.length, 0.0);
        await asset.setMorphTargetWeights(_morphEntity!, zeroWeights);
      }
      
      if (kDebugMode) {
        debugPrint('⏹️ 口型同步已停止');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 停止口型同步失败: $e');
      }
    }
  }

  /// 检查是否正在播放
  bool get isPlaying => _isPlaying;


  /// 强制测试单个jawOpen - 完全停止动画并强制应用权重
  Future<void> forceTestJawOpen() async {
    if (_morphTargetNames == null || _morphEntity == null) {
      debugPrint('❌ 没有选中的实体');
      return;
    }

    try {
      debugPrint('🔥 强制测试 jawOpen - 完全停止所有动画');

      // 1. 完全停止所有可能的动画（比之前更彻底）
      final childEntities = await asset.getChildEntities();
      for (int i = 0; i < childEntities.length; i++) {
        try {
          // 尝试停止每个实体的所有可能的动画
          for (int animIndex = 0; animIndex < 10; animIndex++) {
            try {
              await asset.stopGltfAnimation(animIndex);
            } catch (_) {}
          }
        } catch (_) {}
      }

      debugPrint('⏸️ 已尝试停止所有动画');
      await Future.delayed(const Duration(seconds: 1));

      // 2. 重置所有实体的所有morph weights为0
      for (int entityIndex = 0; entityIndex < childEntities.length; entityIndex++) {
        try {
          final entity = childEntities[entityIndex];
          final morphTargets = await asset.getMorphTargetNames(entity: entity);
          if (morphTargets.isNotEmpty) {
            final zeroWeights = List.filled(morphTargets.length, 0.0);
            await asset.setMorphTargetWeights(entity, zeroWeights);
            debugPrint('🔄 已重置实体 $entityIndex 的所有权重');
          }
        } catch (e) {
          debugPrint('⚠️ 重置实体 $entityIndex 失败: $e');
        }
      }

      await Future.delayed(const Duration(seconds: 1));

      // 3. 找到jawOpen索引
      int jawOpenIndex = -1;
      for (int i = 0; i < _morphTargetNames!.length; i++) {
        if (_morphTargetNames![i] == 'BS.jawOpen') {
          jawOpenIndex = i;
          break;
        }
      }

      if (jawOpenIndex == -1) {
        debugPrint('❌ 未找到 BS.jawOpen');
        return;
      }

      debugPrint('✅ 找到 BS.jawOpen 在索引: $jawOpenIndex');

      // 4. 强制应用不同的jawOpen值，每次都等待足够长的时间
      final testValues = [0.0, 0.2, 0.5, 0.8, 1.0, 2.0, 5.0];

      for (final value in testValues) {
        debugPrint('🎯 强制设置 BS.jawOpen = $value');

        // 创建完全干净的权重数组
        final weights = List.filled(_morphTargetNames!.length, 0.0);
        weights[jawOpenIndex] = value;

        // 应用到当前选中的实体
        await asset.setMorphTargetWeights(_morphEntity!, weights);

        // 同时也应用到独立的jawOpen实体（实体12或13）
        for (int entityIdx in [12, 13]) {
          if (childEntities.length > entityIdx) {
            try {
              final jawEntity = childEntities[entityIdx];
              final morphTargetsJaw = await asset.getMorphTargetNames(entity: jawEntity);
              if (morphTargetsJaw.isNotEmpty) {
                final weightsJaw = List.filled(morphTargetsJaw.length, 0.0);
                // 查找jawOpen相关的target
                final jawIndex = morphTargetsJaw.indexWhere((name) {
                  final lowerName = name.toLowerCase();
                  return lowerName.contains('jawopen') || lowerName.contains('jaw_open') ||
                         (lowerName.contains('jaw') && lowerName.contains('open'));
                });
                if (jawIndex >= 0) {
                  weightsJaw[jawIndex] = value;
                  await asset.setMorphTargetWeights(jawEntity, weightsJaw);
                  debugPrint('   同时设置实体$entityIdx的jawOpen: ${morphTargetsJaw[jawIndex]}');
                  break; // 找到并处理了，退出循环
                }
              }
            } catch (e) {
              debugPrint('   设置实体$entityIdx失败: $e');
            }
          }
        }

        // 等待更长时间观察效果
        debugPrint('   等待5秒观察效果...');
        await Future.delayed(const Duration(seconds: 5));
      }

      // 5. 最后重置所有权重
      final resetWeights = List.filled(_morphTargetNames!.length, 0.0);
      await asset.setMorphTargetWeights(_morphEntity!, resetWeights);

      debugPrint('✅ 强制测试完成');

    } catch (e) {
      debugPrint('❌ 强制测试失败: $e');
    }
  }

  /// 对比bs.json和模型blendshape，找出缺少的映射
  Future<void> compareBlendshapeMapping() async {
    if (_blendshapeData == null || _morphTargetNames == null) {
      debugPrint('❌ 数据未加载完成');
      return;
    }

    debugPrint('🔍 开始对比 bs.json 和模型 blendshape 映射...');
    debugPrint('📊 bs.json 权重数量: ${_blendshapeData!.first.length}');
    debugPrint('📊 模型 blendshape 数量: ${_morphTargetNames!.length}');

    // 标准ARKit blendshape顺序（bs.json应该遵循的顺序）
    final standardARKitOrder = [
      'BS.eyeBlinkLeft',      // 0
      'BS.eyeLookDownLeft',   // 1
      'BS.eyeLookInLeft',     // 2
      'BS.eyeLookOutLeft',    // 3
      'BS.eyeLookUpLeft',     // 4
      'BS.eyeSquintLeft',     // 5
      'BS.eyeWideLeft',       // 6
      'BS.eyeBlinkRight',     // 7
      'BS.eyeLookDownRight',  // 8
      'BS.eyeLookInRight',    // 9
      'BS.eyeLookOutRight',   // 10
      'BS.eyeLookUpRight',    // 11
      'BS.eyeSquintRight',    // 12
      'BS.eyeWideRight',      // 13
      'BS.jawForward',        // 14
      'BS.jawLeft',           // 15
      'BS.jawRight',          // 16
      'BS.jawOpen',           // 17
      'BS.mouthClose',        // 18
      'BS.mouthFunnel',       // 19
      'BS.mouthPucker',       // 20
      'BS.mouthLeft',         // 21
      'BS.mouthRight',        // 22
      'BS.mouthSmileLeft',    // 23
      'BS.mouthSmileRight',   // 24
      'BS.mouthFrownLeft',    // 25
      'BS.mouthFrownRight',   // 26
      'BS.mouthDimpleLeft',   // 27
      'BS.mouthDimpleRight',  // 28
      'BS.mouthStretchLeft',  // 29
      'BS.mouthStretchRight', // 30
      'BS.mouthRollLower',    // 31
      'BS.mouthRollUpper',    // 32
      'BS.mouthShrugLower',   // 33
      'BS.mouthShrugUpper',   // 34
      'BS.mouthPressLeft',    // 35
      'BS.mouthPressRight',   // 36
      'BS.mouthLowerDownLeft', // 37
      'BS.mouthLowerDownRight', // 38
      'BS.mouthUpperUpLeft',   // 39
      'BS.mouthUpperUpRight',  // 40
      'BS.browDownLeft',       // 41
      'BS.browDownRight',      // 42
      'BS.browInnerUp',        // 43
      'BS.browOuterUpLeft',    // 44
      'BS.browOuterUpRight',   // 45
      'BS.cheekPuff',          // 46
      'BS.cheekSquintLeft',    // 47
      'BS.cheekSquintRight',   // 48
      'BS.noseSneerLeft',      // 49
      'BS.noseSneerRight',     // 50
      'BS.tongueOut',          // 51
      // 注意：ARKit标准有52个，但有些实现可能有更多
    ];

    debugPrint('🎯 标准ARKit顺序 vs 模型实际顺序:');

    // 对比标准顺序和模型实际顺序
    final missingInModel = <String>[];
    final extraInModel = <String>[];
    final wrongPosition = <String>[];

    // 检查模型中缺少的blendshape
    for (int i = 0; i < standardARKitOrder.length; i++) {
      final standardName = standardARKitOrder[i];
      if (!_morphTargetNames!.contains(standardName)) {
        missingInModel.add('[$i]$standardName');
      } else {
        // 检查位置是否正确
        final actualIndex = _morphTargetNames!.indexOf(standardName);
        if (actualIndex != i) {
          wrongPosition.add('$standardName: 期望[$i] 实际[$actualIndex]');
        }
      }
    }

    // 检查模型中多出的blendshape
    for (int i = 0; i < _morphTargetNames!.length; i++) {
      final modelName = _morphTargetNames![i];
      if (!standardARKitOrder.contains(modelName)) {
        extraInModel.add('[$i]$modelName');
      }
    }

    // 输出结果
    if (missingInModel.isNotEmpty) {
      debugPrint('❌ 模型中缺少的 blendshape:');
      for (final missing in missingInModel) {
        debugPrint('   $missing');
      }
    }

    if (extraInModel.isNotEmpty) {
      debugPrint('➕ 模型中多出的 blendshape:');
      for (final extra in extraInModel) {
        debugPrint('   $extra');
      }
    }

    if (wrongPosition.isNotEmpty) {
      debugPrint('🔄 位置不匹配的 blendshape:');
      for (final wrong in wrongPosition) {
        debugPrint('   $wrong');
      }
    }

    // 分析bs.json数据长度问题
    debugPrint('📏 数据长度分析:');
    debugPrint('   bs.json权重数: ${_blendshapeData!.first.length}');
    debugPrint('   模型blendshape数: ${_morphTargetNames!.length}');
    debugPrint('   标准ARKit数: ${standardARKitOrder.length}');

    if (_blendshapeData!.first.length == 55) {
      debugPrint('💡 bs.json有55个权重，可能包含额外的自定义blendshape');
      debugPrint('   额外的3个权重可能是: [52], [53], [54]');
    }

    // 重点检查jawOpen映射
    debugPrint('🎯 重点检查 jawOpen 映射:');
    final jawOpenInModel = _morphTargetNames!.indexOf('BS.jawOpen');
    debugPrint('   BS.jawOpen 在模型中的索引: $jawOpenInModel');
    debugPrint('   标准ARKit中 jawOpen 应该在索引: 17');
    debugPrint('   bs.json[17] 对应模型的: ${jawOpenInModel >= 0 ? _morphTargetNames![17] : '超出范围'}');

    if (jawOpenInModel != 17) {
      debugPrint('⚠️ jawOpen 映射错误！');
      debugPrint('   解决方案：修改映射逻辑或重新制作模型');
    }

    debugPrint('✅ 映射对比完成');
  }

  /// 深度调试实体1的BS.jawOpen
  Future<void> deepDebugEntity1() async {
    try {
      final childEntities = await asset.getChildEntities();
      final entity1 = childEntities[1]; // 实体1
      final morphTargets = await asset.getMorphTargetNames(entity: entity1);

      debugPrint('🔬 深度调试实体1 (BS.前缀)...');
      debugPrint('📊 Morph targets 总数: ${morphTargets.length}');

      // 找到jawOpen的确切索引
      int jawOpenIndex = -1;
      for (int i = 0; i < morphTargets.length; i++) {
        if (morphTargets[i] == 'BS.jawOpen') {
          jawOpenIndex = i;
          break;
        }
      }

      if (jawOpenIndex == -1) {
        debugPrint('❌ 未找到 BS.jawOpen');
        return;
      }

      debugPrint('✅ 找到 BS.jawOpen 在索引: $jawOpenIndex');

      // 停止所有动画，避免干扰
      debugPrint('⏸️ 停止所有动画...');
      // 这里应该停止动画，但我们先专注于权重测试

      // 测试极端权重值
      final testValues = [0.1, 0.3, 0.5, 0.7, 1.0, 2.0, 5.0, 10.0];

      for (final value in testValues) {
        debugPrint('🎯 测试 BS.jawOpen = $value');

        // 创建权重数组，只设置jawOpen
        final weights = List.filled(morphTargets.length, 0.0);
        weights[jawOpenIndex] = value;

        // 应用权重
        await asset.setMorphTargetWeights(entity1, weights);

        // 等待更长时间观察
        await Future.delayed(const Duration(seconds: 2));

        // 验证权重是否真的设置成功
        debugPrint('   权重已设置，等待观察...');
      }

      // 重置所有权重
      debugPrint('🔄 重置所有权重...');
      final resetWeights = List.filled(morphTargets.length, 0.0);
      await asset.setMorphTargetWeights(entity1, resetWeights);

      // 尝试设置其他明显的blendshape进行对比
      debugPrint('🧪 对比测试其他明显的 blendshape...');

      // 测试eyeBlinkLeft (应该有明显效果)
      int eyeBlinkIndex = -1;
      for (int i = 0; i < morphTargets.length; i++) {
        if (morphTargets[i] == 'BS.eyeBlinkLeft') {
          eyeBlinkIndex = i;
          break;
        }
      }

      if (eyeBlinkIndex >= 0) {
        debugPrint('🧪 测试 BS.eyeBlinkLeft = 1.0 (应该有眨眼效果)');
        final eyeWeights = List.filled(morphTargets.length, 0.0);
        eyeWeights[eyeBlinkIndex] = 1.0;
        await asset.setMorphTargetWeights(entity1, eyeWeights);
        await Future.delayed(const Duration(seconds: 2));

        // 重置
        await asset.setMorphTargetWeights(entity1, resetWeights);
      }

      debugPrint('✅ 深度调试完成');
    } catch (e) {
      debugPrint('❌ 深度调试失败: $e');
    }
  }

  /// 手动指定使用特定实体进行口型同步
  Future<void> switchToEntity(int entityIndex) async {
    try {
      final childEntities = await asset.getChildEntities();
      if (entityIndex >= childEntities.length) {
        debugPrint('❌ 实体索引超出范围: $entityIndex >= ${childEntities.length}');
        return;
      }

      final entity = childEntities[entityIndex];
      final morphTargets = await asset.getMorphTargetNames(entity: entity);

      if (morphTargets.isEmpty) {
        debugPrint('❌ 实体 $entityIndex 没有 morph targets');
        return;
      }

      // 切换到指定实体
      _morphTargetEntityIndex = entityIndex;
      _morphTargetNames = morphTargets;
      _morphEntity = entity;
      _morphTargetCount = morphTargets.length;

      debugPrint('✅ 已切换到实体 $entityIndex');
      debugPrint('   Morph targets 数量: ${morphTargets.length}');
      debugPrint('   前缀: ${morphTargets.first.split('.').first}');

      // 显示嘴部相关的targets
      final mouthTargets = <String>[];
      for (int i = 0; i < morphTargets.length; i++) {
        final name = morphTargets[i].toLowerCase();
        if (name.contains('jaw') || name.contains('mouth')) {
          mouthTargets.add('[$i]${morphTargets[i]}');
        }
      }
      if (mouthTargets.isNotEmpty) {
        debugPrint('   🗣️ 嘴部相关: ${mouthTargets.join(', ')}');
      }
    } catch (e) {
      debugPrint('❌ 切换实体失败: $e');
    }
  }

  /// 测试当前选中实体的jawOpen
  Future<void> testCurrentEntityJawOpen() async {
    if (_morphTargetNames == null || _morphEntity == null) {
      debugPrint('❌ 没有选中的实体');
      return;
    }

    try {
      // 找到jawOpen的索引
      int jawOpenIndex = -1;
      for (int i = 0; i < _morphTargetNames!.length; i++) {
        if (_morphTargetNames![i].toLowerCase().contains('jawopen')) {
          jawOpenIndex = i;
          break;
        }
      }

      if (jawOpenIndex == -1) {
        debugPrint('❌ 当前实体没有 jawOpen target');
        return;
      }

      debugPrint('🎯 测试当前实体(${_morphTargetEntityIndex}) jawOpen: [${jawOpenIndex}]${_morphTargetNames![jawOpenIndex]}');

      // 测试不同的权重值
      final testValues = [0.2, 0.5, 0.8, 1.0];
      for (final value in testValues) {
        final weights = List.filled(_morphTargetNames!.length, 0.0);
        weights[jawOpenIndex] = value;

        debugPrint('   设置 jawOpen = $value');
        await asset.setMorphTargetWeights(_morphEntity!, weights);
        await Future.delayed(const Duration(seconds: 1));
      }

      // 重置
      final resetWeights = List.filled(_morphTargetNames!.length, 0.0);
      await asset.setMorphTargetWeights(_morphEntity!, resetWeights);
      debugPrint('✅ 测试完成，已重置');
    } catch (e) {
      debugPrint('❌ 测试失败: $e');
    }
  }

  /// 调试工具：测试所有有morph targets的实体
  Future<void> debugAllMorphEntities() async {
    try {
      final childEntities = await asset.getChildEntities();
      debugPrint('🔍 开始调试所有morph实体...');

      for (int i = 0; i < childEntities.length; i++) {
        try {
          final entity = childEntities[i];
          final morphTargets = await asset.getMorphTargetNames(entity: entity);

          if (morphTargets.isNotEmpty) {
            debugPrint('🎭 测试实体 $i (${morphTargets.length} morph targets)');

            // 显示前5个morph target名称
            final firstFew = morphTargets.take(5).join(', ');
            debugPrint('   前5个: $firstFew');

            // 查找jaw相关的target
            final jawTargets = <String>[];
            for (int j = 0; j < morphTargets.length; j++) {
              final name = morphTargets[j].toLowerCase();
              if (name.contains('jaw') || name.contains('mouth')) {
                jawTargets.add('[$j]${morphTargets[j]}');
              }
            }
            if (jawTargets.isNotEmpty) {
              debugPrint('   🗣️ 嘴部相关: ${jawTargets.join(', ')}');
            }

            // 测试应用最大权重到所有morph targets
            debugPrint('   🧪 测试最大权重...');
            final testWeights = List.filled(morphTargets.length, 1.0);
            await asset.setMorphTargetWeights(entity, testWeights);
            await Future.delayed(const Duration(seconds: 2));

            // 重置
            final resetWeights = List.filled(morphTargets.length, 0.0);
            await asset.setMorphTargetWeights(entity, resetWeights);
            await Future.delayed(const Duration(milliseconds: 500));

            // 如果有jaw相关的，单独测试
            for (int j = 0; j < morphTargets.length; j++) {
              final name = morphTargets[j].toLowerCase();
              if (name.contains('jawopen')) {
                debugPrint('   🎯 单独测试 jawOpen: [${j}]${morphTargets[j]}');
                final singleWeights = List.filled(morphTargets.length, 0.0);
                singleWeights[j] = 1.0;
                await asset.setMorphTargetWeights(entity, singleWeights);
                await Future.delayed(const Duration(seconds: 2));
                await asset.setMorphTargetWeights(entity, resetWeights);
                break;
              }
            }
          }
        } catch (e) {
          debugPrint('❌ 实体 $i 测试失败: $e');
        }
      }

      debugPrint('✅ 所有实体测试完成');
    } catch (e) {
      debugPrint('❌ 调试失败: $e');
    }
  }

  /// 释放资源
  void dispose() {
    audioPlayer.dispose();
  }
}
