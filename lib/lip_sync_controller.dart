import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:thermion_flutter/thermion_flutter.dart';
import 'package:audioplayers/audioplayers.dart';

class LipSyncController {
  final ThermionAsset asset;
  final AudioPlayer audioPlayer = AudioPlayer();
  static bool enableLogs = false; // 关闭 blendshape 详细日志
  
  List<List<double>>? _blendshapeData;
  List<String>? _morphTargetNames;
  bool _isPlaying = false;
  
  // 存储有 morph targets 的实体索引
  int? _morphTargetEntityIndex;
  // 直接缓存实体句柄与 target 数，避免每帧查询与潜在失效
  int? _morphEntity;
  int _morphTargetCount = 0;
  
  // 权重放大倍数（根据模型调节，通常 1.0 即可）
  double weightMultiplier = 1.0;
  
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
    'jawopen': 0.7,
    'jaw': 0.85,
    'mouthfunnel': 0.6,
    'mouthpucker': 0.6,
    'mouthstretch': 0.8,
    'mouthshrug': 0.8,
    'mouthroll': 0.85,
    'mouthlowerdown': 0.85,
    'mouthupperup': 0.85,
    'mouthclose': 0.9,
    // 兜底：所有 mouth 相关略降一点
    'mouth': 0.9,
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

      // 暂停 idle 动画
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

  /// 应用单帧的 blendshape 权重
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
      
      // 确保权重数组长度匹配 morph targets 数量
      final maxLength = _morphTargetCount > 0 ? _morphTargetCount : _morphTargetNames!.length;
      List<double> actualWeights;
      
      if (weights.length >= maxLength) {
        // 如果权重数组过长，截取前面的部分
        actualWeights = weights.take(maxLength).toList();
      } else {
        // 如果权重数组过短，用0填充
        actualWeights = List<double>.from(weights);
        while (actualWeights.length < maxLength) {
          actualWeights.add(0.0);
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
      final double mul = (multiplier ?? weightMultiplier).clamp(0.0, 1.0);
      final List<double> scaledWeights = List<double>.filled(actualWeights.length, 0.0);
      for (int i = 0; i < actualWeights.length; i++) {
        double local = 1.0;
        final name = _morphTargetNames![i].toLowerCase();
        for (final entry in channelGains.entries) {
          if (name.contains(entry.key)) {
            local *= entry.value; // 可叠乘多个关键词（通常命中一个）
          }
        }
        final v = (actualWeights[i] * mul * local).clamp(0.0, 1.0);
        scaledWeights[i] = v;
      }
      
      // 应用权重到模型
      await asset.setMorphTargetWeights(entity, scaledWeights);
      
      // 第一帧显示缩放后的权重
      if (kDebugMode && enableLogs && _frameCounter == 1) {
        debugPrint('🔧 应用权重倍率: x${mul.toStringAsFixed(2)}（含通道局部增益）');
      }
      
      // 第一帧显示完整的权重映射
      if (kDebugMode && enableLogs && _frameCounter == 1) {
        debugPrint('🔍 第一帧完整权重映射:');
        for (int i = 0; i < actualWeights.length; i++) {
          if (actualWeights[i] > 0.0001) {
            debugPrint('   [$i] ${_morphTargetNames![i]}: ${actualWeights[i].toStringAsFixed(6)}');
          }
        }
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

  /// 释放资源
  void dispose() {
    audioPlayer.dispose();
  }
}
