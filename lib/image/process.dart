import 'package:flutter/foundation.dart';

import 'rgba_image.dart';

/// 「处理」阶段的参数：**原图 → 处理 → 抖动** 里的中间一步。
///
/// 为什么不把这套逻辑塞进 `dither.dart`：抖动是「把颜色压到调色板上」，
/// 处理是「在压之前先把图调整到适合压的状态」。两者独立演化，
/// 而且处理的参数（自动亮度 / 亮度 / 色彩简化）跟抖动算法可以任意组合。
@immutable
class ProcessSettings {
  const ProcessSettings({
    this.autoBrightness = true,
    this.brightness = 0,
    this.simplifyColors = false,
    this.simplifyColorCount = 8,
  });

  /// 默认设置：**只做自动亮度**（用户选定的默认策略）。
  ///
  /// 自动亮度只做直方图拉伸，不改色相、不改变构图，对绝大多数照片都只会
  /// 让抖动结果更干净；而色彩简化会明显改变观感，所以默认关。
  static const ProcessSettings defaults = ProcessSettings();

  /// 是否做自动亮度（直方图白/黑点拉伸）。
  final bool autoBrightness;

  /// 手动亮度补偿，范围 -100 ~ 100，映射成 ±255 的加法。
  final double brightness;

  /// 是否做色彩简化（median cut 降到 [simplifyColorCount] 色）。
  final bool simplifyColors;

  /// 色彩简化后的颜色数，范围 2 ~ 64。
  final int simplifyColorCount;

  /// 三个开关都没开时，处理阶段是恒等变换，可以整段跳过。
  bool get isIdentity =>
      !autoBrightness && brightness == 0 && !simplifyColors;

  ProcessSettings copyWith({
    bool? autoBrightness,
    double? brightness,
    bool? simplifyColors,
    int? simplifyColorCount,
  }) {
    return ProcessSettings(
      autoBrightness: autoBrightness ?? this.autoBrightness,
      brightness: brightness ?? this.brightness,
      simplifyColors: simplifyColors ?? this.simplifyColors,
      simplifyColorCount: simplifyColorCount ?? this.simplifyColorCount,
    );
  }

  /// 用于缓存判断；必须覆盖所有会影响输出的字段。
  int get key => Object.hash(
        autoBrightness,
        brightness,
        simplifyColors,
        simplifyColorCount,
      );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ProcessSettings &&
        other.autoBrightness == autoBrightness &&
        other.brightness == brightness &&
        other.simplifyColors == simplifyColors &&
        other.simplifyColorCount == simplifyColorCount;
  }

  @override
  int get hashCode => key;

  @override
  String toString() => 'ProcessSettings(autoBrightness: $autoBrightness, '
      'brightness: $brightness, simplifyColors: $simplifyColors, '
      'simplifyColorCount: $simplifyColorCount)';
}

/// 预览的三个阶段。界面上「原图 / 处理 / 抖动」三档切换用。
enum PreviewStage {
  original('原图'),
  processed('处理'),
  dithered('抖动');

  const PreviewStage(this.label);

  final String label;
}

/// 应用整个「处理」阶段。**不修改入参**，返回新图。
RgbaImage processImage(RgbaImage image, ProcessSettings settings) {
  RgbaImage out = image.clone();
  if (settings.autoBrightness) {
    out = applyAutoBrightness(out);
  }
  if (settings.brightness != 0) {
    out = applyBrightness(out, settings.brightness);
  }
  if (settings.simplifyColors) {
    out = simplifyColors(out, settings.simplifyColorCount);
  }
  return out;
}

/// 线性亮度补偿。
///
/// `amount` 取值 -100 ~ 100，映射到 ±255 的加法（与常见图像软件的
/// 「亮度」滑块量级接近）。alpha 不动。
RgbaImage applyBrightness(RgbaImage image, double amount) {
  final Uint8List data = image.data;
  final int delta = (amount.clamp(-100.0, 100.0) * 255 / 100).round();
  if (delta == 0) {
    return image.clone();
  }
  for (int i = 0; i < data.length; i += 4) {
    data[i] = _clampByte(data[i] + delta);
    data[i + 1] = _clampByte(data[i + 1] + delta);
    data[i + 2] = _clampByte(data[i + 2] + delta);
  }
  return image;
}

