import 'dart:typed_data';

import 'epd_protocol.dart';

// 「设备指令 · 调试」里那些高级/危险命令的构造与校验。
//
// 这里只做纯数据的事：把用户输入的十六进制串解析成字节、拼出完整负载、
// 以及给出可读的参数检查结果。真正发送仍由 AppState 的 _sendSimple 负责，
// 这样这一层可以用普通单元测试覆盖，不需要真机或 BLE 桥。
//
// 命令字来自固件 EPD/EPD_service.c：
// - 0x03 SEND_CMD：只取 1 字节写进屏幕控制器的命令寄存器；
// - 0x04 SEND_DATA：负载长度不限，整段写进数据寄存器；
// - 0x21 SET_WEEK_START：1 字节，取值 0..6；
// - 0x90 SET_CONFIG：最多 13 字节（超出部分固件忽略，不足则只覆盖前几项）；
// - 0x91 SYS_RESET：重启芯片，链路会断；
// - 0x92 SYS_SLEEP：深度睡眠，不可通过网络唤醒；
// - 0x99 CFG_ERASE：抹掉配置并重启，等于恢复默认。

/// 命令参数的检查结果。`ok == false` 时仍然允许发送，只是界面上标红提示。
class CommandCheck {
  const CommandCheck({required this.ok, required this.message});

  const CommandCheck.ok([this.message = ''])
      : ok = true;

  final bool ok;
  final String message;

  @override
  String toString() => ok ? 'OK' : message;
}

