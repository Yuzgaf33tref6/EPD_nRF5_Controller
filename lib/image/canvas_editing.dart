/// 画布手绘编辑：画笔、橡皮、撤销/重做历史。
///
/// 全部是纯 Dart 像素操作，不依赖 Flutter 引擎，方便单元测试。文字工具需要引擎
/// 光栅化字体，单独放在 `text_raster.dart` 里。
///
/// 与 web 版 `html/js/paint.js` 的差别：web 版把每一笔都存在独立 canvas 元素上，
/// 这里直接把笔画烘进位图 —— 抖动与位打包都只认位图，烘进去以后"所见即所发"。
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'epd_color.dart';
import 'rgba_image.dart';

/// 画笔颜色：web 版提供黑白（真实墨水色）等固定几种，这里直接用调色板取值。
class BrushColor {
  const BrushColor(this.label, this.r, this.g, this.b);

  final String label;
  final int r;
  final int g;
  final int b;
}

/// 画布可选的画笔颜色。三色/四色墨水屏只能显示调色板里的颜色，但底图可以有别的
/// 颜色（抖动后会量化），所以这里给黑白红黄蓝绿六种，与 web 版画笔色一致。
const List<BrushColor> kBrushColors = <BrushColor>[
  BrushColor('黑', 0, 0, 0),
  BrushColor('白', 255, 255, 255),
  BrushColor('红', 255, 0, 0),
  BrushColor('黄', 255, 255, 0),
  BrushColor('蓝', 0, 0, 255),
  BrushColor('绿', 41, 204, 20),
];

/// 把单个像素写成指定颜色（不做混合，墨水屏需要硬边）。
void _setPixel(RgbaImage image, int x, int y, int r, int g, int b) {
  if (x < 0 || y < 0 || x >= image.width || y >= image.height) {
    return;
  }
  final int index = (y * image.width + x) * 4;
  image.data[index] = r;
  image.data[index + 1] = g;
  image.data[index + 2] = b;
  image.data[index + 3] = 255;
}

/// 在 (cx, cy) 盖一个实心圆形笔尖。
void _stampCircle(
  RgbaImage image,
  int cx,
  int cy,
  double radius,
  int r,
  int g,
  int b,
) {
  final int extent = radius.ceil();
  final double radiusSquared = radius * radius;
  for (int dy = -extent; dy <= extent; dy++) {
    for (int dx = -extent; dx <= extent; dx++) {
      if (dx * dx + dy * dy <= radiusSquared) {
        _setPixel(image, cx + dx, cy + dy, r, g, b);
      }
    }
  }
}

/// 画一段从 ([x0], [y0]) 到 ([x1], [y1]) 的笔迹。
///
/// 用 1px 步长沿线插值并逐点盖笔尖，这样即使手指移动很快（两次事件间隔几十像素）
/// 也不会断成虚线。坐标允许是小数（触控事件本身就是小数）。
void drawStroke(
  RgbaImage image, {
  required double x0,
  required double y0,
  required double x1,
  required double y1,
  required double radius,
  int r = 0,
  int g = 0,
  int b = 0,
}) {
  final double dx = x1 - x0;
  final double dy = y1 - y0;
  final double distance = math.sqrt(dx * dx + dy * dy);
  final int steps = distance < 1 ? 1 : distance.ceil();
  for (int i = 0; i <= steps; i++) {
    final double t = steps == 0 ? 0 : i / steps;
    _stampCircle(
      image,
      (x0 + dx * t).round(),
      (y0 + dy * t).round(),
      radius,
      r,
      g,
      b,
    );
  }
}

/// 画一个单独的笔尖点（点一下屏幕）。
void drawDot(
  RgbaImage image, {
  required double x,
  required double y,
  required double radius,
  int r = 0,
  int g = 0,
  int b = 0,
}) {
  _stampCircle(image, x.round(), y.round(), radius, r, g, b);
}

/// 橡皮：把像素刷成白色（墨水屏的"无墨"就是白）。
void eraseStroke(
  RgbaImage image, {
  required double x0,
  required double y0,
  required double x1,
  required double y1,
  required double radius,
}) {
  drawStroke(
    image,
    x0: x0,
    y0: y0,
    x1: x1,
    y1: y1,
    radius: radius,
    r: 255,
    g: 255,
    b: 255,
  );
}

/// 用调色板里的某个颜色填满整张图。
void fillImage(RgbaImage image, EpdColor color) {
  final Uint8List data = image.data;
  for (int i = 0; i < data.length; i += 4) {
    data[i] = color.r;
    data[i + 1] = color.g;
    data[i + 2] = color.b;
    data[i + 3] = 255;
  }
}

/// 撤销/重做历史。
///
/// 存整份快照而不是笔画差分：400×300 的 RGBA 快照 480 KB，默认留 12 步约 5.8 MB，
/// 对手机可接受；差分实现要处理分辨率变化、旋转、文字合成等一堆边界，不值得。
class ImageHistory {
  ImageHistory({this.limit = 12});

  /// 最多保留多少步历史（含当前状态）。
  final int limit;

  final List<RgbaImage> _snapshots = <RgbaImage>[];
  int _index = -1;

  /// 当前是不是空历史。
  bool get isEmpty => _index < 0;

  /// 还能撤销。
  bool get canUndo => _index > 0;

  /// 还能重做。
  bool get canRedo => _index >= 0 && _index < _snapshots.length - 1;

  /// 历史里的状态数。
  int get length => _snapshots.length;

  /// 清空历史，并把 [image] 作为初始状态。
  void reset(RgbaImage image) {
    _snapshots
      ..clear()
      ..add(_copy(image));
    _index = 0;
  }

  /// 提交一个新状态（会丢弃 redo 分支）。
  void push(RgbaImage image) {
    if (_index < 0) {
      reset(image);
      return;
    }
    if (_index < _snapshots.length - 1) {
      _snapshots.removeRange(_index + 1, _snapshots.length);
    }
    _snapshots.add(_copy(image));
    while (_snapshots.length > limit) {
      _snapshots.removeAt(0);
    }
    _index = _snapshots.length - 1;
  }

  /// 退一步，返回新状态；不能撤销时返回 null。
  RgbaImage? undo() {
    if (!canUndo) {
      return null;
    }
    _index -= 1;
    return _copy(_snapshots[_index]);
  }

  /// 进一步，返回新状态；不能重做时返回 null。
  RgbaImage? redo() {
    if (!canRedo) {
      return null;
    }
    _index += 1;
    return _copy(_snapshots[_index]);
  }

  static RgbaImage _copy(RgbaImage image) {
    return RgbaImage(
      image.width,
      image.height,
      Uint8List.fromList(image.data),
    );
  }
}