/// 自动亮度：按亮度直方图的白/黑点做拉伸。
///
/// 做法（自研，思路是通用的自动色阶）：
/// 1. 统计不透明像素的亮度直方图（256 桶，整数 luma）；
/// 2. 取 `lowPercentile` / `highPercentile` 分位对应的亮度当作黑点与白点；
/// 3. 把 `[low, high]` 线性映射到 `[0, 255]`，三个通道用同一张查找表
///    （同一张 LUT 意味着**不改变色相**）。
///
/// 三个保守处理，避免把图弄脏：
/// - 动态范围本来就够（`high - low >= 250`）时不做任何事；
/// - 动态范围过窄（`high - low < 8`，几乎纯色）时也不做，否则纯色图会被
///   拉伸成噪声；
/// - 分位点用直方图近似，不需要排序像素。
RgbaImage applyAutoBrightness(
  RgbaImage image, {
  double lowPercentile = 0.005,
  double highPercentile = 0.995,
}) {
  final Uint8List data = image.data;
  final int pixels = image.width * image.height;
  if (pixels == 0) {
    return image.clone();
  }

  final Int32List histogram = Int32List(256);
  int opaque = 0;
  for (int i = 0; i < data.length; i += 4) {
    if (data[i + 3] == 0) {
      continue;
    }
    final int luma =
        (299 * data[i] + 587 * data[i + 1] + 114 * data[i + 2]) ~/ 1000;
    histogram[luma.clamp(0, 255)] += 1;
    opaque += 1;
  }
  if (opaque == 0) {
    return image.clone();
  }

  final int lowCount = (opaque * lowPercentile).floor();
  final int highCount = (opaque * highPercentile).ceil();
  int low = 0;
  int high = 255;
  int cumulative = 0;
  for (int i = 0; i < 256; i++) {
    cumulative += histogram[i];
    if (cumulative > lowCount) {
      low = i;
      break;
    }
  }
  cumulative = 0;
  for (int i = 0; i < 256; i++) {
    cumulative += histogram[i];
    if (cumulative >= highCount) {
      high = i;
      break;
    }
  }

  // 已经用满动态范围，或者几乎是纯色图 —— 都不动。
  if (high - low >= 250 || high - low < 8) {
    return image.clone();
  }

  final Uint8List lut = Uint8List(256);
  final double span = (high - low).toDouble();
  for (int i = 0; i < 256; i++) {
    final double mapped = (i - low) * 255 / span;
    lut[i] = _clampByte(mapped.round());
  }

  for (int i = 0; i < data.length; i += 4) {
    if (data[i + 3] == 0) {
      continue;
    }
    data[i] = lut[data[i]];
    data[i + 1] = lut[data[i + 1]];
    data[i + 2] = lut[data[i + 2]];
  }
  return image;
}

