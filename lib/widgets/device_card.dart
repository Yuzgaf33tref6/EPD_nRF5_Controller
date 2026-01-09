import 'package:flutter/material.dart';
import '../models/epd_device.dart';

class DeviceCard extends StatelessWidget {
  final EpdDevice device;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  const DeviceCard({
    super.key,
    required this.device,
    required this.onConnect,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.bluetooth,
                  color: device.isConnected ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'ID: ${device.id}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                if (device.rssi != null)
                  Row(
                    children: [
                      Icon(
                        Icons.signal_cellular_alt,
                        size: 16,
                        color: _getRssiColor(device.rssi!),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${device.rssi} dBm',
                        style: TextStyle(
                          fontSize: 12,
                          color: _getRssiColor(device.rssi!),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: Icon(
                      device.isConnected
                          ? Icons.bluetooth_disabled
                          : Icons.bluetooth_connected,
                    ),
                    label: Text(
                      device.isConnected ? '断开连接' : '连接',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: device.isConnected
                          ? Colors.red
                          : Theme.of(context).primaryColor,
                    ),
                    onPressed: device.isConnected ? onDisconnect : onConnect,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getRssiColor(int rssi) {
    if (rssi >= -50) return Colors.green;
    if (rssi >= -70) return Colors.orange;
    return Colors.red;
  }
}