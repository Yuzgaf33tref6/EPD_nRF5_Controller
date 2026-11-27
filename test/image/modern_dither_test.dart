import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:epd_controller/image/dither.dart';
import 'package:epd_controller/image/epd_color.dart';
import 'package:epd_controller/image/noise_mask.dart';
import 'package:epd_controller/image/rgba_image.dart';

/// 确定性的渐变测试图（+ 一块纯色避免整张图都在同一亮度）。
RgbaImage buildGradient(int width, int height) {
  final Uint8List data = Uint8List(width * height * 4);
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final int index = (y * width + x) * 4;
      final int luma = ((x + y) * 255) ~/ (width + height);
      data[index] = luma;
      data[index + 1] = luma;
      data[index + 2] = luma;
      data[index + 3] = 255;
    }
  }
  return RgbaImage(width, height, data);
}

/// 纯灰图（每个像素都一样），有序抖动的周期性验证要用它。
RgbaImage buildFlat(int width, int height, int value) {
  final Uint8List data = Uint8List(width * height * 4);
  for (int i = 0; i < width * height; i++) {
    data[i * 4] = value;
    data[i * 4 + 1] = value;
    data[i * 4 + 2] = value;
    data[i * 4 + 3] = 255;
  }
  return RgbaImage(width, height, data);
}

/// 纯彩色平涂图（彩度够大、亮度方差为 0），用来喂自动推荐的判定。
RgbaImage flatColorImage(int width, int height) {
  final Uint8List data = Uint8List(width * height * 4);
  for (int i = 0; i < width * height; i++) {
    data[i * 4] = 150;
    data[i * 4 + 1] = 120;
    data[i * 4 + 2] = 60;
    data[i * 4 + 3] = 255;
  }
  return RgbaImage(width, height, data);
}

List<int> pixelAt(RgbaImage image, int x, int y) {
  final int index = (y * image.width + x) * 4;
  return <int>[
    image.data[index],
    image.data[index + 1],
    image.data[index + 2],
  ];
}

/// 断言整张图的颜色都落在 [mode] 的调色板里。
void expectPaletteOnly(RgbaImage image, EpdColorMode mode) {
  final Set<String> palette = mode.palette
      .map((EpdColor color) => '${color.r},${color.g},${color.b}')
      .toSet();
  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final List<int> pixel = pixelAt(image, x, y);
      expect(
        palette.contains('${pixel[0]},${pixel[1]},${pixel[2]}'),
        isTrue,
        reason: '($x,$y) 的颜色 $pixel 不在调色板里',
      );
    }
  }
}

