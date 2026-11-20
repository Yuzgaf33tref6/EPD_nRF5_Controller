import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../image/epd_color.dart';
import '../protocol/debug_commands.dart';
import '../protocol/epd_protocol.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

/// 「设备指令 · 调试」页：直接给固件发底层指令。
///
/// 这里的每一条都会真的动硬件，所以危险命令（深度睡眠、擦配置、重启）
/// 都带二次确认。参数是否合理由 [debug_commands] 里的校验函数判断，
/// **即使不合规也允许发送**（按用户要求：只是标红提示，不拦）。
class DebugCommandsScreen extends StatelessWidget {
  const DebugCommandsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState state = AppStateScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('设备指令 · 调试')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: <Widget>[
          if (!state.isConnected) ...<Widget>[
            const Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text('还没连接设备。下面这些指令都要连上设备才能发。'),
              ),
            ),
            const SizedBox(height: 12),
          ],
          _SendCommandCard(state: state),
          const SizedBox(height: 12),
          _SendDataCard(state: state),
          const SizedBox(height: 12),
          _WeekStartCard(state: state),
          const SizedBox(height: 12),
          _ConfigCard(state: state),
          const SizedBox(height: 12),
          _DangerCard(state: state),
          const SizedBox(height: 12),
          _SolidColorCard(state: state),
        ],
      ),
    );
  }
}

/// `0x03` 发送屏幕命令。
class _SendCommandCard extends StatefulWidget {
  const _SendCommandCard({required this.state});

  final AppState state;

  @override
  State<_SendCommandCard> createState() => _SendCommandCardState();
}

class _SendCommandCardState extends State<_SendCommandCard> {
  late final TextEditingController _controller =
      TextEditingController(text: '22');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Uint8List? data = _tryParse(_controller.text);
    final CommandCheck check =
        data == null ? const CommandCheck(ok: false, message: '十六进制格式不对') : checkSendCommandData(data);
    return SectionCard(
      title: '0x03 发送屏幕命令',
      icon: Icons.code,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _HexField(
            controller: _controller,
            label: '命令码（十六进制）',
            hint: '例如 22 = 0x22',
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 8),
          _CheckHint(check: check),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: data == null || !widget.state.isConnected
                ? null
                : () => widget.state.sendScreenCommand(data),
            child: const Text('发送 0x03'),
          ),
        ],
      ),
    );
  }
}

/// `0x04` 发送屏幕数据。
class _SendDataCard extends StatefulWidget {
  const _SendDataCard({required this.state});

  final AppState state;

  @override
  State<_SendDataCard> createState() => _SendDataCardState();
}

class _SendDataCardState extends State<_SendDataCard> {
  late final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Uint8List? data = _tryParse(_controller.text);
    final CommandCheck check = data == null
        ? const CommandCheck(ok: false, message: '十六进制格式不对')
        : checkSendDataData(data);
    return SectionCard(
      title: '0x04 发送屏幕数据',
      icon: Icons.data_array,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _HexField(
            controller: _controller,
            label: '数据（十六进制，可多字节）',
            hint: '例如 11 22 33',
            maxLines: 3,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 8),
          _CheckHint(check: check),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: data == null || !widget.state.isConnected
                ? null
                : () => widget.state.sendScreenData(data),
            child: const Text('发送 0x04'),
          ),
        ],
      ),
    );
  }
}

/// `0x21` 设置周起始日。
class _WeekStartCard extends StatefulWidget {
  const _WeekStartCard({required this.state});

  final AppState state;

  @override
  State<_WeekStartCard> createState() => _WeekStartCardState();
}

class _WeekStartCardState extends State<_WeekStartCard> {
  int _value = 1;

  static const List<String> _labels = <String>[
    '周日',
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
  ];

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: '0x21 设置周起始日',
      icon: Icons.calendar_view_week,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          DropdownButtonFormField<int>(
            initialValue: _value,
            decoration: const InputDecoration(labelText: '一周从哪天开始'),
            items: <DropdownMenuItem<int>>[
              for (int i = 0; i < _labels.length; i++)
                DropdownMenuItem<int>(value: i, child: Text('$_labels[$i]（$i）')),
            ],
            onChanged: (int? v) => setState(() => _value = v ?? 1),
          ),
          const SizedBox(height: 8),
          Text(
            '只影响固件日历页的排版，改完立即生效（固件会顺手写一次配置）。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed:
                widget.state.isConnected ? () => widget.state.setWeekStart(_value) : null,
            child: const Text('发送 0x21'),
          ),
        ],
      ),
    );
  }
}

/// `0x90` 写配置（13 个字段）。
class _ConfigCard extends StatefulWidget {
  const _ConfigCard({required this.state});

  final AppState state;

  @override
  State<_ConfigCard> createState() => _ConfigCardState();
}

