/// 抖动（dithering）与调色板量化。
///
/// 移植自 web 上位机的 `html/js/dithering.js`。为了保证 Android 端渲染结果与
/// web 版**逐字节一致**，这里的实现刻意保留了 JS 的循环结构、误差扩散顺序和
/// 数值运算顺序（包括 `Uint8ClampedArray` 的舍入语义），不要为了"写法更漂亮"
/// 而重排运算，否则个别像素会偏 1。
library;

import 'dart:typed_data';

import 'color_space.dart';
import 'epd_color.dart';
import 'rgba_image.dart';

/// JS `Uint8ClampedArray` 的赋值语义：先夹到 0-255，再就近取整，恰好 .5 时取偶数。
///
/// Dart 的 `double.round()` 是 `.5` 远离零取整（2.5 -> 3），与 JS 不同（2.5 -> 2），
/// 误差扩散里大量出现 x.5 附近的中间值，所以必须自己实现。
int _toUint8Clamp(num value) {
  final double v = value.toDouble();
  if (v.isNaN || v <= 0) {
    return 0;
  }
  if (v >= 255) {
    return 255;
  }
  final int floor = v.floor();
  final double fraction = v - floor;
  if (fraction > 0.5) {
    return floor + 1;
  }
  if (fraction < 0.5) {
    return floor;
  }
  return floor.isEven ? floor : floor + 1;
}

/// 把一个像素的 RGB 三个通道同时加上扩散误差（等价于 JS 里连续三次
/// `Math.min(255, Math.max(0, temp[i] + delta))` 赋值给 Uint8ClampedArray）。
void _spread(Uint8List temp, int index, double deltaR, double deltaG, double deltaB) {
  temp[index] = _toUint8Clamp(temp[index] + deltaR);
  temp[index + 1] = _toUint8Clamp(temp[index + 1] + deltaG);
  temp[index + 2] = _toUint8Clamp(temp[index + 2] + deltaB);
}

/// 各模式调色板的 Lab 值缓存。
///
/// 调色板颜色是常量，Lab 转换结果也恒定；`findClosestColor` 每处理一个像素都要
/// 跟整张调色板比一次，把调色板的 Lab 预先算好能把每像素的 `rgbToLab` 次数从
/// 「1 + 调色板大小」降到 1 —— 在 400×300 的图上就是 72 万次浮点幂运算的差别，
/// 直接决定了画布页会不会卡。数值结果与现算完全一致。
final Map<EpdColorMode, List<LabColor>> _paletteLabCache =
    <EpdColorMode, List<LabColor>>{};

List<LabColor> _paletteLab(EpdColorMode mode) {
  return _paletteLabCache.putIfAbsent(mode, () {
    return <LabColor>[
      for (final EpdColor color in mode.palette)
        rgbToLab(color.r, color.g, color.b),
    ];
  });
}

/// 在指定调色板里找 Lab 空间距离最近的颜色。
///
/// [r] [g] [b] 允许是小数：Bayer 抖动会把阈值加到原始颜色上再量化，
/// web 版同样把小数传进来比较。
EpdColor findClosestColor(num r, num g, num b, EpdColorMode mode) {
  final List<EpdColor> palette = mode.palette;

  // 蓝色特殊情况（仅限非三色、四色模式）。这段特判来自 web 版，看起来是为了
  // 避免暗淡的蓝色被 Lab 距离判成黑色，行为必须保留。
  if (mode != EpdColorMode.fourColor &&
      mode != EpdColorMode.threeColor &&
      r < 50 &&
      g < 150 &&
      b > 100) {
    return rgbPalette[4];
  }

  final LabColor inputLab = rgbToLab(r, g, b);
  final List<LabColor> paletteLab = _paletteLab(mode);
  double minDistance = double.infinity;
  EpdColor closest = palette.first;

  for (int i = 0; i < palette.length; i++) {
    final double distance = labDistance(inputLab, paletteLab[i]);
    if (distance < minDistance) {
      minDistance = distance;
      closest = palette[i];
    }
  }

  return closest;
}

