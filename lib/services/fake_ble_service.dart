/// 蓝牙层的占位实现。
///
/// 真正的 BLE 需要 `flutter_reactive_ble`，而用户要求先把纯 Dart 部分收尾、再加第三方依赖
/// （失败点集中，好定位）。所以 UI 骨架阶段先用这份假数据驱动界面：扫描返回固定的几台
/// 模拟设备，连接时给出一个符合真实固件行为的版本号 / 引脚 / 通知时序。
///
/// 后续接入真实 BLE 时，把 [FakeBleService] 换成真实现即可，[AppState] 只依赖这里的模型。
library;

import 'dart:typed_data';

import '../protocol/epd_protocol.dart';
import '../protocol/transfer.dart';

/// 扫描到的一台设备。
class FakeEpdDevice {
  const FakeEpdDevice({
    required this.id,
    required this.name,
    required this.rssi,
  });

  /// 平台设备 id（真机上通常是 MAC 地址）。
  final String id;

  /// 广播名。
  final String name;

  /// 信号强度（dBm，负数）。
  final int rssi;

  /// 广播名里是否像 4.2 寸三色屏（用来给默认选择做提示）。
  bool get looksLikeThreeColor => name.contains('BWR');
}

/// 假蓝牙服务：结果固定、时序固定，方便写测试。
class FakeBleService {
  /// 模拟的固件版本，与上游 `EPD_service.h` 的 `APP_VERSION 0x1a` 一致。
  static const int firmwareVersion = 0x1a;

  /// 模拟的引脚配置，取自上游 `docs/devices.md` 里「老五 4.2 寸三色」那一行。
  static const String pinsHex = '0A0B0C0D0E0F10';

  /// 模拟的 MTU（固件 INIT 之后会通过通知报上来）。
  static const int mtu = 20;

  /// 模拟扫描结果。
  List<FakeEpdDevice> discover() => const <FakeEpdDevice>[
        FakeEpdDevice(
          id: 'C4:7F:51:00:00:01',
          name: 'EPD-4.2-BWR',
          rssi: -46,
        ),
        FakeEpdDevice(
          id: 'C4:7F:51:00:00:02',
          name: 'EPD-4.2-BW',
          rssi: -63,
        ),
        FakeEpdDevice(
          id: 'C4:7F:51:00:00:03',
          name: 'EPD-7.5-BWR',
          rssi: -78,
        ),
      ];

  /// 模拟连接后固件主动上报的配置通知（7 引脚 + 驱动 id）。
  EpdConfig configFor(FakeEpdDevice device, {required int driverCode}) {
    return EpdConfig(
      pins: parseHexBytes(pinsHex),
      driver: driverCode,
    );
  }

  /// 模拟连接后固件回复的文本通知：`mtu=20 rle=1`。
  String textNotification({required int mtuValue, required bool rle}) {
    return 'mtu=$mtuValue${rle ? ' rle=1' : ''}';
  }

  /// 供 UI 显示用的引脚字节。
  Uint8List get pins => parseHexBytes(pinsHex);
}
