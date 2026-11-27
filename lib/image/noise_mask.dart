/// 蓝噪声阈值表的加载与解码。
///
/// 内置资产的来源见 `assets/NOTICE.md`：`.png` 是 64×64、8 位灰度的蓝噪声
/// 排序矩阵，每个像素就是一个「阈值排名」（0-255，分布均匀）。抖动时按
/// `(y % 64) * 64 + (x % 64)` 平铺取样即可，肉眼看不到规则网格。
///
/// 为什么不做成程序生成：真正的蓝噪声需要频谱优化（void-and-cluster 之类），
/// 现算一次要几百毫秒且不稳定；内置一张 4 KB 的纹理是业界常规做法。
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

/// 内置蓝噪声纹理的资产路径（需在 pubspec.yaml 里注册）。
const String kBlueNoiseAsset = 'assets/blue_noise_64.png';

/// 内置纹理的边长（像素）。
const int kBlueNoiseTextureEdge = 64;

/// 把一张灰度 PNG 解码成阈值表（取 R 通道即可，灰度三通道相同）。
///
/// 解码失败、或者尺寸不是正方形时返回 null，调用方应退回
/// `syntheticNoiseMask()` 兜底，不要抛异常打断预览。
Future<Uint8List?> decodeNoiseMask(Uint8List pngBytes) async {
  ui.Codec? codec;
  ui.Image? image;
  try {
    codec = await ui.instantiateImageCodec(pngBytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    image = frame.image;
    final ByteData? data =
        await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) {
      return null;
    }
    final Uint8List rgba = data.buffer.asUint8List();
    final int pixelCount = image.width * image.height;
    if (pixelCount <= 0 || rgba.length < pixelCount * 4) {
      return null;
    }
    final Uint8List mask = Uint8List(pixelCount);
    for (int i = 0; i < pixelCount; i++) {
      mask[i] = rgba[i * 4];
    }
    return mask;
  } catch (_) {
    return null;
  } finally {
    image?.dispose();
    codec?.dispose();
  }
}

/// 从 assets 读取并解码蓝噪声纹理。
///
/// 任何异常（资产缺失、解码失败）都收敛成 null，由调用方决定怎么兜底。
Future<Uint8List?> loadNoiseMask({AssetBundle? bundle}) async {
  try {
    final ByteData data = await (bundle ?? rootBundle).load(kBlueNoiseAsset);
    return decodeNoiseMask(data.buffer.asUint8List());
  } catch (_) {
    return null;
  }
}

/// 由掩膜长度推算边长；不是正方形时退回内置边长。
int squareEdgeOf(Uint8List mask) {
  final int edge = _integerSqrt(mask.length);
  return edge > 0 ? edge : kBlueNoiseTextureEdge;
}

int _integerSqrt(int value) {
  if (value <= 0) {
    return 0;
  }
  int guess = value;
  int next = (guess + 1) ~/ 2;
  while (next < guess) {
    guess = next;
    next = (guess + value ~/ guess) ~/ 2;
  }
  return guess * guess == value ? guess : 0;
}
