import 'dart:typed_data';
import 'dart:math';
import 'package:image/image.dart' as img;

int _clampByte(int val) => val < 0 ? 0 : (val > 255 ? 255 : val);

class PaletteColor {
  final String name;
  final int r, g, b;
  final int value;
  PaletteColor(this.name, this.r, this.g, this.b, this.value);
}

final rgbPalette = [
  PaletteColor('黄色', 255, 255, 0, 0xe2),
  PaletteColor('绿色', 41, 204, 20, 0x96),
  PaletteColor('蓝色', 0, 0, 255, 0x1d),
  PaletteColor('红色', 255, 0, 0, 0x4c),
  PaletteColor('黑色', 0, 0, 0, 0x00),
  PaletteColor('白色', 255, 255, 255, 0xff),
];

final fourColorPalette = [
  PaletteColor('黑色', 0, 0, 0, 0x00),
  PaletteColor('白色', 255, 255, 255, 0x01),
  PaletteColor('红色', 255, 0, 0, 0x03),
  PaletteColor('黄色', 255, 255, 0, 0x02),
];

final threeColorPalette = [
  PaletteColor('黑色', 0, 0, 0, 0x00),
  PaletteColor('白色', 255, 255, 255, 0x01),
  PaletteColor('红色', 255, 0, 0, 0x02),
];

class Lab {
  final double l, a, b;
  Lab(this.l, this.a, this.b);
}

Lab rgbToLab(int rIn, int gIn, int bIn) {
  double r = rIn / 255.0;
  double g = gIn / 255.0;
  double b = bIn / 255.0;

  r = r > 0.04045 ? pow((r + 0.055) / 1.055, 2.4).toDouble() : r / 12.92;
  g = g > 0.04045 ? pow((g + 0.055) / 1.055, 2.4).toDouble() : g / 12.92;
  b = b > 0.04045 ? pow((b + 0.055) / 1.055, 2.4).toDouble() : b / 12.92;

  r *= 100;
  g *= 100;
  b *= 100;

  double x = r * 0.4124 + g * 0.3576 + b * 0.1805;
  double y = r * 0.2126 + g * 0.7152 + b * 0.0722;
  double z = r * 0.0193 + g * 0.1192 + b * 0.9505;

  x /= 95.047;
  y /= 100.0;
  z /= 108.883;

  x = x > 0.008856 ? pow(x, 1 / 3).toDouble() : (7.787 * x) + (16 / 116);
  y = y > 0.008856 ? pow(y, 1 / 3).toDouble() : (7.787 * y) + (16 / 116);
  z = z > 0.008856 ? pow(z, 1 / 3).toDouble() : (7.787 * z) + (16 / 116);

  final l = (116 * y) - 16;
  final aVal = 500 * (x - y);
  final bVal = 200 * (y - z);
  return Lab(l, aVal, bVal);
}

double labDistance(Lab l1, Lab l2) {
  final dl = l1.l - l2.l;
  final da = l1.a - l2.a;
  final db = l1.b - l2.b;
  return sqrt(0.2 * dl * dl + 3 * da * da + 3 * db * db);
}

PaletteColor findClosestColor(int r, int g, int b, String mode) {
  List<PaletteColor> palette;
  if (mode == 'fourColor') palette = fourColorPalette;
  else if (mode == 'threeColor') palette = threeColorPalette;
  else palette = rgbPalette;

  if (mode != 'fourColor' && mode != 'threeColor' && r < 50 && g < 150 && b > 100) {
    return rgbPalette[2];
  }

  if (mode == 'threeColor') {
    if (r > 120 && r > g * 1.5 && r > b * 1.5) return threeColorPalette[2];
    final luminance = 0.299 * r + 0.587 * g + 0.114 * b;
    return luminance < 128 ? threeColorPalette[0] : threeColorPalette[1];
  }

  final inputLab = rgbToLab(r, g, b);
  double minDistance = double.infinity;
  PaletteColor closest = palette[0];
  for (final c in palette) {
    final lab = rgbToLab(c.r, c.g, c.b);
    final d = labDistance(inputLab, lab);
    if (d < minDistance) {
      minDistance = d;
      closest = c;
    }
  }
  return closest;
}

