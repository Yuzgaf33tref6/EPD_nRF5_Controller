import 'package:epd_controller/devices/canvas_size.dart';
import 'package:epd_controller/devices/epd_driver.dart';
import 'package:epd_controller/image/epd_color.dart';
import 'package:flutter_test/flutter_test.dart';

/// 驱动表与画布尺寸表的一致性检查。
///
/// 这两张表是直接从 `html/index.html` 的下拉框搬过来的，最怕两类错：
/// 搬漏/搬多一项、以及驱动表里引用了不存在的画布尺寸。
void main() {
  group('驱动表', () {
    test('17 项且顺序与网页一致', () {
      expect(kEpdDrivers.length, 17);
      expect(
        kEpdDrivers.map((EpdDriver d) => d.id).toList(),
        <String>[
          '01', '03', '04', '02', '05',
          '0f', '0e', '11', '10', '0d',
          '06', '07', '0c', '08', '09',
          '0a', '0b',
        ],
      );
    });

    test('id 唯一且是两位十六进制', () {
      final Set<String> seen = <String>{};
      for (final EpdDriver driver in kEpdDrivers) {
        expect(seen.add(driver.id), isTrue, reason: 'id ${driver.id} 重复');
        expect(RegExp(r'^[0-9a-f]{2}$').hasMatch(driver.id), isTrue,
            reason: 'id ${driver.id} 不是两位小写十六进制');
        expect(driver.code, int.parse(driver.id, radix: 16));
      }
    });

    test('每个驱动引用的画布尺寸都存在', () {
      for (final EpdDriver driver in kEpdDrivers) {
        expect(canvasSizeByName(driver.canvasSizeName), isNotNull,
            reason: '驱动 ${driver.id} 的画布尺寸 ${driver.canvasSizeName} 不在表里');
        expect(driver.canvasSize.width, greaterThan(0));
        expect(driver.canvasSize.height, greaterThan(0));
      }
    });

    test('颜色模式与 label 里的中文描述一致', () {
      // label 形如 `4.2寸 (三色, UC8176)`，括号里第一个逗号前就是颜色描述。
      const Map<EpdColorMode, String> keywords = <EpdColorMode, String>{
        EpdColorMode.blackWhiteColor: '黑白',
        EpdColorMode.threeColor: '三色',
        EpdColorMode.fourColor: '四色',
        EpdColorMode.sixColor: '六色',
      };
      for (final EpdDriver driver in kEpdDrivers) {
        expect(driver.label.contains(keywords[driver.colorMode]!), isTrue,
            reason: '驱动 ${driver.id} (${driver.label}) 的颜色模式是 ${driver.colorMode.jsName}');
        expect(driver.label.contains(driver.controller), isTrue);
      }
    });

    test('只有 UC8159 低分屏驱动走 4bit 合并通道', () {
      final List<String> uc8159 =
          kEpdDrivers.where((EpdDriver d) => d.usesUc8159).map((EpdDriver d) => d.id).toList();
      expect(uc8159, <String>['0f', '0e', '08', '09']);
      for (final EpdDriver driver in kEpdDrivers) {
        expect(driver.usesUc8159, driver.controller == 'UC8159',
            reason: '驱动 ${driver.id} 的 usesUc8159 与芯片型号不一致');
      }
    });

    test('按 id 与按字节都能查到驱动', () {
      expect(driverById('03')?.controller, 'UC8176');
      expect(driverById('0f')?.usesUc8159, isTrue);
      expect(driverById('zz'), isNull);
      expect(driverByCode(0x03)?.id, '03');
      expect(driverByCode(0x0f)?.id, '0f');
      expect(driverByCode(0xff), isNull);
    });
  });

  group('画布尺寸表', () {
    test('26 项且 name 唯一', () {
      expect(kCanvasSizes.length, 26);
      final Set<String> names = kCanvasSizes.map((EpdCanvasSize s) => s.name).toSet();
      expect(names.length, 26);
    });

    test('name 的后两段与 width/height 一致', () {
      for (final EpdCanvasSize size in kCanvasSizes) {
        final List<String> parts = size.name.split('_');
        expect(parts.length, 3, reason: '${size.name} 不是三段式');
        expect(int.parse(parts[1]), size.width, reason: '${size.name} 宽度');
        expect(int.parse(parts[2]), size.height, reason: '${size.name} 高度');
        expect(size.aspectRatio, closeTo(size.width / size.height, 1e-12));
      }
    });

    test('label 前缀与 name 前缀一致', () {
      for (final EpdCanvasSize size in kCanvasSizes) {
        final String namePrefix = size.name.split('_').first;
        expect(size.label.startsWith('$namePrefix '), isTrue,
            reason: '${size.name} 的 label 是 ${size.label}');
        expect(size.label.contains('${size.width}x${size.height}'), isTrue,
            reason: '${size.name} 的 label 是 ${size.label}');
      }
    });

    test('默认尺寸存在且与网页一致', () {
      expect(kDefaultCanvasSizeName, '4.2_400_300');
      final EpdCanvasSize? size = canvasSizeByName(kDefaultCanvasSizeName);
      expect(size, isNotNull);
      expect(size!.width, 400);
      expect(size.height, 300);
      expect(canvasSizeByName('不存在'), isNull);
    });

    test('货架标签尺寸的产品代号前缀不能当数字解析', () {
      // `4.0E6` 若被 double.parse 会变成 4000000，这里确认我们没这么干。
      final EpdCanvasSize? shelf = canvasSizeByName('4.0E6_600_400');
      expect(shelf, isNotNull);
      expect(shelf!.label, '4.0E6 (600x400)');
      expect(shelf.width, 600);
      expect(shelf.height, 400);
    });
  });
}
