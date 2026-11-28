import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:epd_controller/devices/epd_driver.dart';
import 'package:epd_controller/image/canvas_editing.dart';
import 'package:epd_controller/image/dither.dart';
import 'package:epd_controller/image/epd_color.dart';
import 'package:epd_controller/image/preview_computer.dart';
import 'package:epd_controller/image/process.dart';
import 'package:epd_controller/image/rgba_image.dart';
import 'package:epd_controller/models/transfer_speed.dart';
import 'package:epd_controller/protocol/debug_commands.dart';
import 'package:epd_controller/protocol/epd_protocol.dart';
import 'package:epd_controller/protocol/transfer.dart';
import 'package:epd_controller/services/ble_service.dart';
import 'package:epd_controller/services/fake_ble_service.dart';
import 'package:epd_controller/services/image_pick_service.dart';
import 'package:epd_controller/services/settings_store.dart';
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

/// 带持久化桩的状态：用来验证新加的设置键会被写入 / 读回。
AppState buildStateWithStore(MemorySettingsStore store) => AppState(
      bleService: buildFake(),
      settingsStore: store,
      scanDelay: Duration.zero,
      connectDelay: Duration.zero,
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
      // RLE 不按版本号猜，只认固件通知里的 rle=1（web 版同此逻辑）；
      // 模拟固件在 INIT 之后回了 `mtu=20 rle=1`，所以这里是 true。
      expect(state.rleSupported, isTrue);
      // 固件推的配置通知是完整的 13 字节时的行为：
      // 前 7 字节是 7 个引脚，第 8 个字节（index 7）是驱动号，
      // 而 index 10 的 en_pin 会被当作额外的第 8 个引脚，所以是 8 个。
      expect(state.pinsText.split(' ').length, 8);
      expect(state.config, isNotNull);
      // 连接流程里自动发了一条 INIT。
      expect(state.writesSent, 1);
      // 连上时顺手读了一次真实的信号强度。
      expect(state.liveRssi, isNotNull);
    });

    test('刷新信号强度会更新 liveRssi，断开后清空', () async {
      final FakeBleService ble = buildFake();
      final AppState state = buildState(ble: ble);
      await state.scan();
      await state.connect(state.devices.first);
      await settle();

      ble.fakeRssi = -77;
      await state.refreshRssi();
      expect(state.liveRssi, -77);
      expect(state.isReadingRssi, isFalse);

      await state.disconnect();
      await settle();
      expect(state.liveRssi, isNull);
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
      // 「最大」（吃满 242 字节/块）。
      expect(state.writeMtu, 244);
      expect(state.speed, TransferSpeed.max);
      expect(state.writeChunkBytes, 242);
      expect(state.planMtu, 244);
    });

    test('切换分块档位会改变每块字节数', () {
      final AppState state = buildState();
      // 未连接时 MTU 还是固件默认的 20，所以各档都被压到 ATT_MTU-3-2 = 15。
      expect(state.writeChunkBytes, 15);
      state.setMtu(247);
      // 默认档是「最大」，吃满 242。
      expect(state.writeChunkBytes, 242);
      state.setSpeed(TransferSpeed.stable);
      expect(state.writeChunkBytes, 18);
      state.setSpeed(TransferSpeed.fast);
      expect(state.writeChunkBytes, 128);
      state.setSpeed(TransferSpeed.max);
      // 吃满 ATT_MTU-3-2 = 242。
      expect(state.writeChunkBytes, 242);
      expect(state.planMtu, 244);
      state.setSpeed(TransferSpeed.custom);
      expect(state.writeChunkBytes, state.customChunkBytes);
      state.setCustomChunkBytes(200);
      expect(state.writeChunkBytes, 200);
      // 自定义值会被夹到 MTU 上限内。
      state.setCustomChunkBytes(9999);
      expect(state.writeChunkBytes, 242);
      // 档位变了必须让传图计划重算（缓存键里带了档位）。
      expect(state.transferPlan.totalWrites, greaterThan(1));
    });

    test('发送纯色测试会完整走 INIT → 图像 → REFRESH', () async {
      final FakeBleService ble = buildFake();
      final AppState state = buildState(ble: ble);
      await state.scan();
      await state.connect(state.devices.first);
      await settle();
      final int before = ble.writtenPayloads.length;

      await state.sendSolidColor(rgbPalette[0]);

      final List<Uint8List> sent = ble.writtenPayloads.sublist(before);
      expect(sent.length, greaterThan(2));
      expect(sent.first.first, EpdCmd.init.code);
      expect(sent.last.first, EpdCmd.refresh.code);
      // 纯色图 RLE 后每个平面约 116 个 run code（15000/130），稳妥档每块只装
      // 8 个 code（16 字节 ≤ 18），所以两个平面合计约 30 条，远少于满图的 1667 条。
      expect(sent.length, lessThan(60));
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

    test('接收后台抖动结果后 previewImage 直接复用它（不在 UI 线程重算）', () {
      final AppState state = buildState();
      final RgbaImage fromIsolate = state.sourceImage.clone();
      state.adoptDitheredResult(fromIsolate);
      expect(identical(state.previewImage, fromIsolate), isTrue);
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

  group('设置持久化', () {
    test('改设置会写进 store', () async {
      final MemorySettingsStore store = MemorySettingsStore();
      final AppState state = AppState(
        bleService: buildFake(),
        settingsStore: store,
        scanDelay: Duration.zero,
        connectDelay: Duration.zero,
        autoReconnect: false,
      );
      await settle();

      state.setSpeed(TransferSpeed.fast);
      state.setVerboseTransfers(false);
      state.setThemeMode(ThemeMode.dark);
      state.setInterleavedCount(33);
      state.setSerpentine(true);
      await settle();

      expect(store.saveCount, greaterThan(0));
      final Map<String, Object?>? saved = store.data;
      expect(saved, isNotNull);
      expect(saved!['speed'], 'fast');
      expect(saved['verboseTransfers'], false);
      expect(saved['themeMode'], 'dark');
      expect(saved['interleavedCount'], 33);
      expect(saved['serpentine'], true);
      expect(saved['version'], AppState.kSettingsVersion);
    });

    test('启动时恢复上次保存的设置', () async {
      final MemorySettingsStore store = MemorySettingsStore(<String, Object?>{
        'version': AppState.kSettingsVersion,
        'themeMode': 'dark',
        'driverId': '0c',
        'speed': 'fast',
        'customChunkBytes': 200,
        'interleavedCount': 33,
        'interleavedOverride': true,
        'rleSupported': false,
        'verboseTransfers': false,
        'serpentine': true,
      });
      final AppState state = AppState(
        bleService: buildFake(),
        settingsStore: store,
        scanDelay: Duration.zero,
        connectDelay: Duration.zero,
        autoReconnect: false,
      );
      await settle();

      expect(state.driver.id, '0c');
      expect(state.canvasSize.width, 800);
      expect(state.canvasSize.height, 480);
      expect(state.speed, TransferSpeed.fast);
      expect(state.themeMode, ThemeMode.dark);
      expect(state.interleavedCount, 33);
      expect(state.interleavedCountOverridden, isTrue);
      expect(state.verboseTransfers, isFalse);
      expect(state.serpentine, isTrue);
      // 恢复了驱动，示例图应当按新画布尺寸重生成
      expect(state.sourceImage.width, 800);
    });

    test('设置文件读不到时用默认值', () async {
      final AppState state = AppState(
        bleService: buildFake(),
        settingsStore: MemorySettingsStore(),
        scanDelay: Duration.zero,
        connectDelay: Duration.zero,
        autoReconnect: false,
      );
      await settle();
      expect(state.driver.id, '03');
      expect(state.speed, TransferSpeed.max);
      expect(state.themeMode, ThemeMode.system);
    });

    test('驱动模式与上次设备也会写进 store 并恢复', () async {
      final MemorySettingsStore store = MemorySettingsStore();
      final AppState state = buildStateWithStore(store);
      await settle();

      state.setDriverMode(DriverSelectionMode.manual);
      await settle();
      expect(store.data?['driverMode'], 'manual');

      final AppState restored = buildStateWithStore(MemorySettingsStore(
        <String, Object?>{
          'version': AppState.kSettingsVersion,
          'driverMode': 'manual',
          'lastDeviceId': 'C4:7F:51:00:00:01',
          'lastDeviceName': 'EPD-4.2-BWR',
          'driverWarningMuted': true,
        },
      ));
      await settle();
      expect(restored.driverMode, DriverSelectionMode.manual);
      expect(restored.lastDeviceId, 'C4:7F:51:00:00:01');
      expect(restored.lastDeviceName, 'EPD-4.2-BWR');
      expect(restored.hasLastDevice, isTrue);
      expect(restored.driverWarningMuted, isTrue);
    });
  });

  group('驱动选择模式', () {
    test('自动模式下按固件上报的驱动号切换', () async {
      final FakeBleService ble = buildFake();
      final AppState state = buildState(ble: ble);
      await state.scan();
      await state.connect(state.devices.first);
      await settle();
      // FakeBleService 上报 0x03。
      expect(state.driverMode, DriverSelectionMode.auto);
      expect(state.driver.id, '03');
      expect(state.hasConfig, isTrue);
    });

    test('手动模式不跟随固件上报', () async {
      final FakeBleService ble = buildFake();
      final AppState state = buildState(ble: ble);
      state.setDriver(driverById('0c')!);
      state.setDriverMode(DriverSelectionMode.manual);
      await state.scan();
      await state.connect(state.devices.first);
      await settle();
      expect(state.driver.id, '0c');
      expect(state.canvasSize.width, 800);
    });

    test('切回自动模式时立刻按已有配置同步', () async {
      final FakeBleService ble = buildFake();
      final AppState state = buildState(ble: ble);
      await state.scan();
      await state.connect(state.devices.first);
      await settle();

      state.setDriver(driverById('0c')!);
      state.setDriverMode(DriverSelectionMode.manual);
      await settle();
      expect(state.driver.id, '0c');

      state.setDriverMode(DriverSelectionMode.auto);
      await settle();
      expect(state.driver.id, '03');
    });

    test('没收到配置时才提示驱动可能错误', () async {
      final AppState state = buildState();
      // 未连接：不提示。
      expect(state.shouldWarnDriverMismatch, isFalse);

      // 静音后也不提示。
      state.setDriverWarningMuted(true);
      expect(state.shouldWarnDriverMismatch, isFalse);
    });
  });

  group('启动权限检查', () {
    test('权限被授予时 requestPermissions 为真，不写日志', () async {
      final AppState state = buildState();
      final int before = state.logs.length;
      expect(await state.requestPermissions(), isTrue);
      expect(state.permissionDenied, isFalse);
      expect(state.logs.length, before);
    });

    test('权限被拒绝时 permissionDenied 为真', () async {
      final AppState state = buildState(ble: buildFake(grantPermission: false));
      expect(await state.requestPermissions(), isFalse);
      expect(state.permissionDenied, isTrue);
    });

    test('ensurePermissionsOnce 只跑一次', () async {
      final FakeBleService ble = buildFake(grantPermission: false);
      final AppState state = buildState(ble: ble);
      await state.ensurePermissionsOnce();
      expect(state.permissionDenied, isTrue);
      // 第二次不会再申请（即使这次允许，状态也不会变）。
      await state.ensurePermissionsOnce();
      expect(state.permissionDenied, isTrue);
    });

    test('retryPermissions 可以重新申请', () async {
      final AppState state = buildState(ble: buildFake(grantPermission: false));
      await state.ensurePermissionsOnce();
      expect(state.permissionDenied, isTrue);
      expect(await state.retryPermissions(), isFalse);
      expect(state.permissionDenied, isTrue);
    });
  });

  group('调试指令', () {
    /// 连上设备，返回 (state, fake)。
    Future<(AppState, FakeBleService)> connected() async {
      final FakeBleService ble = buildFake();
      final AppState state = buildState(ble: ble);
      addTearDown(state.dispose);
      addTearDown(ble.dispose);
      await state.connect(
        const EpdBleDevice(id: 'C4:7F:51:00:00:01', name: 'EPD-4.2-BWR', rssi: -46),
      );
      await settle();
      return (state, ble);
    }

    test('0x03 会把命令字和数据一起发出去', () async {
      final (AppState state, FakeBleService ble) = await connected();
      final int before = ble.writtenPayloads.length;
      await state.sendScreenCommand(Uint8List.fromList(<int>[0x22]));
      expect(ble.writtenPayloads.length, before + 1);
      expect(ble.writtenPayloads.last, <int>[0x03, 0x22]);
    });

    test('0x04 带多字节数据', () async {
      final (AppState state, FakeBleService ble) = await connected();
      await state.sendScreenData(Uint8List.fromList(<int>[0x11, 0x22, 0x33]));
      expect(ble.writtenPayloads.last, <int>[0x04, 0x11, 0x22, 0x33]);
    });

    test('0x21 设置周起始日', () async {
      final (AppState state, FakeBleService ble) = await connected();
      await state.setWeekStart(1);
      expect(ble.writtenPayloads.last, <int>[0x21, 0x01]);
    });

    test('0x90 只发到最后一个变化的字段', () async {
      final (AppState state, FakeBleService ble) = await connected();
      // 只改 model_id（第 8 项）→ 负载应当是 0x90 + 前 8 字节。
      final EpdConfigPayload cfg =
          EpdConfigPayload.factoryDefault.copyWith(modelId: 0x05);
      await state.writeConfig(cfg, byteCount: 8);
      final List<int> sent = ble.writtenPayloads.last;
      expect(sent.length, 9); // 命令字 + 8 字节
      expect(sent.first, 0x90);
      expect(sent[8], 0x05); // 第 8 个数据字节就是 model_id
    });

    test('0x91 / 0x92 / 0x99 都只发一个命令字', () async {
      final (AppState state, FakeBleService ble) = await connected();
      await state.systemReset();
      expect(ble.writtenPayloads.last, <int>[0x91]);
      await state.systemSleep();
      expect(ble.writtenPayloads.last, <int>[0x92]);
      await state.eraseConfig();
      expect(ble.writtenPayloads.last, <int>[0x99]);
    });

    test('未连接时不发任何字节，只记一条警告', () async {
      final FakeBleService ble = buildFake();
      final AppState state = buildState(ble: ble);
      addTearDown(state.dispose);
      addTearDown(ble.dispose);
      await state.systemReset();
      expect(ble.writtenPayloads, isEmpty);
      expect(state.logs.last.level, LogLevel.warning);
    });

    test('收到完整配置后能拿到唤醒引脚，睡眠判定为 safe', () async {
      final (AppState state, _) = await connected();
      expect(state.wakeupPin, 0x09);
      expect(state.sleepSafety, SleepSafety.safe);
    });

    test('配置里唤醒引脚为 0xFF 时判定为 unsafe', () async {
      final FakeBleService ble = FakeBleService(
        scanDelay: Duration.zero,
        connectDelay: Duration.zero,
        wakeupPin: 0xFF,
      );
      final AppState state = buildState(ble: ble);
      addTearDown(state.dispose);
      addTearDown(ble.dispose);
      await state.connect(
        const EpdBleDevice(id: 'C4:7F:51:00:00:01', name: 'EPD-4.2-BWR', rssi: -46),
      );
      await settle();
      expect(state.wakeupPin, 0xFF);
      expect(state.sleepSafety, SleepSafety.unsafe);
    });
  });

  group('处理阶段', () {
    test('默认什么都不处理', () {
      final AppState state = buildState();
      addTearDown(state.dispose);
      expect(state.brightness, 0);
      expect(state.brightnessBalance, isFalse);
      expect(state.preprocess, PreprocessPreset.none);
      expect(state.simplifyColors, isFalse);
      expect(state.simplifyColorCount, 8);
      expect(state.processSummary, '不处理');
    });

    test('任意处理参数都会参与 process 与摘要', () {
      final AppState state = buildState();
      addTearDown(state.dispose);
      state.setBrightnessBalance(true);
      state.setPreprocess(PreprocessPreset.vividPhoto);
      state.setBrightness(-12);
      expect(state.process.brightnessBalance, isTrue);
      expect(state.process.preprocess, PreprocessPreset.vividPhoto);
      expect(state.processSummary, '动态照片 · 亮度均衡 · 亮度 -12');
      state.setPreprocess(PreprocessPreset.none);
      state.setBrightnessBalance(false);
      expect(state.processSummary, '亮度 -12');
    });

    test('自动亮度按钮会把等效亮度写进滑块', () {
      final AppState state = buildState();
      addTearDown(state.dispose);
      // 示例图偏亮/偏暗取决于渐变与色块，这里只要求「算出有限值并写入」。
      final double value = state.applyAutoBrightness();
      expect(value, inInclusiveRange(-100, 100));
      expect(state.brightness, value);
    });

    test('改处理参数会影响预览，并在恢复默认后回到原样', () {
      final AppState state = buildState();
      addTearDown(state.dispose);
      final List<int> before =
          List<int>.of(state.previewImage.data, growable: false);

      state.setBrightness(-40);
      expect(state.brightness, -40);
      final List<int> darkened =
          List<int>.of(state.previewImage.data, growable: false);
      expect(darkened, isNot(equals(before)));

      state.resetProcess();
      expect(state.brightness, 0);
      expect(
        List<int>.of(state.previewImage.data, growable: false),
        equals(before),
      );
    });

    test('参数会被夹到合法范围', () {
      final AppState state = buildState();
      addTearDown(state.dispose);
      state.setBrightness(-999);
      expect(state.brightness, -100);
      state.setBrightness(999);
      expect(state.brightness, 100);
      state.setSimplifyColorCount(1);
      expect(state.simplifyColorCount, 2);
      state.setSimplifyColorCount(999);
      expect(state.simplifyColorCount, 64);
    });

    test('处理档预览与「处理」层一致、原图档等于源图', () {
      final AppState state = buildState();
      addTearDown(state.dispose);
      state.setSimplifyColors(true);
      state.setSimplifyColorCount(4);

      final RgbaImage processed =
          computeDitherJobSync(state.previewJob(PreviewStage.processed));
      expect(processed.data, equals(state.processedImage.data));

      final RgbaImage original =
          computeDitherJobSync(state.previewJob(PreviewStage.original));
      expect(original.data, equals(state.sourceImage.data));

      final RgbaImage dithered =
          computeDitherJobSync(state.previewJob(PreviewStage.dithered));
      expect(dithered.data, isNot(equals(processed.data)));
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
