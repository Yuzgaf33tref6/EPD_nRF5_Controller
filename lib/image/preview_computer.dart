import 'dart:async';

import 'package:flutter/foundation.dart';

import 'dither.dart';
import 'epd_color.dart';
import 'process.dart';
import 'rgba_image.dart';

/// 预览计算的入参。必须全部是「可跨 isolate 传递」的值类型。
///
/// 之所以不直接传 `RgbaImage` 对象：`compute` 要求入参和返回值都能在 isolate 之间
/// 传递，实体类虽然多数情况下可以，但这里显式把 RGBA 字节拆出来传，行为更可预期，
/// 也方便单测（无 Flutter 环境也能算）。
///
/// 流水线：**原图 → 处理（预处理 / 亮度均衡 / 亮度 / 色彩简化）→ 抖动**。
/// [stage] 决定算到哪一步停：`original` 直接返回原图，`processed` 停在做完处理，
/// `dithered` 再往下跑对比度与抖动。
@immutable
class DitherJob {
  const DitherJob({
    required this.width,
    required this.height,
    required this.rgba,
    required this.algorithm,
    required this.strength,
    required this.contrast,
    required this.mode,
    this.process = ProcessSettings.defaults,
    this.stage = PreviewStage.dithered,
    this.serpentine = false,
    this.noiseMask,
    this.noiseMaskEdge = kBlueNoiseEdge,
    this.alreadyProcessed = false,
  });

  final int width;
  final int height;
  final Uint8List rgba;
  final DitherAlgorithm algorithm;
  final double strength;
  final double contrast;
  final EpdColorMode mode;

  /// 处理阶段的参数。
  final ProcessSettings process;

  /// 算到哪一步停。
  final PreviewStage stage;

  /// 误差扩散是否走蛇形扫描（奇数行反向）。
  final bool serpentine;

  /// 蓝噪声阈值表（只在 [DitherAlgorithm.blueNoise] 时用）。
  ///
  /// 必须随 job 一起传进 isolate —— 后台 isolate 里读不了 `rootBundle`。
  final Uint8List? noiseMask;

  /// [noiseMask] 的边长。
  final int noiseMaskEdge;

  /// [rgba] 是否**已经**是处理完的数据（只改抖动参数时复用处理结果用）。
  ///
  /// 为真时跳过 [processImage]，直接用 [rgba] 当抖动输入。这样「只动了抖动设置」
  /// 就不会再把色彩简化 / 亮度均衡重算一遍 —— 那正是用户反馈的那几秒卡顿。
  final bool alreadyProcessed;

  /// 标识这份入参的键，用来判断结果是否还有效。
  Object get key => Object.hash(
        width,
        height,
        algorithm,
        strength,
        contrast,
        mode,
        process.key,
        stage,
        serpentine,
        noiseMask == null ? 0 : _hashBytes(noiseMask!),
        noiseMaskEdge,
        alreadyProcessed,
        _hashBytes(rgba),
      );

  DitherJob copyWith({
    PreviewStage? stage,
    Uint8List? rgba,
    bool? alreadyProcessed,
  }) =>
      DitherJob(
        width: width,
        height: height,
        rgba: rgba ?? this.rgba,
        algorithm: algorithm,
        strength: strength,
        contrast: contrast,
        mode: mode,
        process: process,
        stage: stage ?? this.stage,
        serpentine: serpentine,
        noiseMask: noiseMask,
        noiseMaskEdge: noiseMaskEdge,
        alreadyProcessed: alreadyProcessed ?? this.alreadyProcessed,
      );
}

