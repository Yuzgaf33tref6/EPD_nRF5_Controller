// Placeholder color palette mapping
class ColorPaletteItem {
  final String name;
  final int r, g, b;
  final int value;
  const ColorPaletteItem(this.name, this.r, this.g, this.b, this.value);

  static const List<ColorPaletteItem> sixColor = [
    ColorPaletteItem('黄色', 255, 255, 0, 0xe2),
    ColorPaletteItem('绿色', 41, 204, 20, 0x96),
    ColorPaletteItem('蓝色', 0, 0, 255, 0x1d),
    ColorPaletteItem('红色', 255, 0, 0, 0x4c),
    ColorPaletteItem('黑色', 0, 0, 0, 0x00),
    ColorPaletteItem('白色', 255, 255, 255, 0xff),
  ];
}
