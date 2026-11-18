/// 驱动表 —— 逐项搬运 web 版 `html/index.html` 的 `#epddriver` 下拉框。
///
/// 每个 option 带 `data-color`（颜色模式）与 `data-size`（画布尺寸），选中后
/// `updateDitcherOptions()` 会把这两个值联动到对应的下拉框。这里把同一份映射
/// 做成不可变数据表，避免 Flutter 侧再解析字符串。
library;

import '../image/epd_color.dart';
import 'canvas_size.dart';

/// 一种可选的墨水屏驱动。
class EpdDriver {
  const EpdDriver({
    required this.id,
    required this.label,
    required this.colorMode,
    required this.canvasSizeName,
    required this.controller,
  });

  /// web 版 option 的 value，两位十六进制字符串，如 `03`、`0f`。
  ///
  /// 它既是 INIT 指令的负载，也是驱动与固件的约定编号，别当十进制用。
  final String id;

  /// web 版 option 的显示文字，如 `4.2寸 (三色, UC8176)`。
  final String label;

  /// 该驱动的原生颜色模式（`data-color`）。
  final EpdColorMode colorMode;

  /// 该驱动对应的画布尺寸（`data-size`）。
  final String canvasSizeName;

  /// 屏驱动芯片型号，仅用于界面展示。
  final String controller;

  /// INIT 指令要发的单字节驱动编号。
  int get code => int.parse(id, radix: 16);

  /// 该驱动对应的画布尺寸；表内数据保证一定存在。
  EpdCanvasSize get canvasSize => canvasSizeByName(canvasSizeName)!;

  /// 是否走 UC8159 的 4bit/px 合并通道。
  ///
  /// web 版 `sendimg()` 里硬编码了 `['08', '09', '0e', '0f']` 这个集合：这四款
  /// 驱动把"黑白 + 红白"两个位平面合并成 4bit/px 一次写入，其余驱动分两次写。
  bool get usesUc8159 => const <String>{'08', '09', '0e', '0f'}.contains(id);

  @override
  String toString() => 'EpdDriver($id, $label)';
}

/// web 版 `#epddriver` 的全部 17 项，顺序与网页一致。
const List<EpdDriver> kEpdDrivers = <EpdDriver>[
  EpdDriver(
    id: '01',
    label: '4.2寸 (黑白, UC8176)',
    colorMode: EpdColorMode.blackWhiteColor,
    canvasSizeName: '4.2_400_300',
    controller: 'UC8176',
  ),
  EpdDriver(
    id: '03',
    label: '4.2寸 (三色, UC8176)',
    colorMode: EpdColorMode.threeColor,
    canvasSizeName: '4.2_400_300',
    controller: 'UC8176',
  ),
  EpdDriver(
    id: '04',
    label: '4.2寸 (黑白, SSD1619)',
    colorMode: EpdColorMode.blackWhiteColor,
    canvasSizeName: '4.2_400_300',
    controller: 'SSD1619',
  ),
  EpdDriver(
    id: '02',
    label: '4.2寸 (三色, SSD1619)',
    colorMode: EpdColorMode.threeColor,
    canvasSizeName: '4.2_400_300',
    controller: 'SSD1619',
  ),
  EpdDriver(
    id: '05',
    label: '4.2寸 (四色, JD79668)',
    colorMode: EpdColorMode.fourColor,
    canvasSizeName: '4.2_400_300',
    controller: 'JD79668',
  ),
  EpdDriver(
    id: '0f',
    label: '5.83寸低分 (黑白, UC8159)',
    colorMode: EpdColorMode.blackWhiteColor,
    canvasSizeName: '5.83_600_448',
    controller: 'UC8159',
  ),
  EpdDriver(
    id: '0e',
    label: '5.83寸低分 (三色, UC8159)',
    colorMode: EpdColorMode.threeColor,
    canvasSizeName: '5.83_600_448',
    controller: 'UC8159',
  ),
  EpdDriver(
    id: '11',
    label: '5.83寸 (黑白, UC8179)',
    colorMode: EpdColorMode.blackWhiteColor,
    canvasSizeName: '5.83_648_480',
    controller: 'UC8179',
  ),
  EpdDriver(
    id: '10',
    label: '5.83寸 (三色, UC8179)',
    colorMode: EpdColorMode.threeColor,
    canvasSizeName: '5.83_648_480',
    controller: 'UC8179',
  ),
  EpdDriver(
    id: '0d',
    label: '5.83寸 (四色, JD79665)',
    colorMode: EpdColorMode.fourColor,
    canvasSizeName: '5.83_648_480',
    controller: 'JD79665',
  ),
  EpdDriver(
    id: '06',
    label: '7.5寸 (黑白, UC8179)',
    colorMode: EpdColorMode.blackWhiteColor,
    canvasSizeName: '7.5_800_480',
    controller: 'UC8179',
  ),
  EpdDriver(
    id: '07',
    label: '7.5寸 (三色, UC8179)',
    colorMode: EpdColorMode.threeColor,
    canvasSizeName: '7.5_800_480',
    controller: 'UC8179',
  ),
  EpdDriver(
    id: '0c',
    label: '7.5寸 (四色, JD79665)',
    colorMode: EpdColorMode.fourColor,
    canvasSizeName: '7.5_800_480',
    controller: 'JD79665',
  ),
  EpdDriver(
    id: '08',
    label: '7.5寸低分 (黑白, UC8159)',
    colorMode: EpdColorMode.blackWhiteColor,
    canvasSizeName: '7.5_640_384',
    controller: 'UC8159',
  ),
  EpdDriver(
    id: '09',
    label: '7.5寸低分 (三色, UC8159)',
    colorMode: EpdColorMode.threeColor,
    canvasSizeName: '7.5_640_384',
    controller: 'UC8159',
  ),
  EpdDriver(
    id: '0a',
    label: '7.5寸HD (黑白, SSD1677)',
    colorMode: EpdColorMode.blackWhiteColor,
    canvasSizeName: '7.5_880_528',
    controller: 'SSD1677',
  ),
  EpdDriver(
    id: '0b',
    label: '7.5寸HD (三色, SSD1677)',
    colorMode: EpdColorMode.threeColor,
    canvasSizeName: '7.5_880_528',
    controller: 'SSD1677',
  ),
];

/// 按两位十六进制 [id] 查驱动，找不到返回 null。
EpdDriver? driverById(String id) {
  for (final EpdDriver driver in kEpdDrivers) {
    if (driver.id == id) {
      return driver;
    }
  }
  return null;
}

/// 按驱动编号字节查驱动（设备配置通知里 `bytes[7]` 就是它）。
EpdDriver? driverByCode(int code) {
  for (final EpdDriver driver in kEpdDrivers) {
    if (driver.code == code) {
      return driver;
    }
  }
  return null;
}
