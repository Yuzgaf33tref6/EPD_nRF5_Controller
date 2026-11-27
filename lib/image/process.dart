import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'rgba_image.dart';

/// 「预处理」预设：把一组常用调整打包成一个选项。
///
/// 这些名字只是「效果类型」的描述，具体参数与实现都是本项目的自研实现
/// （参考了常见修图软件里同名的处理思路：对比度 / 饱和度 / gamma /
/// 白平衡 / 色阶），不含任何第三方代码。
enum PreprocessPreset {
  none('不处理'),
  vividPhoto('动态照片'),
  vividIllustration('鲜明插画'),
  softGradient('柔和渐变'),
  grayscalePhoto('灰阶照片'),
  restoreOldPhoto('旧照片修复'),
  paperPoster('纸张与海报');

  const PreprocessPreset(this.label);

  final String label;
}

/// 「处理」阶段的参数：**原图 → 处理 → 抖动** 里的中间一步。
///
/// 为什么不把这套逻辑塞进 `dither.dart`：抖动是「把颜色压到调色板上」，
/// 处理是「在压之前先把图调整到适合压的状态」。两者独立演化，
/// 而且处理的参数跟抖动算法可以任意组合。
///
/// 默认值全部关闭（0.3.0 起）：自动亮度改成了「一键算初值」的按钮
/// （把结果直接写进 [brightness]），因此不再是一个常驻开关。
@immutable
class ProcessSettings {
  const ProcessSettings({
    this.brightness = 0,
    this.brightnessBalance = false,
    this.preprocess = PreprocessPreset.none,
    this.simplifyColors = false,
    this.simplifyColorCount = 8,
  });

  /// 默认设置：全部不处理。
  static const ProcessSettings defaults = ProcessSettings();

  /// 手动亮度补偿，范围 -100 ~ 100，映射成 ±255 的加法。
  final double brightness;

  /// 是否做「亮度均衡」：分位裁剪定黑白点 + 中位亮度对齐到 0.5。
  ///
  /// 由界面上的「亮度均衡」开关控制，默认关。比原来的自动亮度（纯直方图
  /// 拉伸）更贴合人眼：它会把中位亮度也拉到中间，所以高调（大片白）和
  /// 低调（整体偏暗）的图也能得到合理结果。
  final bool brightnessBalance;

  /// 预处理预设（默认 [PreprocessPreset.none]）。
  final PreprocessPreset preprocess;

  /// 是否做色彩简化（median cut 降到 [simplifyColorCount] 色）。
  final bool simplifyColors;

  /// 色彩简化后的颜色数，范围 2 ~ 64。
  final int simplifyColorCount;

  /// 所有开关都没开、亮度为 0 时，处理阶段是恒等变换，可以整段跳过。
  bool get isIdentity =>
      brightness == 0 &&
      !brightnessBalance &&
      preprocess == PreprocessPreset.none &&
      !simplifyColors;

  ProcessSettings copyWith({
    double? brightness,
    bool? brightnessBalance,
    PreprocessPreset? preprocess,
    bool? simplifyColors,
    int? simplifyColorCount,
  }) {
    return ProcessSettings(
      brightness: brightness ?? this.brightness,
      brightnessBalance: brightnessBalance ?? this.brightnessBalance,
      preprocess: preprocess ?? this.preprocess,
      simplifyColors: simplifyColors ?? this.simplifyColors,
      simplifyColorCount: simplifyColorCount ?? this.simplifyColorCount,
    );
  }

