import 'dart:typed_data';

import 'package:epd_controller/image/canvas_editing.dart';
import 'package:epd_controller/image/epd_color.dart';
import 'package:epd_controller/image/rgba_image.dart';
import 'package:flutter_test/flutter_test.dart';

RgbaImage blankImage(int width, int height, {int value = 255}) {
  final Uint8List data = Uint8List(width * height * 4);
  for (int i = 0; i < data.length; i += 4) {
    data[i] = value;
    data[i + 1] = value;
    data[i + 2] = value;
    data[i + 3] = 255;
  }
  return RgbaImage(width, height, data);
}

List<int> pixelAt(RgbaImage image, int x, int y) {
  final int i = (y * image.width + x) * 4;
  return <int>[image.data[i], image.data[i + 1], image.data[i + 2]];
}

void main() {
  group('画笔', () {
    test('画一条横线会覆盖沿途像素', () {
      final RgbaImage image = blankImage(20, 10);
      drawStroke(
        image,
        x0: 2,
        y0: 5,
        x1: 17,
        y1: 5,
        radius: 0.5,
        r: 0,
        g: 0,
        b: 0,
      );
      for (int x = 2; x <= 17; x++) {
        expect(pixelAt(image, x, 5), <int>[0, 0, 0], reason: 'x=$x');
      }
      expect(pixelAt(image, 1, 5), <int>[255, 255, 255]);
      expect(pixelAt(image, 18, 5), <int>[255, 255, 255]);
    });

    test('斜线用插值补齐，不会断成虚线', () {
      final RgbaImage image = blankImage(12, 12);
      drawStroke(
        image,
        x0: 0,
        y0: 0,
        x1: 10,
        y1: 10,
        radius: 0.5,
      );
      for (int i = 0; i <= 10; i++) {
        expect(pixelAt(image, i, i), <int>[0, 0, 0], reason: 'i=$i');
      }
    });

    test('半径决定笔迹宽度', () {
      final RgbaImage image = blankImage(21, 21);
      drawDot(image, x: 10, y: 10, radius: 3);
      expect(pixelAt(image, 10, 10), <int>[0, 0, 0]);
      expect(pixelAt(image, 13, 10), <int>[0, 0, 0]);
      expect(pixelAt(image, 14, 10), <int>[255, 255, 255]);
      expect(pixelAt(image, 12, 12), <int>[0, 0, 0]);
      // 圆角外侧不该被涂到
      expect(pixelAt(image, 13, 13), <int>[255, 255, 255]);
    });

    test('超出画布的部分被安全忽略', () {
      final RgbaImage image = blankImage(8, 8);
      drawStroke(image, x0: 6, y0: 6, x1: 30, y1: 30, radius: 2);
      expect(pixelAt(image, 7, 7), <int>[0, 0, 0]);
      expect(image.data.length, 8 * 8 * 4);
    });

    test('橡皮把笔迹刷回白色', () {
      final RgbaImage image = blankImage(10, 10);
      drawDot(image, x: 5, y: 5, radius: 2);
      expect(pixelAt(image, 5, 5), <int>[0, 0, 0]);
      eraseStroke(image, x0: 5, y0: 5, x1: 5, y1: 5, radius: 2);
      expect(pixelAt(image, 5, 5), <int>[255, 255, 255]);
    });

    test('填充会用调色板颜色覆盖整张图', () {
      final RgbaImage image = blankImage(6, 4);
      fillImage(image, rgbPalette[3]);
      for (int y = 0; y < 4; y++) {
        for (int x = 0; x < 6; x++) {
          expect(pixelAt(image, x, y), <int>[255, 0, 0]);
        }
      }
      expect(image.data[3], 255);
    });
  });

  group('撤销栈', () {
    test('初始状态不能撤销也不能重做', () {
      final ImageHistory history = ImageHistory();
      history.reset(blankImage(2, 2));
      expect(history.canUndo, isFalse);
      expect(history.canRedo, isFalse);
      expect(history.length, 1);
    });

    test('提交后可以撤销、撤销后可以重做', () {
      final ImageHistory history = ImageHistory();
      final RgbaImage first = blankImage(2, 2, value: 255);
      history.reset(first);

      final RgbaImage second = blankImage(2, 2, value: 0);
      history.push(second);
      expect(history.canUndo, isTrue);
      expect(history.canRedo, isFalse);

      final RgbaImage? undone = history.undo();
      expect(undone, isNotNull);
      expect(undone!.data[0], 255);
      expect(history.canUndo, isFalse);
      expect(history.canRedo, isTrue);

      final RgbaImage? redone = history.redo();
      expect(redone, isNotNull);
      expect(redone!.data[0], 0);
      expect(history.canRedo, isFalse);
    });

    test('撤销后提交新状态会丢弃 redo 分支', () {
      final ImageHistory history = ImageHistory();
      history.reset(blankImage(2, 2, value: 255));
      history.push(blankImage(2, 2, value: 10));
      history.push(blankImage(2, 2, value: 20));
      history.undo();
      expect(history.canRedo, isTrue);

      history.push(blankImage(2, 2, value: 30));
      expect(history.canRedo, isFalse);
      expect(history.length, 3);
    });

    test('历史长度受 limit 限制，最早的状态被丢掉', () {
      final ImageHistory history = ImageHistory(limit: 3);
      history.reset(blankImage(2, 2, value: 255));
      for (int v = 0; v < 5; v++) {
        history.push(blankImage(2, 2, value: v));
      }
      expect(history.length, 3);
      // 只能退两步（3 个状态里最早的那张已丢弃）
      expect(history.undo(), isNotNull);
      expect(history.undo(), isNotNull);
      expect(history.undo(), isNull);
    });

    test('历史快照是拷贝，外部改原图不会污染历史', () {
      final ImageHistory history = ImageHistory();
      final RgbaImage image = blankImage(2, 2, value: 255);
      history.reset(image);
      history.push(blankImage(2, 2, value: 0));

      // 提交后再去改当初那张原图，撤销回来的快照不能被影响
      image.data[0] = 7;
      final RgbaImage? undone = history.undo();
      expect(undone, isNotNull);
      expect(undone!.data[0], 255);
    });
  });
}
