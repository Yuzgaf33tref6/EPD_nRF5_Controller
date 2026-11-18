/// 传输编排 —— 把"一张图 + 一个驱动"翻译成完整的一串 BLE 写指令。
///
/// 对应 web 版 `html/js/main.js` 的 `sendimg()`（第 220-284 行）、`setDriver()`
/// （154-157）、`syncTime()`（159-176）、`clearScreen()`（178-184）。
/// 这里只生成指令序列，不碰蓝牙；BLE 层拿到序列逐条发出即可。
library;

import 'dart:typed_data';

import '../devices/epd_driver.dart';
import '../image/epd_color.dart';
import '../image/packing.dart';
import '../image/rgba_image.dart';
import 'epd_protocol.dart';

/// 一条待发送的 BLE 写指令。
///
/// [payload] 已经是最终字节（命令字 + 负载），直接丢给
/// `characteristic.write(payload, withResponse: ...)`。
class EpdWrite {
  const EpdWrite({required this.payload, required this.withResponse});

  final Uint8List payload;

  /// 是否等待设备应答（有应答写 / 无应答写）。
  final bool withResponse;

  /// 首字节即命令字；理论上不会为空。
  EpdCmd? get command {
    for (final EpdCmd cmd in EpdCmd.values) {
      if (cmd.code == payload[0]) {
        return cmd;
      }
    }
    return null;
  }

  /// 命令字之后的负载。
  Uint8List get data => payload.sublist(1);

  @override
  String toString() =>
      'EpdWrite(${command?.name ?? payload[0].toString()}, ${payload.length} B, '
      'withResponse: $withResponse)';
}

/// 发送前需要用户确认的不匹配项（web 版用 `confirm()` 弹窗询问是否继续）。
enum TransferWarning {
  /// 画布尺寸与驱动声明的尺寸不一致。
  canvasSizeMismatch,

  /// 颜色模式与驱动声明的颜色模式不一致。
  colorModeMismatch,
}

/// 一次传图的完整计划。
class ImageTransferPlan {
  const ImageTransferPlan({
    required this.writes,
    required this.warnings,
    required this.processedBytes,
    required this.imageWrites,
    required this.usedUc8159,
    required this.usedRle,
  });

  /// 按顺序要发的全部指令：INIT → 若干 WRITE_IMG → REFRESH。
  final List<EpdWrite> writes;

  /// 需要用户确认的不匹配项；为空表示完全匹配，可直接发。
  final List<TransferWarning> warnings;

  /// `processImageData()` 输出的字节数（一个位平面的长度）。
  final int processedBytes;

  /// WRITE_IMG 指令条数（RLE 与分块都会影响它）。
  final int imageWrites;

  /// 是否走了 UC8159 的 4bit/px 合并通道。
  final bool usedUc8159;

  /// 是否有任意一个位平面真的启用了 RLE。
  final bool usedRle;

  int get totalWrites => writes.length;

  @override
  String toString() => 'ImageTransferPlan(${writes.length} 写, '
      '${processedBytes}B, imageWrites=$imageWrites, '
      'uc8159=$usedUc8159, rle=$usedRle)';
}

/// 把两位十六进制串转成字节（等价 web 版 `hex2bytes`）。
///
/// 长度必须为偶数，否则抛 [FormatException]。
Uint8List parseHexBytes(String hex) {
  final String text = hex.trim();
  if (text.length.isOdd) {
    throw FormatException('十六进制串长度必须为偶数', text);
  }
  final bytes = Uint8List(text.length ~/ 2);
  for (int i = 0; i < bytes.length; i++) {
    final int? value = int.tryParse(text.substring(i * 2, i * 2 + 2), radix: 16);
    if (value == null) {
      throw FormatException('不是合法的十六进制字节', text.substring(i * 2, i * 2 + 2));
    }
    bytes[i] = value;
  }
  return bytes;
}