/// 支持的抖动算法。
///
/// 前 5 个是 web 版（老上位机）自带、已逐字节对拍的算法；其余是 0.3.0 新增的
/// 「现代抖动」，用来解决老算法在照片上容易出现斜纹/色块的问题。
enum DitherAlgorithm {
  floydSteinberg('floydSteinberg'),
  atkinson('atkinson'),
  stucki('stucki'),
  jarvis('jarvis'),
  bayer('bayer'),

  // ---- 0.3.0 新增：误差扩散补全 ----

  /// Sierra Lite（也叫 Sierra-2-4A），核 `2 / 1 1`，除数 4，速度快、
  /// 边缘比 Floyd 干净一点。
  sierraLite('sierraLite'),

  /// Burkes，除数 32，两行核，颗粒比 Stucki 稍大、条纹更少。
  burkes('burkes'),

  /// Shiau-Fan，除数 8，核偏右，适合文字/线条类图像。
  shiauFan('shiauFan'),

  /// Shiau-Fan 2，除数 14，扩散更集中，暗部颗粒更细。
  shiauFan2('shiauFan2'),

  // ---- 0.3.0 新增：有序抖动 ----

  /// 4×4 Bayer（16 级），比 8×8 的网点更大更"复古"。
  bayer4x4('bayer4x4'),

  /// 蓝噪声有序抖动：用 64×64 蓝噪声掩膜当阈值，肉眼看不到规则网格，
  /// 是目前公认观感最好的一种有序抖动。
  blueNoise('blueNoise'),

  /// 不做抖动，直接量化。
  none('none');

  const DitherAlgorithm(this.jsName);

  /// web 版使用的算法名字符串，保留用于对拍测试和日志。
  final String jsName;

  /// 由 web 版字符串还原算法，找不到时抛 [ArgumentError]。
  static DitherAlgorithm fromJsName(String name) {
    for (final DitherAlgorithm alg in DitherAlgorithm.values) {
      if (alg.jsName == name) {
        return alg;
      }
    }
    throw ArgumentError.value(name, 'name', '未知的抖动算法');
  }
}

/// 按 web 版的语义就地修改 [image] 并返回它。
///
/// [strength] 是误差强度（web 版默认 1.0），[mode] 决定量化到哪个调色板。
/// `none` 时不做任何处理，直接返回原图。
///
/// [serpentine] 只对误差扩散类算法有效：奇数行反向扫描，能明显减少
/// 「从左往右刷」留下的斜向纹路。[noiseMask] 只对 [DitherAlgorithm.blueNoise]
/// 有效，是 64×64（或 [noiseMaskEdge] 见方）的蓝噪声阈值表。
RgbaImage ditherImage(
  RgbaImage image,
  DitherAlgorithm algorithm,
  double strength,
  EpdColorMode mode, {
  bool serpentine = false,
  Uint8List? noiseMask,
  int noiseMaskEdge = kBlueNoiseEdge,
}) {
  // 误差扩散：蛇形扫描时统一走通用扩散引擎（老算法优先保留逐行版本，
  // 因为它是和 web 版逐字节对拍的基准，不能动）。
  final List<DiffusionTap>? taps = _diffusionKernels[algorithm];
  if (taps != null) {
    if (serpentine) {
      return _diffuse(image, strength, mode, taps, serpentine: true);
    }
    switch (algorithm) {
      case DitherAlgorithm.floydSteinberg:
        return _floydSteinberg(image, strength, mode);
      case DitherAlgorithm.atkinson:
        return _atkinson(image, strength, mode);
      case DitherAlgorithm.stucki:
        return _stucki(image, strength, mode);
      case DitherAlgorithm.jarvis:
        return _jarvis(image, strength, mode);
      default:
        return _diffuse(image, strength, mode, taps, serpentine: false);
    }
  }

  switch (algorithm) {
    case DitherAlgorithm.bayer:
      return _bayer(image, strength, mode);
    case DitherAlgorithm.bayer4x4:
      return _applyOrdered(image, strength, mode, (int x, int y) {
        return (_bayerMatrix4[y % 4][x % 4] / 16) * 255;
      });
    case DitherAlgorithm.blueNoise:
      return _applyOrdered(image, strength, mode, (int x, int y) {
        final int edge = noiseMaskEdge > 0 ? noiseMaskEdge : kBlueNoiseEdge;
        final int threshold = _noiseThreshold(noiseMask, edge, x, y);
        return threshold.toDouble();
      });
    case DitherAlgorithm.none:
      return image;
    default:
      return image;
  }
}

