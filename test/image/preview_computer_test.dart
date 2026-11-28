import 'dart:typed_data';

import 'package:epd_controller/image/dither.dart';
import 'package:epd_controller/image/epd_color.dart';
import 'package:epd_controller/image/preview_computer.dart';
import 'package:epd_controller/image/process.dart';
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
  ProcessSettings process = ProcessSettings.defaults,
  PreviewStage stage = PreviewStage.dithered,
  bool serpentine = false,
  Uint8List? noiseMask,
  int noiseMaskEdge = 64,
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
    process: process,
    stage: stage,
    serpentine: serpentine,
    noiseMask: noiseMask,
    noiseMaskEdge: noiseMaskEdge,
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

    test('蛇形扫描与蓝噪声掩膜也参与 key', () {
      expect(
        buildJob().key,
        isNot(equals(buildJob(serpentine: true).key)),
      );
      final Uint8List mask = Uint8List.fromList(<int>[1, 2, 3, 4]);
      expect(
        buildJob(algorithm: DitherAlgorithm.blueNoise).key,
        isNot(equals(buildJob(
          algorithm: DitherAlgorithm.blueNoise,
          noiseMask: mask,
          noiseMaskEdge: 2,
        ).key)),
      );
    });

    test('处理参数或预览档位不同，key 也会变', () {
      expect(
        buildJob().key,
        isNot(equals(
          buildJob(
            process: const ProcessSettings(brightness: 12),
          ).key,
        )),
      );
      expect(
        buildJob().key,
        isNot(equals(buildJob(stage: PreviewStage.processed).key)),
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

    test('copyWith 只换档位', () {
      final DitherJob job = buildJob();
      final DitherJob copy = job.copyWith(stage: PreviewStage.original);
      expect(copy.stage, PreviewStage.original);
      expect(copy.algorithm, job.algorithm);
      expect(copy.process, job.process);
      expect(copy.rgba, same(job.rgba));
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

    test('none 算法等价于「处理 + 对比度」两步', () {
      final DitherJob job = buildJob(algorithm: DitherAlgorithm.none);
      final RgbaImage result = computeDitherJobSync(job);
      final RgbaImage reference = RgbaImage(
        job.width,
        job.height,
        Uint8List.fromList(job.rgba),
      );
      final RgbaImage expected = ditherImage(
        adjustContrast(
          processImage(reference, job.process),
          job.contrast,
        ),
        DitherAlgorithm.none,
        job.strength,
        job.mode,
      );
      expect(result.data, equals(expected.data));
    });

    test('原图档直接返回输入像素', () {
      final DitherJob job = buildJob(stage: PreviewStage.original);
      final RgbaImage result = computeDitherJobSync(job);
      expect(result.data, equals(job.rgba));
    });

    test('处理档只处理不抖动', () {
      final DitherJob job = buildJob(stage: PreviewStage.processed);
      final RgbaImage result = computeDitherJobSync(job);
      final RgbaImage reference = RgbaImage(
        job.width,
        job.height,
        Uint8List.fromList(job.rgba),
      );
      expect(result.data, equals(processImage(reference, job.process).data));
    });

    test('三档输出互不相同', () {
      // 处理参数必须是非恒等的，否则「处理」档和「原图」档本来就该一样。
      const ProcessSettings process = ProcessSettings(brightness: 24);
      final RgbaImage original = computeDitherJobSync(
        buildJob(stage: PreviewStage.original, process: process),
      );
      final RgbaImage processed = computeDitherJobSync(
        buildJob(stage: PreviewStage.processed, process: process),
      );
      final RgbaImage dithered = computeDitherJobSync(
        buildJob(stage: PreviewStage.dithered, process: process),
      );
      expect(original.data, isNot(equals(processed.data)));
      expect(processed.data, isNot(equals(dithered.data)));
      expect(original.data, isNot(equals(dithered.data)));
    });

    test('alreadyProcessed 时跳过处理，结果与完整流水线一致', () {
      const ProcessSettings process = ProcessSettings(brightness: 24);
      final DitherJob full = buildJob(process: process);
      final RgbaImage expected = computeDitherJobSync(full);

      // 模拟「只改了抖动参数」：拿上次的处理结果直接当输入。
      final RgbaImage processed = computeDitherJobSync(
        buildJob(stage: PreviewStage.processed, process: process),
      );
      final DitherJob reused = DitherJob(
        width: full.width,
        height: full.height,
        rgba: Uint8List.fromList(processed.data),
        algorithm: full.algorithm,
        strength: full.strength,
        contrast: full.contrast,
        mode: full.mode,
        process: process,
        alreadyProcessed: true,
      );
      expect(computeDitherJobSync(reused).data, equals(expected.data));
    });

    test('alreadyProcessed 也参与 key（避免误命中缓存）', () {
      final DitherJob job = buildJob(process: const ProcessSettings(brightness: 8));
      expect(job.key, isNot(equals(job.copyWith(alreadyProcessed: true).key)));
    });
  });
}
