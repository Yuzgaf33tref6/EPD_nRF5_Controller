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

int lumaOf(List<int> pixel) =>
    (299 * pixel[0] + 587 * pixel[1] + 114 * pixel[2]) ~/ 1000;

void main() {
  group('applyBrightness', () {
    test('按 -100~100 映射到 ±255 的加法', () {
      final RgbaImage image =
          buildImage(1, 1, (int x, int y) => <int>[10, 20, 30]);
      final RgbaImage out = applyBrightness(image, 10);
      // delta = round(10 * 255 / 100) = 26
      expect(pixelAt(out, 0, 0), <int>[36, 46, 56, 255]);
    });

    test('负数变暗，最低夹到 0', () {
      final RgbaImage image =
          buildImage(1, 1, (int x, int y) => <int>[10, 120, 200]);
      final RgbaImage out = applyBrightness(image, -50);
      // delta = round(-127.5) = -128
      expect(pixelAt(out, 0, 0), <int>[0, 0, 72, 255]);
    });

    test('超过上限时夹到 255', () {
      final RgbaImage image =
          buildImage(1, 1, (int x, int y) => <int>[250, 10, 0]);
      final RgbaImage out = applyBrightness(image, 100);
      expect(pixelAt(out, 0, 0), <int>[255, 255, 255, 255]);
    });

    test('不改变 alpha', () {
      final RgbaImage image =
          buildImage(1, 1, (int x, int y) => <int>[100, 100, 100, 7]);
      final RgbaImage out = applyBrightness(image, 20);
      expect(out.data[3], 7);
    });

    test('amount 为 0 时数据不变', () {
      final RgbaImage image = grayStrip(<int>[10, 20, 30]);
      final RgbaImage out = applyBrightness(image, 0);
      expect(out.data, equals(image.data));
    });
  });

  group('applyContrast', () {
    test('以 128 为中心放大', () {
      final RgbaImage image = grayStrip(<int>[64, 128, 192]);
      final RgbaImage out = applyContrast(image, 2);
      // 128 + (64-128)*2 = 0；128 不变；128 + 64*2 = 256 → 255
      expect(pixelAt(out, 0, 0)[0], 0);
      expect(pixelAt(out, 1, 0)[0], 128);
      expect(pixelAt(out, 2, 0)[0], 255);
    });

    test('factor 为 1 时数据不变', () {
      final RgbaImage image = grayStrip(<int>[10, 200]);
      expect(applyContrast(image, 1).data, equals(image.data));
    });
  });

  group('applyGamma', () {
    test('gamma=2 提亮中间调、端点不变', () {
      final RgbaImage image = grayStrip(<int>[0, 64, 255]);
      final RgbaImage out = applyGamma(image, 2);
      expect(pixelAt(out, 0, 0)[0], 0);
      // (64/255)^0.5 * 255 ≈ 127.8
      expect(pixelAt(out, 1, 0)[0], closeTo(128, 2));
      expect(pixelAt(out, 2, 0)[0], 255);
    });

    test('gamma=1 时数据不变', () {
      final RgbaImage image = grayStrip(<int>[13, 240]);
      expect(applyGamma(image, 1).data, equals(image.data));
    });
  });

  group('applySaturation', () {
    test('amount=0 变灰', () {
      final RgbaImage image =
          buildImage(1, 1, (int x, int y) => <int>[200, 120, 40]);
      final List<int> out = pixelAt(applySaturation(image, 0), 0, 0);
      expect(out[0], out[1]);
      expect(out[1], out[2]);
    });

    test('amount=1 时数据不变', () {
      final RgbaImage image =
          buildImage(1, 1, (int x, int y) => <int>[200, 120, 40]);
      expect(applySaturation(image, 1).data, equals(image.data));
    });

    test('amount>1 时通道差变大', () {
      final RgbaImage image =
          buildImage(1, 1, (int x, int y) => <int>[150, 120, 90]);
      final List<int> out = pixelAt(applySaturation(image, 1.5), 0, 0);
      expect(out[0] - out[2], greaterThan(60));
    });
  });

  group('applyWhiteBalance', () {
    test('偏红图会被拉回中性', () {
      // 红色分量整体偏高、且动态范围更宽：白平衡后中位灰更接近。
      final RgbaImage image = buildImage(3, 1, (int x, int y) {
        return switch (x) {
          0 => <int>[120, 100, 100],
          1 => <int>[180, 140, 140],
          _ => <int>[240, 180, 180],
        };
      });
      final RgbaImage out = applyWhiteBalance(image);
      final List<int> last = pixelAt(out, 2, 0);
      // 高光应该是接近白的中性色（三通道差被压缩）。
      expect((last[0] - last[1]).abs(), lessThan(30));
    });

    test('各通道都是常量时不拉伸（不会变成噪声）', () {
      final RgbaImage image =
          buildImage(2, 1, (int x, int y) => <int>[128, 128, 128]);
      expect(applyWhiteBalance(image).data, equals(image.data));
    });
  });

  group('applyBrightnessBalance', () {
    test('拉伸黑白点，并把中位亮度拉到中间', () {
      final RgbaImage image = grayStrip(<int>[100, 120, 140, 160]);
      final RgbaImage out = applyBrightnessBalance(image);
      expect(pixelAt(out, 0, 0)[0], 0);
      expect(pixelAt(out, 3, 0)[0], 255);
      // 中位（120→85 拉伸后）被抬到 ~128。
      expect(pixelAt(out, 1, 0)[0], closeTo(128, 6));
      // 单调不减。
      final List<int> values = <int>[
        for (int x = 0; x < 4; x++) pixelAt(out, x, 0)[0],
      ];
      for (int i = 1; i < values.length; i++) {
        expect(values[i], greaterThanOrEqualTo(values[i - 1]));
      }
    });

    test('接近纯色时不拉伸（避免把纯色弄成噪声）', () {
      final RgbaImage image = grayStrip(<int>[120, 122, 124]);
      expect(applyBrightnessBalance(image).data, equals(image.data));
    });

    test('全透明图不做改动', () {
      final RgbaImage image =
          buildImage(2, 1, (int x, int y) => <int>[10, 20, 30, 0]);
      expect(applyBrightnessBalance(image).data, equals(image.data));
    });

    test('整体偏暗的图会被提亮', () {
      final RgbaImage image = grayStrip(<int>[20, 40, 60, 80]);
      // apply* 系列是就地修改的（processImage 负责先 clone），所以要先取值。
      final int beforeMedian = pixelAt(image, 1, 0)[0];
      final RgbaImage out = applyBrightnessBalance(image);
      final int afterMedian = pixelAt(out, 1, 0)[0];
      expect(afterMedian, greaterThan(beforeMedian));
      // 亮度均衡的目标就是把中间调拉到 128 附近。
      expect(afterMedian, closeTo(128, 8));
    });
  });

  group('estimateAutoBrightness', () {
    test('偏暗的图给出正值，偏亮的图给出负值', () {
      final double dark = estimateAutoBrightness(grayStrip(<int>[10, 20, 30, 40]));
      final double bright =
          estimateAutoBrightness(grayStrip(<int>[215, 225, 235, 245]));
      expect(dark, greaterThan(0));
      expect(bright, lessThan(0));
      expect(dark, inInclusiveRange(-100, 100));
      expect(bright, inInclusiveRange(-100, 100));
    });

    test('中位已经落在中间的图不需要补偿', () {
      final double value = estimateAutoBrightness(grayStrip(<int>[0, 128, 255]));
      expect(value.abs(), lessThanOrEqualTo(1));
    });

    test('纯色图不补偿', () {
      expect(estimateAutoBrightness(grayStrip(<int>[128, 128, 128])), 0);
    });
  });

  group('applyPreprocess', () {
    test('不处理时数据不变', () {
      final RgbaImage image = grayStrip(<int>[10, 200]);
      expect(
        applyPreprocess(image, PreprocessPreset.none).data,
        equals(image.data),
      );
    });

    test('灰阶照片预设会去掉颜色（r==g==b）', () {
      final RgbaImage image =
          buildImage(1, 1, (int x, int y) => <int>[200, 60, 30]);
      final List<int> out =
          pixelAt(applyPreprocess(image, PreprocessPreset.grayscalePhoto), 0, 0);
      expect(out[0], out[1]);
      expect(out[1], out[2]);
    });

    test('每个预设都会真正改变像素（不塌成恒等）', () {
      final RgbaImage source = buildImage(8, 8, (int x, int y) {
        return <int>[x * 30, y * 30, 128];
      });
      for (final PreprocessPreset preset in PreprocessPreset.values) {
        if (preset == PreprocessPreset.none) {
          continue;
        }
        final RgbaImage out = applyPreprocess(source.clone(), preset);
        expect(
          out.data,
          isNot(equals(source.data)),
          reason: '预设 ${preset.label} 应该是非恒等变换',
        );
      }
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
      expect(simplifyColors(image, 8).data, equals(image.data));
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
      expect(
        distinctColors(simplifyColors(image, 1)).length,
        lessThanOrEqualTo(2),
      );
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
          brightness: 20,
          brightnessBalance: true,
          preprocess: PreprocessPreset.vividPhoto,
          simplifyColors: true,
          simplifyColorCount: 4,
        ),
      );
      expect(image.data, equals(before));
    });

    test('全关时与源图一致', () {
      final RgbaImage image = grayStrip(<int>[100, 120, 140, 160]);
      final RgbaImage out = processImage(image, ProcessSettings.defaults);
      expect(out.data, equals(image.data));
    });

    test('按「预处理 → 亮度均衡 → 亮度 → 简化」的顺序应用', () {
      final RgbaImage image = grayStrip(<int>[100, 120, 140, 160]);
      // 手动逐步应用，结果应与 processImage 一次到位一致。
      RgbaImage expected = applyPreprocess(image.clone(), PreprocessPreset.vividPhoto);
      expected = applyBrightnessBalance(expected);
      expected = applyBrightness(expected, 8);
      final RgbaImage actual = processImage(
        image,
        const ProcessSettings(
          brightness: 8,
          brightnessBalance: true,
          preprocess: PreprocessPreset.vividPhoto,
        ),
      );
      expect(actual.data, equals(expected.data));
    });

    test('亮度均衡与预处理都会改变亮度分布', () {
      final RgbaImage image = grayStrip(<int>[100, 120, 140, 160]);
      final int before = lumaOf(pixelAt(image, 1, 0));
      final RgbaImage balanced = processImage(
        image,
        const ProcessSettings(brightnessBalance: true),
      );
      expect(lumaOf(pixelAt(balanced, 1, 0)), isNot(before));
    });
  });

  group('ProcessSettings', () {
    test('默认值全部关闭', () {
      const ProcessSettings settings = ProcessSettings.defaults;
      expect(settings.brightness, 0);
      expect(settings.brightnessBalance, isFalse);
      expect(settings.preprocess, PreprocessPreset.none);
      expect(settings.simplifyColors, isFalse);
      expect(settings.simplifyColorCount, 8);
      expect(settings.isIdentity, isTrue);
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
      expect(base.key, isNot(const ProcessSettings(brightness: 1).key));
      expect(base.key, isNot(const ProcessSettings(brightnessBalance: true).key));
      expect(
        base.key,
        isNot(const ProcessSettings(preprocess: PreprocessPreset.vividPhoto).key),
      );
      expect(base.key, isNot(const ProcessSettings(simplifyColors: true).key));
      expect(
        const ProcessSettings(simplifyColors: true).key,
        isNot(
          const ProcessSettings(simplifyColors: true, simplifyColorCount: 4).key,
        ),
      );
      expect(base, isNot(const ProcessSettings(brightness: 1)));
    });

    test('isIdentity 只看有没有实际处理', () {
      expect(const ProcessSettings(brightness: 0).isIdentity, isTrue);
      expect(const ProcessSettings(brightness: 1).isIdentity, isFalse);
      expect(
        const ProcessSettings(brightnessBalance: true).isIdentity,
        isFalse,
      );
      expect(
        const ProcessSettings(preprocess: PreprocessPreset.softGradient)
            .isIdentity,
        isFalse,
      );
    });

    test('copyWith 只改指定字段', () {
      const ProcessSettings base = ProcessSettings();
      final ProcessSettings copy = base.copyWith(brightness: 30);
      expect(copy.brightness, 30);
      expect(copy.brightnessBalance, base.brightnessBalance);
      expect(copy.preprocess, base.preprocess);
      expect(copy.simplifyColors, base.simplifyColors);
      expect(copy.simplifyColorCount, base.simplifyColorCount);
    });
  });

  group('文案', () {
    test('describeProcess 覆盖不处理与多参数组合', () {
      expect(describeProcess(ProcessSettings.defaults), '不处理');
      expect(
        describeProcess(
          const ProcessSettings(
            preprocess: PreprocessPreset.paperPoster,
            brightnessBalance: true,
            brightness: 12,
            simplifyColors: true,
            simplifyColorCount: 8,
          ),
        ),
        '纸张与海报 · 亮度均衡 · 亮度 +12 · 简化到 8 色',
      );
      expect(
        describeProcess(const ProcessSettings(brightness: -5)),
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