/// 对比度调整：`(c - 128) * factor + 128` 后夹到 0-255，不改动 Alpha。
RgbaImage adjustContrast(RgbaImage image, double factor) {
  final Uint8List data = image.data;
  for (int i = 0; i < data.length; i += 4) {
    data[i] = _toUint8Clamp((data[i] - 128) * factor + 128);
    data[i + 1] = _toUint8Clamp((data[i + 1] - 128) * factor + 128);
    data[i + 2] = _toUint8Clamp((data[i + 2] - 128) * factor + 128);
  }
  return image;
}

/// Floyd-Steinberg：右 7/16、左下 3/16、下 5/16、右下 1/16。
///
/// 与 web 版一致分两遍：第一遍只往 temp 扩散误差，第二遍再用 temp 的最终值量化。
RgbaImage _floydSteinberg(RgbaImage image, double strength, EpdColorMode mode) {
  final int width = image.width;
  final int height = image.height;
  final Uint8List data = image.data;
  final Uint8List temp = Uint8List.fromList(data);

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final int idx = (y * width + x) * 4;
      final int r = temp[idx];
      final int g = temp[idx + 1];
      final int b = temp[idx + 2];

      final EpdColor closest = findClosestColor(r, g, b, mode);

      final double errR = (r - closest.r) * strength;
      final double errG = (g - closest.g) * strength;
      final double errB = (b - closest.b) * strength;

      if (x + 1 < width) {
        _spread(temp, idx + 4, errR * 7 / 16, errG * 7 / 16, errB * 7 / 16);
      }
      if (y + 1 < height) {
        if (x > 0) {
          _spread(temp, idx + width * 4 - 4, errR * 3 / 16, errG * 3 / 16,
              errB * 3 / 16);
        }
        _spread(temp, idx + width * 4, errR * 5 / 16, errG * 5 / 16,
            errB * 5 / 16);
        if (x + 1 < width) {
          _spread(temp, idx + width * 4 + 4, errR * 1 / 16, errG * 1 / 16,
              errB * 1 / 16);
        }
      }
    }
  }

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final int idx = (y * width + x) * 4;
      final EpdColor closest =
          findClosestColor(temp[idx], temp[idx + 1], temp[idx + 2], mode);
      data[idx] = closest.r;
      data[idx + 1] = closest.g;
      data[idx + 2] = closest.b;
    }
  }

  return image;
}

/// Atkinson：每个邻居各 1/8，扩散到右、右二、左下、下、右下、下二。
///
/// 与 web 版一致：在第一遍里同时写入量化结果。
RgbaImage _atkinson(RgbaImage image, double strength, EpdColorMode mode) {
  final int width = image.width;
  final int height = image.height;
  final Uint8List data = image.data;
  final Uint8List temp = Uint8List.fromList(data);

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final int idx = (y * width + x) * 4;
      final int r = temp[idx];
      final int g = temp[idx + 1];
      final int b = temp[idx + 2];

      final EpdColor closest = findClosestColor(r, g, b, mode);

      data[idx] = closest.r;
      data[idx + 1] = closest.g;
      data[idx + 2] = closest.b;

      final double errR = (r - closest.r) * strength;
      final double errG = (g - closest.g) * strength;
      final double errB = (b - closest.b) * strength;

      const double fraction = 1 / 8;

      if (x + 1 < width) {
        _spread(temp, idx + 4, errR * fraction, errG * fraction,
            errB * fraction);
      }
      if (x + 2 < width) {
        _spread(temp, idx + 8, errR * fraction, errG * fraction,
            errB * fraction);
      }
      if (y + 1 < height) {
        if (x > 0) {
          _spread(temp, idx + width * 4 - 4, errR * fraction, errG * fraction,
              errB * fraction);
        }
        _spread(temp, idx + width * 4, errR * fraction, errG * fraction,
            errB * fraction);
        if (x + 1 < width) {
          _spread(temp, idx + width * 4 + 4, errR * fraction, errG * fraction,
              errB * fraction);
        }
      }
      if (y + 2 < height) {
        _spread(temp, idx + width * 8, errR * fraction, errG * fraction,
            errB * fraction);
      }
    }
  }

  return image;
}

