import 'dart:typed_data';

import 'package:epd_controller/devices/epd_driver.dart';
import 'package:epd_controller/image/epd_color.dart';
import 'package:epd_controller/image/rgba_image.dart';
import 'package:epd_controller/protocol/epd_protocol.dart';
import 'package:epd_controller/protocol/transfer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/golden.dart';

/// 传输编排与 web 版 `sendimg()` 的逐字节对拍。
///
/// golden 由 `tools/gen-transfer-golden.mjs` 生成：位打包直接 eval 真实
/// `dithering.js`，分流/分块/UC8159 按 `main.js` 逐行抄写。
void main() {
  group('planImageTransfer 与 web 版对拍', () {
    final Map<String, dynamic> golden = loadGoldenJson('transfer.json');
    final Map<String, dynamic> images = golden['images'] as Map<String, dynamic>;
    final List<dynamic> cases = golden['cases'] as List<dynamic>;

    test('至少有 7 组向量', () {
      expect(cases.length, greaterThanOrEqualTo(7));
    });

    for (final dynamic rawCase in cases) {
      final Map<String, dynamic> testCase = rawCase as Map<String, dynamic>;
      final String name = testCase['name'] as String;

      test(name, () {
        final RgbaImage image =
            imageFromGolden(images[testCase['imageName']] as Map<String, dynamic>);
        final EpdDriver driver = driverById(testCase['driverId'] as String)!;
        final ImageTransferPlan plan = planImageTransfer(
          image: image,
          driver: driver,
          colorMode: EpdColorMode.fromJsName(testCase['colorMode'] as String),
          canvasSizeName: testCase['canvasSizeName'] as String,
          mtu: testCase['mtu'] as int,
          rleSupported: testCase['rleSupported'] as bool,
          interleavedCount: testCase['interleavedCount'] as int,
        );

        expect(plan.processedBytes, testCase['processedBytes'], reason: '位打包长度');
        expect(plan.imageWrites, testCase['imageWrites'], reason: 'WRITE_IMG 条数');
        expect(plan.usedUc8159, testCase['usedUc8159'], reason: 'UC8159 通道');
        expect(plan.usedRle, testCase['usedRle'], reason: 'RLE 是否生效');

        final List<dynamic> expectedWarnings = testCase['warnings'] as List<dynamic>;
        expect(
          plan.warnings.map((TransferWarning w) => w.name).toList(),
          expectedWarnings,
          reason: '不匹配警告',
        );

        final List<dynamic> expectedWrites = testCase['writes'] as List<dynamic>;
        expect(plan.writes.length, expectedWrites.length, reason: '写指令总条数');
        for (int i = 0; i < expectedWrites.length; i++) {
          final Map<String, dynamic> write = expectedWrites[i] as Map<String, dynamic>;
          expectBytesMatchGoldenPayload(
            write['payload_base64'] as String,
            plan.writes[i].payload,
            '第 $i 条写指令',
          );
          expect(
            plan.writes[i].withResponse,
            write['withResponse'] as bool,
            reason: '第 $i 条写指令的应答要求',
          );
        }

        // 首尾固定：INIT 开头、REFRESH 结尾。
        expect(plan.writes.first.command, EpdCmd.init);
        expect(plan.writes.last.command, EpdCmd.refresh);
      });
    }
  });

  group('驱动配置', () {
    test('planSetDriver 先 SET_PINS 再 INIT', () {
      final EpdDriver driver = driverById('03')!;
      final List<EpdWrite> writes = planSetDriver(driver: driver, pinsHex: '0508090A0B0C0D');
      expect(writes.length, 2);
      expect(writes[0].payload, <int>[0x00, 0x05, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d]);
      expect(writes[1].payload, <int>[0x01, 0x03]);
      expect(writes[0].withResponse, isTrue);
      expect(writes[1].withResponse, isTrue);
      expect(writes[0].command, EpdCmd.setPins);
      expect(writes[1].command, EpdCmd.init);
    });

    test('planConfigureFromNotification 用设备上报的引脚与驱动号', () {
      final EpdConfig config = EpdConfig(
        pins: Uint8List.fromList(<int>[0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10]),
        driver: 0x02,
      );
      final List<EpdWrite> writes = planConfigureFromNotification(config);
      expect(writes.length, 2);
      expect(writes[0].payload.sublist(1), config.pins);
      expect(writes[1].payload, <int>[0x01, 0x02]);
    });

    test('驱动号不在表里时不给指令', () {
      final EpdConfig config = EpdConfig(
        pins: Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7]),
        driver: 0x7f,
      );
      expect(planConfigureFromNotification(config), isEmpty);
    });
  });

  group('设备控制指令', () {
    test('planSyncTime 的负载是 4 字节大端时间戳 + 时区 + 模式', () {
      final EpdWrite write = planSyncTime(unixSeconds: 1763500000, utcOffsetHours: 8).single;
      expect(write.command, EpdCmd.setTime);
      final Uint8List data = write.data;
      expect(data.length, 6);
      expect(data[0], (1763500000 >> 24) & 0xff);
      expect(data[1], (1763500000 >> 16) & 0xff);
      expect(data[2], (1763500000 >> 8) & 0xff);
      expect(data[3], 1763500000 & 0xff);
      expect(data[4], 8);
      expect(data[5], EpdTimeMode.calendar.code);
    });

    test('时钟模式写 2', () {
      final EpdWrite write =
          planSyncTime(unixSeconds: 0, utcOffsetHours: -5, mode: EpdTimeMode.clock).single;
      expect(write.data[4], 0xfb, reason: '负数时区取低 8 位');
      expect(write.data[5], 2);
    });

    test('清屏/刷新/休眠', () {
      expect(planClearScreen().single.payload, <int>[0x02]);
      expect(planRefresh().single.payload, <int>[0x05]);
      expect(planSleep().single.payload, <int>[0x06]);
    });

    test('手输命令：合法十六进制原样发出', () {
      expect(planRawCommand('300102')?.payload, <int>[0x30, 0x01, 0x02]);
      expect(planRawCommand('  ') , isNull);
      expect(planRawCommand('0'), isNull, reason: '奇数长度判为非法');
      expect(planRawCommand('zz'), isNull);
      // web 版 hex2bytes 也不处理空格，这里保持同样严格的行为。
      expect(planRawCommand('30 01'), isNull);
    });

    test('parseHexBytes 的报错', () {
      expect(() => parseHexBytes('abc'), throwsFormatException);
      expect(() => parseHexBytes('zz'), throwsFormatException);
      expect(parseHexBytes(''), isEmpty);
    });
  });

  group('平面排查开关', () {
    // 32×8 的小图：三色模式下两个位平面各 32 字节（4 字节/行 × 8 行）。
    RgbaImage buildImage() {
      final RgbaImage image = RgbaImage(32, 8);
      for (int i = 0; i < 32 * 8; i++) {
        final int offset = i * 4;
        image.data[offset] = 220; // 纯红：黑白平面判黑、红白平面判红（都是 0 位）
        image.data[offset + 3] = 255;
      }
      return image;
    }

    ImageTransferPlan plan({bool swap = false, bool invert = false}) {
      return planImageTransfer(
        image: buildImage(),
        driver: driverById('03')!,
        colorMode: EpdColorMode.threeColor,
        canvasSizeName: '4.2_400_300',
        mtu: 20,
        rleSupported: false,
        swapPlanes: swap,
        invertRedPlane: invert,
      );
    }

    /// payload = [0x30, flag, ...data]，这里只比数据段。
    List<int> dataOf(EpdWrite write) => write.payload.sublist(2);

    test('默认不变；打开取反后红白平面的每个数据字节都翻过来', () {
      final ImageTransferPlan normal = plan();
      final ImageTransferPlan inverted = plan(invert: true);
      expect(inverted.imageWrites, normal.imageWrites);
      final int half = normal.imageWrites ~/ 2;
      for (int i = 0; i < half; i++) {
        // 黑白平面不受影响。
        expect(dataOf(inverted.writes[1 + i]), dataOf(normal.writes[1 + i]));
        // 红白平面整体取反。
        final List<int> a = dataOf(normal.writes[1 + half + i]);
        final List<int> b = dataOf(inverted.writes[1 + half + i]);
        expect(b.length, a.length);
        for (int j = 0; j < a.length; j++) {
          expect(b[j], 0xFF ^ a[j]);
        }
      }
    });

    test('调换平面后两段数据互换', () {
      final ImageTransferPlan normal = plan();
      final ImageTransferPlan swapped = plan(swap: true);
      final int half = normal.imageWrites ~/ 2;
      for (int i = 0; i < half; i++) {
        expect(dataOf(swapped.writes[1 + i]), dataOf(normal.writes[1 + half + i]));
        expect(dataOf(swapped.writes[1 + half + i]), dataOf(normal.writes[1 + i]));
      }
    });
  });

  group('参数校验与兼容性提示', () {
    test('mtu 小于 3 抛参数错误（web 版会死循环）', () {
      final RgbaImage image = RgbaImage(8, 8);
      expect(
        () => planImageTransfer(
          image: image,
          driver: driverById('01')!,
          colorMode: EpdColorMode.blackWhiteColor,
          canvasSizeName: '4.2_400_300',
          mtu: 2,
          rleSupported: false,
        ),
        throwsArgumentError,
      );
    });

    test('interleavedCount 小于 1 抛参数错误', () {
      final RgbaImage image = RgbaImage(8, 8);
      expect(
        () => planImageTransfer(
          image: image,
          driver: driverById('01')!,
          colorMode: EpdColorMode.blackWhiteColor,
          canvasSizeName: '4.2_400_300',
          mtu: 20,
          rleSupported: false,
          interleavedCount: 0,
        ),
        throwsArgumentError,
      );
    });

    test('完全匹配时没有警告，尺寸/颜色不符时各出一条', () {
      final EpdDriver driver = driverById('03')!;
      expect(
        checkTransferCompatibility(
          driver: driver,
          colorMode: EpdColorMode.threeColor,
          canvasSizeName: '4.2_400_300',
        ),
        isEmpty,
      );
      expect(
        checkTransferCompatibility(
          driver: driver,
          colorMode: EpdColorMode.fourColor,
          canvasSizeName: '1.54_152_152',
        ),
        <TransferWarning>[
          TransferWarning.canvasSizeMismatch,
          TransferWarning.colorModeMismatch,
        ],
      );
    });
  });
}