class _ConfigCardState extends State<_ConfigCard> {
  late EpdConfigPayload _config = EpdConfigPayload.factoryDefault;
  late final List<TextEditingController> _controllers = <TextEditingController>[
    for (final ConfigField f in EpdConfigPayload.fields)
      TextEditingController(text: _hex(_config.fieldAt(0))),
  ];

  static String _hex(int v) =>
      '0x${v.toRadixString(16).toUpperCase().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _syncControllers();
  }

  void _syncControllers() {
    final Uint8List bytes = _config.toBytes();
    for (int i = 0; i < _controllers.length; i++) {
      _controllers[i].text = _hex(bytes[i]);
    }
  }

  @override
  void dispose() {
    for (final TextEditingController c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  int? _parseHex(String text) {
    String s = text.trim();
    if (s.toLowerCase().startsWith('0x')) {
      s = s.substring(2);
    }
    if (s.isEmpty) {
      return null;
    }
    final int? v = int.tryParse(s, radix: 16);
    if (v == null || v < 0 || v > 0xFF) {
      return null;
    }
    return v;
  }

  void _applyField(int index, int value) {
    switch (index) {
      case 0:
        _config = _config.copyWith(mosiPin: value);
      case 1:
        _config = _config.copyWith(sclkPin: value);
      case 2:
        _config = _config.copyWith(csPin: value);
      case 3:
        _config = _config.copyWith(dcPin: value);
      case 4:
        _config = _config.copyWith(rstPin: value);
      case 5:
        _config = _config.copyWith(busyPin: value);
      case 6:
        _config = _config.copyWith(bsPin: value);
      case 7:
        _config = _config.copyWith(modelId: value);
      case 8:
        _config = _config.copyWith(wakeupPin: value);
      case 9:
        _config = _config.copyWith(ledPin: value);
      case 10:
        _config = _config.copyWith(enPin: value);
      case 11:
        _config = _config.copyWith(displayMode: value);
      case 12:
        _config = _config.copyWith(weekStart: value);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 找出最后一个被改动的字段，只发到那里（固件按前缀覆盖，其余保持原值）。
    final int prefix =
        _config.changedPrefixLength(EpdConfigPayload.factoryDefault);
    final Uint8List payload =
        _config.firstBytes(prefix == 0 ? 0 : prefix);
    return SectionCard(
      title: '0x90 写配置（${EpdConfigPayload.size} 项）',
      icon: Icons.tune,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '按固件 epd_config_t 的字段顺序。写完后不会立即生效，'
            '需要再发一次 0x91 重启。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          for (int i = 0; i < EpdConfigPayload.fields.length; i++) ...<Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: <Widget>[
                  Expanded(
                    flex: 3,
                    child: Text(
                      EpdConfigPayload.fields[i].label,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _controllers[i],
                      style: const TextStyle(fontFamily: 'monospace'),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (String text) {
                        final int? v = _parseHex(text);
                        if (v != null) {
                          setState(() => _applyField(i, v));
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            prefix == 0
                ? '和出厂默认相同，不需要发送。'
                : '将写入前 $prefix 项：${payload.map((int b) => _hex(b)).join(' ')}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() {
                    _config = EpdConfigPayload.factoryDefault;
                    _syncControllers();
                  }),
                  child: const Text('恢复出厂值'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonal(
                  onPressed: !widget.state.isConnected || prefix == 0
                      ? null
                      : () => widget.state.writeConfig(_config,
                          byteCount: prefix),
                  child: const Text('发送 0x90'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 危险指令：重启 / 深度睡眠 / 恢复默认配置。
class _DangerCard extends StatelessWidget {
  const _DangerCard({required this.state});

  final AppState state;

  Future<bool> _confirmCheckBox(
    BuildContext context, {
    required String title,
    required String message,
    required String checkboxLabel,
    required String action,
  }) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        bool checked = false;
        return StatefulBuilder(
          builder: (BuildContext ctx, StateSetter setLocal) {
            return AlertDialog(
              title: Text(title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(message),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    value: checked,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(checkboxLabel),
                    onChanged: (bool? v) => setLocal(() => checked = v ?? false),
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: checked ? () => Navigator.of(ctx).pop(true) : null,
                  child: Text(action),
                ),
              ],
            );
          },
        );
      },
    );
    return ok ?? false;
  }

  Future<bool> _confirmSimple(
    BuildContext context, {
    required String title,
    required String message,
    required String action,
  }) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final SleepSafety safety = state.sleepSafety;
    final int? wakeupPin = state.wakeupPin;
    // unsafe：配置明确说没有唤醒引脚 → 直接禁用。
    // unknown：还没收到配置 → 允许，但强制勾选确认。
    final bool sleepDisabled = !state.isConnected || safety == SleepSafety.unsafe;

    return SectionCard(
      title: '危险指令',
      icon: Icons.warning_amber,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          OutlinedButton.icon(
            onPressed: state.isConnected ? () => state.refreshScreen() : null,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('不发指令，仅刷新屏幕（安全）'),
          ),
          const SizedBox(height: 10),
          // ---- 0x91 重启 ----
          OutlinedButton.icon(
            onPressed: !state.isConnected
                ? null
                : () async {
                    final bool ok = await _confirmCheckBox(
                      context,
                      title: '重启设备（0x91）？',
                      message: '芯片会立刻重启，蓝牙连接会断开，需要重新连接。'
                          '写过的配置会在重启后生效。',
                      checkboxLabel: '我知道连接会断开',
                      action: '重启',
                    );
                    if (ok) {
                      await state.systemReset();
                    }
                  },
            icon: const Icon(Icons.restart_alt, size: 18),
            label: const Text('0x91 系统重启（会断开连接）'),
          ),
          const SizedBox(height: 10),
          // ---- 0x92 深度睡眠 ----
          OutlinedButton.icon(
            onPressed: sleepDisabled
                ? null
                : () async {
                    final bool ok = await _confirmCheckBox(
                      context,
                      title: '系统深度睡眠（0x92）？',
                      message: describeSleepSafety(safety, wakeupPin),
                      checkboxLabel: safety == SleepSafety.unknown
                          ? '我确认该设备已配置唤醒引脚'
                          : '我知道需要按唤醒键才能恢复',
                      action: '睡眠',
                    );
                    if (ok) {
                      await state.systemSleep();
                    }
                  },
            icon: const Icon(Icons.bedtime, size: 18),
            label: const Text('0x92 系统睡眠（不可通过网络唤醒）'),
          ),
          const SizedBox(height: 4),
          Text(
            describeSleepSafety(safety, wakeupPin),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: safety == SleepSafety.safe
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : Theme.of(context).colorScheme.error,
                ),
          ),
          const SizedBox(height: 10),
          // ---- 0x99 恢复默认 ----
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: !state.isConnected
                ? null
                : () async {
                    final bool ok = await _confirmCheckBox(
                      context,
                      title: '恢复默认配置（0x99）？',
                      message: '会抹掉设备上的引脚/驱动配置，恢复成出厂默认，'
                          '然后重启。如果默认值和你的屏幕不匹配，屏幕将再也刷不出图，'
                          '需要用其他工具重新写配置。',
                      checkboxLabel: '我知道这会抹掉当前配置',
                      action: '恢复默认',
                    );
                    if (ok) {
                      await state.eraseConfig();
                    }
                  },
            icon: const Icon(Icons.delete_forever, size: 18),
            label: const Text('0x99 恢复默认配置（会重启）'),
          ),
        ],
      ),
    );
  }
}

/// 等宽十六进制输入框。
class _HexField extends StatelessWidget {
  const _HexField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.onChanged,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final VoidCallback onChanged;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(fontFamily: 'monospace'),
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-FxX\s,]')),
      ],
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: (_) => onChanged(),
    );
  }
}

