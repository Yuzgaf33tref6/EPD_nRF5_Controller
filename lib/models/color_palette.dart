import 'package:flutter/material.dart';
import 'screen_type.dart';

class ColorPalette {
  final String name;
  final int r;
  final int g;
  final int b;
  final int value;

  const ColorPalette({
    required this.name,
    required this.r,
    required this.g,
    required this.b,
    required this.value,
  });

  // 六色调色板
  static const List<ColorPalette> sixColorPalette = [
    ColorPalette(name: "黄色", r: 255, g: 255, b: 0, value: 0xe2),
    ColorPalette(name: "绿色", r: 41, g: 204, b: 20, value: 0x96),
    ColorPalette(name: "蓝色", r: 0, g: 0, b: 255, value: 0x1d),
    ColorPalette(name: "红色", r: 255, g: 0, b: 0, value: 0x4c),
    ColorPalette(name: "黑色", r: 0, g: 0, b: 0, value: 0x00),
    ColorPalette(name: "白色", r: 255, g: 255, b: 255, value: 0xff),
  ];

  // 四色调色板
  static const List<ColorPalette> fourColorPalette = [
    ColorPalette(name: "黑色", r: 0, g: 0, b: 0, value: 0x00),
    ColorPalette(name: "白色", r: 255, g: 255, b: 255, value: 0x01),
    ColorPalette(name: "红色", r: 255, g: 0, b: 0, value: 0x03),
    ColorPalette(name: "黄色", r: 255, g: 255, b: 0, value: 0x02),
  ];

  // 三色调色板
  static const List<ColorPalette> threeColorPalette = [
    ColorPalette(name: "黑色", r: 0, g: 0, b: 0, value: 0x00),
    ColorPalette(name: "白色", r: 255, g: 255, b: 255, value: 0x01),
    ColorPalette(name: "红色", r: 255, g: 0, b: 0, value: 0x02),
  ];

  // 获取对应模式的调色板
  static List<ColorPalette> getPaletteByMode(EpdColorMode mode) {
    switch (mode) {
      case EpdColorMode.fourColor:
        return fourColorPalette;
      case EpdColorMode.threeColor:
        return threeColorPalette;
      case EpdColorMode.sixColor:
        return sixColorPalette;
      case EpdColorMode.blackWhiteColor:
        return [threeColorPalette[0], threeColorPalette[1]]; // 黑白模式
    }
  }

  // 将颜色转换为Flutter Color对象
  Color toColor() => Color.fromRGBO(r, g, b, 1.0);
}