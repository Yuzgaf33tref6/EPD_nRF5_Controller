/// 墨水屏调色板定义。
///
/// 移植自 web 上位机的 `html/js/dithering.js`。色值与 [EpdColor.value] 必须
/// 与 web 版逐字节一致：`value` 会直接写进墨水屏显存，改动会导致屏幕显示错色。
library;

/// 调色板中的一种颜色。
class EpdColor {
  const EpdColor(this.name, this.r, this.g, this.b, this.value);

  /// 中文颜色名，与 web 版一致，仅用于日志和调试。
  final String name;

  final int r;
  final int g;
  final int b;

  /// 写进显存的调色板编号（不是 RGB 索引）。
  final int value;
}

/// 六色调色板（黑、白、黄、红、蓝、绿），对应 web 版 `rgbPalette`。
///
/// 注意顺序：蓝色在索引 4、绿色在索引 5，与 [EpdColor.value] 的 0x05/0x06 对应。
const List<EpdColor> rgbPalette = <EpdColor>[
  EpdColor('黑色', 0, 0, 0, 0x00),
  EpdColor('白色', 255, 255, 255, 0x01),
  EpdColor('黄色', 255, 255, 0, 0x02),
  EpdColor('红色', 255, 0, 0, 0x03),
  EpdColor('蓝色', 0, 0, 255, 0x05),
  EpdColor('绿色', 41, 204, 20, 0x06),
];

/// 四色调色板（黑、白、红、黄），对应 web 版 `fourColorPalette`。
const List<EpdColor> fourColorPalette = <EpdColor>[
  EpdColor('黑色', 0, 0, 0, 0x00),
  EpdColor('白色', 255, 255, 255, 0x01),
  EpdColor('红色', 255, 0, 0, 0x03),
  EpdColor('黄色', 255, 255, 0, 0x02),
];

/// 三色调色板（黑、白、红），对应 web 版 `threeColorPalette`。
const List<EpdColor> threeColorPalette = <EpdColor>[
  EpdColor('黑色', 0, 0, 0, 0x00),
  EpdColor('白色', 255, 255, 255, 0x01),
  EpdColor('红色', 255, 0, 0, 0x02),
];

/// 墨水屏颜色模式，对应 web 版里各处传递的 `mode` 字符串。
enum EpdColorMode {
  /// 黑白双色。
  blackWhiteColor('blackWhiteColor'),

  /// 三色：黑白红（本项目目标设备 4.2 寸三色屏）。
  threeColor('threeColor'),

  /// 四色：黑白红黄。
  fourColor('fourColor'),

  /// 六色：黑白红黄蓝绿。
  sixColor('sixColor');

  const EpdColorMode(this.jsName);

  /// web 版使用的模式字符串，保留用于对拍测试和日志。
  final String jsName;

  /// 由 web 版字符串还原模式，找不到时抛 [ArgumentError]。
  static EpdColorMode fromJsName(String name) {
    for (final EpdColorMode mode in EpdColorMode.values) {
      if (mode.jsName == name) {
        return mode;
      }
    }
    throw ArgumentError.value(name, 'name', '未知的颜色模式');
  }

  /// 该模式使用的调色板：四色/三色各有专用调色板，其余（黑白、六色）用六色调色板。
  List<EpdColor> get palette {
    switch (this) {
      case EpdColorMode.fourColor:
        return fourColorPalette;
      case EpdColorMode.threeColor:
        return threeColorPalette;
      case EpdColorMode.blackWhiteColor:
      case EpdColorMode.sixColor:
        return rgbPalette;
    }
  }
}
