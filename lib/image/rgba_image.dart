/// 简易 RGBA 位图容器。
///
/// 等价于浏览器里的 `ImageData`：每像素 4 字节（R、G、B、A），行优先、无 padding。
/// 之所以不用 Flutter 的 `ui.Image`，是因为图像处理核心层要能在纯 Dart 环境
/// （`flutter test` 无 UI）下逐字节对拍 web 版的结果。
library;

import 'dart:typed_data';

/// 不可变的宽高 + 可变的像素缓冲。
///
/// [data] 长度必须是 `width * height * 4`，Alpha 通道不参与墨水屏计算但保留，
/// 以便和 web 版字节布局完全一致。
class RgbaImage {
  RgbaImage(this.width, this.height, [Uint8List? data])
      : data = data ?? Uint8List(width * height * 4) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('图像尺寸必须为正：${width}x$height');
    }
    final int expected = width * height * 4;
    if (this.data.length != expected) {
      throw ArgumentError(
        '像素缓冲长度应为 $expected（${width}x$height RGBA），实际为 ${this.data.length}',
      );
    }
  }

  final int width;
  final int height;
  final Uint8List data;

  /// 深拷贝，避免算法就地修改调用方的数据。
  RgbaImage clone() => RgbaImage(width, height, Uint8List.fromList(data));
}