/// Stucki：除数 42，三行扩散核
/// `8 4 / 2 4 8 4 2 / 1 2 4 2 1`，与 web 版一样两遍式。
RgbaImage _stucki(RgbaImage image, double strength, EpdColorMode mode) {
  final int width = image.width;
  final int height = image.height;
  final Uint8List data = image.data;
  final Uint8List temp = Uint8List.fromList(data);

  const double divisor = 42;

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final int idx = (y * width + x) * 4;
      final int r = temp[idx];
      final int g = temp[idx + 1];
      final int b = temp[idx + 2];

      final EpdColor closest = findClosestColor(r, g, b, mode);

      final double errR = (r - closest.r) * strength;
      final double errG = (g - closest.g) * strength;
      final double errB = (b - closest.b) * strength;

      if (x + 1 < width) {
        _spread(temp, idx + 4, errR * 8 / divisor, errG * 8 / divisor,
            errB * 8 / divisor);
      }
      if (x + 2 < width) {
        _spread(temp, idx + 8, errR * 4 / divisor, errG * 4 / divisor,
            errB * 4 / divisor);
      }
      if (y + 1 < height) {
        if (x > 1) {
          _spread(temp, idx + width * 4 - 8, errR * 2 / divisor,
              errG * 2 / divisor, errB * 2 / divisor);
        }
        if (x > 0) {
          _spread(temp, idx + width * 4 - 4, errR * 4 / divisor,
              errG * 4 / divisor, errB * 4 / divisor);
        }
        _spread(temp, idx + width * 4, errR * 8 / divisor, errG * 8 / divisor,
            errB * 8 / divisor);
        if (x + 1 < width) {
          _spread(temp, idx + width * 4 + 4, errR * 4 / divisor,
              errG * 4 / divisor, errB * 4 / divisor);
        }
        if (x + 2 < width) {
          _spread(temp, idx + width * 4 + 8, errR * 2 / divisor,
              errG * 2 / divisor, errB * 2 / divisor);
        }
      }
      if (y + 2 < height) {
        if (x > 1) {
          _spread(temp, idx + width * 8 - 8, errR * 1 / divisor,
              errG * 1 / divisor, errB * 1 / divisor);
        }
        if (x > 0) {
          _spread(temp, idx + width * 8 - 4, errR * 2 / divisor,
              errG * 2 / divisor, errB * 2 / divisor);
        }
        _spread(temp, idx + width * 8, errR * 4 / divisor, errG * 4 / divisor,
            errB * 4 / divisor);
        if (x + 1 < width) {
          _spread(temp, idx + width * 8 + 4, errR * 2 / divisor,
              errG * 2 / divisor, errB * 2 / divisor);
        }
        if (x + 2 < width) {
          _spread(temp, idx + width * 8 + 8, errR * 1 / divisor,
              errG * 1 / divisor, errB * 1 / divisor);
        }
      }
    }
  }

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final int idx = (y * width + x) * 4;
      final EpdColor closest =
          findClosestColor(temp[idx], temp[idx + 1], temp[idx + 2], mode);
      data[idx] = closest.r;
      data[idx + 1] = closest.g;
      data[idx + 2] = closest.b;
    }
  }

  return image;
}

