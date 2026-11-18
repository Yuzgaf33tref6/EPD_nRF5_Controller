/// 假蓝牙服务：行为固定、时序固定，让 UI 与状态层在没有真机 / 没有蓝牙硬件时也能跑通。
///
/// 它的时序刻意模仿真实固件：连接成功后不会主动说话，只有收到 `INIT` 命令才回
/// 「配置通知（7 引脚 + 驱动 id）」和「文本通知（mtu=20 rle=1）」，这正是
/// `EPD/EPD_service.c` 里 `epd_send_mtu` 的行为。测试因此可以走完整条真实链路。
library;

import 'dart:async';
import 'dart:typed_data';

import '../protocol/epd_protocol.dart';
import '../protocol/transfer.dart';
import 'ble_service.dart';

/// 假实现。写入内容会被记录在 [writtenPayloads] 里，测试可以逐条核对。
class FakeBleService implements EpdBleService {
  FakeBleService({
    this.scanDelay = const Duration(milliseconds: 700),
    this.connectDelay = const Duration(milliseconds: 450),
    this.driverCode = 0x03,
    this.grantPermission = true,
  });

  /// 模拟的固件版本，与上游 `EPD_service.h` 的 `APP_VERSION 0x1a` 一致。
  static const int firmwareVersion = 0x1a;

  /// 模拟的引脚配置，取自上游 `docs/devices.md` 里「老五 4.2 寸三色」。
  static const String pinsHex = '0A0B0C0D0E0F10';

  /// 模拟的 MTU（固件 INIT 之后通过通知报上来）。
  static const int mtu = 20;

  /// 扫描耗时。
  final Duration scanDelay;

  /// 连接耗时。
  final Duration connectDelay;

  /// 连接后「固件」上报的驱动 id。
  final int driverCode;

  /// 权限申请是否会被批准（用来测「用户拒绝权限」分支）。
  final bool grantPermission;

  final StreamController<Uint8List> _notifications =
      StreamController<Uint8List>.broadcast();

  /// 收到的所有写入负载，按顺序。
  final List<Uint8List> writtenPayloads = <Uint8List>[];

  String? _deviceId;
  bool _isConnected = false;

  @override
  bool get isConnected => _isConnected;

  @override
  String? get connectedDeviceId => _deviceId;

  @override
  Stream<Uint8List> get notifications => _notifications.stream;

  @override
  Future<BlePermissionResult> ensurePermissions() async {
    if (!grantPermission) {
      return const BlePermissionResult(
        granted: false,
        message: '（模拟）用户拒绝了蓝牙权限',
      );
    }
    return const BlePermissionResult(
      granted: true,
      message: '（模拟）蓝牙权限已授予',
    );
  }

  @override
  Future<String> describeAdapterStatus() async => '（模拟）蓝牙可用';

  @override
  Future<List<EpdBleDevice>> scan({required Duration timeout}) async {
    await Future<void>.delayed(scanDelay);
    return const <EpdBleDevice>[
      EpdBleDevice(id: 'C4:7F:51:00:00:01', name: 'EPD-4.2-BWR', rssi: -46),
      EpdBleDevice(id: 'C4:7F:51:00:00:02', name: 'EPD-4.2-BW', rssi: -63),
      EpdBleDevice(id: 'C4:7F:51:00:00:03', name: 'EPD-7.5-BWR', rssi: -78),
    ];
  }

  @override
  Future<void> connect(String deviceId) async {
    await Future<void>.delayed(connectDelay);
    _deviceId = deviceId;
    _isConnected = true;
  }

  @override
  Future<void> disconnect() async {
    _isConnected = false;
    _deviceId = null;
  }

  @override
  Future<int?> readFirmwareVersion() async {
    if (!_isConnected) {
      return null;
    }
    return firmwareVersion;
  }

  @override
  Future<int> requestMtu(int mtu) async => mtu < FakeBleService.mtu ? mtu : FakeBleService.mtu;

  @override
  Future<void> write(Uint8List payload, {bool withResponse = true}) async {
    if (!_isConnected) {
      throw StateError('未连接设备，无法写入');
    }
    writtenPayloads.add(Uint8List.fromList(payload));
    if (payload.isNotEmpty && payload.first == EpdCmd.init.code) {
      // 固件收到 INIT 后会先报引脚配置，再报 MTU/RLE。
      _notifications.add(_configNotification());
      _notifications.add(_textNotification());
    }
  }

  /// 7 字节引脚 + 1 字节驱动 id，与固件的配置通知格式一致。
  Uint8List _configNotification() {
    final Uint8List pins = parseHexBytes(pinsHex);
    return Uint8List.fromList(<int>[...pins, driverCode]);
  }

  /// `mtu=20 rle=1`，UTF-8 编码。
  Uint8List _textNotification() {
    final String text = 'mtu=$mtu rle=1 t=${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
    return Uint8List.fromList(text.codeUnits);
  }

  /// 释放内部 StreamController，测试结束前调用。
  Future<void> dispose() async {
    await _notifications.close();
  }
}
