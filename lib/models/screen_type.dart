enum EpdColorMode {
  blackWhiteColor,
  threeColor,
  fourColor,
  sixColor,
}

enum DitherAlgorithm {
  floydSteinberg,
  atkinson,
  bayer,
  stucki,
  jarvis,
  none,
}

class ScreenType {
  final String name;
  final int width;
  final int height;
  final String driver;
  final EpdColorMode colorMode;
  final bool isDebug;

  const ScreenType({
    required this.name,
    required this.width,
    required this.height,
    required this.driver,
    required this.colorMode,
    this.isDebug = false,
  });

  // 从Web的data-size格式解析
  factory ScreenType.fromSizeString(String sizeString, 
      {required String driver, required EpdColorMode colorMode, bool debug = false}) {
    
    final parts = sizeString.split('_');
    if (parts.length >= 3) {
      final sizeName = parts[0];
      final width = int.tryParse(parts[1]) ?? 400;
      final height = int.tryParse(parts[2]) ?? 300;
      
      return ScreenType(
        name: sizeName,
        width: width,
        height: height,
        driver: driver,
        colorMode: colorMode,
        isDebug: debug,
      );
    }
    
    return ScreenType(
      name: '4.2',
      width: 400,
      height: 300,
      driver: driver,
      colorMode: colorMode,
      isDebug: debug,
    );
  }

  // 获取所有预设屏幕类型
  static List<ScreenType> get presets => [
    // 4.2寸屏幕
    const ScreenType(
      name: '4.2寸黑白UC8176',
      width: 400,
      height: 300,
      driver: '01',
      colorMode: EpdColorMode.blackWhiteColor,
    ),
    const ScreenType(
      name: '4.2寸三色UC8176',
      width: 400,
      height: 300,
      driver: '03',
      colorMode: EpdColorMode.threeColor,
    ),
    const ScreenType(
      name: '4.2寸黑白SSD1619',
      width: 400,
      height: 300,
      driver: '04',
      colorMode: EpdColorMode.blackWhiteColor,
    ),
    const ScreenType(
      name: '4.2寸三色SSD1619',
      width: 400,
      height: 300,
      driver: '02',
      colorMode: EpdColorMode.threeColor,
    ),
    const ScreenType(
      name: '4.2寸四色JD79668',
      width: 400,
      height: 300,
      driver: '05',
      colorMode: EpdColorMode.fourColor,
    ),
    // 7.5寸屏幕
    const ScreenType(
      name: '7.5寸黑白UC8179',
      width: 800,
      height: 480,
      driver: '06',
      colorMode: EpdColorMode.blackWhiteColor,
    ),
    const ScreenType(
      name: '7.5寸三色UC8179',
      width: 800,
      height: 480,
      driver: '07',
      colorMode: EpdColorMode.threeColor,
    ),
    const ScreenType(
      name: '7.5寸四色JD79668',
      width: 800,
      height: 480,
      driver: '0c',
      colorMode: EpdColorMode.fourColor,
    ),
    // 调试模式下的额外选项
    const ScreenType(
      name: '7.5寸低分黑白UC8159',
      width: 640,
      height: 384,
      driver: '08',
      colorMode: EpdColorMode.blackWhiteColor,
      isDebug: true,
    ),
    const ScreenType(
      name: '7.5寸低分三色UC8159',
      width: 640,
      height: 384,
      driver: '09',
      colorMode: EpdColorMode.threeColor,
      isDebug: true,
    ),
    const ScreenType(
      name: '7.5寸HD黑白SSD1677',
      width: 880,
      height: 528,
      driver: '0a',
      colorMode: EpdColorMode.blackWhiteColor,
      isDebug: true,
    ),
    const ScreenType(
      name: '7.5寸HD三色SSD1677',
      width: 880,
      height: 528,
      driver: '0b',
      colorMode: EpdColorMode.threeColor,
      isDebug: true,
    ),
  ];

  // 根据驱动值获取屏幕类型
  static ScreenType? fromDriver(String driver) {
    return presets.firstWhere(
      (type) => type.driver == driver,
      orElse: () => presets.first,
    );
  }

  @override
  String toString() => '$name (${width}x$height)';
}