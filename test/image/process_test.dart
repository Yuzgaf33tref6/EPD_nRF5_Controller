import 'dart:typed_data';

import 'package:epd_controller/image/process.dart';
import 'package:epd_controller/image/rgba_image.dart';
import 'package:flutter_test/flutter_test.dart';

/// 造一张图，像素值由 [pixel] 给出。
RgbaImage buildImage(
  int width,
  int height,
  List<int> Function(int x, int y) pixel,
) {
  final Uint8List data = Uint8List(width * height * 4);
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final int i = (y * width + x) * 4;
      final List<int> rgba = pixel(x, y);
      data[i] = rgba[0];
      data[i + 1] = rgba[1];
      data[i + 2] = rgba[2];
      data[i + 3] = rgba.length > 3 ? rgba[3] : 255;
    }
  }
  return RgbaImage(width, height, data);
}

/// 灰阶图：第 i 个像素的灰度取灰度值列表里的第 i 个。
RgbaImage grayStrip(List<int> values) {
  return buildImage(values.length, 1, (int x, int y) {
    final int v = values[x];
    return <int>[v, v, v, 255];
  });
}

List<int> pixelAt(RgbaImage image, int x, int y) {
  final int i = (y * image.width + x) * 4;
  return <int>[
    image.data[i],
    image.data[i + 1],
    image.data[i + 2],
    image.data[i + 3],
  ];
}

Set<int> distinctColors(RgbaImage image) {
  final Set<int> colors = <int>{};
  for (int i = 0; i < image.data.length; i += 4) {
    colors.add(
      (image.data[i] << 16) | (image.data[i + 1] << 8) | image.data[i + 2],
    );
  }
  return colors;
}