/// 稳定的字节哈希（FNV-1a）。不用 `Object.hashAll` 是因为它每次进程启动都不同，
/// 不能让结果在多次调用之间比较。
int _hashBytes(Uint8List bytes) {
  int hash = 0x811c9dc5;
  // 只采样，避免每次对 12 万字节全扫（采样漏判的代价只是多算一次预览）。
  final int step = bytes.length <= 4096 ? 1 : bytes.length ~/ 4096;
  for (int i = 0; i < bytes.length; i += step) {
    hash ^= bytes[i];
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash ^ bytes.length;
}

/// 在**后台 isolate** 里算预览。
///
/// 这是「一进预览页就卡」的正面解法：处理 + 对比度 + 抖动要遍历 12 万像素、
/// 每个像素还要跟调色板做一次 Lab 距离比较，跑在主 isolate 上必然掉帧。
/// 放到后台后，UI 线程只负责画已经转好的贴图，滑块拖动期间界面依然跟手。
///
/// 另外它还负责**缓存处理结果**：处理参数没变、只改了抖动参数时，
/// 直接把上次的处理结果当输入丢进 isolate，跳过预处理 / 亮度均衡 / 色彩简化。
class PreviewComputer {
  PreviewComputer();

  /// 上一次的结果与它的键，用于避免重复计算。
  RgbaImage? _lastResult;
  Object? _lastKey;

  /// 处理阶段的结果缓存（与 [DitherJob.process] + 原图绑定）。
  RgbaImage? _processedBase;
  Object? _processedBaseKey;

  /// 已经排队但还没开始的请求只保留最后一个（拖动滑块时中间的都不需要）。
  DitherJob? _queued;
  bool _running = false;
  bool _disposed = false;

  /// 结果回调。每次算完都会带「这次算的是哪个请求」一起调用一次。
  ///
  /// 带上 [DitherJob] 是为了让界面能判断结果是否还对应现在选中的档位：
  /// 算的过程中用户可能已经切到别的档了，那种结果要丢掉。
  void Function(DitherJob job, RgbaImage image)? onResult;

  /// 处理结果的缓存键：原图（按对象身份，换了图自然失效）+ 处理参数。
  Object _processedKeyOf(DitherJob job) =>
      Object.hash(identityHashCode(job.rgba), job.rgba.length, job.process.key);

  /// 拿到「处理完」的图：命中缓存就直接返回，否则去后台算一次并缓存。
  Future<RgbaImage> _ensureProcessed(DitherJob job) async {
    final Object key = _processedKeyOf(job);
    final RgbaImage? cached = _processedBase;
    if (cached != null && _processedBaseKey == key) {
      return cached;
    }
    final RgbaImage fresh = await compute(
      _runDitherJob,
      job.copyWith(stage: PreviewStage.processed, alreadyProcessed: false),
    );
    _processedBase = fresh;
    _processedBaseKey = key;
    return fresh;
  }

  /// 提交一次计算请求。相同的入参会被跳过；正在算时新请求会覆盖掉排队的那个。
  void request(DitherJob job) {
    if (_disposed) {
      return;
    }
    final Object key = job.key;
    if (_lastKey == key && _lastResult != null) {
      return;
    }
    _queued = job;
    if (!_running) {
      unawaited(_pump());
    }
  }

  Future<void> _pump() async {
    _running = true;
    try {
      while (_queued != null && !_disposed) {
        final DitherJob job = _queued!;
        _queued = null;
        final RgbaImage result = await _run(job);
        if (_disposed) {
          return;
        }
        _lastResult = result;
        _lastKey = job.key;
        onResult?.call(job, result);
      }
    } finally {
      _running = false;
    }
  }

  Future<RgbaImage> _run(DitherJob job) async {
    if (job.stage == PreviewStage.original) {
      return compute(_runDitherJob, job);
    }
    if (job.stage == PreviewStage.processed) {
      return _ensureProcessed(job);
    }
    // 抖动档：先确保处理结果可用，再只跑「对比度 + 抖动」。
    final RgbaImage processed = await _ensureProcessed(job);
    final DitherJob ditherJob = job.copyWith(
      rgba: processed.data,
      alreadyProcessed: true,
    );
    return compute(_runDitherJob, ditherJob);
  }

  void dispose() {
    _disposed = true;
    _queued = null;
    _lastResult = null;
    _lastKey = null;
    _processedBase = null;
    _processedBaseKey = null;
    onResult = null;
  }
}

/// 顶层函数，供 [compute] 在 isolate 里执行。
///
/// 阶段：原图 → 处理 → （对比度）→ 抖动。
RgbaImage _runDitherJob(DitherJob job) {
  final RgbaImage base = RgbaImage(
    job.width,
    job.height,
    Uint8List.fromList(job.rgba),
  );
  if (job.stage == PreviewStage.original) {
    return base;
  }
  RgbaImage out = job.alreadyProcessed ? base : processImage(base, job.process);
  if (job.stage == PreviewStage.processed) {
    return out;
  }
  out = adjustContrast(out, job.contrast);
  out = ditherImage(
    out,
    job.algorithm,
    job.strength,
    job.mode,
    serpentine: job.serpentine,
    noiseMask: job.noiseMask,
    noiseMaskEdge: job.noiseMaskEdge,
  );
  return out;
}

/// 给测试/同步场景用的直接计算版本（不开 isolate）。
RgbaImage computeDitherJobSync(DitherJob job) => _runDitherJob(job);