/// 生成传图计划。逐行复刻 `sendimg()`。
///
/// [image] 必须已经是画布尺寸（web 版直接在 canvas 上取像素），[colorMode] 是
/// 用户在下拉框里选的模式（可能和 [driver] 不符 —— 那会进 [ImageTransferPlan.warnings]）。
///
/// 流程：
/// 1. `processImageData()` 得到位打包数据；
/// 2. 发 INIT；
/// 3. 按颜色模式与驱动分流：
///    * 三色：拆成前半黑白、后半红白；UC8159 驱动合并为 4bit/px 一次写，其余分两次写；
///    * 黑白：UC8159 驱动补一层全 `0xFF` 的红白平面再合并，其余直接写；
///    * 四色 / 六色：一次写；
/// 4. 发 REFRESH。
ImageTransferPlan planImageTransfer({
  required RgbaImage image,
  required EpdDriver driver,
  required EpdColorMode colorMode,
  required String canvasSizeName,
  required int mtu,
  required bool rleSupported,
  int interleavedCount = 50,
  bool alwaysWithResponse = false,
  bool swapPlanes = false,
  bool invertRedPlane = false,
}) {
  final warnings = <TransferWarning>[
    if (canvasSizeName != driver.canvasSizeName) TransferWarning.canvasSizeMismatch,
    if (colorMode != driver.colorMode) TransferWarning.colorModeMismatch,
  ];

  final Uint8List processed = processImageData(image, colorMode);
  final writes = <EpdWrite>[
    EpdWrite(payload: buildCommand(EpdCmd.init), withResponse: true),
  ];

  var imageWrites = 0;
  var usedRle = false;
  final bool uc8159 = driver.usesUc8159;

  void writePlane(Uint8List data, ImagePlane plane) {
    final WriteImagePlan plan = planWriteImage(
      data: data,
      mtu: mtu,
      plane: plane,
      rleSupported: rleSupported,
      interleavedCount: interleavedCount,
      alwaysWithResponse: alwaysWithResponse,
    );
    usedRle = usedRle || plan.useRle;
    for (final WriteImageChunk chunk in plan.chunks) {
      writes.add(EpdWrite(payload: chunk.toPayload(), withResponse: chunk.withResponse));
      imageWrites++;
    }
  }

  if (colorMode == EpdColorMode.threeColor) {
    // web 版用 Math.floor，两个位平面等长，这里 ~/ 与之等价。
    final int halfLength = processed.length ~/ 2;
    Uint8List blackWhiteData = Uint8List.sublistView(processed, 0, halfLength);
    Uint8List redWhiteData = Uint8List.sublistView(processed, halfLength);
    // 真机上排查「颜色不对」用的两个开关，默认都关（默认行为与 web 版逐字节一致）。
    if (invertRedPlane) {
      final Uint8List inverted = Uint8List(redWhiteData.length);
      for (int i = 0; i < redWhiteData.length; i++) {
        inverted[i] = 0xFF ^ redWhiteData[i];
      }
      redWhiteData = inverted;
    }
    if (swapPlanes) {
      final Uint8List tmp = blackWhiteData;
      blackWhiteData = redWhiteData;
      redWhiteData = tmp;
    }
    if (uc8159) {
      writePlane(convertUC8159(blackWhiteData, redWhiteData), ImagePlane.black);
    } else {
      writePlane(blackWhiteData, ImagePlane.black);
      writePlane(redWhiteData, ImagePlane.red);
    }
  } else if (colorMode == EpdColorMode.blackWhiteColor) {
    if (uc8159) {
      final Uint8List emptyData = Uint8List(processed.length)..fillRange(0, processed.length, 0xff);
      writePlane(convertUC8159(processed, emptyData), ImagePlane.black);
    } else {
      writePlane(processed, ImagePlane.black);
    }
  } else {
    // 四色 / 六色：一次写入（需要 v1.6+ 固件，web 版不再分支）。
    writePlane(processed, ImagePlane.black);
  }

  writes.add(EpdWrite(payload: buildCommand(EpdCmd.refresh), withResponse: true));

  return ImageTransferPlan(
    writes: writes,
    warnings: warnings,
    processedBytes: processed.length,
    imageWrites: imageWrites,
    usedUc8159: uc8159,
    usedRle: usedRle,
  );
}

