/// CIELAB 色彩空间与色差计算。
///
/// 移植自 web 上位机的 `html/js/dithering.js`（`rgbToLab` / `labDistance`）。
/// 浮点运算顺序必须与 JS 完全一致，否则抖动结果会出现个别像素偏差。
///
/// web 版里另有 `colorDistance` / `findNearestColor`（RGB 欧氏距离），但它们只被
/// `findClosestColor` 中一段从未被调用的 `BWR` 分支使用，属于死代码，未移植。
library;

import 'dart:math' as math;

/// CIELAB 颜色值（L 为明度，a/b 为色度轴）。
class LabColor {
  const LabColor(this.l, this.a, this.b);

  final double l;
  final double a;
  final double b;
}

/// sRGB 到线性 RGB 的分段变换（与 web 版逐行一致）。
double _linearize(double v) =>
    v > 0.04045 ? math.pow((v + 0.055) / 1.055, 2.4).toDouble() : v / 12.92;

/// XYZ 到 Lab 的立方根分段变换。
double _f(double v) =>
    v > 0.008856 ? math.pow(v, 1 / 3).toDouble() : 7.787 * v + (16 / 116);

/// 把 sRGB 分量（0-255，允许小数）转换成 CIELAB。
LabColor rgbToLab(num r, num g, num b) {
  final double lr = _linearize(r / 255);
  final double lg = _linearize(g / 255);
  final double lb = _linearize(b / 255);

  final double r100 = lr * 100;
  final double g100 = lg * 100;
  final double b100 = lb * 100;

  final double xRaw = r100 * 0.4124 + g100 * 0.3576 + b100 * 0.1805;
  final double yRaw = r100 * 0.2126 + g100 * 0.7152 + b100 * 0.0722;
  final double zRaw = r100 * 0.0193 + g100 * 0.1192 + b100 * 0.9505;

  final double x = _f(xRaw / 95.047);
  final double y = _f(yRaw / 100.0);
  final double z = _f(zRaw / 108.883);

  return LabColor((116 * y) - 16, 500 * (x - y), 200 * (y - z));
}

/// Lab 空间加权色差：`sqrt(0.2*dl^2 + 3*da^2 + 3*db^2)`。
double labDistance(LabColor c1, LabColor c2) {
  final double dl = c1.l - c2.l;
  final double da = c1.a - c2.a;
  final double db = c1.b - c2.b;
  return math.sqrt(0.2 * dl * dl + 3 * da * da + 3 * db * db);
}
