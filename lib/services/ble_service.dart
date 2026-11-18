/// 真实 BLE 传输层。
///
/// 只负责「链路」：扫描、连接、读写特征值、订阅通知、协商 MTU。
/// 协议语义（命令字、传图分块、通知解析）留在 `AppState` 与 `lib/protocol/` 里，
/// 这样真假两层可以共用同一套协议代码，测试也可以用 `FakeBleService` 跑全流程。
///
/// 版本说明：`flutter_reactive_ble` 的 Dart API 在 5.5.0 / 5.6.0 完全一致，但 5.6.0
/// 的原生实现要求 compileSdk 37 / AGP 9.1 / Kotlin 2.4.10，本项目（Flutter 3.44.9）
/// 编不过，所以 `pubspec.yaml` 把 Dart 层与 `reactive_ble_mobile` 都钉在 5.5.0。
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

import '../protocol/epd_protocol.dart';

/// 扫描到的一台设备。
class EpdBleDevice {
  const EpdBleDevice({
    required this.id,
    required this.name,
    required this.rssi,
  });

  /// 平台设备 id（Android 上是 MAC 地址）。
  final String id;

  /// 广播名，可能为空字符串。
  final String name;

  /// 信号强度（dBm，负数）。
  final int rssi;

  /// 广播名里是否像 4.2 寸三色屏（用来给默认选择做提示）。
  bool get looksLikeThreeColor => name.contains('BWR');
}

/// 权限申请结果。
class BlePermissionResult {
  const BlePermissionResult({
    required this.granted,
    required this.message,
  });

  final bool granted;

  /// 说明文字，直接进日志。
  final String message;
}

/// 蓝牙链路抽象。真实现见 [ReactiveBleService]，测试用 FakeBleService。
abstract class EpdBleService {
  /// 申请运行时权限（Android 12+ 的 BLUETOOTH_SCAN/CONNECT，老系统的定位权限）。
  Future<BlePermissionResult> ensurePermissions();

  /// 当前蓝牙子系统状态描述（蓝牙关闭 / 未授权 / 可用）。
  Future<String> describeAdapterStatus();

  /// 扫描一段时间，返回按信号强度排序的设备列表（同一 id 只保留最后一次）。
  Future<List<EpdBleDevice>> scan({required Duration timeout});

  /// 建立连接并完成服务发现。
  Future<void> connect(String deviceId);

  /// 断开连接并释放订阅。
  Future<void> disconnect();

  /// 读版本特征的首字节（固件版本号）。失败返回 null。
  Future<int?> readFirmwareVersion();

  /// 请求 MTU，返回实际协商到的值。
  Future<int> requestMtu(int mtu);

  /// 往命令特征写一条完整负载（已含命令字）。
  Future<void> write(Uint8List payload, {bool withResponse = true});

  /// 命令特征的通知流（连接后可用）。
  Stream<Uint8List> get notifications;

  /// 是否已连接。
  bool get isConnected;

  /// 已连接设备 id。
  String? get connectedDeviceId;
}

/// 真实现：基于 flutter_reactive_ble。
class ReactiveBleService implements EpdBleService {
  ReactiveBleService({FlutterReactiveBle? ble})
      : _ble = ble ?? FlutterReactiveBle();

  final FlutterReactiveBle _ble;

  final StreamController<Uint8List> _notifications =
      StreamController<Uint8List>.broadcast();

  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  StreamSubscription<List<int>>? _notificationSubscription;

  String? _deviceId;
  bool _isConnected = false;

  static final Uuid _serviceUuid = Uuid.parse(EpdUuid.service);
  static final Uuid _commandUuid = Uuid.parse(EpdUuid.commandCharacteristic);
  static final Uuid _versionUuid = Uuid.parse(EpdUuid.versionCharacteristic);

  QualifiedCharacteristic _commandCharacteristic(String deviceId) {
    return QualifiedCharacteristic(
      serviceId: _serviceUuid,
      characteristicId: _commandUuid,
      deviceId: deviceId,
    );
  }

  QualifiedCharacteristic _versionCharacteristic(String deviceId) {
    return QualifiedCharacteristic(
      serviceId: _serviceUuid,
      characteristicId: _versionUuid,
      deviceId: deviceId,
    );
  }

  @override
  bool get isConnected => _isConnected;

  @override
  String? get connectedDeviceId => _deviceId;

  @override
  Stream<Uint8List> get notifications => _notifications.stream;

  @override
  Future<BlePermissionResult> ensurePermissions() async {
    // Android 12+ 用的是 bluetoothScan / bluetoothConnect；Android 11 及以下
    // 这两个权限在系统里不存在，permission_handler 会返回 denied，此时退回定位权限。
    final Map<Permission, PermissionStatus> statuses =
        await <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    final bool bluetoothGranted = statuses.values.every(
      (PermissionStatus status) => status.isGranted,
    );
    if (bluetoothGranted) {
      return const BlePermissionResult(
        granted: true,
        message: '蓝牙权限已授予',
      );
    }

    final Map<Permission, PermissionStatus> locationStatuses =
        await <Permission>[
      Permission.locationWhenInUse,
    ].request();
    final bool locationGranted = locationStatuses.values.every(
      (PermissionStatus status) => status.isGranted,
    );
    if (locationGranted) {
      return const BlePermissionResult(
        granted: true,
        message: '蓝牙权限走老系统的定位权限通道（Android 11 及以下）',
      );
    }
    return const BlePermissionResult(
      granted: false,
      message: '蓝牙权限被拒绝：请到系统设置里允许「附近的设备」权限',
    );
  }

