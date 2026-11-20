import 'dart:convert';
import 'dart:typed_data';

import 'rle.dart';

/// EPD-nRF5 固件通过 BLE 暴露的 GATT UUID。
///
/// 与 web 版 `html/js/main.js` 的 `connect()` 保持一致。
class EpdUuid {
  const EpdUuid._();

  /// 主服务。
  static const String service = '62750001-d828-918d-fb46-b6c11c675aec';

  /// 命令/数据特征：所有命令都往这里写，通知也从这里来。
  static const String commandCharacteristic = '62750002-d828-918d-fb46-b6c11c675aec';

  /// 版本特征：只读，`byte[0]` 是固件 `APP_VERSION`。
  static const String versionCharacteristic = '62750003-d828-918d-fb46-b6c11c675aec';
}

/// 固件支持 RLE 压缩传输的最低版本（1.6）。
const int kMinRleFirmwareVersion = 0x16;

/// 固件命令字，与 `EPD/EPD_service.h` 的 `EpdCmd` 一致。
enum EpdCmd {
  setPins(0x00),
  init(0x01),
  clear(0x02),
  sendCmd(0x03),
  sendData(0x04),
  refresh(0x05),
  sleep(0x06),
  setTime(0x20),
  setWeekStart(0x21),
  writeImg(0x30),
  setConfig(0x90),
  sysReset(0x91),
  sysSleep(0x92),
  cfgErase(0x99);

  const EpdCmd(this.code);

  /// 线上传输的单字节命令字。
  final int code;
}

/// 时间同步的两种模式。
enum EpdTimeMode {
  /// 日历模式：按当前时间渲染日历。
  calendar(1),

  /// 时钟模式：用全刷实现，只建议用来修残影。
  clock(2);

  const EpdTimeMode(this.code);

  final int code;
}

/// 图像数据落在哪一半显存：黑白层还是红色层。
enum ImagePlane { black, red }

/// 拼一条命令：`[cmd, ...data]`。对应 web 版的 `write()`。
Uint8List buildCommand(EpdCmd cmd, [List<int> data = const <int>[]]) {
  final out = Uint8List(1 + data.length);
  out[0] = cmd.code & 0xff;
  out.setRange(1, out.length, data);
  return out;
}

/// 构造 SET_TIME(0x20) 的负载：4 字节大端 unix 时间戳 + 1 字节时区小时 + 1 字节模式。
///
/// 对应 web 版 `syncTime()`：
/// `[ts>>24, ts>>16, ts>>8, ts, -(getTimezoneOffset()/60), mode]`。
/// 其中 `getTimezoneOffset()` 返回"本地时间比 UTC 晚多少分钟"，东八区是 -480，
/// 取负再除以 60 得到 +8，所以 [utcOffsetHours] 就是"东为正"的小时数。
Uint8List buildSetTimeData({
  required int unixSeconds,
  required int utcOffsetHours,
  EpdTimeMode mode = EpdTimeMode.calendar,
}) {
  final ts = unixSeconds.toSigned(32);
  return Uint8List.fromList(<int>[
    (ts >> 24) & 0xff,
    (ts >> 16) & 0xff,
    (ts >> 8) & 0xff,
    ts & 0xff,
    utcOffsetHours & 0xff,
    mode.code & 0xff,
  ]);
}

/// 一块待写入的 WRITE_IMG(0x30) 负载。
class WriteImageChunk {
  const WriteImageChunk({
    required this.flag,
    required this.data,
    required this.withResponse,
  });

  /// WRITE_IMG 的 flag 字节，含义见 [planWriteImage]。
  final int flag;

  /// 该块的数据字节（不含 flag）。
  final Uint8List data;

  /// 这次写入要不要等应答。web 版每 [interleavedCount] 块用一次有应答写。
  final bool withResponse;

  /// 拼成完整的 BLE 写入内容：`[0x30, flag, ...data]`。
  Uint8List toPayload() {
    final out = Uint8List(2 + data.length);
    out[0] = EpdCmd.writeImg.code;
    out[1] = flag & 0xff;
    out.setRange(2, out.length, data);
    return out;
  }
}