void main() {
  group('applyBrightness', () {
    test('按 -100~100 映射到 ±255 的加法', () {
      final RgbaImage image = buildImage(1, 1, (int x, int y) => <int>[10, 20, 30]);
      final RgbaImage out = applyBrightness(image, 10);
      // delta = round(10 * 255 / 100) = 26
      expect(pixelAt(out, 0, 0), <int>[36, 46, 56, 255]);
    });

    test('负数变暗，最低夹到 0', () {
      final RgbaImage image = buildImage(1, 1, (int x, int y) => <int>[10, 120, 200]);
      final RgbaImage out = applyBrightness(image, -50);
      // delta = round(-127.5) = -128
      expect(pixelAt(out, 0, 0), <int>[0, 0, 72, 255]);
    });

    test('超过上限时夹到 255', () {
      final RgbaImage image = buildImage(1, 1, (int x, int y) => <int>[250, 10, 0]);
      final RgbaImage out = applyBrightness(image, 100);
      expect(pixelAt(out, 0, 0), <int>[255, 255, 255, 255]);
    });

    test('不改变 alpha', () {
      final RgbaImage image = buildImage(1, 1, (int x, int y) => <int>[100, 100, 100, 7]);
      final RgbaImage out = applyBrightness(image, 20);
      expect(out.data[3], 7);
    });

    test('amount 为 0 时返回等值的副本', () {
      final RgbaImage image = grayStrip(<int>[10, 20, 30]);
      final RgbaImage out = applyBrightness(image, 0);
      expect(out, isNot(same(image)));
      expect(out.data, equals(image.data));
    });
  });

  group('applyAutoBrightness', () {
    test('把黑白点拉伸到 0 和 255', () {
      final RgbaImage image = grayStrip(<int>[100, 120, 140, 160]);
      final RgbaImage out = applyAutoBrightness(image);
      expect(pixelAt(out, 0, 0)[0], 0);
      expect(pixelAt(out, 1, 0)[0], 85); // (120-100)*255/60 = 85
      expect(pixelAt(out, 2, 0)[0], 170);
      expect(pixelAt(out, 3, 0)[0], 255);
    });

    test('动态范围已满时不做改动', () {
      final RgbaImage image = grayStrip(<int>[0, 128, 255]);
      final RgbaImage out = applyAutoBrightness(image);
      expect(out.data, equals(image.data));
    });

    test('接近纯色时不拉伸（避免把纯色弄成噪声）', () {
      final RgbaImage image = grayStrip(<int>[120, 122, 124]);
      final RgbaImage out = applyAutoBrightness(image);
      expect(out.data, equals(image.data));
    });

    test('三通道共用同一张 LUT，灰色仍是灰色', () {
      // 灰阶 100~160 + 一个彩色像素；拉伸后灰色像素必须 r==g==b。
      final RgbaImage image = buildImage(3, 1, (int x, int y) {
        return switch (x) {
          0 => <int>[100, 100, 100],
          1 => <int>[160, 160, 160],
          _ => <int>[160, 100, 60],
        };
      });
      final RgbaImage out = applyAutoBrightness(image);
      for (int x = 0; x < 2; x++) {
        final List<int> p = pixelAt(out, x, 0);
        expect(p[0], p[1]);
        expect(p[1], p[2]);
      }
      // 彩色像素也逐通道按同一 LUT 映射（单调，不会出现通道反转）。
      final List<int> colored = pixelAt(out, 2, 0);
      expect(colored[0], greaterThanOrEqualTo(colored[2]));
    });

    test('全透明图不做改动', () {
      final RgbaImage image = buildImage(2, 1, (int x, int y) => <int>[10, 20, 30, 0]);
      final RgbaImage out = applyAutoBrightness(image);
      expect(out.data, equals(image.data));
    });
  });

  group('simplifyColors', () {
    test('把颜色数量压到目标以内', () {
      final RgbaImage image = buildImage(4, 4, (int x, int y) {
        final int v = (y * 4 + x) * 16;
        return <int>[v, 255 - v, (v * 2) % 256];
      });
      expect(distinctColors(image).length, 16);
      final RgbaImage out = simplifyColors(image, 4);
      expect(distinctColors(out).length, lessThanOrEqualTo(4));
    });

    test('唯一色数不超过目标时原样返回', () {
      final RgbaImage image = buildImage(2, 1, (int x, int y) {
        return x == 0 ? <int>[10, 10, 10] : <int>[200, 200, 200];
      });
      final RgbaImage out = simplifyColors(image, 8);
      expect(out.data, equals(image.data));
    });

    test('不改 alpha', () {
      final RgbaImage image = buildImage(2, 1, (int x, int y) {
        return <int>[x * 100, 0, 0, 9];
      });
      final RgbaImage out = simplifyColors(image, 2);
      expect(out.data[3], 9);
      expect(out.data[7], 9);
    });

    test('目标色数会被夹到 2~64', () {
      final RgbaImage image = buildImage(3, 1, (int x, int y) {
        return <int>[x * 100, x * 50, 0];
      });
      // 传 1 → 夹到 2；这里只验证不抛异常且颜色数不超过 2。
      expect(distinctColors(simplifyColors(image, 1)).length, lessThanOrEqualTo(2));
    });
  });

  group('processImage', () {
    test('不修改入参', () {
      final RgbaImage image = buildImage(4, 3, (int x, int y) {
        return <int>[x * 40, y * 60, 128];
      });
      final List<int> before = List<int>.of(image.data);
      processImage(
        image,
        const ProcessSettings(
          autoBrightness: true,
          brightness: 20,
          simplifyColors: true,
          simplifyColorCount: 4,
        ),
      );
      expect(image.data, equals(before));
    });

    test('默认设置只做自动亮度', () {
      final RgbaImage image = grayStrip(<int>[100, 120, 140, 160]);
      final RgbaImage out = processImage(image, ProcessSettings.defaults);
      final RgbaImage reference = applyAutoBrightness(image.clone());
      expect(out.data, equals(reference.data));
    });

    test('全关时与源图一致', () {
      final RgbaImage image = grayStrip(<int>[100, 120, 140, 160]);
      final RgbaImage out = processImage(
        image,
        const ProcessSettings(autoBrightness: false),
      );
      expect(out.data, equals(image.data));
    });
  });

  group('ProcessSettings', () {
    test('默认值：自动亮度开、亮度 0、不做色彩简化', () {
      const ProcessSettings settings = ProcessSettings.defaults;
      expect(settings.autoBrightness, isTrue);
      expect(settings.brightness, 0);
      expect(settings.simplifyColors, isFalse);
      expect(settings.simplifyColorCount, 8);
    });

    test('相等的设置 key 相同', () {
      expect(
        const ProcessSettings(brightness: 12).key,
        const ProcessSettings(brightness: 12).key,
      );
      expect(
        const ProcessSettings(brightness: 12),
        const ProcessSettings(brightness: 12),
      );
    });

    test('任一字段不同则 key 与相等性都不同', () {
      const ProcessSettings base = ProcessSettings();
      expect(base.key, isNot(const ProcessSettings(autoBrightness: false).key));
      expect(base.key, isNot(const ProcessSettings(brightness: 1).key));
      expect(base.key, isNot(const ProcessSettings(simplifyColors: true).key));
      expect(
        const ProcessSettings(simplifyColors: true).key,
        isNot(const ProcessSettings(simplifyColors: true, simplifyColorCount: 4).key),
      );
      expect(base, isNot(const ProcessSettings(brightness: 1)));
    });

    test('copyWith 只改指定字段', () {
      const ProcessSettings base = ProcessSettings();
      final ProcessSettings copy = base.copyWith(brightness: 30);
      expect(copy.brightness, 30);
      expect(copy.autoBrightness, base.autoBrightness);
      expect(copy.simplifyColors, base.simplifyColors);
      expect(copy.simplifyColorCount, base.simplifyColorCount);
    });
  });

  group('文案', () {
    test('describeProcess 覆盖不处理与多参数组合', () {
      expect(describeProcess(const ProcessSettings(autoBrightness: false)), '不处理');
      expect(describeProcess(ProcessSettings.defaults), '自动亮度');
      expect(
        describeProcess(
          const ProcessSettings(
            autoBrightness: false,
            brightness: 12,
            simplifyColors: true,
            simplifyColorCount: 8,
          ),
        ),
        '亮度 +12 · 简化到 8 色',
      );
      expect(
        describeProcess(
          const ProcessSettings(autoBrightness: false, brightness: -5),
        ),
        '亮度 -5',
      );
    });

    test('formatBrightness 带正负号', () {
      expect(formatBrightness(12), '+12');
      expect(formatBrightness(-5), '-5');
      expect(formatBrightness(0), '0');
      expect(formatBrightness(12.4), '+12');
    });
  });
}