/// 把 `"0A 0B 0C"` / `"0a0b0c"` / `"0a,0b"` 这类输入解析成字节。
///
/// 允许空格、逗号、`0x` 前缀和换行；空串返回空列表。
/// 出现非十六进制字符或奇数位时抛 [FormatException]。
Uint8List parseHexPayload(String input) {
  String s = input.replaceAll(RegExp(r'0[xX]'), '');
  s = s.replaceAll(RegExp(r'[\s,]'), '');
  if (s.isEmpty) {
    return Uint8List(0);
  }
  if (s.length.isOdd) {
    throw const FormatException('十六进制位数必须是偶数');
  }
  if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(s)) {
    throw const FormatException('包含非十六进制字符');
  }
  final Uint8List out = Uint8List(s.length ~/ 2);
  for (int i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// 校验为 `0x03` 准备的数据：固件只取第 1 个字节。
CommandCheck checkSendCommandData(Uint8List data) {
  if (data.isEmpty) {
    return const CommandCheck(
      ok: false,
      message: '需要一个字节的命令码；为空时固件会直接忽略这条指令。',
    );
  }
  if (data.length > 1) {
    return CommandCheck(
      ok: false,
      message: '固件只取第 1 个字节（0x${data.first.toRadixString(16).toUpperCase().padLeft(2, '0')}），'
          '后面的 ${data.length - 1} 个字节会被丢掉。',
    );
  }
  return const CommandCheck.ok();
}

/// 校验为 `0x04` 准备的数据：固件把整段写进数据寄存器，没有长度限制。
CommandCheck checkSendDataData(Uint8List data) {
  if (data.isEmpty) {
    return const CommandCheck(
      ok: false,
      message: '数据为空，发过去不会有任何效果。',
    );
  }
  return CommandCheck.ok('共 ${data.length} 字节');
}

/// 校验为 `0x21`（周起始日）准备的数据：必须是 1 字节且小于 7。
CommandCheck checkWeekStartData(Uint8List data) {
  if (data.length != 1) {
    return CommandCheck(
      ok: false,
      message: '需要正好 1 个字节（0~6），当前 ${data.length} 字节。',
    );
  }
  if (data.first > 6) {
    return const CommandCheck(
      ok: false,
      message: '取值必须是 0~6（0=周日 … 6=周六），固件会忽略其它值。',
    );
  }
  return const CommandCheck.ok();
}

/// 校验为 `0x90`（写配置）准备的数据：0~13 字节，不足则只覆盖前几项。
CommandCheck checkConfigData(Uint8List data) {
  if (data.length > EpdConfigPayload.size) {
    return CommandCheck(
      ok: false,
      message: '最多 ${EpdConfigPayload.size} 字节，固件会忽略超出的 '
          '${data.length - EpdConfigPayload.size} 个字节。',
    );
  }
  if (data.isEmpty) {
    return const CommandCheck(
      ok: false,
      message: '没有要写入的字段，发过去只会触发一次写 flash。',
    );
  }
  if (data.length < EpdConfigPayload.size) {
    return CommandCheck.ok(
      '只写了前 ${data.length} 项，其余字段保持原值。',
    );
  }
  return const CommandCheck.ok('写满 ${EpdConfigPayload.size} 项');
}

/// 构造 `0x03` 的完整负载（命令字 + 数据）。
Uint8List buildSendCommand(Uint8List data) =>
    buildCommand(EpdCmd.sendCmd, data);

/// 构造 `0x04` 的完整负载。
Uint8List buildSendData(Uint8List data) =>
    buildCommand(EpdCmd.sendData, data);

/// 构造 `0x21` 的完整负载；[weekStart] 超出 0..6 时抛 [ArgumentError]。
Uint8List buildWeekStart(int weekStart) {
  if (weekStart < 0 || weekStart > 6) {
    throw ArgumentError.value(weekStart, 'weekStart', '必须在 0..6 之间');
  }
  return buildCommand(EpdCmd.setWeekStart, <int>[weekStart]);
}

/// 构造 `0x95` 之外的几条「一键」命令。
Uint8List buildSystemReset() => buildCommand(EpdCmd.sysReset);

/// 深度睡眠。调用方必须先确认唤醒引脚可用。
Uint8List buildSystemSleep() => buildCommand(EpdCmd.sysSleep);

/// 抹掉配置并重启。
Uint8List buildConfigErase() => buildCommand(EpdCmd.cfgErase);

/// 固件 `epd_config_t` 的 13 个字段，顺序与 `EPD/EPD_config.h` 完全一致。
///
/// 用类而不是裸数组，是为了让表单能按字段名逐个编辑，也方便把「用户只改了
/// 某几项」翻译成「只发前 N 项」的最短负载。
class EpdConfigPayload {
  const EpdConfigPayload({
    this.mosiPin = 0x0A,
    this.sclkPin = 0x0B,
    this.csPin = 0x0C,
    this.dcPin = 0x0D,
    this.rstPin = 0x0E,
    this.busyPin = 0x0F,
    this.bsPin = 0x10,
    this.modelId = 0x03,
    this.wakeupPin = 0x09,
    this.ledPin = 0x03,
    this.enPin = 0xFF,
    this.displayMode = 0x00,
    this.weekStart = 0x00,
  });

  /// 与固件 `epd_config_t` 同尺寸（13 字节）。
  static const int size = 13;

  /// 出厂默认值（`EPD_service.c` 里的 `EPD_CFG_DEFAULT`，4.2 寸三色 UC8176）。
  ///
  /// 注意固件默认只填了前 10 项，`en_pin` 等后面几项是 0xFF。
  static const EpdConfigPayload factoryDefault = EpdConfigPayload();

  final int mosiPin;
  final int sclkPin;
  final int csPin;
  final int dcPin;
  final int rstPin;
  final int busyPin;
  final int bsPin;
  final int modelId;
  final int wakeupPin;
  final int ledPin;
  final int enPin;
  final int displayMode;
  final int weekStart;

  /// 按固件顺序序列化。
  Uint8List toBytes() => Uint8List.fromList(<int>[
        mosiPin,
        sclkPin,
        csPin,
        dcPin,
        rstPin,
        busyPin,
        bsPin,
        modelId,
        wakeupPin,
        ledPin,
        enPin,
        displayMode,
        weekStart,
      ]);

  /// 从字节还原，不足 13 字节的部分用 [factoryDefault] 补。
  factory EpdConfigPayload.fromBytes(List<int> bytes) {
    final List<int> full = List<int>.generate(
      size,
      (int i) => i < bytes.length ? bytes[i] : factoryDefault.fieldAt(i),
    );
    return EpdConfigPayload(
      mosiPin: full[0],
      sclkPin: full[1],
      csPin: full[2],
      dcPin: full[3],
      rstPin: full[4],
      busyPin: full[5],
      bsPin: full[6],
      modelId: full[7],
      wakeupPin: full[8],
      ledPin: full[9],
      enPin: full[10],
      displayMode: full[11],
      weekStart: full[12],
    );
  }

  /// 按索引取字段（用于和 [factoryDefault] 对齐补齐）。
  int fieldAt(int index) => toBytes()[index];

  /// 各字段的中文名与取值范围，供表单渲染。
  static const List<ConfigField> fields = <ConfigField>[
    ConfigField('mosi_pin', 'MOSI 引脚', 0, 31),
    ConfigField('sclk_pin', 'SCLK 引脚', 0, 31),
    ConfigField('cs_pin', 'CS 引脚', 0, 31),
    ConfigField('dc_pin', 'DC 引脚', 0, 31),
    ConfigField('rst_pin', 'RST 引脚', 0, 31),
    ConfigField('busy_pin', 'BUSY 引脚', 0, 31),
    ConfigField('bs_pin', 'BS 引脚', 0, 31),
    ConfigField('model_id', '驱动型号 ID', 0, 0xFF),
    ConfigField('wakeup_pin', '唤醒引脚', 0, 0xFF),
    ConfigField('led_pin', 'LED 引脚', 0, 0xFF),
    ConfigField('en_pin', 'EN 引脚', 0, 0xFF),
    ConfigField('display_mode', '显示模式', 0, 0xFF),
    ConfigField('week_start', '周起始日', 0, 6),
  ];

  EpdConfigPayload copyWith({
    int? mosiPin,
    int? sclkPin,
    int? csPin,
    int? dcPin,
    int? rstPin,
    int? busyPin,
    int? bsPin,
    int? modelId,
    int? wakeupPin,
    int? ledPin,
    int? enPin,
    int? displayMode,
    int? weekStart,
  }) {
    return EpdConfigPayload(
      mosiPin: mosiPin ?? this.mosiPin,
      sclkPin: sclkPin ?? this.sclkPin,
      csPin: csPin ?? this.csPin,
      dcPin: dcPin ?? this.dcPin,
      rstPin: rstPin ?? this.rstPin,
      busyPin: busyPin ?? this.busyPin,
      bsPin: bsPin ?? this.bsPin,
      modelId: modelId ?? this.modelId,
      wakeupPin: wakeupPin ?? this.wakeupPin,
      ledPin: ledPin ?? this.ledPin,
      enPin: enPin ?? this.enPin,
      displayMode: displayMode ?? this.displayMode,
      weekStart: weekStart ?? this.weekStart,
    );
  }

  /// 只保留前 [count] 项，用于「只改前几项」的最短负载。
  Uint8List firstBytes(int count) => Uint8List.fromList(
        toBytes().sublist(0, count.clamp(0, size)),
      );

  /// 和 [other] 相比，最后一个**不同**字段的下标（1 起算的字节数）；完全相同返回 0。
  ///
  /// 固件是按 `memcpy(..., min(length-1, 13))` 覆盖前缀的，所以只发到最后一个
  /// 变化的字段即可，剩下的保持设备上的原值。
  int changedPrefixLength(EpdConfigPayload other) {
    final Uint8List a = toBytes();
    final Uint8List b = other.toBytes();
    int last = 0;
    for (int i = 0; i < size; i++) {
      if (a[i] != b[i]) {
        last = i + 1;
      }
    }
    return last;
  }

  @override
  bool operator ==(Object other) =>
      other is EpdConfigPayload &&
      changedPrefixLength(other) == 0 &&
      other.changedPrefixLength(this) == 0;

  @override
  int get hashCode => Object.hashAll(toBytes());

  @override
  String toString() =>
      'EpdConfigPayload(0x${toBytes().map((int b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ')})';
}