/// 色彩简化：median cut 把图降到 `colorCount` 色以内。
///
/// 对墨水屏很有用：先把彩色照片压到有限的几种颜色，抖动时的误差扩散
/// 才不会在调色板边界反复横跳。
RgbaImage simplifyColors(RgbaImage image, int colorCount) {
  final int target = colorCount.clamp(2, 64);
  final Uint8List data = image.data;
  final int pixels = image.width * image.height;
  if (pixels == 0) {
    return image.clone();
  }

  // 收集不透明像素的 RGB 三元组。
  final List<int> reds = <int>[];
  final List<int> greens = <int>[];
  final List<int> blues = <int>[];
  final List<int> pixelIndices = <int>[];
  for (int p = 0; p < pixels; p++) {
    final int i = p * 4;
    if (data[i + 3] == 0) {
      continue;
    }
    reds.add(data[i]);
    greens.add(data[i + 1]);
    blues.add(data[i + 2]);
    pixelIndices.add(p);
  }
  if (reds.length <= target) {
    return image.clone();
  }

  // median cut：每次挑通道跨度最大的盒子，从中位数处切开。
  List<List<int>> boxes = <List<int>>[List<int>.generate(reds.length, (int i) => i)];
  while (boxes.length < target) {
    int bestBox = -1;
    int bestChannel = 0;
    int bestRange = -1;
    for (int b = 0; b < boxes.length; b++) {
      final List<int> box = boxes[b];
      if (box.length < 2) {
        continue;
      }
      for (int channel = 0; channel < 3; channel++) {
        final List<int> values = _channelValues(channel, box, reds, greens, blues);
        final int range = values.last - values.first;
        if (range > bestRange) {
          bestRange = range;
          bestBox = b;
          bestChannel = channel;
        }
      }
    }
    if (bestBox < 0 || bestRange <= 0) {
      break;
    }
    final List<int> box = boxes[bestBox];
    final List<int> values = _channelValues(bestChannel, box, reds, greens, blues);
    final int median = values[values.length ~/ 2];
    final List<int> lower = <int>[];
    final List<int> upper = <int>[];
    for (final int index in box) {
      final int value = _channelValue(bestChannel, index, reds, greens, blues);
      if (value <= median) {
        lower.add(index);
      } else {
        upper.add(index);
      }
    }
    // 全落在同一边（中位数正好是边界值）时，按顺序硬切一半，保证收敛。
    if (lower.isEmpty || upper.isEmpty) {
      final int half = box.length ~/ 2;
      boxes[bestBox] = box.sublist(0, half);
      boxes.add(box.sublist(half));
    } else {
      boxes[bestBox] = lower;
      boxes.add(upper);
    }
  }

  // 每个盒子用平均色表示。
  for (final List<int> box in boxes) {
    if (box.isEmpty) {
      continue;
    }
    int sumR = 0;
    int sumG = 0;
    int sumB = 0;
    for (final int index in box) {
      sumR += reds[index];
      sumG += greens[index];
      sumB += blues[index];
    }
    final int r = (sumR / box.length).round();
    final int g = (sumG / box.length).round();
    final int b = (sumB / box.length).round();
    for (final int index in box) {
      final int i = pixelIndices[index] * 4;
      data[i] = r;
      data[i + 1] = g;
      data[i + 2] = b;
    }
  }
  return image;
}

List<int> _channelValues(
  int channel,
  List<int> box,
  List<int> reds,
  List<int> greens,
  List<int> blues,
) {
  final List<int> values = <int>[
    for (final int index in box)
      _channelValue(channel, index, reds, greens, blues),
  ];
  values.sort();
  return values;
}

int _channelValue(
  int channel,
  int index,
  List<int> reds,
  List<int> greens,
  List<int> blues,
) {
  switch (channel) {
    case 0:
      return reds[index];
    case 1:
      return greens[index];
    default:
      return blues[index];
  }
}

int _clampByte(int value) => value < 0 ? 0 : (value > 255 ? 255 : value);

/// 供 UI 描述当前处理强度的短文案。
String describeProcess(ProcessSettings settings) {
  final List<String> parts = <String>[];
  if (settings.autoBrightness) {
    parts.add('自动亮度');
  }
  if (settings.brightness != 0) {
    parts.add('亮度 ${settings.brightness > 0 ? '+' : ''}'
        '${settings.brightness.toStringAsFixed(0)}');
  }
  if (settings.simplifyColors) {
    parts.add('简化到 ${settings.simplifyColorCount} 色');
  }
  return parts.isEmpty ? '不处理' : parts.join(' · ');
}

/// 调试用：把亮度值格式化成短字符串。
String formatBrightness(double value) {
  final int rounded = value.round();
  return rounded > 0 ? '+$rounded' : '$rounded';
}