/// 参数检查结果的提示行。不合规标红，但发送按钮仍可用。
class _CheckHint extends StatelessWidget {
  const _CheckHint({required this.check});

  final CommandCheck check;

  @override
  Widget build(BuildContext context) {
    final Color color = check.ok
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : Theme.of(context).colorScheme.error;
    final String text =
        check.ok ? (check.message.isEmpty ? '参数看起来没问题' : check.message) : check.message;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          check.ok ? Icons.check_circle_outline : Icons.error_outline,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 12, color: color)),
        ),
      ],
    );
  }
}

/// 解析失败返回 null（含空串）。
Uint8List? _tryParse(String text) {
  try {
    return parseHexPayload(text);
  } on FormatException {
    return null;
  }
}

/// 纯色测试：分别发全黑 / 全白 / 全红，用来排查平面极性问题。
///
/// 原来在「蓝牙诊断」页，挪到这里是因为它属于「真的会改屏幕内容」的调试指令。
class _SolidColorCard extends StatelessWidget {
  const _SolidColorCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: '纯色测试（查平面极性）',
      icon: Icons.palette_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final EpdColor color in <EpdColor>[
                rgbPalette[0],
                rgbPalette[1],
                rgbPalette[3],
              ])
                OutlinedButton(
                  onPressed: state.isConnected
                      ? () => state.sendSolidColor(color)
                      : null,
                  child: Text('全${color.name}'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '分别发一次全黑 / 全白 / 全红，屏幕应当整屏变成对应颜色：\n'
            '· 发全黑却出来红色 → 黑白平面与红白平面搞反了；\n'
            '· 发全红却出来白色（或反之）→ 红白平面极性相反；\n'
            '· 三个都对 → 数据链路没问题，问题在抖动后的图本身。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
