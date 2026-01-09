import 'dart:typed_data';
import 'dart:ui' as ui;
import '../models/screen_type.dart';
// ignore: unused_import
import '../models/color_palette.dart';
import 'color_utils.dart';

class ImageConverter {
  // 将图片数据转换为像素数据
  static Future<List<int>> imageToPixels(ui.Image image) async {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) {
      throw Exception('Failed to convert image to byte data');
    }
    return byteData.buffer.asUint8List().toList();
  }

  // 处理图片数据
  static Uint8List processImageData(
      List<int> pixels, int width, int height, EpdColorMode mode) {
    final processedData = <int>[];

    if (mode == EpdColorMode.sixColor) {
      processedData.length = width * height;
      
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final index = (y * width + x) * 4;
          final r = pixels[index];
          final g = pixels[index + 1];
          final b = pixels[index + 2];

          final closest = ColorUtils.findClosestColor(r, g, b, mode);
          final newIndex = (x * height) + (height - 1 - y);
          processedData[newIndex] = closest.value;
        }
      }
    } else if (mode == EpdColorMode.fourColor) {
      final byteCount = (width * height / 4).ceil();
      processedData.length = byteCount;
      
      for (var i = 0; i < processedData.length; i++) {
        processedData[i] = 0;
      }
      
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final index = (y * width + x) * 4;
          final r = pixels[index];
          final g = pixels[index + 1];
          final b = pixels[index + 2];
          
          final closest = ColorUtils.findClosestColor(r, g, b, mode);
          final colorValue = closest.value;
          final byteIndex = (y * width + x) ~/ 4;
          final shift = 6 - ((x % 4) * 2);
          processedData[byteIndex] |= (colorValue << shift);
        }
      }
    } else if (mode == EpdColorMode.blackWhiteColor) {
      final byteWidth = (width / 8).ceil();
      final byteCount = byteWidth * height;
      processedData.length = byteCount;
      
      const threshold = 140;
      
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final index = (y * width + x) * 4;
          final r = pixels[index];
          final g = pixels[index + 1];
          final b = pixels[index + 2];
          
          final grayscale = ColorUtils.calculateGrayscale(r, g, b);
          final bit = grayscale >= threshold ? 1 : 0;
          final byteIndex = y * byteWidth + (x ~/ 8);
          final bitIndex = 7 - (x % 8);
          
          if (bit == 1) {
            processedData[byteIndex] |= (1 << bitIndex);
          }
        }
      }
    } else if (mode == EpdColorMode.threeColor) {
      final byteWidth = (width / 8).ceil();
      final totalBytes = byteWidth * height * 2;
      processedData.length = totalBytes;
      
      const blackWhiteThreshold = 140;
      const redThreshold = 160;
      
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final index = (y * width + x) * 4;
          final r = pixels[index];
          final g = pixels[index + 1];
          final b = pixels[index + 2];
          
          final grayscale = ColorUtils.calculateGrayscale(r, g, b);
          
          // 黑白位
          final blackWhiteBit = grayscale >= blackWhiteThreshold ? 1 : 0;
          final blackWhiteByteIndex = y * byteWidth + (x ~/ 8);
          final blackWhiteBitIndex = 7 - (x % 8);
          
          if (blackWhiteBit == 1) {
            processedData[blackWhiteByteIndex] |= (1 << blackWhiteBitIndex);
          }
          
          // 红白位
          final redWhiteBit = (r > redThreshold && r > g && r > b) ? 0 : 1;
          final redWhiteByteIndex = blackWhiteByteIndex + (byteWidth * height);
          final redWhiteBitIndex = blackWhiteBitIndex;
          
          if (redWhiteBit == 1) {
            processedData[redWhiteByteIndex] |= (1 << redWhiteBitIndex);
          }
        }
      }
    }

    return Uint8List.fromList(processedData);
  }
}