/// 显存位打包：把 RGBA 图像打包成墨水屏驱动要的字节流，以及反向解码。
///
/// 移植自 web 上位机的 `html/js/dithering.js`（`processImageData` /
/// `decodeProcessedData`）和 `html/js/main.js:193-218`（`convertUC8159`）。
///
/// 每个模式的打包格式都不一样，而且行宽不是 8 的整数倍时末字节要补位，
/// 这些细节全部按 web 版原样实现，并用 golden 逐字节对拍。
library;

import 'dart:typed_data';

import 'dither.dart';
import 'epd_color.dart';
import 'rgba_image.dart';

/// 黑白/三色模式判黑白的灰度阈值（与 web 版一致）。
const int _grayThreshold = 140;

/// 三色模式判定「红」的阈值：`r > 160 && r > g && r > b`。
const int _redThreshold = 160;

/// 按 `value` 在调色板里查颜色，找不到时返回 [fallback]（对应 web 版的
/// `palette.find(...) || 默认白`）。
EpdColor _colorByValue(
  List<EpdColor> palette,
  int value,
  EpdColor fallback,
) {
  for (final EpdColor color in palette) {
    if (color.value == value) {
      return color;
    }
  }
  return fallback;
}

/// 把图像打包成显存字节流。
///
/// - `sixColor`：4bpp，每字节两个像素（左像素在高 4 位）。
/// - `fourColor`：2bpp，每字节四个像素，从最高 2 位开始。
/// - `blackWhiteColor`：1bpp，行优先，`byteWidth = ceil(width / 8)`，最高位是行首像素。
/// - `threeColor`：两段 1bpp 平面拼接，前段黑白、后段红白（该位为 0 表示红）。
Uint8List processImageData(RgbaImage image, EpdColorMode mode) {
  final int width = image.width;
  final int height = image.height;
  final Uint8List data = image.data;

  switch (mode) {
    case EpdColorMode.sixColor:
      final Uint8List processed = Uint8List(((width * height) + 1) ~/ 2);
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int index = (y * width + x) * 4;
          final EpdColor closest = findClosestColor(
            data[index],
            data[index + 1],
            data[index + 2],
            mode,
          );
          final int value = closest.value;
          final int newIndex = (y * width + x) >> 1;
          if (x % 2 == 0) {
            processed[newIndex] |= (value << 4) & 0xff;
          } else {
            processed[newIndex] |= value;
          }
        }
      }
      return processed;

    case EpdColorMode.fourColor:
      final Uint8List processed = Uint8List(((width * height) + 3) ~/ 4);
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int index = (y * width + x) * 4;
          final EpdColor closest = findClosestColor(
            data[index],
            data[index + 1],
            data[index + 2],
            mode,
          );
          final int value = closest.value;
          final int newIndex = (y * width + x) ~/ 4;
          final int shift = 6 - ((x % 4) * 2);
          processed[newIndex] |= (value << shift) & 0xff;
        }
      }
      return processed;

    case EpdColorMode.blackWhiteColor:
      final int byteWidth = (width + 7) ~/ 8;
      final Uint8List processed = Uint8List(byteWidth * height);
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int index = (y * width + x) * 4;
          final int grayscale = (0.299 * data[index] +
                  0.587 * data[index + 1] +
                  0.114 * data[index + 2])
              .round();
          final int bit = grayscale >= _grayThreshold ? 1 : 0;
          if (bit != 0) {
            final int byteIndex = y * byteWidth + (x ~/ 8);
            final int bitIndex = 7 - (x % 8);
            processed[byteIndex] |= (bit << bitIndex) & 0xff;
          }
        }
      }
      return processed;

    case EpdColorMode.threeColor:
      final int byteWidth = (width + 7) ~/ 8;
      final Uint8List blackWhite = Uint8List(byteWidth * height);
      final Uint8List redWhite = Uint8List(byteWidth * height);
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int index = (y * width + x) * 4;
          final int r = data[index];
          final int g = data[index + 1];
          final int b = data[index + 2];
          final int grayscale = (0.299 * r + 0.587 * g + 0.114 * b).round();

          final int byteIndex = y * byteWidth + (x ~/ 8);
          final int bitIndex = 7 - (x % 8);

          final int blackWhiteBit = grayscale >= _grayThreshold ? 1 : 0;
          if (blackWhiteBit != 0) {
            blackWhite[byteIndex] |= (1 << bitIndex) & 0xff;
          } else {
            blackWhite[byteIndex] &= ~((1 << bitIndex) & 0xff) & 0xff;
          }

          final int redWhiteBit =
              (r > _redThreshold && r > g && r > b) ? 0 : 1;
          if (redWhiteBit != 0) {
            redWhite[byteIndex] |= (1 << bitIndex) & 0xff;
          } else {
            redWhite[byteIndex] &= ~((1 << bitIndex) & 0xff) & 0xff;
          }
        }
      }
      final Uint8List processed =
          Uint8List(blackWhite.length + redWhite.length);
      processed.setAll(0, blackWhite);
      processed.setAll(blackWhite.length, redWhite);
      return processed;
  }
}

