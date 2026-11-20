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

/// 单条权限的检查结果，供「权限检查」页展示。
class AppPermissionStatus {
  const AppPermissionStatus({
    required this.name,
    required this.androidName,
    required this.status,
    required this.reason,
    this.alwaysGranted = false,
  });

  /// 面向用户的名字，例如「附近的设备（扫描）」。
  final String name;

  /// Android 层面对应的权限名，例如 `BLUETOOTH_SCAN`。
  final String androidName;

  /// 系统返回的状态原文（granted / denied / permanentlyDenied …）。
  final PermissionStatus status;

  /// 为什么需要这条权限。
  final String reason;

  /// 该权限在系统里不存在（老版本 Android），视为不需要。
  final bool alwaysGranted;

  /// 是否已经可用。
  bool get granted => alwaysGranted || status.isGranted;

  /// 是否被永久拒绝（需要去系统设置里开）。
  bool get permanentlyDenied => !alwaysGranted && status.isPermanentlyDenied;
}

/// 蓝牙链路抽象。真实现见 [ReactiveBleService]，测试用 FakeBleService。
abstract class EpdBleService {
  /// 申请运行时权限（Android 12+ 的 BLUETOOTH_SCAN/CONNECT，老系统的定位权限）。
  Future<BlePermissionResult> ensurePermissions();

  /// **只查询**当前权限状态，不弹系统对话框。
  Future<List<AppPermissionStatus>> checkPermissions();

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

  /// 重新打开通知（关掉 CCCD 再打开）。
  ///
  /// 固件只在收到「开启通知」时把配置结构体（引脚 + 驱动 id）推一次，
  /// 一旦那条通知漏了，唯一的补救办法就是让 CCCD 重新打开一次。
  Future<void> resubscribeNotifications();

  /// 连接状态变化：true = 已连接，false = 已断开（含意外断开）。
  Stream<bool> get connectionChanges;

  /// 是否已连接。
  bool get isConnected;

  /// 已连接设备 id。
  String? get connectedDeviceId;
}

/// 真实现：基于 flutter_reactive_ble。
class ReactiveBleService implements EpdBleService {
  ReactiveBleService({FlutterReactiveBle? ble}) : _injectedBle = ble;

  /// 注入的实例（测试用）；为空时在第一次真正用到蓝牙时才创建单例。
  ///
  /// 不能在构造函数里直接 `FlutterReactiveBle()`：它的构造函数会立刻走平台通道
  /// 初始化，如果此时 WidgetsBinding 还没初始化就会抛空指针。
  final FlutterReactiveBle? _injectedBle;

  FlutterReactiveBle? _bleInstance;

  FlutterReactiveBle get _ble => _bleInstance ??= _injectedBle ?? FlutterReactiveBle();

  final StreamController<Uint8List> _notifications =
      StreamController<Uint8List>.broadcast();

  /// 还没有人监听时先攒着：固件常在连接成功的那一瞬间就推「配置通知」，
  /// 而 broadcast 流在没有监听者时会把这些事件直接丢掉（驱动号/引脚就丢了）。
  final List<Uint8List> _pendingNotifications = <Uint8List>[];
  bool _notificationsClaimed = false;

  final StreamController<bool> _connectionChanges =
      StreamController<bool>.broadcast();

  @override
  Stream<bool> get connectionChanges => _connectionChanges.stream;

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
  Stream<Uint8List> get notifications {
    if (_notificationsClaimed) {
      return _notifications.stream;
    }
    _notificationsClaimed = true;
    final List<Uint8List> replay = List<Uint8List>.of(_pendingNotifications);
    _pendingNotifications.clear();
    return Stream<Uint8List>.multi((StreamController<Uint8List> controller) {
      for (final Uint8List value in replay) {
        controller.add(value);
      }
      final StreamSubscription<Uint8List> subscription =
          _notifications.stream.listen(controller.add);
      controller.onCancel = subscription.cancel;
    });
  }