/// 一次传图的完整分块计划。
class WriteImagePlan {
  const WriteImagePlan({
    required this.chunkSize,
    required this.useRle,
    required this.chunks,
  });

  /// 每个数据块的字节上限（`mtu - 2`）。
  final int chunkSize;

  /// 是否真的启用了 RLE（压缩后确实更短才算）。
  final bool useRle;

  final List<WriteImageChunk> chunks;

  int get totalChunks => chunks.length;
}

/// 把整层图像数据切成 WRITE_IMG 分块，逐行复刻 web 版 `main.js` 的 `writeImage()`。
///
/// flag 字节的算法（原样搬运，两套固件语义不同，不要"简化"）：
///
/// * 固件支持 RLE 时：`(黑白 ? 0x00 : 0x01) | (首块 ? 0x02 : 0x00) | (用RLE ? 0x04 : 0x00)`
/// * 老固件（不支持 RLE）时：`(黑白 ? 0x0F : 0x00) | (首块 ? 0x00 : 0xF0)`
///
/// 应答节奏：连续 [interleavedCount] 块用"无应答写"，紧接着一块用"有应答写"，
/// 如此循环；第一块也是无应答写。
WriteImagePlan planWriteImage({
  required Uint8List data,
  required int mtu,
  required ImagePlane plane,
  required bool rleSupported,
  int interleavedCount = 50,
  bool alwaysWithResponse = false,
}) {
  if (mtu < 3) {
    // mtu - 2 < 1 会让分块数为 Infinity，web 版在这种情况下会死循环。
    throw ArgumentError.value(mtu, 'mtu', '至少为 3（chunkSize = mtu - 2 必须为正）');
  }
  if (interleavedCount < 1) {
    throw ArgumentError.value(interleavedCount, 'interleavedCount', '至少为 1');
  }

  final chunkSize = mtu - 2;
  final rleChunks = rleSupported ? rleCompressMtu(data, chunkSize) : null;
  final int encodedLength = rleChunks == null
      ? data.length
      : rleChunks.fold<int>(0, (total, chunk) => total + chunk.length);
  final useRle = rleSupported && encodedLength < data.length;

  final chunks = <WriteImageChunk>[];
  if (useRle) {
    for (var i = 0; i < rleChunks!.length; i++) {
      chunks.add(WriteImageChunk(
        flag: _writeImageFlag(
          plane: plane,
          isFirst: i == 0,
          rleSupported: true,
          useRle: true,
        ),
        data: rleChunks[i],
        withResponse: false,
      ));
    }
  } else {
    final totalChunks = (data.length + chunkSize - 1) ~/ chunkSize;
    for (var i = 0; i < totalChunks; i++) {
      final offset = i * chunkSize;
      final end = offset + chunkSize < data.length ? offset + chunkSize : data.length;
      chunks.add(WriteImageChunk(
        flag: _writeImageFlag(
          plane: plane,
          isFirst: i == 0,
          rleSupported: rleSupported,
          useRle: false,
        ),
        data: data.sublist(offset, end),
        withResponse: false,
      ));
    }
  }

  if (alwaysWithResponse) {
    // 一条一条等设备确认。实测 nRF51 上连续几十条无响应写会撑爆蓝牙缓冲，
    // Android 直接回 GATT 133 并拆掉连接，所以真机上必须能切成「全带响应」。
    return WriteImagePlan(
      chunkSize: chunkSize,
      useRle: useRle,
      chunks: <WriteImageChunk>[
        for (final WriteImageChunk chunk in chunks)
          WriteImageChunk(
            flag: chunk.flag,
            data: chunk.data,
            withResponse: true,
          ),
      ],
    );
  }

  // 应答节奏单独走一遍，保证与 web 版逐块一致。
  final paced = <WriteImageChunk>[];
  var noReplyCount = interleavedCount;
  for (final chunk in chunks) {
    final bool withResponse;
    if (noReplyCount > 0) {
      withResponse = false;
      noReplyCount--;
    } else {
      withResponse = true;
      noReplyCount = interleavedCount;
    }
    paced.add(WriteImageChunk(
      flag: chunk.flag,
      data: chunk.data,
      withResponse: withResponse,
    ));
  }

  return WriteImagePlan(chunkSize: chunkSize, useRle: useRle, chunks: paced);
}