/// [EpdConfigPayload.fields] 的一项：字节名、中文名、取值范围。
class ConfigField {
  const ConfigField(this.key, this.label, this.min, this.max);

  final String key;
  final String label;
  final int min;
  final int max;

  ConfigField copyWith({int? min, int? max}) =>
      ConfigField(key, label, min ?? this.min, max ?? this.max);
}

/// `0x92` 深度睡眠前的安全性判断。
enum SleepSafety {
  /// 配置通知里有唤醒引脚且不是 0xFF —— 可以放心睡。
  safe,

  /// 有配置但唤醒引脚是 0xFF —— 睡了就起不来，建议禁用。
  unsafe,

  /// 没收到配置，不知道唤醒引脚是多少 —— 允许发送，但必须二次确认。
  unknown,
}

/// 根据唤醒引脚推断 [SleepSafety]。
///
/// [wakeupPin] 为 null 表示还没收到固件配置通知（这在我们这套固件上很常见，
/// 因为配置通知只在开启通知那一刻推一次，漏掉就再也没有）。
SleepSafety evaluateSleepSafety(int? wakeupPin) {
  if (wakeupPin == null) {
    return SleepSafety.unknown;
  }
  if (wakeupPin == 0xFF) {
    return SleepSafety.unsafe;
  }
  return SleepSafety.safe;
}

/// 给界面用的一句话说明。
String describeSleepSafety(SleepSafety safety, int? wakeupPin) {
  switch (safety) {
    case SleepSafety.safe:
      return '已收到配置，唤醒引脚为 0x${wakeupPin!.toRadixString(16).toUpperCase().padLeft(2, '0')}，'
          '发这条指令后按一下墨水屏的唤醒键即可重新唤醒。';
    case SleepSafety.unsafe:
      return '配置里的唤醒引脚是 0xFF（未配置），发送后设备将**无法唤醒**，'
          '只能重新刷固件。已禁用这条指令。';
    case SleepSafety.unknown:
      return '还没收到固件配置，无法确认唤醒引脚。如果设备没配置唤醒引脚，'
          '发送后只能重新刷固件才能唤醒 —— 请先确认再发送。';
  }
}