  @override
  Future<List<AppPermissionStatus>> checkPermissions() async {
    // 一次问完所有权限的当前状态（不会弹窗）。
    final Map<Permission, PermissionStatus> statuses =
        await <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].status;

    return <AppPermissionStatus>[
      AppPermissionStatus(
        name: '附近的设备（扫描）',
        androidName: 'BLUETOOTH_SCAN',
        status: statuses[Permission.bluetoothScan] ?? PermissionStatus.denied,
        reason: '扫描周围墨水屏需要；Android 12 起属于「附近的设备」。',
      ),
      AppPermissionStatus(
        name: '附近的设备（连接）',
        androidName: 'BLUETOOTH_CONNECT',
        status: statuses[Permission.bluetoothConnect] ?? PermissionStatus.denied,
        reason: '连接设备、读写特征值、接收通知需要。',
      ),
      AppPermissionStatus(
        name: '位置信息',
        androidName: 'ACCESS_FINE_LOCATION',
        status: statuses[Permission.locationWhenInUse] ??
            PermissionStatus.denied,
        reason: 'Android 11 及以下扫描蓝牙必须开定位；12 起不再要求。',
      ),
    ];
  }

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
      final FlutterReactiveBle ble = _ble;
      // statusStream 在订阅时会先 initialize()，能拿到真实适配器状态；
      // 拿不到就退回当前缓存的 status，不让界面卡住。
      final BleStatus status = await ble.statusStream
          .first
          .timeout(const Duration(seconds: 3), onTimeout: () => ble.status);
      return switch (status) {
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

    // 每次连接都重新进入「攒着等监听者」的状态：固件只在收到 CCCD（开启通知）
    // 的那一刻推一次「配置通知」，那条通知比 connect() 返回还早。
    _pendingNotifications.clear();
    _notificationsClaimed = false;

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
          _connectionChanges.add(true);
          if (!completer.isCompleted) {
            completer.complete();
          }
        } else if (update.connectionState == DeviceConnectionState.disconnected) {
          final bool wasConnected = _isConnected;
          _isConnected = false;
          if (wasConnected) {
            _connectionChanges.add(false);
          }
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
    _listenCommandNotifications(deviceId);
  }

  /// 把命令特征的原始字节灌进 [_notifications]（没人监听时先攒着）。
  void _onCommandNotification(List<int> value) {
    final Uint8List bytes = Uint8List.fromList(value);
    if (_notificationsClaimed) {
      _notifications.add(bytes);
    } else {
      _pendingNotifications.add(bytes);
    }
  }

  void _listenCommandNotifications(String deviceId) {
    _notificationSubscription = _ble
        .subscribeToCharacteristic(_commandCharacteristic(deviceId))
        .listen(
      _onCommandNotification,
      onError: (Object error) {
        // 通知订阅失败不影响已有连接，交给上层日志体现。
      },
    );
  }

  @override
  Future<void> resubscribeNotifications() async {
    final String? deviceId = _deviceId;
    if (deviceId == null || !_isConnected) {
      return;
    }
    // 先取消订阅（插件会写 CCCD=0），再重新订阅（CCCD=1）——
    // 固件在 CCCD 打开时会把配置结构体推一次，这样就能补救漏掉的那条。
    await _notificationSubscription?.cancel();
    _notificationSubscription = null;
    await Future<void>.delayed(const Duration(milliseconds: 150));
    _pendingNotifications.clear();
    _notificationsClaimed = false;
    _listenCommandNotifications(deviceId);
  }

  @override
  Future<void> disconnect() async {
    final bool wasConnected = _isConnected;
    await _notificationSubscription?.cancel();
    _notificationSubscription = null;
    _pendingNotifications.clear();
    _notificationsClaimed = false;
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _isConnected = false;
    _deviceId = null;
    if (wasConnected) {
      _connectionChanges.add(false);
    }
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
