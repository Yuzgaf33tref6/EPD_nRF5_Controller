import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:epd_controller/devices/epd_driver.dart';
import 'package:epd_controller/image/canvas_editing.dart';
import 'package:epd_controller/image/dither.dart';
import 'package:epd_controller/image/rgba_image.dart';
import 'package:epd_controller/models/transfer_speed.dart';
import 'package:epd_controller/protocol/epd_protocol.dart';
import 'package:epd_controller/protocol/transfer.dart';
import 'package:epd_controller/services/ble_service.dart';
import 'package:epd_controller/services/fake_ble_service.dart';
import 'package:epd_controller/services/image_pick_service.dart';
import 'package:epd_controller/state/app_state.dart';

/// 这些测试里所有延时都设成 0，避免真等。
FakeBleService buildFake({bool grantPermission = true}) => FakeBleService(
      scanDelay: Duration.zero,
      connectDelay: Duration.zero,
      grantPermission: grantPermission,
    );

AppState buildState({FakeBleService? ble, ImagePickService? picker}) => AppState(
      bleService: ble ?? buildFake(),
      imagePickService: picker,
      scanDelay: Duration.zero,
      connectDelay: Duration.zero,
      // 关掉自动重连：否则「意外断开」的用例会被自动接回去。
      autoReconnect: false,
    );

/// 固定返回一张图的选图服务，用来避免测试碰真实相册。
class FakePickService implements ImagePickService {
  FakePickService({this.result});

  RgbaImage? result;
  int calls = 0;

  @override
  Future<RgbaImage?> pickFromGallery() async {
    calls++;
    return result;
  }
}