  /// 用于缓存判断；必须覆盖所有会影响输出的字段。
  int get key => Object.hash(
        brightness,
        brightnessBalance,
        preprocess,
        simplifyColors,
        simplifyColorCount,
      );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ProcessSettings &&
        other.brightness == brightness &&
        other.brightnessBalance == brightnessBalance &&
        other.preprocess == preprocess &&
        other.simplifyColors == simplifyColors &&
        other.simplifyColorCount == simplifyColorCount;
  }

  @override
  int get hashCode => key;

  @override
  String toString() => 'ProcessSettings(brightness: $brightness, '
      'brightnessBalance: $brightnessBalance, preprocess: $preprocess, '
      'simplifyColors: $simplifyColors, '
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
///
/// 顺序是有讲究的：
/// 1. 预处理预设（对比度 / 饱和度 / 白平衡 / gamma）—— 先把图「修好」；
/// 2. 亮度均衡 —— 再把动态范围与中位亮度归一；
/// 3. 亮度补偿 —— 最后做用户手动的整体加减；
/// 4. 色彩简化 —— 放到最后，避免前面的曲线把量化误差放大。
RgbaImage processImage(RgbaImage image, ProcessSettings settings) {
  RgbaImage out = image.clone();
  if (settings.preprocess != PreprocessPreset.none) {
    out = applyPreprocess(out, settings.preprocess);
  }
  if (settings.brightnessBalance) {
    out = applyBrightnessBalance(out);
  }
  if (settings.brightness != 0) {
    out = applyBrightness(out, settings.brightness);
  }
  if (settings.simplifyColors) {
    out = simplifyColors(out, settings.simplifyColorCount);
  }
  return out;
}

/// 按 [PreprocessPreset] 应用一组调整。
RgbaImage applyPreprocess(RgbaImage image, PreprocessPreset preset) {
  RgbaImage out = image;
  switch (preset) {
    case PreprocessPreset.none:
      break;
    case PreprocessPreset.vividPhoto:
      out = applyContrast(out, 1.10);
      out = applySaturation(out, 1.20);
      out = applyGamma(out, 0.95);
    case PreprocessPreset.vividIllustration:
      out = applyWhiteBalance(out);
      out = applyContrast(out, 1.16);
      out = applySaturation(out, 1.35);
      out = applyGamma(out, 0.92);
    case PreprocessPreset.softGradient:
      out = applyContrast(out, 0.94);
      out = applySaturation(out, 0.95);
      out = applyGamma(out, 1.18);
    case PreprocessPreset.grayscalePhoto:
      out = applySaturation(out, 0);
      out = applyContrast(out, 1.05);
    case PreprocessPreset.restoreOldPhoto:
      out = applyWhiteBalance(out, lowPercentile: 0.01, highPercentile: 0.99);
      out = applyContrast(out, 1.06);
      out = applySaturation(out, 1.08);
      out = applyGamma(out, 0.97);
    case PreprocessPreset.paperPoster:
      out = applyBrightnessBalance(
        out,
        lowPercentile: 0.02,
        highPercentile: 0.98,
      );
      out = applyContrast(out, 1.25);
      out = applySaturation(out, 1.10);
  }
  return out;
}

/// 线性亮度补偿。
///
/// `amount` 取值 -100 ~ 100，映射到 ±255 的加法（与常见图像软件的
/// 「亮度」滑块量级接近）。alpha 不动。
RgbaImage applyBrightness(RgbaImage image, double amount) {
  final int delta = (amount.clamp(-100.0, 100.0) * 255 / 100).round();
  return _applyLut(image, _offsetLut(delta));
}

/// 对比度：`128 + (v - 128) * factor`，alpha 不动。
RgbaImage applyContrast(RgbaImage image, double factor) {
  final double f = factor.clamp(0.1, 4.0);
  final Uint8List lut = Uint8List(256);
  for (int i = 0; i < 256; i++) {
    lut[i] = _clampByte((128 + (i - 128) * f).round());
  }
  return _applyLut(image, lut);
}

/// gamma 调整：`(v/255)^(1/gamma) * 255`。gamma > 1 提亮中间调。
RgbaImage applyGamma(RgbaImage image, double gamma) {
  final double g = gamma.clamp(0.2, 5.0);
  final Uint8List lut = Uint8List(256);
  for (int i = 0; i < 256; i++) {
    final double normalized = i / 255;
    lut[i] = _clampByte(
      (math.pow(normalized, 1 / g) * 255).round(),
    );
  }
  return _applyLut(image, lut);
}

