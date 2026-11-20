import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image_picker/image_picker.dart';

import '../image/rgba_image.dart';

/// 把任意格式的图片字节解码成 RGBA8888 像素。
///
/// 用 `dart:ui` 的解码器（Android 上就是系统的 BitmapFactory），这样可以支持
/// JPEG/PNG/WebP/HEIC 等所有系统认识的格式，也不需要额外依赖 `package:image`。
Future<RgbaImage?> decodeRgbaImage(Uint8List bytes) async {
  if (bytes.isEmpty) {
    return null;
  }
  final ui.Codec codec = await ui.instantiateImageCodec(bytes);
  try {
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ui.Image image = frame.image;
    try {
      final int width = image.width;
      final int height = image.height;
      final ByteData? data = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (data == null) {
        return null;
      }
      return RgbaImage(
        width,
        height,
        Uint8List.fromList(data.buffer.asUint8List()),
      );
    } finally {
      image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

/// 选图能力的抽象，便于在测试里替换掉真实的系统相册。
abstract class ImagePickService {
  /// 从相册选一张图；取消返回 null。
  Future<RgbaImage?> pickFromGallery();
}

/// 基于 `image_picker` 的真实实现。
class GalleryImagePickService implements ImagePickService {
  GalleryImagePickService({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// 选图阶段让系统先缩小一次的上限。
  ///
  /// 墨水屏最大也就 800x480，但裁切时用户会放大细看，所以留足余量：
  /// 4096 长边在 400×300 的画布上放大到 5 倍仍有余量，同时把内存压在
  /// 64MB 以内（4096×3072×4 ≈ 48MB），不会因为一张手机原图（约 4000 万像素、
  /// 160MB）直接把进程顶掉。
  static const double _maxSourceEdge = 4096;

  @override
  Future<RgbaImage?> pickFromGallery() async {
    final XFile? file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: _maxSourceEdge,
      maxHeight: _maxSourceEdge,
      requestFullMetadata: false,
    );
    if (file == null) {
      return null;
    }
    return decodeRgbaImage(await file.readAsBytes());
  }
}
