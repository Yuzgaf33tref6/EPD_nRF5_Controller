import 'dart:typed_data';

import 'package:epd_controller/image/dither.dart';
import 'package:epd_controller/image/epd_color.dart';
import 'package:epd_controller/image/preview_computer.dart';
import 'package:epd_controller/image/rgba_image.dart';
import 'package:flutter_test/flutter_test.dart';

/// 造一张确定性的测试图（渐变 + 红条），不依赖任何随机数。
RgbaImage buildImage(int width, int height) {
  final Uint8List data = Uint8List(width * height * 4);
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final int i = (y * width + x) * 4;
      final bool redBand = y > height ~/ 3 && y < height * 2 ~/ 3;
      data[i] = redBand ? 200 : (x * 255 ~/ width);
      data[i + 1] = redBand ? 20 : (y * 255 ~/ height);
      data[i + 2] = redBand ? 30 : 128;
      data[i + 3] = 255;
    }
  }
  return RgbaImage(width, height, data);
}

DitherJob buildJob({
  DitherAlgorithm algorithm = DitherAlgorithm.floydSteinberg,
  double strength = 1.0,
  double contrast = 1.2,
  EpdColorMode mode = EpdColorMode.threeColor,
}) {
  final RgbaImage image = buildImage(24, 16);
  return DitherJob(
    width: image.width,
    height: image.height,
    rgba: image.data,
    algorithm: algorithm,
    strength: strength,
    contrast: contrast,
    mode: mode,
  );
}

void main() {
  group('DitherJob', () {
    test('相同参数得到相同的 key', () {
      final RgbaImage image = buildImage(8, 6);
      DitherJob make() => DitherJob(
            width: image.width,
            height: image.height,
            rgba: Uint8List.fromList(image.data),
            algorithm: DitherAlgorithm.atkinson,
            strength: 1.5,
            contrast: 1.0,
            mode: EpdColorMode.blackWhiteColor,
          );
      expect(make().key, equals(make().key));
    });

    test('参数不同 key 就不同', () {
      final DitherJob base = buildJob();
      final DitherJob other = buildJob(strength: 2.0);
      expect(base.key, isNot(equals(other.key)));
    });

    test('只改算法或色彩模式，key 也会变', () {
      expect(
        buildJob().key,
        isNot(equals(buildJob(algorithm: DitherAlgorithm.bayer).key)),
      );
      expect(
        buildJob().key,
        isNot(equals(buildJob(mode: EpdColorMode.sixColor).key)),
      );
    });

    test('图像内容变化会导致 key 变化', () {
      final RgbaImage a = buildImage(10, 10);
      final RgbaImage b = a.clone();
      b.data[0] = b.data[0] == 0 ? 255 : 0;
      DitherJob job(RgbaImage image) => DitherJob(
            width: image.width,
            height: image.height,
            rgba: Uint8List.fromList(image.data),
            algorithm: DitherAlgorithm.none,
            strength: 1,
            contrast: 1,
            mode: EpdColorMode.threeColor,
          );
      expect(job(a).key, isNot(equals(job(b).key)));
    });
  });

  group('computeDitherJobSync', () {
    test('输出的尺寸与入参一致，且像素被量化到调色板', () {
      final DitherJob job = buildJob();
      final RgbaImage result = computeDitherJobSync(job);
      expect(result.width, job.width);
      expect(result.height, job.height);

      // 三色模式量化后，每个像素都必须是三色调色板里的某一个。
      final Set<int> allowed = <int>{
        for (final EpdColor color in EpdColorMode.threeColor.palette)
          (color.r << 16) | (color.g << 8) | color.b,
      };
      for (int i = 0; i < result.data.length; i += 4) {
        final int key =
            (result.data[i] << 16) | (result.data[i + 1] << 8) | result.data[i + 2];
        expect(allowed, contains(key));
      }
    });

    test('不修改传入的原始字节', () {
      final DitherJob job = buildJob();
      final List<int> before = List<int>.of(job.rgba, growable: false);
      computeDitherJobSync(job);
      expect(job.rgba, equals(before));
    });

    test('none 算法等价于只做对比度调整', () {
      final DitherJob job = buildJob(algorithm: DitherAlgorithm.none);
      final RgbaImage result = computeDitherJobSync(job);
      // 对比度 1.0 时应当与源图完全一致（用同样的路径算一遍做对照）。
      final RgbaImage reference = RgbaImage(
        job.width,
        job.height,
        Uint8List.fromList(job.rgba),
      );
      final RgbaImage expected =
          ditherImage(adjustContrast(reference, job.contrast),
              DitherAlgorithm.none, job.strength, job.mode);
      expect(result.data, equals(expected.data));
    });
  });
}