/// 把显存字节流还原成 RGBA 图像（web 版用于把量化结果回显到画布）。
///
/// 除三色模式的红色像素外，其余像素都是纯黑或纯白，Alpha 统一为 255。
RgbaImage decodeProcessedData(
  Uint8List processed,
  int width,
  int height,
  EpdColorMode mode,
) {
  final RgbaImage image = RgbaImage(width, height);
  final Uint8List data = image.data;

  switch (mode) {
    case EpdColorMode.sixColor:
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int newIndex = (y * width + x) >> 1;
          final int value = x % 2 == 0
              ? (processed[newIndex] >> 4) & 0x0f
              : processed[newIndex] & 0x0f;
          final EpdColor color =
              _colorByValue(rgbPalette, value, rgbPalette[1]);
          final int index = (y * width + x) * 4;
          data[index] = color.r;
          data[index + 1] = color.g;
          data[index + 2] = color.b;
          data[index + 3] = 255;
        }
      }
      return image;

    case EpdColorMode.fourColor:
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int newIndex = (y * width + x) ~/ 4;
          final int shift = 6 - ((x % 4) * 2);
          final int value = (processed[newIndex] >> shift) & 0x03;
          final EpdColor color =
              _colorByValue(fourColorPalette, value, fourColorPalette[1]);
          final int index = (y * width + x) * 4;
          data[index] = color.r;
          data[index + 1] = color.g;
          data[index + 2] = color.b;
          data[index + 3] = 255;
        }
      }
      return image;

    case EpdColorMode.blackWhiteColor:
      final int byteWidth = (width + 7) ~/ 8;
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int byteIndex = y * byteWidth + (x ~/ 8);
          final int bitIndex = 7 - (x % 8);
          final int bit = (processed[byteIndex] >> bitIndex) & 1;
          final int index = (y * width + x) * 4;
          final int gray = bit != 0 ? 255 : 0;
          data[index] = gray;
          data[index + 1] = gray;
          data[index + 2] = gray;
          data[index + 3] = 255;
        }
      }
      return image;

    case EpdColorMode.threeColor:
      final int byteWidth = (width + 7) ~/ 8;
      final int planeLength = byteWidth * height;
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int byteIndex = y * byteWidth + (x ~/ 8);
          final int bitIndex = 7 - (x % 8);
          final int blackWhiteBit =
              (processed[byteIndex] >> bitIndex) & 1;
          final int redWhiteBit =
              (processed[planeLength + byteIndex] >> bitIndex) & 1;
          final int index = (y * width + x) * 4;
          if (redWhiteBit == 0) {
            data[index] = 255;
            data[index + 1] = 0;
            data[index + 2] = 0;
          } else {
            final int gray = blackWhiteBit != 0 ? 255 : 0;
            data[index] = gray;
            data[index + 1] = gray;
            data[index + 2] = gray;
          }
          data[index + 3] = 255;
        }
      }
      return image;
  }
}

/// UC8159 系列低分辨率屏（驱动 08/09/0e/0f）要的 4bit/像素格式。
///
/// 每个输入字节对（黑/白平面 + 红/白平面）展开成 4 个输出字节、共 8 个像素，
/// 每像素 4 位：红色 0x04、黑色 0x00、白色 0x03。
Uint8List convertUC8159(Uint8List blackWhiteData, Uint8List redWhiteData) {
  if (blackWhiteData.length != redWhiteData.length) {
    throw ArgumentError(
      '黑白平面与红白平面长度必须一致：'
      '${blackWhiteData.length} != ${redWhiteData.length}',
    );
  }

  final int halfLength = blackWhiteData.length;
  final Uint8List payload = Uint8List(halfLength * 4);
  int payloadIndex = 0;

  for (int i = 0; i < halfLength; i++) {
    int blackData = blackWhiteData[i];
    int colorData = redWhiteData[i];

    // 内层每轮处理两个像素，同时手动 j++ 一次，与 web 版的双像素展开一致。
    for (int j = 0; j < 8; j++) {
      int value;
      if ((colorData & 0x80) == 0x00) {
        value = 0x04; // 红
      } else if ((blackData & 0x80) == 0x00) {
        value = 0x00; // 黑
      } else {
        value = 0x03; // 白
      }
      int byte = (value << 4) & 0xff;
      blackData = (blackData << 1) & 0xff;
      colorData = (colorData << 1) & 0xff;
      j++;

      if ((colorData & 0x80) == 0x00) {
        value = 0x04;
      } else if ((blackData & 0x80) == 0x00) {
        value = 0x00;
      } else {
        value = 0x03;
      }
      byte |= value;
      blackData = (blackData << 1) & 0xff;
      colorData = (colorData << 1) & 0xff;

      payload[payloadIndex++] = byte;
    }
  }

  return payload;
}
