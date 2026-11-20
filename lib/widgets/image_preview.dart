import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../image/rgba_image.dart';
import '../state/app_state.dart';

/// 一张 RGBA 位图的绘制器。
///
/// 直接把 12 万像素逐点画会慢到掉帧，所以按「同一行里连续相同颜色」合并成矩形，
/// 一张墨水屏图通常几千个矩形就够，重绘开销可以接受。
class RgbaImagePainter extends CustomPainter {
  RgbaImagePainter(this.image, {this.version = 0});

  final RgbaImage image;

  /// 外部版本号。手绘时是**就地**改同一张图，[shouldRepaint] 靠它判断要不要重画。
  final int version;

  final Map<int, Color> _colorCache = <int, Color>{};

  @override
  void paint(Canvas canvas, Size size) {
    final int width = image.width;
    final int height = image.height;
    if (width == 0 || height == 0) {
      return;
    }
    final double scaleX = size.width / width;
    final double scaleY = size.height / height;
    final Paint paint = Paint()..isAntiAlias = false;
    final Uint8List data = image.data;

    for (int y = 0; y < height; y++) {
      int x = 0;
      while (x < width) {
        final int offset = (y * width + x) * 4;
        final int r = data[offset];
        final int g = data[offset + 1];
        final int b = data[offset + 2];
        final int key = (r << 16) | (g << 8) | b;
        int runEnd = x + 1;
        while (runEnd < width) {
          final int o2 = (y * width + runEnd) * 4;
          if (data[o2] != r || data[o2 + 1] != g || data[o2 + 2] != b) {
            break;
          }
          runEnd++;
        }
        paint.color = _colorCache[key] ??=
            Color.fromARGB(255, r, g, b);
        canvas.drawRect(
          Rect.fromLTWH(
            x * scaleX,
            y * scaleY,
            (runEnd - x) * scaleX + 0.5,
            scaleY + 0.5,
          ),
          paint,
        );
        x = runEnd;
      }
    }
  }

  @override
  bool shouldRepaint(covariant RgbaImagePainter oldDelegate) {
    return oldDelegate.version != version ||
        !identical(oldDelegate.image, image);
  }
}

/// 一张位图的展示组件：按图片宽高比铺满可用宽度。
class RgbaImagePreview extends StatelessWidget {
  const RgbaImagePreview({
    super.key,
    required this.image,
    this.version = 0,
    this.maxWidth = 360,
  });

  final RgbaImage image;

  /// 与 [RgbaImagePainter.version] 配套使用。
  final int version;

  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: AspectRatio(
            aspectRatio: image.width / math.max(1, image.height),
            child: CustomPaint(
              painter: RgbaImagePainter(image, version: version),
              size: Size.infinite,
            ),
          ),
        ),
      ),
    );
  }
}

/// 墨水屏状态栏：展示设备名 + 最近一次操作的结果，作为「日志藏起来」后的替代反馈。
class DeviceStatusBar extends StatelessWidget {
  const DeviceStatusBar({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final LogEntry? latest = state.latestLog;
    final bool connected = state.isConnected;
    final Color color = latest == null
        ? theme.colorScheme.onSurfaceVariant
        : switch (latest.level) {
            LogLevel.success => theme.colorScheme.primary,
            LogLevel.warning => Colors.orange.shade800,
            LogLevel.error => theme.colorScheme.error,
            LogLevel.info => theme.colorScheme.onSurfaceVariant,
          };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            connected
                ? Icons.bluetooth_connected
                : Icons.bluetooth_disabled,
            size: 15,
            color: connected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline,
          ),
          const SizedBox(width: 6),
          Text(
            connected
                ? (state.connectedDevice?.name ?? '已连接')
                : '未连接',
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(width: 10),
          Container(
            width: 1,
            height: 12,
            color: theme.colorScheme.outlineVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              latest?.message ?? '就绪',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
