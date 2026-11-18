/// 画布尺寸表 —— 逐项搬运 web 版 `html/index.html` 的 `#canvasSize` 下拉框
/// （与 `html/js/main.js:27-54` 的 `canvasSizes` 数组一一对应）。
///
/// [name] 同时是 web 版 option 的 value、驱动表的 `data-size`、以及画布尺寸的
/// 唯一标识；不要自己另起格式。
library;

/// 一种可选画布尺寸。
class EpdCanvasSize {
  const EpdCanvasSize({
    required this.name,
    required this.label,
    required this.width,
    required this.height,
  });

  /// web 版 option 的 value，形如 `4.2_400_300`。
  final String name;

  /// web 版 option 的显示文字，形如 `4.2 (400x300)`。
  ///
  /// 注意：这里的 "4.2" 是屏幕对角线英寸数，但 `4.0E6` / `7.3E6` 是货架标签的
  /// 产品代号（不是 4.0×10^6 英寸），所以**不要**把前缀当数字解析。
  final String label;

  final int width;
  final int height;

  /// 宽高比，用于判断待导入图片要不要进裁剪模式。
  double get aspectRatio => width / height;

  @override
  String toString() => 'EpdCanvasSize($name, $width x $height)';
}

/// web 版 `#canvasSize` 的全部 26 项，顺序与网页一致（默认选中 `4.2_400_300`）。
const List<EpdCanvasSize> kCanvasSizes = <EpdCanvasSize>[
  EpdCanvasSize(name: '1.54_152_152', label: '1.54 (152x152)', width: 152, height: 152),
  EpdCanvasSize(name: '1.54_200_200', label: '1.54 (200x200)', width: 200, height: 200),
  EpdCanvasSize(name: '2.13_104_212', label: '2.13 (104x212)', width: 104, height: 212),
  EpdCanvasSize(name: '2.13_122_250', label: '2.13 (122x250)', width: 122, height: 250),
  EpdCanvasSize(name: '2.66_152_296', label: '2.66 (152x296)', width: 152, height: 296),
  EpdCanvasSize(name: '2.66_184_360', label: '2.66 (184x360)', width: 184, height: 360),
  EpdCanvasSize(name: '2.9_128_296', label: '2.9 (128x296)', width: 128, height: 296),
  EpdCanvasSize(name: '2.9_168_384', label: '2.9 (168x384)', width: 168, height: 384),
  EpdCanvasSize(name: '3.5_184_384', label: '3.5 (184x384)', width: 184, height: 384),
  EpdCanvasSize(name: '3.5_360_600', label: '3.5 (360x600)', width: 360, height: 600),
  EpdCanvasSize(name: '3.7_240_416', label: '3.7 (240x416)', width: 240, height: 416),
  EpdCanvasSize(name: '3.7_280_480', label: '3.7 (280x480)', width: 280, height: 480),
  EpdCanvasSize(name: '3.97_800_480', label: '3.97 (800x480)', width: 800, height: 480),
  EpdCanvasSize(name: '3.98_768_552', label: '3.98 (768x552)', width: 768, height: 552),
  EpdCanvasSize(name: '4.2_400_300', label: '4.2 (400x300)', width: 400, height: 300),
  EpdCanvasSize(name: '5.79_792_272', label: '5.79 (792x272)', width: 792, height: 272),
  EpdCanvasSize(name: '5.83_600_448', label: '5.83 (600x448)', width: 600, height: 448),
  EpdCanvasSize(name: '5.83_648_480', label: '5.83 (648x480)', width: 648, height: 480),
  EpdCanvasSize(name: '7.5_640_384', label: '7.5 (640x384)', width: 640, height: 384),
  EpdCanvasSize(name: '7.5_800_480', label: '7.5 (800x480)', width: 800, height: 480),
  EpdCanvasSize(name: '7.5_880_528', label: '7.5 (880x528)', width: 880, height: 528),
  EpdCanvasSize(name: '10.2_960_640', label: '10.2 (960x640)', width: 960, height: 640),
  EpdCanvasSize(name: '10.85_1360_480', label: '10.85 (1360x480)', width: 1360, height: 480),
  EpdCanvasSize(name: '11.6_960_640', label: '11.6 (960x640)', width: 960, height: 640),
  EpdCanvasSize(name: '4.0E6_600_400', label: '4.0E6 (600x400)', width: 600, height: 400),
  EpdCanvasSize(name: '7.3E6_800_480', label: '7.3E6 (800x480)', width: 800, height: 480),
];

/// web 版默认选中的画布尺寸。
const String kDefaultCanvasSizeName = '4.2_400_300';

/// 按 [name] 查画布尺寸，找不到返回 null（web 版此时会抛异常，这里不抛）。
EpdCanvasSize? canvasSizeByName(String name) {
  for (final EpdCanvasSize size in kCanvasSizes) {
    if (size.name == name) {
      return size;
    }
  }
  return null;
}