  @override
  Future<String> describeAdapterStatus() async {
    try {
      return switch (_ble.status) {
        BleStatus.unknown => '蓝牙状态未知（尚未初始化）',
        BleStatus.unsupported => '这台设备不支持 BLE',
        BleStatus.unauthorized => '未获得蓝牙使用授权',
        BleStatus.poweredOff => '蓝牙已关闭，请先在系统里打开',
        BleStatus.locationServicesDisabled => '定位服务已关闭（老系统扫描 BLE 需要它）',
        BleStatus.ready => '蓝牙可用',
      };
    } catch (error) {
      return '读取蓝牙状态失败：$error';
    }
  }

  @override
  Future<List<EpdBleDevice>> scan({required Duration timeout}) async {
    final Map<String, EpdBleDevice> found = <String, EpdBleDevice>{};
    StreamSubscription<DiscoveredDevice>? subscription;
    try {
      subscription = _ble
          .scanForDevices(
            withServices: const <Uuid>[],
            scanMode: ScanMode.lowLatency,
            requireLocationServicesEnabled: false,
          )
          .listen(
        (DiscoveredDevice device) {
          found[device.id] = EpdBleDevice(
            id: device.id,
            name: device.name,
            rssi: device.rssi,
          );
        },
        onError: (Object error) {
          // 扫描出错不抛出，交给调用方按「扫到的部分结果」处理。
        },
      );
      await Future<void>.delayed(timeout);
    } finally {
      await subscription?.cancel();
    }
    final List<EpdBleDevice> result = found.values.toList()
      ..sort((EpdBleDevice a, EpdBleDevice b) => b.rssi.compareTo(a.rssi));
    return result;
  }

  @override
  Future<void> connect(String deviceId) async {
    if (_isConnected && _deviceId == deviceId) {
      return;
    }
    await disconnect();

    final Completer<void> completer = Completer<void>();
    _deviceId = deviceId;
    _connectionSubscription = _ble
        .connectToDevice(
          id: deviceId,
          connectionTimeout: const Duration(seconds: 15),
        )
        .listen(
      (ConnectionStateUpdate update) {
        if (update.connectionState == DeviceConnectionState.connected) {
          _isConnected = true;
          if (!completer.isCompleted) {
            completer.complete();
          }
        } else if (update.connectionState == DeviceConnectionState.disconnected) {
          _isConnected = false;
          if (!completer.isCompleted) {
            completer.completeError(
              StateError('设备在连接过程中断开：${update.deviceId}'),
            );
          }
        }
      },
      onError: (Object error) {
        _isConnected = false;
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
      },
    );

    await completer.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () => throw TimeoutException('连接 $deviceId 超时'),
    );

    // 主动做一次服务发现：不发现的话特征读写会报「characteristic 不存在」。
    try {
      await _ble.discoverAllServices(deviceId);
    } catch (error) {
      // 发现失败不直接中断，后续读写会给出更具体的错误。
    }

    // 订阅命令特征的通知。必须在连接成功之后，订阅内部会做服务发现。
    _notificationSubscription = _ble
        .subscribeToCharacteristic(_commandCharacteristic(deviceId))
        .listen(
      (List<int> value) => _notifications.add(Uint8List.fromList(value)),
      onError: (Object error) {
        // 通知订阅失败不影响已有连接，交给上层日志体现。
      },
    );
  }

  @override
  Future<void> disconnect() async {
    await _notificationSubscription?.cancel();
    _notificationSubscription = null;
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _isConnected = false;
    _deviceId = null;
  }

  @override
  Future<int?> readFirmwareVersion() async {
    final String? deviceId = _deviceId;
    if (deviceId == null) {
      return null;
    }
    try {
      final List<int> value =
          await _ble.readCharacteristic(_versionCharacteristic(deviceId));
      if (value.isEmpty) {
        return null;
      }
      return value.first;
    } catch (error) {
      return null;
    }
  }

  @override
  Future<int> requestMtu(int mtu) async {
    final String? deviceId = _deviceId;
    if (deviceId == null) {
      throw StateError('未连接设备，无法协商 MTU');
    }
    return _ble.requestMtu(deviceId: deviceId, mtu: mtu);
  }

  @override
  Future<void> write(Uint8List payload, {bool withResponse = true}) async {
    final String? deviceId = _deviceId;
    if (deviceId == null || !_isConnected) {
      throw StateError('未连接设备，无法写入');
    }
    final QualifiedCharacteristic characteristic =
        _commandCharacteristic(deviceId);
    final List<int> value = payload.toList(growable: false);
    if (withResponse) {
      await _ble.writeCharacteristicWithResponse(characteristic, value: value);
    } else {
      await _ble.writeCharacteristicWithoutResponse(characteristic, value: value);
    }
  }
}