class DitherAlgorithms {
  // data is RGBA bytes
  static Uint8List processImageRGBA(Uint8List data, int width, int height,
      {double strength = 1.0, String mode = 'sixColor', String alg = 'floydSteinberg'}) {
    final out = Uint8List.fromList(data);
    if (alg == 'atkinson') return atkinson(out, width, height, strength, mode);
    if (alg == 'stucki') return stucki(out, width, height, strength, mode);
    if (alg == 'jarvis') return jarvis(out, width, height, strength, mode);
    // default floyd
    return floydSteinberg(out, width, height, strength, mode);
  }

  static Uint8List floydSteinberg(Uint8List data, int width, int height, double strength, String mode) {
    final temp = Uint8List.fromList(data);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final idx = (y * width + x) * 4;
        final r = temp[idx];
        final g = temp[idx + 1];
        final b = temp[idx + 2];
        final closest = findClosestColor(r, g, b, mode);
        final errR = (r - closest.r) * strength;
        final errG = (g - closest.g) * strength;
        final errB = (b - closest.b) * strength;

        if (x + 1 < width) {
          final i = idx + 4;
          temp[i] = _clampByte((temp[i] + errR * 7 / 16).round());
          temp[i + 1] = _clampByte((temp[i + 1] + errG * 7 / 16).round());
          temp[i + 2] = _clampByte((temp[i + 2] + errB * 7 / 16).round());
        }
        if (y + 1 < height) {
          if (x > 0) {
            final i = idx + width * 4 - 4;
            temp[i] = _clampByte((temp[i] + errR * 3 / 16).round());
            temp[i + 1] = _clampByte((temp[i + 1] + errG * 3 / 16).round());
            temp[i + 2] = _clampByte((temp[i + 2] + errB * 3 / 16).round());
          }
          final i2 = idx + width * 4;
          temp[i2] = _clampByte((temp[i2] + errR * 5 / 16).round());
          temp[i2 + 1] = _clampByte((temp[i2 + 1] + errG * 5 / 16).round());
          temp[i2 + 2] = _clampByte((temp[i2 + 2] + errB * 5 / 16).round());
          if (x + 1 < width) {
            final i3 = idx + width * 4 + 4;
            temp[i3] = _clampByte((temp[i3] + errR * 1 / 16).round());
            temp[i3 + 1] = _clampByte((temp[i3 + 1] + errG * 1 / 16).round());
            temp[i3 + 2] = _clampByte((temp[i3 + 2] + errB * 1 / 16).round());
          }
        }
      }
    }

    // Write back closest palette
    final out = Uint8List.fromList(data);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final idx = (y * width + x) * 4;
        final r = temp[idx];
        final g = temp[idx + 1];
        final b = temp[idx + 2];
        final c = findClosestColor(r, g, b, mode);
        out[idx] = c.r;
        out[idx + 1] = c.g;
        out[idx + 2] = c.b;
        out[idx + 3] = 255;
      }
    }
    // Convert RGBA bytes to a PNG preview (using package:image)
    final image = img.Image(width: width, height: height);
    for (int i = 0; i < out.length; i += 4) {
      final pixelIdx = i ~/ 4;
      final row = pixelIdx ~/ width;
      final col = pixelIdx % width;
      image.setPixelRgba(col, row, out[i], out[i + 1], out[i + 2], out[i + 3]);
    }
    final png = img.encodePng(image);
    return Uint8List.fromList(png);
  }

  static Uint8List atkinson(Uint8List data, int width, int height, double strength, String mode) {
    final temp = Uint8List.fromList(data);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final idx = (y * width + x) * 4;
        final r = temp[idx];
        final g = temp[idx + 1];
        final b = temp[idx + 2];
        final closest = findClosestColor(r, g, b, mode);
        data[idx] = closest.r;
        data[idx + 1] = closest.g;
        data[idx + 2] = closest.b;
        final errR = (r - closest.r) * strength;
        final errG = (g - closest.g) * strength;
        final errB = (b - closest.b) * strength;
        final fraction = 1 / 8;
        if (x + 1 < width) _addError(temp, idx + 4, errR * fraction, errG * fraction, errB * fraction);
        if (x + 2 < width) _addError(temp, idx + 8, errR * fraction, errG * fraction, errB * fraction);
        if (y + 1 < height) {
          if (x > 0) _addError(temp, idx + width * 4 - 4, errR * fraction, errG * fraction, errB * fraction);
          _addError(temp, idx + width * 4, errR * fraction, errG * fraction, errB * fraction);
          if (x + 1 < width) _addError(temp, idx + width * 4 + 4, errR * fraction, errG * fraction, errB * fraction);
        }
        if (y + 2 < height) _addError(temp, idx + width * 8, errR * fraction, errG * fraction, errB * fraction);
      }
    }
    // encode preview
    final out = Uint8List.fromList(data);
    final image = img.Image(width: width, height: height);
    for (int i = 0; i < out.length; i += 4) {
      final pixelIdx = i ~/ 4;
      final row = pixelIdx ~/ width;
      final col = pixelIdx % width;
      image.setPixelRgba(col, row, out[i], out[i + 1], out[i + 2], out[i + 3]);
    }
    final png = img.encodePng(image);
    return Uint8List.fromList(png);
  }

  static Uint8List stucki(Uint8List data, int width, int height, double strength, String mode) {
    final temp = Uint8List.fromList(data);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final idx = (y * width + x) * 4;
        final r = temp[idx];
        final g = temp[idx + 1];
        final b = temp[idx + 2];
        final closest = findClosestColor(r, g, b, mode);
        data[idx] = closest.r;
        data[idx + 1] = closest.g;
        data[idx + 2] = closest.b;
        final errR = (r - closest.r) * strength;
        final errG = (g - closest.g) * strength;
        final errB = (b - closest.b) * strength;
        const int divisor = 42;

        if (x + 1 < width) {
          final i = idx + 4;
          _addErrorScaled(temp, i, errR * 8 / divisor, errG * 8 / divisor, errB * 8 / divisor);
        }
        if (x + 2 < width) {
          final i = idx + 8;
          _addErrorScaled(temp, i, errR * 4 / divisor, errG * 4 / divisor, errB * 4 / divisor);
        }
        if (y + 1 < height) {
          if (x > 1) {
            final i = idx + width * 4 - 8;
            _addErrorScaled(temp, i, errR * 2 / divisor, errG * 2 / divisor, errB * 2 / divisor);
          }
          if (x > 0) {
            final i = idx + width * 4 - 4;
            _addErrorScaled(temp, i, errR * 4 / divisor, errG * 4 / divisor, errB * 4 / divisor);
          }
          final i2 = idx + width * 4;
          _addErrorScaled(temp, i2, errR * 8 / divisor, errG * 8 / divisor, errB * 8 / divisor);
          if (x + 1 < width) {
            final i3 = idx + width * 4 + 4;
            _addErrorScaled(temp, i3, errR * 4 / divisor, errG * 4 / divisor, errB * 4 / divisor);
          }
          if (x + 2 < width) {
            final i4 = idx + width * 4 + 8;
            _addErrorScaled(temp, i4, errR * 2 / divisor, errG * 2 / divisor, errB * 2 / divisor);
          }
        }
        if (y + 2 < height) {
          if (x > 1) {
            final i = idx + width * 8 - 8;
            _addErrorScaled(temp, i, errR * 1 / divisor, errG * 1 / divisor, errB * 1 / divisor);
          }
          if (x > 0) {
            final i = idx + width * 8 - 4;
            _addErrorScaled(temp, i, errR * 2 / divisor, errG * 2 / divisor, errB * 2 / divisor);
          }
          final i2 = idx + width * 8;
          _addErrorScaled(temp, i2, errR * 4 / divisor, errG * 4 / divisor, errB * 4 / divisor);
          if (x + 1 < width) {
            final i3 = idx + width * 8 + 4;
            _addErrorScaled(temp, i3, errR * 2 / divisor, errG * 2 / divisor, errB * 2 / divisor);
          }
          if (x + 2 < width) {
            final i4 = idx + width * 8 + 8;
            _addErrorScaled(temp, i4, errR * 1 / divisor, errG * 1 / divisor, errB * 1 / divisor);
          }
        }
      }
    }
    final out = Uint8List.fromList(data);
    final image = img.Image(width: width, height: height);
    for (int i = 0; i < out.length; i += 4) {
      final pixelIdx = i ~/ 4;
      final row = pixelIdx ~/ width;
      final col = pixelIdx % width;
      image.setPixelRgba(col, row, out[i], out[i + 1], out[i + 2], out[i + 3]);
    }
    final png = img.encodePng(image);
    return Uint8List.fromList(png);
  }

  static Uint8List jarvis(Uint8List data, int width, int height, double strength, String mode) {
    final temp = Uint8List.fromList(data);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final idx = (y * width + x) * 4;
        final r = temp[idx];
        final g = temp[idx + 1];
        final b = temp[idx + 2];
        final closest = findClosestColor(r, g, b, mode);
        data[idx] = closest.r;
        data[idx + 1] = closest.g;
        data[idx + 2] = closest.b;
        final errR = (r - closest.r) * strength;
        final errG = (g - closest.g) * strength;
        final errB = (b - closest.b) * strength;
        const int divisor = 48;

        if (x + 1 < width) {
          final i = idx + 4;
          _addErrorScaled(temp, i, errR * 7 / divisor, errG * 7 / divisor, errB * 7 / divisor);
        }
        if (x + 2 < width) {
          final i = idx + 8;
          _addErrorScaled(temp, i, errR * 5 / divisor, errG * 5 / divisor, errB * 5 / divisor);
        }
        if (y + 1 < height) {
          if (x > 1) {
            final i = idx + width * 4 - 8;
            _addErrorScaled(temp, i, errR * 3 / divisor, errG * 3 / divisor, errB * 3 / divisor);
          }
          if (x > 0) {
            final i = idx + width * 4 - 4;
            _addErrorScaled(temp, i, errR * 5 / divisor, errG * 5 / divisor, errB * 5 / divisor);
          }
          final i2 = idx + width * 4;
          _addErrorScaled(temp, i2, errR * 7 / divisor, errG * 7 / divisor, errB * 7 / divisor);
          if (x + 1 < width) {
            final i3 = idx + width * 4 + 4;
            _addErrorScaled(temp, i3, errR * 5 / divisor, errG * 5 / divisor, errB * 5 / divisor);
          }
          if (x + 2 < width) {
            final i4 = idx + width * 4 + 8;
            _addErrorScaled(temp, i4, errR * 3 / divisor, errG * 3 / divisor, errB * 3 / divisor);
          }
        }
        if (y + 2 < height) {
          if (x > 1) {
            final i = idx + width * 8 - 8;
            _addErrorScaled(temp, i, errR * 1 / divisor, errG * 1 / divisor, errB * 1 / divisor);
          }
          if (x > 0) {
            final i = idx + width * 8 - 4;
            _addErrorScaled(temp, i, errR * 3 / divisor, errG * 3 / divisor, errB * 3 / divisor);
          }
          final i2 = idx + width * 8;
          _addErrorScaled(temp, i2, errR * 5 / divisor, errG * 5 / divisor, errB * 5 / divisor);
          if (x + 1 < width) {
            final i3 = idx + width * 8 + 4;
            _addErrorScaled(temp, i3, errR * 3 / divisor, errG * 3 / divisor, errB * 3 / divisor);
          }
          if (x + 2 < width) {
            final i4 = idx + width * 8 + 8;
            _addErrorScaled(temp, i4, errR * 1 / divisor, errG * 1 / divisor, errB * 1 / divisor);
          }
        }
      }
    }
    final out = Uint8List.fromList(data);
    final image = img.Image(width: width, height: height);
    for (int i = 0; i < out.length; i += 4) {
      final pixelIdx = i ~/ 4;
      final row = pixelIdx ~/ width;
      final col = pixelIdx % width;
      image.setPixelRgba(col, row, out[i], out[i + 1], out[i + 2], out[i + 3]);
    }
    final png = img.encodePng(image);
    return Uint8List.fromList(png);
  }
}

// Static helper functions defined outside the class
void _addError(Uint8List arr, int idx, double errR, double errG, double errB) {
  if (idx + 2 >= arr.length) return;
  arr[idx] = _clampByteHelper((arr[idx] + errR).round());
  arr[idx + 1] = _clampByteHelper((arr[idx + 1] + errG).round());
  arr[idx + 2] = _clampByteHelper((arr[idx + 2] + errB).round());
}

void _addErrorScaled(Uint8List arr, int idx, double errR, double errG, double errB) {
  _addError(arr, idx, errR, errG, errB);
}

int _clampByteHelper(int v) => v < 0 ? 0 : (v > 255 ? 255 : v);