/// 对应 `setDriver()`：先 SET_PINS 再 INIT。
///
/// [pinsHex] 是引脚十六进制串（如 `0508090A0B0C0D`），通常来自设备配置通知或
/// 用户手填。
List<EpdWrite> planSetDriver({required EpdDriver driver, required String pinsHex}) {
  return <EpdWrite>[
    EpdWrite(payload: buildCommand(EpdCmd.setPins, parseHexBytes(pinsHex)), withResponse: true),
    EpdWrite(payload: buildCommand(EpdCmd.init, <int>[driver.code]), withResponse: true),
  ];
}

/// 根据设备上报的配置通知生成"引脚 + 驱动"配置指令。
///
/// 驱动编号不在表里时返回空列表（web 版此时会写一个不存在的驱动号）。
List<EpdWrite> planConfigureFromNotification(EpdConfig config) {
  final EpdDriver? driver = driverByCode(config.driver);
  if (driver == null) {
    return const <EpdWrite>[];
  }
  return <EpdWrite>[
    EpdWrite(
      payload: buildCommand(EpdCmd.setPins, config.pins),
      withResponse: true,
    ),
    EpdWrite(
      payload: buildCommand(EpdCmd.init, <int>[driver.code]),
      withResponse: true,
    ),
  ];
}

/// 对应 `syncTime()`：同步 RTC。时钟模式（[EpdTimeMode.clock]）走全刷，用于修残影。
List<EpdWrite> planSyncTime({
  required int unixSeconds,
  required int utcOffsetHours,
  EpdTimeMode mode = EpdTimeMode.calendar,
}) {
  return <EpdWrite>[
    EpdWrite(
      payload: buildCommand(
        EpdCmd.setTime,
        buildSetTimeData(
          unixSeconds: unixSeconds,
          utcOffsetHours: utcOffsetHours,
          mode: mode,
        ),
      ),
      withResponse: true,
    ),
  ];
}

/// 对应 `clearScreen()`。
List<EpdWrite> planClearScreen() => <EpdWrite>[
      EpdWrite(payload: buildCommand(EpdCmd.clear), withResponse: true),
    ];

/// 单独发一次刷新（例如手动画完后重刷）。
List<EpdWrite> planRefresh() => <EpdWrite>[
      EpdWrite(payload: buildCommand(EpdCmd.refresh), withResponse: true),
    ];

/// 让屏幕进入低功耗休眠。
List<EpdWrite> planSleep() => <EpdWrite>[
      EpdWrite(payload: buildCommand(EpdCmd.sleep), withResponse: true),
    ];

/// 把用户手输的十六进制命令串（web 版 `#cmdTXT`）转成一条原始写指令。
///
/// 返回 null 表示输入为空或非法。
EpdWrite? planRawCommand(String hex) {
  if (hex.trim().isEmpty) {
    return null;
  }
  final Uint8List bytes;
  try {
    bytes = parseHexBytes(hex);
  } on FormatException {
    return null;
  }
  if (bytes.isEmpty) {
    return null;
  }
  return EpdWrite(payload: bytes, withResponse: true);
}

/// 画布尺寸与驱动是否匹配（web 版 `sendimg()` 的两个 `confirm`）。
List<TransferWarning> checkTransferCompatibility({
  required EpdDriver driver,
  required EpdColorMode colorMode,
  required String canvasSizeName,
}) {
  return <TransferWarning>[
    if (canvasSizeName != driver.canvasSizeName) TransferWarning.canvasSizeMismatch,
    if (colorMode != driver.colorMode) TransferWarning.colorModeMismatch,
  ];
}
