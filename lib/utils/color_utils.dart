import 'dart:math';
import '../models/color_palette.dart';
import '../models/screen_type.dart';

class ColorUtils {
  // RGB转Lab颜色空间 (来自web端)
  static Map<String, double> rgbToLab(int r, int g, int b) {
    double rr = r / 255.0;
    double gg = g / 255.0;
    double bb = b / 255.0;

    rr = rr > 0.04045 ? pow((rr + 0.055) / 1.055, 2.4).toDouble() : rr / 12.92;
    gg = gg > 0.04045 ? pow((gg + 0.055) / 1.055, 2.4).toDouble() : gg / 12.92;
    bb = bb > 0.04045 ? pow((bb + 0.055) / 1.055, 2.4).toDouble() : bb / 12.92;

    rr *= 100;
    gg *= 100;
    bb *= 100;

    double x = rr * 0.4124 + gg * 0.3576 + bb * 0.1805;
    double y = rr * 0.2126 + gg * 0.7152 + bb * 0.0722;
    double z = rr * 0.0193 + gg * 0.1192 + bb * 0.9505;

    x /= 95.047;
    y /= 100.0;
    z /= 108.883;

    x = x > 0.008856 ? pow(x, 1 / 3).toDouble() : (7.787 * x) + (16 / 116);
    y = y > 0.008856 ? pow(y, 1 / 3).toDouble() : (7.787 * y) + (16 / 116);
    z = z > 0.008856 ? pow(z, 1 / 3).toDouble() : (7.787 * z) + (16 / 116);

    final l = (116 * y) - 16;
    final a = 500 * (x - y);
    final bLab = 200 * (y - z);

    return {'l': l, 'a': a, 'b': bLab};
  }

  // 计算Lab颜色空间距离
  static double labDistance(
      Map<String, double> lab1, Map<String, double> lab2) {
    final dl = lab1['l']! - lab2['l']!;
    final da = lab1['a']! - lab2['a']!;
    final db = lab1['b']! - lab2['b']!;
    return sqrt(0.2 * dl * dl + 3 * da * da + 3 * db * db);
  }

  // 查找最接近的颜色 (基于web端的findClosestColor)
  static ColorPalette findClosestColor(
      int r, int g, int b, EpdColorMode mode) {
    final palette = ColorPalette.getPaletteByMode(mode);

    // 蓝色特殊情况（仅限非三色、四色模式）
    if (mode != EpdColorMode.fourColor &&
        mode != EpdColorMode.threeColor &&
        r < 50 &&
        g < 150 &&
        b > 100) {
      return ColorPalette.sixColorPalette[2]; // 蓝色
    }

    // 三色模式下优先检测红色
    if (mode == EpdColorMode.threeColor) {
      // 如果红色通道显著高于绿色和蓝色，且强度足够
      if (r > 120 && r > g * 1.5 && r > b * 1.5) {
        return ColorPalette.threeColorPalette[2]; // 红色
      }
      // 否则根据亮度选择黑或白
      final luminance = 0.299 * r + 0.587 * g + 0.114 * b;
      return luminance < 128
          ? ColorPalette.threeColorPalette[0]
          : ColorPalette.threeColorPalette[1];
    }

    // 对于其他模式，使用Lab颜色空间计算
    final inputLab = rgbToLab(r, g, b);
    double minDistance = double.infinity;
    ColorPalette closestColor = palette.first;

    for (final color in palette) {
      final colorLab = rgbToLab(color.r, color.g, color.b);
      final distance = labDistance(inputLab, colorLab);
      if (distance < minDistance) {
        minDistance = distance;
        closestColor = color;
      }
    }

    return closestColor;
  }

  // 计算灰度值
  static int calculateGrayscale(int r, int g, int b) {
    return (0.299 * r + 0.587 * g + 0.114 * b).round();
  }

  // 调整对比度
  static List<int> adjustContrast(List<int> pixels, double factor) {
    final adjusted = <int>[];
    for (var i = 0; i < pixels.length; i += 4) {
      final r = pixels[i];
      final g = pixels[i + 1];
      final b = pixels[i + 2];

      adjusted.addAll([
        (128 + (r - 128) * factor).clamp(0, 255).round(),
        (128 + (g - 128) * factor).clamp(0, 255).round(),
        (128 + (b - 128) * factor).clamp(0, 255).round(),
        pixels[i + 3], // Alpha保持不变
      ]);
    }
    return adjusted;
  }
}