/// 广播流的通知是异步派发的，等一个微任务让通知处理函数跑完。
Future<void> settle() => Future<void>.delayed(Duration.zero);

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
    test('扫描返回设备，连接后拿到固件版本与引脚', () async {
      final AppState state = buildState();
      await state.scan();
      expect(state.isScanning, isFalse);
      expect(state.devices, isNotEmpty);

      final EpdBleDevice device = state.devices.first;
      await state.connect(device);
      await settle();
      expect(state.isConnected, isTrue);
      expect(state.connectedDevice!.id, device.id);
      expect(state.firmwareVersion, FakeBleService.firmwareVersion);
      expect(state.firmwareVersionText, '0x1A');
      // 版本 0x1a >= 0x16，所以 RLE 自动开启。
      expect(state.rleSupported, isTrue);
      expect(state.pinsText.split(' ').length, 7);
      expect(state.config, isNotNull);
      // 连接流程里自动发了一条 INIT。
      expect(state.writesSent, 1);
    });

    test('连接后自动发 INIT，固件回配置通知与 MTU 文本通知', () async {
      final FakeBleService ble = buildFake();
      final AppState state = buildState(ble: ble);
      await state.scan();
      await state.connect(state.devices.first);
      await settle();

      expect(ble.writtenPayloads, hasLength(1));
      expect(ble.writtenPayloads.first.first, EpdCmd.init.code);
      expect(state.notificationLog, hasLength(2));
      expect(state.notificationLog.first, contains('配置通知'));
      expect(state.notificationLog.last, contains('mtu=20'));
      // 连接时主动协商到 247；固件那条过时的 mtu=20 不会把协商结果打回去。
      expect(state.mtu, 247);
      // 一条写请求最多 ATT_MTU - 3 = 244 字节；再减命令字与 flag。默认档位是
      // 「稳妥」（18 字节/块，与 web 版默认 MTU 20、chunkSize 18 一致）。
      expect(state.writeMtu, 244);
      expect(state.speed, TransferSpeed.conservative);
      expect(state.writeChunkBytes, 18);
      expect(state.planMtu, 20);
    });

    test('切换分块档位会改变每块字节数', () {
      final AppState state = buildState();
      expect(state.writeChunkBytes, 18);
      state.setSpeed(TransferSpeed.fast);
      expect(state.writeChunkBytes, 64);
      state.setSpeed(TransferSpeed.extreme);
      expect(state.writeChunkBytes, 180);
      state.setSpeed(TransferSpeed.custom);
      // 未连接时 MTU 还是固件默认的 20，自定义档取 ATT_MTU-3-2 = 15。
      expect(state.writeChunkBytes, 15);
      state.setMtu(247);
      expect(state.writeChunkBytes, 242);
    });

    test('意外断开时把连接状态清掉并记错误日志', () async {
      final FakeBleService ble = buildFake();
      final AppState state = buildState(ble: ble);
      await state.scan();
      await state.connect(state.devices.first);
      await settle();
      expect(state.isConnected, isTrue);

      ble.simulateDisconnect();
      await settle();

      expect(state.isConnected, isFalse);
      expect(state.connectedDevice, isNull);
      expect(
        state.logs.map((LogEntry entry) => entry.level),
        contains(LogLevel.error),
      );
    });

    test('断开后清空固件与配置', () async {
      final AppState state = buildState();
      await state.scan();
      await state.connect(state.devices.first);
      await settle();
      await state.disconnect();
      expect(state.isConnected, isFalse);
      expect(state.firmwareVersion, isNull);
      expect(state.config, isNull);
      expect(state.rleSupported, isFalse);
    });

    test('权限被拒绝时不去扫描也不去连接，并记错误日志', () async {
      final FakeBleService ble = buildFake(grantPermission: false);
      final AppState state = buildState(ble: ble);
      await state.scan();
      // 扫描前就要权限，没权限时不会去扫，也就不会有设备。
      expect(state.devices, isEmpty);
      expect(
        state.logs.any(
          (LogEntry entry) => entry.message.contains('扫描需要蓝牙权限'),
        ),
        isTrue,
      );
      await state.connect(
        const EpdBleDevice(
          id: 'C4:7F:51:00:00:01',
          name: 'EPD-4.2-BWR',
          rssi: -46,
        ),
      );
      expect(state.isConnected, isFalse);
      expect(state.isConnecting, isFalse);
      expect(ble.writtenPayloads, isEmpty);
      expect(
        state.logs.map((LogEntry entry) => entry.level),
        contains(LogLevel.error),
      );
    });

    test('未连接时发送与设备控制只记警告，不抛异常', () async {
      final AppState state = buildState();
      final int before = state.logs.length;
      await state.sendPreview();
      await state.clearScreen();
      await state.syncTime(clockMode: false);
      expect(state.isConnected, isFalse);
      expect(state.logs.length, greaterThan(before));
      expect(
        state.logs.map((LogEntry entry) => entry.level),
        contains(LogLevel.warning),
      );
    });

    test('已连接时可以发送与同步时间，写指令真的发出去了', () async {
      final FakeBleService ble = buildFake();
      final AppState state = buildState(ble: ble);
      await state.scan();
      await state.connect(state.devices.first);
      await settle();

      final int afterConnect = ble.writtenPayloads.length;
      await state.sendPreview();
      await state.syncTime(clockMode: false);
      await state.clearScreen();

      final ImageTransferPlan plan = state.transferPlan;
      expect(ble.writtenPayloads.length,
          afterConnect + plan.totalWrites + 1 + 1);
      // 传图的第一条是 INIT，最后一条是 REFRESH。
      expect(ble.writtenPayloads[afterConnect].first, EpdCmd.init.code);
      expect(
        ble.writtenPayloads[afterConnect + plan.totalWrites - 1].first,
        EpdCmd.refresh.code,
      );
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
      // 抖动后的位打包数据 run 很短，压缩经常没有收益；有收益时才必须更小。
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

  group('画布编辑', () {
    test('提交笔画后预览随之变化，撤销能还原', () {
      final AppState state = buildState();
      final List<int> before =
          List<int>.of(state.previewImage.data, growable: false);

      state.beginEditing();
      expect(state.canUndo, isFalse);

      final RgbaImage edited = state.sourceImage.clone();
      drawDot(edited, x: 200, y: 150, radius: 20);
      state.commitEdit(edited);
      expect(state.canUndo, isTrue);

      final List<int> after =
          List<int>.of(state.previewImage.data, growable: false);
      expect(after, isNot(equals(before)));

      state.undoEdit();
      final List<int> restored =
          List<int>.of(state.previewImage.data, growable: false);
      expect(restored, equals(before));
      expect(state.canRedo, isTrue);

      state.redoEdit();
      expect(
        List<int>.of(state.previewImage.data, growable: false),
        equals(after),
      );
    });

    test('换底图会重置历史', () {
      final AppState state = buildState();
      state.beginEditing();
      final RgbaImage edited = state.sourceImage.clone();
      drawDot(edited, x: 10, y: 10, radius: 3);
      state.commitEdit(edited);
      expect(state.canUndo, isTrue);

      state.replaceSource(edited.clone());
      expect(state.canUndo, isFalse);
      expect(state.canRedo, isFalse);
    });
  });


  group('导入图片', () {
    test('选到图时返回图片并记一条成功日志', () async {
      final FakePickService picker = FakePickService();
      final RgbaImage picked = RgbaImage(
        3,
        2,
        Uint8List.fromList(List<int>.generate(3 * 2 * 4, (int i) => 255)),
      );
      picker.result = picked;
      final AppState state = buildState(picker: picker);
      final RgbaImage? result = await state.pickImageFromGallery();
      expect(picker.calls, 1);
      expect(identical(result, picked), isTrue);
      expect(
        state.logs.any((LogEntry entry) => entry.message.contains('已选择图片')),
        isTrue,
      );
    });

    test('取消选图返回 null 并记一条提示', () async {
      final FakePickService picker = FakePickService();
      final AppState state = buildState(picker: picker);
      final RgbaImage? result = await state.pickImageFromGallery();
      expect(result, isNull);
      expect(
        state.logs.any((LogEntry entry) => entry.message.contains('已取消选图')),
        isTrue,
      );
    });

    test('replaceSource 换成新图后预览尺寸跟着变', () {
      final AppState state = buildState();
      final RgbaImage replacement = RgbaImage(
        120,
        90,
        Uint8List.fromList(List<int>.generate(120 * 90 * 4, (int i) => 200)),
      );
      state.replaceSource(replacement);
      expect(state.sourceImage.width, 120);
      expect(state.sourceImage.height, 90);
      expect(state.previewImage.width, 120);
      expect(state.previewImage.height, 90);
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
