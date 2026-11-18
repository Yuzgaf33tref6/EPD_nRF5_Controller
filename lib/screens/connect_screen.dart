import 'package:flutter/material.dart';

import '../devices/epd_driver.dart';
import '../services/ble_service.dart';
import '../state/app_state.dart';
import '../widgets/log_panel.dart';
import '../widgets/section_card.dart';

/// 连接页：扫描 → 连接 → 显示固件上报的配置。
class ConnectScreen extends StatelessWidget {
  const ConnectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState state = AppStateScope.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('设备连接')),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: <Widget>[
                SectionCard(
                  title: '扫描',
                  trailing: state.isScanning
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        '扫描使用系统 BLE（flutter_reactive_ble）。'
                        '连接后会自动读固件版本、订阅通知并发 INIT 命令，'
                        '固件随后上报引脚配置与 MTU/RLE 能力。',
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed:
                            state.isScanning ? null : () => state.scan(),
                        icon: const Icon(Icons.search),
                        label: Text(state.isScanning ? '扫描中 …' : '扫描附近设备'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  title: '发现的设备',
                  child: state.devices.isEmpty
                      ? const Text('还没有扫描结果')
                      : Column(
                          children: state.devices
                              .map((EpdBleDevice device) => _DeviceTile(
                                    device: device,
                                    state: state,
                                  ))
                              .toList(),
                        ),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  title: '驱动与引脚',
                  child: _DriverSection(state: state),
                ),
              ],
            ),
          ),
          const LogPanel(),
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device, required this.state});

  final EpdBleDevice device;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final bool isCurrent = state.connectedDevice?.id == device.id;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        isCurrent ? Icons.bluetooth_connected : Icons.bluetooth,
        color: isCurrent ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(device.name.isEmpty ? '(无广播名)' : device.name),
      subtitle: Text('${device.id} · ${device.rssi} dBm'),
      trailing: isCurrent
          ? TextButton(
              onPressed: () => state.disconnect(),
              child: const Text('断开'),
            )
          : TextButton(
              onPressed:
                  state.isConnecting ? null : () => state.connect(device),
              child: Text(state.isConnecting ? '连接中 …' : '连接'),
            ),
    );
  }
}

class _DriverSection extends StatelessWidget {
  const _DriverSection({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Text('驱动'),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButton<String>(
                isExpanded: true,
                value: state.driver.id,
                items: kEpdDrivers
                    .map(
                      (EpdDriver driver) => DropdownMenuItem<String>(
                        value: driver.id,
                        child: Text(
                          driver.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (String? id) {
                  if (id == null) {
                    return;
                  }
                  final EpdDriver? driver = driverById(id);
                  if (driver != null) {
                    state.setDriver(driver);
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '画布 ${state.canvasSize.width}×${state.canvasSize.height}'
          ' · 颜色 ${state.colorMode.jsName}'
          '${state.driver.usesUc8159 ? ' · UC8159 合并写入' : ''}',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        _InfoRow(label: '固件版本', value: state.firmwareVersionText),
        _InfoRow(label: '引脚', value: state.pinsText),
        _InfoRow(label: 'MTU', value: '${state.mtu}'),
        _InfoRow(label: 'RLE', value: state.rleSupported ? '支持' : '不支持'),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 72,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