/// Jarvis-Judice-Ninke：除数 48，三行扩散核
/// `7 5 / 3 5 7 5 3 / 1 3 5 3 1`，与 web 版一样在第一遍里写量化结果。
RgbaImage _jarvis(RgbaImage image, double strength, EpdColorMode mode) {
  final int width = image.width;
  final int height = image.height;
  final Uint8List data = image.data;
  final Uint8List temp = Uint8List.fromList(data);

  const double divisor = 48;

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final int idx = (y * width + x) * 4;
      final int r = temp[idx];
      final int g = temp[idx + 1];
      final int b = temp[idx + 2];

      final EpdColor closest = findClosestColor(r, g, b, mode);

      data[idx] = closest.r;
      data[idx + 1] = closest.g;
      data[idx + 2] = closest.b;

      final double errR = (r - closest.r) * strength;
      final double errG = (g - closest.g) * strength;
      final double errB = (b - closest.b) * strength;

      if (x + 1 < width) {
        _spread(temp, idx + 4, errR * 7 / divisor, errG * 7 / divisor,
            errB * 7 / divisor);
      }
      if (x + 2 < width) {
        _spread(temp, idx + 8, errR * 5 / divisor, errG * 5 / divisor,
            errB * 5 / divisor);
      }
      if (y + 1 < height) {
        if (x > 1) {
          _spread(temp, idx + width * 4 - 8, errR * 3 / divisor,
              errG * 3 / divisor, errB * 3 / divisor);
        }
        if (x > 0) {
          _spread(temp, idx + width * 4 - 4, errR * 5 / divisor,
              errG * 5 / divisor, errB * 5 / divisor);
        }
        _spread(temp, idx + width * 4, errR * 7 / divisor, errG * 7 / divisor,
            errB * 7 / divisor);
        if (x + 1 < width) {
          _spread(temp, idx + width * 4 + 4, errR * 5 / divisor,
              errG * 5 / divisor, errB * 5 / divisor);
        }
        if (x + 2 < width) {
          _spread(temp, idx + width * 4 + 8, errR * 3 / divisor,
              errG * 3 / divisor, errB * 3 / divisor);
        }
      }
      if (y + 2 < height) {
        if (x > 1) {
          _spread(temp, idx + width * 8 - 8, errR * 1 / divisor,
              errG * 1 / divisor, errB * 1 / divisor);
        }
        if (x > 0) {
          _spread(temp, idx + width * 8 - 4, errR * 3 / divisor,
              errG * 3 / divisor, errB * 3 / divisor);
        }
        _spread(temp, idx + width * 8, errR * 5 / divisor, errG * 5 / divisor,
            errB * 5 / divisor);
        if (x + 1 < width) {
          _spread(temp, idx + width * 8 + 4, errR * 3 / divisor,
              errG * 3 / divisor, errB * 3 / divisor);
        }
        if (x + 2 < width) {
          _spread(temp, idx + width * 8 + 8, errR * 1 / divisor,
              errG * 1 / divisor, errB * 1 / divisor);
        }
      }
    }
  }

  return image;
}

/// 8x8 Bayer 有序抖动矩阵。
const List<List<int>> _bayerMatrix = <List<int>>[
  <int>[0, 32, 8, 40, 2, 34, 10, 42],
  <int>[48, 16, 56, 24, 50, 18, 58, 26],
  <int>[12, 44, 4, 36, 14, 46, 6, 38],
  <int>[60, 28, 52, 20, 62, 30, 54, 22],
  <int>[3, 35, 11, 43, 1, 33, 9, 41],
  <int>[51, 19, 59, 27, 49, 17, 57, 25],
  <int>[15, 47, 7, 39, 13, 45, 5, 37],
  <int>[63, 31, 55, 23, 61, 29, 53, 21],
];

/// Bayer 有序抖动：按矩阵阈值偏移后再量化，不做误差扩散。
RgbaImage _bayer(RgbaImage image, double strength, EpdColorMode mode) {
  final int width = image.width;
  final int height = image.height;
  final Uint8List data = image.data;

  const int matrixSize = 8;
  const int maxThreshold = 64;

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final int idx = (y * width + x) * 4;

      final double threshold =
          (_bayerMatrix[y % matrixSize][x % matrixSize] / maxThreshold) * 255;

      final double offset = (threshold - 127.5) * strength;
      final double adjustedR =
          (data[idx] + offset).clamp(0.0, 255.0).toDouble();
      final double adjustedG =
          (data[idx + 1] + offset).clamp(0.0, 255.0).toDouble();
      final double adjustedB =
          (data[idx + 2] + offset).clamp(0.0, 255.0).toDouble();

      final EpdColor closest =
          findClosestColor(adjustedR, adjustedG, adjustedB, mode);

      data[idx] = closest.r;
      data[idx + 1] = closest.g;
      data[idx + 2] = closest.b;
    }
  }

  return image;
}

// ============ 0.3.0 新增：通用误差扩散引擎 / 有序抖动 / 蓝噪声 ============

/// 蓝噪声掩膜的标准边长（内置资产是 64×64）。
const int kBlueNoiseEdge = 64;

