import 'dart:typed_data';

// Placeholder image service: converts decoded image RGBA into device-specific byte arrays
class ImageService {
  ImageService();

  // TODO: implement conversion per device drivers (black/white, 3-color, 4-color, 6-color)
  // For now return input bytes unchanged or minimal transform
  Uint8List prepareImageData(Uint8List rgba, int width, int height, String mode) {
    // Implement conversion algorithm later (use DitherAlgorithms, ImageConverter)
    return rgba;
  }
}