void main() {
  group('现代误差扩散核', () {
    const List<DitherAlgorithm> modern = <DitherAlgorithm>[
      DitherAlgorithm.sierraLite,
      DitherAlgorithm.burkes,
      DitherAlgorithm.shiauFan,
      DitherAlgorithm.shiauFan2,
    ];

    test('每个新核都只输出调色板颜色，且结果可复现', () {
      for (final DitherAlgorithm algorithm in modern) {
        final RgbaImage first = ditherImage(
          buildGradient(24, 18),
          algorithm,
          1.0,
          EpdColorMode.threeColor,
        );
        final RgbaImage second = ditherImage(
          buildGradient(24, 18),
          algorithm,
          1.0,
          EpdColorMode.threeColor,
        );
        expectPaletteOnly(first, EpdColorMode.threeColor);
        expect(
          first.data,
          equals(second.data),
          reason: '$algorithm 两次结果不一致',
        );
      }
    });

    test('不同核的输出互不相同', () {
      final Map<DitherAlgorithm, List<int>> outputs =
          <DitherAlgorithm, List<int>>{};
      for (final DitherAlgorithm algorithm in modern) {
        outputs[algorithm] = List<int>.of(
          ditherImage(buildGradient(24, 18), algorithm, 1.0,
                  EpdColorMode.threeColor)
              .data,
        );
      }
      expect(outputs[DitherAlgorithm.sierraLite],
          isNot(equals(outputs[DitherAlgorithm.burkes])));
      expect(outputs[DitherAlgorithm.shiauFan],
          isNot(equals(outputs[DitherAlgorithm.shiauFan2])));
    });
  });

  group('蛇形扫描', () {
    test('打开后结果与逐行扫描不同，且仍在调色板内', () {
      final RgbaImage row = ditherImage(
        buildGradient(28, 20),
        DitherAlgorithm.floydSteinberg,
        1.0,
        EpdColorMode.threeColor,
      );
      final RgbaImage snake = ditherImage(
        buildGradient(28, 20),
        DitherAlgorithm.floydSteinberg,
        1.0,
        EpdColorMode.threeColor,
        serpentine: true,
      );
      expectPaletteOnly(snake, EpdColorMode.threeColor);
      expect(snake.data, isNot(equals(row.data)));
    });

    test('新核也支持蛇形扫描', () {
      final RgbaImage row = ditherImage(
        buildGradient(20, 16),
        DitherAlgorithm.burkes,
        1.0,
        EpdColorMode.threeColor,
      );
      final RgbaImage snake = ditherImage(
        buildGradient(20, 16),
        DitherAlgorithm.burkes,
        1.0,
        EpdColorMode.threeColor,
        serpentine: true,
      );
      expectPaletteOnly(snake, EpdColorMode.threeColor);
      expect(snake.data, isNot(equals(row.data)));
    });

    test('有序抖动不受蛇形扫描影响', () {
      final RgbaImage a = ditherImage(
        buildGradient(16, 12),
        DitherAlgorithm.bayer4x4,
        1.0,
        EpdColorMode.threeColor,
      );
      final RgbaImage b = ditherImage(
        buildGradient(16, 12),
        DitherAlgorithm.bayer4x4,
        1.0,
        EpdColorMode.threeColor,
        serpentine: true,
      );
      expect(b.data, equals(a.data));
    });
  });

  group('Bayer 4×4', () {
    test('与 8×8 的结果不同，且只输出调色板颜色', () {
      final RgbaImage bayer4 = ditherImage(
        buildGradient(24, 24),
        DitherAlgorithm.bayer4x4,
        1.0,
        EpdColorMode.threeColor,
      );
      final RgbaImage bayer8 = ditherImage(
        buildGradient(24, 24),
        DitherAlgorithm.bayer,
        1.0,
        EpdColorMode.threeColor,
      );
      expectPaletteOnly(bayer4, EpdColorMode.threeColor);
      expect(bayer4.data, isNot(equals(bayer8.data)));
    });

    test('4×4 矩阵以 4 为周期', () {
      final RgbaImage image = ditherImage(
        buildFlat(8, 8, 128),
        DitherAlgorithm.bayer4x4,
        1.0,
        EpdColorMode.threeColor,
      );
      for (int y = 0; y < 4; y++) {
        for (int x = 0; x < 4; x++) {
          expect(pixelAt(image, x, y), equals(pixelAt(image, x + 4, y)));
          expect(pixelAt(image, x, y), equals(pixelAt(image, x, y + 4)));
        }
      }
    });
  });

  group('蓝噪声', () {
    test('按掩膜平铺取样：纯灰图的输出以掩膜边长为周期', () {
      final Uint8List mask = Uint8List.fromList(<int>[
        0, 255, 64, 192, //
        128, 32, 224, 96, //
        16, 240, 80, 160, //
        208, 48, 176, 112, //
      ]);
      final RgbaImage image = ditherImage(
        buildFlat(16, 16, 128),
        DitherAlgorithm.blueNoise,
        1.0,
        EpdColorMode.threeColor,
        noiseMask: mask,
        noiseMaskEdge: 4,
      );
      expectPaletteOnly(image, EpdColorMode.threeColor);
      for (int y = 0; y < 4; y++) {
        for (int x = 0; x < 4; x++) {
          expect(pixelAt(image, x, y), equals(pixelAt(image, x + 4, y)));
          expect(pixelAt(image, x, y), equals(pixelAt(image, x + 8, y)));
          expect(pixelAt(image, x, y), equals(pixelAt(image, x, y + 4)));
        }
      }
    });

    test('换一张掩膜会得到不同结果', () {
      final RgbaImage a = ditherImage(
        buildGradient(20, 20),
        DitherAlgorithm.blueNoise,
        1.0,
        EpdColorMode.threeColor,
        noiseMask: syntheticNoiseMask(edge: 8),
        noiseMaskEdge: 8,
      );
      final RgbaImage b = ditherImage(
        buildGradient(20, 20),
        DitherAlgorithm.blueNoise,
        1.0,
        EpdColorMode.threeColor,
        noiseMask: syntheticNoiseMask(edge: 16),
        noiseMaskEdge: 16,
      );
      expect(a.data, isNot(equals(b.data)));
    });

    test('没有掩膜时退回确定性散列噪声，不抛异常', () {
      final RgbaImage first = ditherImage(
        buildGradient(20, 20),
        DitherAlgorithm.blueNoise,
        1.0,
        EpdColorMode.threeColor,
      );
      final RgbaImage second = ditherImage(
        buildGradient(20, 20),
        DitherAlgorithm.blueNoise,
        1.0,
        EpdColorMode.threeColor,
      );
      expectPaletteOnly(first, EpdColorMode.threeColor);
      expect(first.data, equals(second.data));
    });
  });

  group('Riemersma 与自动推荐', () {
    test('Hilbert 顺序覆盖每个像素且不重复（含非正方形）', () {
      for (final (int w, int h) in <(int, int)>[(5, 3), (8, 8), (13, 7)]) {
        final List<int> order = hilbertPixelOrder(w, h);
        expect(order.length, w * h, reason: '${w}x$h 应覆盖全部像素');
        expect(order.toSet().length, w * h, reason: '${w}x$h 不应重复');
        expect(order.every((int i) => i >= 0 && i < w * h), isTrue);
      }
      expect(hilbertPixelOrder(0, 5), isEmpty);
    });

    test('Riemersma 只输出调色板颜色且可复现', () {
      final RgbaImage first = ditherImage(
        buildGradient(24, 18),
        DitherAlgorithm.riemersma,
        1.0,
        EpdColorMode.threeColor,
      );
      final RgbaImage second = ditherImage(
        buildGradient(24, 18),
        DitherAlgorithm.riemersma,
        1.0,
        EpdColorMode.threeColor,
      );
      expectPaletteOnly(first, EpdColorMode.threeColor);
      expect(first.data, equals(second.data));
    });

    test('Riemersma 与 Floyd 结果不同（不是换名的同一算法）', () {
      final RgbaImage riemersma = ditherImage(
        buildGradient(20, 16),
        DitherAlgorithm.riemersma,
        1.0,
        EpdColorMode.blackWhiteColor,
      );
      final RgbaImage floyd = ditherImage(
        buildGradient(20, 16),
        DitherAlgorithm.floydSteinberg,
        1.0,
        EpdColorMode.blackWhiteColor,
      );
      expect(riemersma.data, isNot(equals(floyd.data)));
    });

    test('自动推荐按内容挑算法', () {
      // 纯灰 → 蓝噪声
      expect(
        resolveAutoAlgorithm(buildGradient(16, 16)),
        DitherAlgorithm.blueNoise,
      );

      // 高对比彩色（暗蓝 / 亮黄两色，彩度大、亮度跨度大）→ Shiau-Fan
      final RgbaImage highContrast = RgbaImage(16, 16);
      for (int i = 0; i < 16 * 16; i++) {
        final bool dark = i % 2 == 0;
        highContrast.data[i * 4] = dark ? 0 : 250;
        highContrast.data[i * 4 + 1] = dark ? 0 : 250;
        highContrast.data[i * 4 + 2] = dark ? 120 : 80;
        highContrast.data[i * 4 + 3] = 255;
      }
      expect(resolveAutoAlgorithm(highContrast), DitherAlgorithm.shiauFan);

      // 大幅彩色照片（400×320 = 12.8 万像素）→ Burkes
      expect(
        resolveAutoAlgorithm(flatColorImage(400, 320)),
        DitherAlgorithm.burkes,
      );

      // 小尺寸彩色图 → Riemersma
      expect(
        resolveAutoAlgorithm(flatColorImage(40, 30)),
        DitherAlgorithm.riemersma,
      );

      // 全透明图有兜底
      expect(
        resolveAutoAlgorithm(RgbaImage(1, 1)),
        DitherAlgorithm.floydSteinberg,
      );
    });

    test('选自动推荐时输出与它挑中的算法完全一致', () {
      final RgbaImage auto = ditherImage(
        buildGradient(20, 16),
        DitherAlgorithm.auto,
        1.0,
        EpdColorMode.threeColor,
      );
      final RgbaImage picked = ditherImage(
        buildGradient(20, 16),
        resolveAutoAlgorithm(buildGradient(20, 16)),
        1.0,
        EpdColorMode.threeColor,
      );
      expect(auto.data, equals(picked.data));
    });
  });

  group('噪声工具', () {
    test('syntheticNoiseMask 尺寸正确且可复现', () {
      final Uint8List mask = syntheticNoiseMask(edge: 8);
      expect(mask.length, 64);
      expect(mask, equals(syntheticNoiseMask(edge: 8)));
      // 散列阈值不应全同一个值（否则等于没抖动）
      expect(mask.toSet().length, greaterThan(8));
    });

    test('squareEdgeOf 能认出平方数，非平方退回默认 64', () {
      expect(squareEdgeOf(Uint8List(4096)), 64);
      expect(squareEdgeOf(Uint8List(64)), 8);
      expect(squareEdgeOf(Uint8List(4100)), kBlueNoiseTextureEdge);
      expect(squareEdgeOf(Uint8List(0)), kBlueNoiseTextureEdge);
    });

    test('内置蓝噪声纹理能解码成 64×64、分布接近均匀', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final ByteData data = await rootBundle.load(kBlueNoiseAsset);
      final Uint8List? mask = await decodeNoiseMask(data.buffer.asUint8List());
      expect(mask, isNotNull);
      expect(mask!.length, 4096);
      expect(squareEdgeOf(mask), 64);

      // 8 个 32 级桶应大致均匀（每桶 512 个），否则说明取错了通道或图不是噪声图。
      final List<int> buckets = List<int>.filled(8, 0);
      for (final int value in mask) {
        buckets[value ~/ 32]++;
      }
      for (final int count in buckets) {
        expect(count, greaterThan(400));
        expect(count, lessThan(700));
      }
    });
  });
}
