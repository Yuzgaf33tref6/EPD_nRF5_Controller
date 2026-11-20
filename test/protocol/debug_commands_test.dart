import 'dart:typed_data';

import 'package:epd_controller/protocol/debug_commands.dart';
import 'package:epd_controller/protocol/epd_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseHexPayload', () {
    test('支持空格、逗号、0x 前缀和大小写', () {
      expect(parseHexPayload('0A 0B 0C'), <int>[0x0A, 0x0B, 0x0C]);
      expect(parseHexPayload('0a0b0c'), <int>[0x0A, 0x0B, 0x0C]);
      expect(parseHexPayload('0xA, 0xb'), <int>[0x0A, 0x0B]);
      expect(parseHexPayload('FF\n00'), <int>[0xFF, 0x00]);
    });

    test('空串得到空列表', () {
      expect(parseHexPayload(''), isEmpty);
      expect(parseHexPayload('   '), isEmpty);
    });

    test('奇数位或非法字符抛 FormatException', () {
      expect(() => parseHexPayload('ABC'), throwsFormatException);
      expect(() => parseHexPayload('ZZ'), throwsFormatException);
    });
  });

  group('参数校验', () {
    test('0x03 只接受 1 字节，多字节要提示会被丢弃', () {
      expect(checkSendCommandData(Uint8List(0)).ok, isFalse);
      expect(checkSendCommandData(Uint8List.fromList(<int>[0x22])).ok, isTrue);
      final CommandCheck multi =
          checkSendCommandData(Uint8List.fromList(<int>[0x22, 0x33]));
      expect(multi.ok, isFalse);
      expect(multi.message, contains('只取第 1 个字节'));
    });

    test('0x04 只要非空就算合规，并报告长度', () {
      expect(checkSendDataData(Uint8List(0)).ok, isFalse);
      final CommandCheck ok =
          checkSendDataData(Uint8List.fromList(<int>[1, 2, 3]));
      expect(ok.ok, isTrue);
      expect(ok.message, contains('3 字节'));
    });

    test('0x21 必须 1 字节且 0..6', () {
      expect(checkWeekStartData(Uint8List(0)).ok, isFalse);
      expect(checkWeekStartData(Uint8List.fromList(<int>[0])).ok, isTrue);
      expect(checkWeekStartData(Uint8List.fromList(<int>[6])).ok, isTrue);
      expect(checkWeekStartData(Uint8List.fromList(<int>[7])).ok, isFalse);
      expect(
        checkWeekStartData(Uint8List.fromList(<int>[1, 2])).ok,
        isFalse,
      );
    });

    test('0x90 允许 1..13 字节，超过要提示被忽略', () {
      expect(checkConfigData(Uint8List(0)).ok, isFalse);
      expect(checkConfigData(Uint8List.fromList(<int>[1])).ok, isTrue);
      expect(
        checkConfigData(Uint8List.fromList(List<int>.filled(13, 0))).ok,
        isTrue,
      );
      expect(
        checkConfigData(Uint8List.fromList(List<int>.filled(14, 0))).ok,
        isFalse,
      );
    });
  });

  group('负载构造', () {
    test('0x03 负载 = 命令字 + 数据', () {
      expect(
        buildSendCommand(Uint8List.fromList(<int>[0x22])),
        <int>[0x03, 0x22],
      );
    });

    test('0x04 负载 = 命令字 + 数据', () {
      expect(
        buildSendData(Uint8List.fromList(<int>[0x11, 0x22])),
        <int>[0x04, 0x11, 0x22],
      );
    });

    test('0x21 负载 = 命令字 + 周起始日', () {
      expect(buildWeekStart(1), <int>[0x21, 0x01]);
      expect(() => buildWeekStart(7), throwsArgumentError);
      expect(() => buildWeekStart(-1), throwsArgumentError);
    });

    test('一键命令只是单字节命令字', () {
      expect(buildSystemReset(), <int>[0x91]);
      expect(buildSystemSleep(), <int>[0x92]);
      expect(buildConfigErase(), <int>[0x99]);
    });
  });

  group('EpdConfigPayload', () {
    test('字段顺序与固件 epd_config_t 一致', () {
      const EpdConfigPayload cfg = EpdConfigPayload(
        mosiPin: 0x01,
        sclkPin: 0x02,
        csPin: 0x03,
        dcPin: 0x04,
        rstPin: 0x05,
        busyPin: 0x06,
        bsPin: 0x07,
        modelId: 0x08,
        wakeupPin: 0x09,
        ledPin: 0x0A,
        enPin: 0x0B,
        displayMode: 0x0C,
        weekStart: 0x0D,
      );
      expect(
        cfg.toBytes(),
        <int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13],
      );
    });

    test('出厂默认值与固件 EPD_CFG_DEFAULT 前 10 项一致', () {
      // EPD_service.c: EPD_CFG_DEFAULT {0x0A,0x0B,0x0C,0x0D,0x0E,0x0F,0x10,0x03,0x09,0x03}
      expect(
        EpdConfigPayload.factoryDefault.toBytes().sublist(0, 10),
        <int>[0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x03, 0x09, 0x03],
      );
    });

    test('changedPrefixLength 只算到最后一项有变化的地方', () {
      const EpdConfigPayload base = EpdConfigPayload.factoryDefault;
      expect(base.changedPrefixLength(base), 0);

      // 只改 model_id（第 8 项）→ 需要发 8 字节。
      final EpdConfigPayload modelChanged = base.copyWith(modelId: 0x05);
      expect(modelChanged.changedPrefixLength(base), 8);

      // 只改 week_start（第 13 项）→ 需要发满 13 字节。
      final EpdConfigPayload weekChanged = base.copyWith(weekStart: 1);
      expect(weekChanged.changedPrefixLength(base), 13);
    });

    test('firstBytes 截断到指定长度', () {
      const EpdConfigPayload cfg = EpdConfigPayload.factoryDefault;
      expect(cfg.firstBytes(0), isEmpty);
      expect(cfg.firstBytes(3), <int>[0x0A, 0x0B, 0x0C]);
      expect(cfg.firstBytes(99).length, EpdConfigPayload.size);
    });

    test('fromBytes 不足 13 字节时用默认值补齐', () {
      final EpdConfigPayload cfg =
          EpdConfigPayload.fromBytes(<int>[0x01, 0x02]);
      expect(cfg.mosiPin, 0x01);
      expect(cfg.sclkPin, 0x02);
      expect(cfg.csPin, EpdConfigPayload.factoryDefault.csPin);
      expect(cfg.weekStart, EpdConfigPayload.factoryDefault.weekStart);
    });

    test('相等判断与 hashCode 一致', () {
      const EpdConfigPayload a = EpdConfigPayload.factoryDefault;
      final EpdConfigPayload b = a.copyWith();
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == a.copyWith(weekStart: 3), isFalse);
    });
  });

  group('睡眠安全性', () {
    test('有唤醒引脚 → safe', () {
      expect(evaluateSleepSafety(0x09), SleepSafety.safe);
      expect(evaluateSleepSafety(0x00), SleepSafety.safe);
      expect(describeSleepSafety(SleepSafety.safe, 0x09), contains('0x09'));
    });

    test('唤醒引脚为 0xFF → unsafe', () {
      expect(evaluateSleepSafety(0xFF), SleepSafety.unsafe);
      expect(
        describeSleepSafety(SleepSafety.unsafe, 0xFF),
        contains('无法唤醒'),
      );
    });

    test('没收到配置 → unknown（允许发但要确认）', () {
      expect(evaluateSleepSafety(null), SleepSafety.unknown);
      expect(
        describeSleepSafety(SleepSafety.unknown, null),
        contains('无法确认唤醒引脚'),
      );
    });
  });

  group('配置通知里的 wakeup_pin', () {
    test('13 字节完整配置能取到唤醒引脚（索引 8）', () {
      final Uint8List value = Uint8List.fromList(<int>[
        0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, // 7 个引脚
        0x03, // driver
        0x09, // wakeup_pin
        0x03, // led
        0xFF, // en
        0x00, // display_mode
        0x00, // week_start
      ]);
      final EpdConfig config = parseConfigNotification(value);
      expect(config.driver, 0x03);
      expect(config.wakeupPin, 0x09);
    });

    test('老固件的 8 字节通知拿不到唤醒引脚', () {
      final Uint8List value = Uint8List.fromList(<int>[
        0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x03,
      ]);
      final EpdConfig config = parseConfigNotification(value);
      expect(config.driver, 0x03);
      expect(config.wakeupPin, isNull);
    });
  });
}
