import 'dart:async';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

class BluetoothService {
  BluetoothService();

  final FlutterReactiveBle _ble = FlutterReactiveBle();
  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<ConnectionStateUpdate>? _connSub;

  // Expose scans and connection updates
  final _scanController = StreamController<DiscoveredDevice>.broadcast();
  Stream<DiscoveredDevice> get scanStream => _scanController.stream;
  final _notifyController = StreamController<List<int>>.broadcast();
  Stream<List<int>> get notifyStream => _notifyController.stream;

  static final Uuid _epdService = Uuid.parse('62750001-d828-918d-fb46-b6c11c675aec');
  static final Uuid _epdWriteChar = Uuid.parse('62750002-d828-918d-fb46-b6c11c675aec');
  static final Uuid _epdNotifyChar = Uuid.parse('62750003-d828-918d-fb46-b6c11c675aec');

  QualifiedCharacteristic? _writeChar;
  QualifiedCharacteristic? _notifyChar;
  String? _connectedDeviceId;

  void startScan() {
    _scanSub?.cancel();
    _scanSub = _ble.scanForDevices(withServices: [_epdService]).listen((device) {
      _scanController.add(device);
    }, onError: (e) {
      // ignore for now
    });
  }

  void stopScan() {
    _scanSub?.cancel();
    _scanSub = null;
  }

  Future<bool> connect(String deviceId, {Duration timeout = const Duration(seconds: 15)}) async {
    // Ensure previous connection cancelled
    _connSub?.cancel();
    final completer = Completer<bool>();

    _connSub = _ble.connectToDevice(id: deviceId, connectionTimeout: timeout).listen((update) async {
      if (update.connectionState == DeviceConnectionState.connected) {
        _connectedDeviceId = deviceId;
        _writeChar = QualifiedCharacteristic(deviceId: deviceId, serviceId: _epdService, characteristicId: _epdWriteChar);
        _notifyChar = QualifiedCharacteristic(deviceId: deviceId, serviceId: _epdService, characteristicId: _epdNotifyChar);

        // subscribe to notifications
        try {
          _ble.subscribeToCharacteristic(_notifyChar!).listen((data) {
            _notifyController.add(data);
          }, onError: (_) {});
        } catch (e) {}

        if (!completer.isCompleted) completer.complete(true);
      } else if (update.connectionState == DeviceConnectionState.disconnected) {
        _connectedDeviceId = null;
        if (!completer.isCompleted) completer.complete(false);
      }
    }, onError: (e) {
      if (!completer.isCompleted) completer.complete(false);
    });

    return completer.future;
  }

  Future<void> disconnect() async {
    await _connSub?.cancel();
    _connSub = null;
    _connectedDeviceId = null;
  }

  Future<bool> sendData(List<int> data, {bool withResponse = true}) async {
    if (_writeChar == null || _connectedDeviceId == null) return false;
    try {
      if (withResponse) {
        await _ble.writeCharacteristicWithResponse(_writeChar!, value: data);
      } else {
        await _ble.writeCharacteristicWithoutResponse(_writeChar!, value: data);
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  // --- EPD high-level commands (based on original JS EpdCmd) ---
  static const int CMD_SET_PINS = 0x00;
  static const int CMD_INIT = 0x01;
  static const int CMD_CLEAR = 0x02;
  static const int CMD_SEND_CMD = 0x03;
  static const int CMD_SEND_DATA = 0x04;
  static const int CMD_REFRESH = 0x05;
  static const int CMD_SLEEP = 0x06;
  static const int CMD_SET_TIME = 0x20;
  static const int CMD_WRITE_IMG = 0x30;

  Future<bool> ensurePermissions() async {
    // Request BLE permissions for Android 12+
    final statuses = await [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.locationWhenInUse,
    ].request();

    // consider granted if bluetooth connect or generic bluetooth granted
    return statuses.values.every((s) => s.isGranted || s.isLimited || s.isRestricted);
  }

  Future<bool> writeCmd(int cmd, List<int>? data, {bool withResponse = true}) async {
    final payload = <int>[cmd & 0xFF];
    if (data != null) payload.addAll(data);
    return sendData(payload, withResponse: withResponse);
  }

  Future<bool> setPins(String hex) async {
    // hex string e.g. '001122'
    final bytes = _hexToBytes(hex);
    return writeCmd(CMD_SET_PINS, bytes);
  }

  Future<bool> initDriver(String hex) async {
    final bytes = _hexToBytes(hex);
    return writeCmd(CMD_INIT, bytes);
  }

  Future<bool> clearScreen() async => writeCmd(CMD_CLEAR, null);

  Future<bool> refresh() async => writeCmd(CMD_REFRESH, null);

  Future<bool> sleep() async => writeCmd(CMD_SLEEP, null);

  Future<bool> setTime(int mode) async {
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final tz = -(DateTime.now().timeZoneOffset.inHours);
    final data = <int>[
      (ts >> 24) & 0xFF,
      (ts >> 16) & 0xFF,
      (ts >> 8) & 0xFF,
      ts & 0xFF,
      tz & 0xFF,
      mode & 0xFF,
    ];
    return writeCmd(CMD_SET_TIME, data);
  }

  List<int> _hexToBytes(String hex) {
    final s = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    final out = <int>[];
    for (var i = 0; i < s.length; i += 2) {
      final part = s.substring(i, i + 2);
      out.add(int.parse(part, radix: 16));
    }
    return out;
  }

  /// Send image data in chunks. `step` can be 'bw' or 'color' etc.
  Future<bool> writeImageChunks(List<int> data, {int mtu = 20, int interleavedCount = 50, String step = 'bw'}) async {
    if (_writeChar == null) return false;
    final chunkSize = (mtu - 2) > 0 ? mtu - 2 : mtu;
    var noReplyCount = interleavedCount;
    for (var i = 0; i < data.length; i += chunkSize) {
      final isFirst = (i == 0);
      final hdr = (step == 'bw' ? 0x0F : 0x00) | (isFirst ? 0x00 : 0xF0);
      final slice = data.sublist(i, i + chunkSize > data.length ? data.length : i + chunkSize);
      final payload = <int>[CMD_WRITE_IMG, hdr, ...slice];
      final withResp = noReplyCount == 0;
      final ok = await sendData(payload, withResponse: withResp);
      if (!ok) return false;
      if (noReplyCount > 0) {
        noReplyCount--;
      } else {
        noReplyCount = interleavedCount;
      }
    }
    return true;
  }

  void dispose() {
    _scanSub?.cancel();
    _connSub?.cancel();
    _scanController.close();
    _notifyController.close();
  }
}
