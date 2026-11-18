import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:epd_controller/devices/epd_driver.dart';
import 'package:epd_controller/image/dither.dart';
import 'package:epd_controller/protocol/epd_protocol.dart';
import 'package:epd_controller/protocol/transfer.dart';
import 'package:epd_controller/services/fake_ble_service.dart';
import 'package:epd_controller/state/app_state.dart';

/// 这些测试里所有延时都设成 0，避免真等。
AppState buildState() => AppState(
      scanDelay: Duration.zero,
      connectDelay: Duration.zero,
      sendDelay: Duration.zero,
    );

void main() {
  group('初始状态', () {
    test('未连接、默认 4.2 寸三色驱动、画布 400x300', () {
      final AppState state = buildState();
      expect(state.isConnected, isFalse);
      expect(state.driver.id, '03');
      expect(state.canvasSize.width, 400);
      expect(state.canvasSize.height, 300);
      expect(state.sourceImage.width, 400);
      expect(state.sourceImage.height, 300);
      expect(state.logs, isNotEmpty);
    });

    test('初始预览可算，且传图计划从 INIT 开始、以 REFRESH 结束', () {
      final AppState state = buildState();
      final ImageTransferPlan plan = state.transferPlan;
      expect(plan.totalWrites, greaterThan(2));
      expect(plan.writes.first.payload.first, EpdCmd.init.code);
      expect(plan.writes.last.payload.first, EpdCmd.refresh.code);
      expect(plan.processedBytes, greaterThan(0));
      expect(plan.imageWrites, greaterThan(0));
    });
  });

  group('扫描与连接', () {
    test('扫描返回模拟设备，连接后拿到固件版本与引脚', () async {
      final AppState state = buildState();
      await state.scan();
      expect(state.isScanning, isFalse);
      expect(state.devices, isNotEmpty);

      final FakeEpdDevice device = state.devices.first;
      await state.connect(device);
      expect(state.isConnected, isTrue);
      expect(state.connectedDevice!.id, device.id);
      expect(state.firmwareVersion, FakeBleService.firmwareVersion);
      expect(state.firmwareVersionText, '0x1A');
      // 版本 0x1a >= 0x16，所以 RLE 自动开启。
      expect(state.rleSupported, isTrue);
      expect(state.pinsText.split(' ').length, 7);
      expect(state.config, isNotNull);
    });

    test('断开后清空固件与配置', () async {
      final AppState state = buildState();
      await state.scan();
      await state.connect(state.devices.first);
      state.disconnect();
      expect(state.isConnected, isFalse);
      expect(state.firmwareVersion, isNull);
      expect(state.config, isNull);
      expect(state.rleSupported, isFalse);
    });

    test('未连接时发送与设备控制只记警告，不抛异常', () async {
      final AppState state = buildState();
      final int before = state.logs.length;
      await state.sendPreview();
      state.clearScreen();
      state.syncTime(clockMode: false);
      expect(state.isConnected, isFalse);
      expect(state.logs.length, greaterThan(before));
      expect(
        state.logs.map((LogEntry entry) => entry.level),
        contains(LogLevel.warning),
      );
    });

    test('已连接时可以发送与同步时间', () async {
      final AppState state = buildState();
      await state.scan();
      await state.connect(state.devices.first);
      await state.sendPreview();
      state.syncTime(clockMode: false);
      state.clearScreen();
      expect(state.isConnected, isTrue);
      expect(
        state.logs.map((LogEntry entry) => entry.message).join('\n'),
        contains('发送完成'),
      );
    });
  });

  group('参数联动', () {
    test('切换驱动会联动画布尺寸并重新生成示例图', () {
      final AppState state = buildState();
      expect(state.canvasSize.name, '4.2_400_300');

      // 0x0c = 7.5 寸黑白，800×480
      final EpdDriver? driver = driverById('0c');
      expect(driver, isNotNull);
      state.setDriver(driver!);
      expect(state.canvasSize.width, 800);
      expect(state.canvasSize.height, 480);
      expect(state.sourceImage.width, 800);
      expect(state.sourceImage.height, 480);
      expect(state.aspectMatchesCanvas, isTrue);
    });

    test('旋转后宽高互换，与画布宽高比不再匹配', () {
      final AppState state = buildState();
      state.rotateSource();
      expect(state.sourceImage.width, 300);
      expect(state.sourceImage.height, 400);
      expect(state.aspectMatchesCanvas, isFalse);
    });

    test('MTU 与交错块数会被夹到合法范围', () {
      final AppState state = buildState();
      state.setMtu(1);
      expect(state.mtu, 20);
      state.setMtu(9999);
      expect(state.mtu, 247);
      state.setInterleavedCount(0);
      expect(state.interleavedCount, 1);
      state.setInterleavedCount(1000);
      expect(state.interleavedCount, 100);
    });

    test('切换 RLE 开关后传图计划仍可生成（是否启用由压缩收益决定）', () {
      final AppState state = buildState();
      expect(state.rleSupported, isFalse);
      final ImageTransferPlan plain = state.transferPlan;
      expect(plain.usedRle, isFalse);
      final int plainBytes = _transmittedBytes(plain);

      state.setRleSupported(true);
      final ImageTransferPlan compressed = state.transferPlan;
      expect(compressed.totalWrites, greaterThan(0));
      // 抖动后的位打包数据run 很短，压缩经常没有收益；有收益时才必须更小。
      if (compressed.usedRle) {
        expect(_transmittedBytes(compressed), lessThan(plainBytes));
      }
    });
    test('抖动算法变化会改变预览图内容', () {
      final AppState state = buildState();
      final List<int> floyd =
          List<int>.of(state.previewImage.data, growable: false);
      expect(state.algorithm, DitherAlgorithm.floydSteinberg);

      state.setAlgorithm(DitherAlgorithm.bayer);
      final List<int> bayer =
          List<int>.of(state.previewImage.data, growable: false);
      expect(state.algorithm, DitherAlgorithm.bayer);
      expect(bayer, isNot(equals(floyd)));
    });
  });

  group('主题与日志', () {
    test('主题可切换', () {
      final AppState state = buildState();
      expect(state.themeMode, ThemeMode.system);
      state.setThemeMode(ThemeMode.dark);
      expect(state.themeMode, ThemeMode.dark);
    });

    test('日志有上限，清空后为空', () {
      final AppState state = buildState();
      state.clearLogs();
      expect(state.logs, isEmpty);
      for (int i = 0; i < 300; i++) {
        state.addLog(LogLevel.info, 'line $i');
      }
      expect(state.logs.length, 200);
      expect(state.logs.last.message, 'line 299');
    });
  });
}

/// 一次传图里真正上网的字节数（含命令字与 flag）。
int _transmittedBytes(ImageTransferPlan plan) {
  return plan.writes.fold<int>(
    0,
    (int sum, EpdWrite write) => sum + write.payload.length,
  );
}