/// 饱和度：`luma + (v - luma) * amount`。amount=0 变灰，1 不变，>1 更艳。
RgbaImage applySaturation(RgbaImage image, double amount) {
  final double a = amount.clamp(0.0, 3.0);
  if (a == 1.0) {
    return image.clone();
  }
  final Uint8List data = image.data;
  for (int i = 0; i < data.length; i += 4) {
    if (data[i + 3] == 0) {
      continue;
    }
    final int r = data[i];
    final int g = data[i + 1];
    final int b = data[i + 2];
    final int luma = (299 * r + 587 * g + 114 * b) ~/ 1000;
    data[i] = _clampByte((luma + (r - luma) * a).round());
    data[i + 1] = _clampByte((luma + (g - luma) * a).round());
    data[i + 2] = _clampByte((luma + (b - luma) * a).round());
  }
  return image;
}

/// 自动白平衡：三个通道各自按分位点拉伸，抵消偏色。
RgbaImage applyWhiteBalance(
  RgbaImage image, {
  double lowPercentile = 0.005,
  double highPercentile = 0.995,
}) {
  final Uint8List data = image.data;
  final List<Int32List> histograms = <Int32List>[
    Int32List(256),
    Int32List(256),
    Int32List(256),
  ];
  int opaque = 0;
  for (int i = 0; i < data.length; i += 4) {
    if (data[i + 3] == 0) {
      continue;
    }
    histograms[0][data[i]] += 1;
    histograms[1][data[i + 1]] += 1;
    histograms[2][data[i + 2]] += 1;
    opaque += 1;
  }
  if (opaque == 0) {
    return image.clone();
  }
  final List<Uint8List> luts = <Uint8List>[];
  for (final Int32List histogram in histograms) {
    final (int low, int high) = _percentileRange(
      histogram,
      opaque,
      lowPercentile,
      highPercentile,
    );
    // 该通道几乎是常量时不要拉伸，否则会被放大成噪声。
    luts.add(high - low < 8 ? _identityLut() : _stretchLut(low, high));
  }
  for (int i = 0; i < data.length; i += 4) {
    if (data[i + 3] == 0) {
      continue;
    }
    data[i] = luts[0][data[i]];
    data[i + 1] = luts[1][data[i + 1]];
    data[i + 2] = luts[2][data[i + 2]];
  }
  return image;
}

/// 亮度均衡：分位裁剪定黑白点 + 中位亮度对齐到 [targetMedian]。
///
/// 相比旧的「自动亮度」（只做直方图拉伸），这里多了一步中间调对齐：
/// - 大片白背景的文档/海报：拉伸后中位亮度仍在 0.8 以上，会被压回中间，
///   黑色文字与背景的区分度更好；
/// - 整体偏暗的夜景：拉伸后仍然偏暗，会被提亮。
///
/// 实现是纯 LUT（一次 256 项 pow + 一次线性遍历），没有局部窗口，
/// 所以不会在纯色区域放大噪点，也不会给照片加光晕。
RgbaImage applyBrightnessBalance(
  RgbaImage image, {
  double lowPercentile = 0.01,
  double highPercentile = 0.99,
  double targetMedian = 0.5,
}) {
  final int pixels = image.width * image.height;
  if (pixels == 0) {
    return image.clone();
  }
  final Int32List histogram = _lumaHistogram(image);
  int opaque = 0;
  for (int i = 0; i < 256; i++) {
    opaque += histogram[i];
  }
  if (opaque == 0) {
    return image.clone();
  }
  final (int low, int high) = _percentileRange(
    histogram,
    opaque,
    lowPercentile,
    highPercentile,
  );
  // 几乎纯色的图不动，否则会被放大成噪声。
  if (high - low < 8) {
    return image.clone();
  }

  // 先线性拉伸，再算拉伸后的中位亮度。
  final Uint8List stretched = _stretchLut(low, high);
  int cumulative = 0;
  int medianLuma = 128;
  final int half = (opaque + 1) ~/ 2;
  for (int i = 0; i < 256; i++) {
    cumulative += histogram[i];
    if (cumulative >= half) {
      medianLuma = stretched[i];
      break;
    }
  }
  final double median = medianLuma / 255;
  // 解 t^k = targetMedian：k = ln(target)/ln(median)，夹到 [0.5, 2] 免得过度。
  double exponent = 1;
  if (median > 0.02 && median < 0.98 && targetMedian > 0.02) {
    exponent = (math.log(targetMedian) / math.log(median)).clamp(0.5, 2.0);
  }
  final Uint8List lut = Uint8List(256);
  for (int i = 0; i < 256; i++) {
    final double normalized = stretched[i] / 255;
    lut[i] = _clampByte((math.pow(normalized, exponent) * 255).round());
  }
  return _applyLut(image, lut);
}