/// 误差扩散核里的一个抽样点：相对当前像素的偏移与权重。
class DiffusionTap {
  const DiffusionTap(this.dx, this.dy, this.factor);

  /// 列偏移（正数 = 右边）。蛇形扫描时会被镜像。
  final int dx;

  /// 行偏移（0 = 本行，1 = 下一行）。
  final int dy;

  /// 权重（已经除过除数，直接乘误差即可）。
  final double factor;
}

/// 各误差扩散算法的核。
///
/// 数值取自经典文献（Floyd–Steinberg / Atkinson / Stucki / Jarvis / Burkes /
/// Sierra Lite / Shiau-Fan），与 epdoptimize（Apache-2.0）里的同名核一致，
/// 便于和 InkTag 那套参数对照。
const Map<DitherAlgorithm, List<DiffusionTap>> _diffusionKernels =
    <DitherAlgorithm, List<DiffusionTap>>{
  DitherAlgorithm.floydSteinberg: <DiffusionTap>[
    DiffusionTap(1, 0, 7 / 16),
    DiffusionTap(-1, 1, 3 / 16),
    DiffusionTap(0, 1, 5 / 16),
    DiffusionTap(1, 1, 1 / 16),
  ],
  DitherAlgorithm.atkinson: <DiffusionTap>[
    DiffusionTap(1, 0, 1 / 8),
    DiffusionTap(2, 0, 1 / 8),
    DiffusionTap(-1, 1, 1 / 8),
    DiffusionTap(0, 1, 1 / 8),
    DiffusionTap(1, 1, 1 / 8),
    DiffusionTap(0, 2, 1 / 8),
  ],
  DitherAlgorithm.stucki: <DiffusionTap>[
    DiffusionTap(1, 0, 8 / 42),
    DiffusionTap(2, 0, 4 / 42),
    DiffusionTap(-2, 1, 2 / 42),
    DiffusionTap(-1, 1, 4 / 42),
    DiffusionTap(0, 1, 8 / 42),
    DiffusionTap(1, 1, 4 / 42),
    DiffusionTap(2, 1, 2 / 42),
    DiffusionTap(-2, 2, 1 / 42),
    DiffusionTap(-1, 2, 2 / 42),
    DiffusionTap(0, 2, 4 / 42),
    DiffusionTap(1, 2, 2 / 42),
    DiffusionTap(2, 2, 1 / 42),
  ],
  DitherAlgorithm.jarvis: <DiffusionTap>[
    DiffusionTap(1, 0, 7 / 48),
    DiffusionTap(2, 0, 5 / 48),
    DiffusionTap(-2, 1, 3 / 48),
    DiffusionTap(-1, 1, 5 / 48),
    DiffusionTap(0, 1, 7 / 48),
    DiffusionTap(1, 1, 5 / 48),
    DiffusionTap(2, 1, 3 / 48),
    DiffusionTap(-2, 2, 1 / 48),
    DiffusionTap(-1, 2, 3 / 48),
    DiffusionTap(0, 2, 5 / 48),
    DiffusionTap(1, 2, 3 / 48),
    DiffusionTap(2, 2, 1 / 48),
  ],
  DitherAlgorithm.sierraLite: <DiffusionTap>[
    DiffusionTap(1, 0, 2 / 4),
    DiffusionTap(-1, 1, 1 / 4),
    DiffusionTap(0, 1, 1 / 4),
  ],
  DitherAlgorithm.burkes: <DiffusionTap>[
    DiffusionTap(1, 0, 8 / 32),
    DiffusionTap(2, 0, 4 / 32),
    DiffusionTap(-2, 1, 2 / 32),
    DiffusionTap(-1, 1, 4 / 32),
    DiffusionTap(0, 1, 8 / 32),
    DiffusionTap(1, 1, 4 / 32),
    DiffusionTap(2, 1, 2 / 32),
  ],
  DitherAlgorithm.shiauFan: <DiffusionTap>[
    DiffusionTap(1, 0, 4 / 8),
    DiffusionTap(-2, 1, 1 / 8),
    DiffusionTap(-1, 1, 1 / 8),
    DiffusionTap(0, 1, 2 / 8),
  ],
  DitherAlgorithm.shiauFan2: <DiffusionTap>[
    DiffusionTap(1, 0, 7 / 14),
    DiffusionTap(-3, 1, 1 / 14),
    DiffusionTap(-2, 1, 1 / 14),
    DiffusionTap(-1, 1, 1 / 14),
    DiffusionTap(0, 1, 3 / 14),
  ],
};