int _writeImageFlag({
  required ImagePlane plane,
  required bool isFirst,
  required bool rleSupported,
  required bool useRle,
}) {
  if (rleSupported) {
    return (plane == ImagePlane.black ? 0x00 : 0x01) |
        (isFirst ? 0x02 : 0x00) |
        (useRle ? 0x04 : 0x00);
  }
  return (plane == ImagePlane.black ? 0x0F : 0x00) |
      (isFirst ? 0x00 : 0xF0);
}

/// 连接后收到的第一条通知：当前引脚配置 + 驱动 id。
class EpdConfig {
  const EpdConfig({required this.pins, required this.driver, this.wakeupPin});

  /// 引脚号列表。通常是 7 个，`byte[10]` 存在时会多一个（第 8 个引脚）。
  final Uint8List pins;

  /// 驱动 id（`html/js/main.js` 里驱动下拉框的值，如 0x03）。
  final int driver;

  /// 唤醒引脚（固件 `epd_config_t` 的第 9 个字节，索引 8）。
  ///
  /// 配置通知刚好 13 字节时才有；只有 8~10 字节的老固件拿不到，为 null。
  /// `0xFF` 表示固件没配唤醒引脚 —— 那种情况下发 `0x92` 深度睡眠就再也唤醒不了。
  final int? wakeupPin;
}

/// 解析配置通知，对应 web 版 `handleNotify(value, 0)`。
///
/// 布局：`bytes[0..7)` = 引脚，`bytes[7]` = 驱动 id，`bytes[10]`（若有）= 追加引脚。
EpdConfig parseConfigNotification(Uint8List value) {
  if (value.length < 8) {
    throw ArgumentError.value(
      value.length,
      'value',
      '配置通知至少 8 字节（7 引脚 + 1 驱动 id）',
    );
  }
  final pins = <int>[...value.sublist(0, 7)];
  if (value.length > 10) {
    pins.add(value[10]);
  }
  return EpdConfig(
    pins: Uint8List.fromList(pins),
    driver: value[7],
    // 13 字节的完整配置里，索引 8 是 wakeup_pin（见 EPD/EPD_config.h）。
    wakeupPin: value.length >= 13 ? value[8] : null,
  );
}

/// 连接后除第一条以外的通知：UTF-8 文本，形如 `mtu=247 rle=1` 或 `t=1763500000`。
class EpdTextNotification {
  const EpdTextNotification({
    required this.text,
    this.mtu,
    this.rleSupported = false,
    this.remoteUnixSeconds,
  });

  /// 原始文本。
  final String text;

  /// 固件广播的 MTU（`mtu=` 前缀时才有）。
  final int? mtu;

  /// 固件是否支持 RLE（`mtu=` 且文本里带 `rle=1` 才置真，和 web 版一致）。
  final bool rleSupported;

  /// 固件侧 unix 时间戳（`t=` 前缀时才有），未加本地时区偏移。
  final int? remoteUnixSeconds;
}

/// 解析文本通知，对应 web 版 `handleNotify(value, idx>0)`。
EpdTextNotification parseTextNotification(Uint8List value) {
  final text = utf8.decode(value, allowMalformed: true);

  if (text.startsWith('mtu=') && text.length > 4) {
    final parsed = _parseIntLikeJs(text.substring(4));
    return EpdTextNotification(
      text: text,
      mtu: parsed,
      rleSupported: text.contains('rle=1'),
    );
  }
  if (text.startsWith('t=') && text.length > 2) {
    return EpdTextNotification(
      text: text,
      remoteUnixSeconds: _parseIntLikeJs(text.substring(2)),
    );
  }
  return EpdTextNotification(text: text);
}

/// 模拟 JS `parseInt()`：取开头的可选符号 + 连续数字，失败返回 null。
int? _parseIntLikeJs(String input) {
  final match = RegExp(r'^\s*([+-]?\d+)').firstMatch(input);
  if (match == null) {
    return null;
  }
  return int.tryParse(match.group(1)!);
}
