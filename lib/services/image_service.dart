import 'package:flutter/foundation.dart';
import '../models/screen_type.dart';

class ImageService extends ChangeNotifier {
  String? imageData;
  ScreenType selectedScreenType = ScreenType.presets[0];
  
  void setImageData(String? data) {
    imageData = data;
    notifyListeners();
  }
  
  void setScreenType(ScreenType type) {
    selectedScreenType = type;
    notifyListeners();
  }
}