/// 4×4 Bayer 矩阵（16 级）。
const List<List<int>> _bayerMatrix4 = <List<int>>[
  <int>[0, 8, 2, 10],
  <int>[12, 4, 14, 6],
  <int>[3, 11, 1, 9],
  <int>[15, 7, 13, 5],
];

/// 通用误差扩散引擎。
///
/// [serpentine] 为真时奇数行反向扫描、并镜像核的列偏移，能打散斜向纹路。
RgbaImage _diffuse(
  RgbaImage image,
  double strength,
  EpdColorMode mode,
  List<DiffusionTap> taps, {
  required bool serpentine,
}) {
  final int width = image.width;
  final int height = image.height;
  final Uint8List data = image.data;
  final Uint8List temp = Uint8List.fromList(data);

  for (int y = 0; y < height; y++) {
    final bool leftToRight = !serpentine || y.isEven;
    for (int step = 0; step < width; step++) {
      final int x = leftToRight ? step : width - 1 - step;
      final int idx = (y * width + x) * 4;

      final int r = temp[idx];
      final int g = temp[idx + 1];
      final int b = temp[idx + 2];

      final EpdColor closest = findClosestColor(r, g, b, mode);

      data[idx] = closest.r;
      data[idx + 1] = closest.g;
      data[idx + 2] = closest.b;

      final double errR = (r - closest.r) * strength;
      final double errG = (g - closest.g) * strength;
      final double errB = (b - closest.b) * strength;

      for (final DiffusionTap tap in taps) {
        final int tx = x + (leftToRight ? tap.dx : -tap.dx);
        final int ty = y + tap.dy;
        if (tx < 0 || tx >= width || ty < 0 || ty >= height) {
          continue;
        }
        _spread(
          temp,
          (ty * width + tx) * 4,
          errR * tap.factor,
          errG * tap.factor,
          errB * tap.factor,
        );
      }
    }
  }

  return image;
}

/// 按「给每个像素一个阈值」的方式做有序抖动（Bayer / 蓝噪声共用）。
RgbaImage _applyOrdered(
  RgbaImage image,
  double strength,
  EpdColorMode mode,
  double Function(int x, int y) thresholdAt,
) {
  final int width = image.width;
  final int height = image.height;
  final Uint8List data = image.data;

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final int idx = (y * width + x) * 4;
      final double offset = (thresholdAt(x, y) - 127.5) * strength;
      final double r = (data[idx] + offset).clamp(0.0, 255.0).toDouble();
      final double g = (data[idx + 1] + offset).clamp(0.0, 255.0).toDouble();
      final double b = (data[idx + 2] + offset).clamp(0.0, 255.0).toDouble();

      final EpdColor closest = findClosestColor(r, g, b, mode);

      data[idx] = closest.r;
      data[idx + 1] = closest.g;
      data[idx + 2] = closest.b;
    }
  }

  return image;
}

/// 取蓝噪声阈值。
///
/// [mask] 为 null 时（资产还没加载好）退回确定性的散列阈值：画面会比真蓝噪声
/// 略差，但至少能用，不会抛异常打断预览。
int _noiseThreshold(Uint8List? mask, int edge, int x, int y) {
  if (mask == null) {
    int h = x * 374761393 + y * 668265263;
    h = (h ^ (h >> 13)) * 1274126177;
    return (h ^ (h >> 16)) & 0xff;
  }
  final int index = (y % edge) * edge + (x % edge);
  return index < mask.length ? mask[index] : 127;
}

/// 生成一张确定性的「伪蓝噪声」掩膜，给测试和资产缺失时兜底用。
Uint8List syntheticNoiseMask({int edge = kBlueNoiseEdge}) {
  final int size = edge > 0 ? edge : kBlueNoiseEdge;
  final Uint8List mask = Uint8List(size * size);
  for (int i = 0; i < mask.length; i++) {
    mask[i] = _noiseThreshold(null, size, i % size, i ~/ size);
  }
  return mask;
}