/// 「自动亮度」按钮用：估算一个等效的整体亮度补偿值（-100 ~ 100）。
///
/// 自动亮度不再是常驻的曲线拉伸（那种曲线没法用一个滑块表示），而是
/// 一次性算出「让中位亮度落到中间」所需要的整体加减量，写进亮度滑块里
/// —— 符合图像软件里「自动色阶 = 帮你把滑块摆好」的惯例。
///
/// 用中位亮度而不是白/黑点：整体加减只能平移，按中位对齐才不会把高光
/// 或暗部大面积压死。想同时处理动态范围时用「亮度均衡」。
double estimateAutoBrightness(RgbaImage image) {
  final Int32List histogram = _lumaHistogram(image);
  int opaque = 0;
  for (int i = 0; i < 256; i++) {
    opaque += histogram[i];
  }
  if (opaque == 0) {
    return 0;
  }
  final (int low, int high) = _percentileRange(histogram, opaque, 0.005, 0.995);
  if (high - low < 8) {
    return 0;
  }
  int cumulative = 0;
  int medianLuma = 128;
  final int half = (opaque + 1) ~/ 2;
  for (int i = 0; i < 256; i++) {
    cumulative += histogram[i];
    if (cumulative >= half) {
      medianLuma = i;
      break;
    }
  }
  final double delta = 128 - medianLuma.toDouble();
  return (delta * 100 / 255).clamp(-100.0, 100.0);
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
  List<List<int>> boxes = <List<int>>[
    List<int>.generate(reds.length, (int i) => i),
  ];
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

Int32List _lumaHistogram(RgbaImage image) {
  final Uint8List data = image.data;
  final Int32List histogram = Int32List(256);
  for (int i = 0; i < data.length; i += 4) {
    if (data[i + 3] == 0) {
      continue;
    }
    final int luma = (299 * data[i] + 587 * data[i + 1] + 114 * data[i + 2]) ~/ 1000;
    histogram[luma.clamp(0, 255)] += 1;
  }
  return histogram;
}

(int, int) _percentileRange(
  Int32List histogram,
  int opaque,
  double lowPercentile,
  double highPercentile,
) {
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
  if (high <= low) {
    high = low + 1;
  }
  return (low, high);
}

Uint8List _stretchLut(int low, int high) {
  final Uint8List lut = Uint8List(256);
  final double span = (high - low).toDouble();
  for (int i = 0; i < 256; i++) {
    final double mapped = (i - low) * 255 / span;
    lut[i] = _clampByte(mapped.round());
  }
  return lut;
}

Uint8List _offsetLut(int delta) {
  final Uint8List lut = Uint8List(256);
  for (int i = 0; i < 256; i++) {
    lut[i] = _clampByte(i + delta);
  }
  return lut;
}

/// 恒等查找表（用作「这个通道不处理」）。
Uint8List _identityLut() {
  final Uint8List lut = Uint8List(256);
  for (int i = 0; i < 256; i++) {
    lut[i] = i;
  }
  return lut;
}

/// 对三个通道应用同一张 LUT，alpha 不动。
RgbaImage _applyLut(RgbaImage image, Uint8List lut) {
  final Uint8List data = image.data;
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
  if (settings.preprocess != PreprocessPreset.none) {
    parts.add(settings.preprocess.label);
  }
  if (settings.brightnessBalance) {
    parts.add('亮度均衡');
  }
  if (settings.brightness != 0) {
    parts.add('亮度 ${formatBrightness(settings.brightness)}');
  }
  if (settings.simplifyColors) {
    parts.add('简化到 ${settings.simplifyColorCount} 色');
  }
  return parts.isEmpty ? '不处理' : parts.join(' · ');
}

/// 把亮度值格式化成短字符串。
String formatBrightness(double value) {
  final int rounded = value.round();
  return rounded > 0 ? '+$rounded' : '$rounded';
}
