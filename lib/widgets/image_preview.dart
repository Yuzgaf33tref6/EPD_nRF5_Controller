import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../image/rgba_image.dart';
import '../state/app_state.dart';

/// 把 [RgbaImage] 转成 GPU 贴图（`ui.Image`）。
///
/// **为什么需要这一步**：直接遍历 12 万像素、画几千个矩形，每帧都要跑一遍，
/// 在低端机上是掉帧的主因。转成 `ui.Image` 之后，绘制阶段只剩一次 `drawImageRect`，
/// 由 GPU 完成缩放与合成，重绘开销从「毫秒级 × 每帧」降到「微秒级」。
///
/// 解码用 `ui.ImmutableBuffer` + `ui.ImageDescriptor.raw`，
/// 比 `decodeImageFromPixels`（已废弃）更快，也不引入第三方解码库。
Future<ui.Image> decodeRgbaToUiImage(RgbaImage image) async {
  final Uint8List data = image.data;
  final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(data);
  final ui.ImageDescriptor descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: image.width,
    height: image.height,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  final ui.Codec codec = await descriptor.instantiateCodec();
  try {
    final ui.FrameInfo frame = await codec.getNextFrame();
    return frame.image;
  } finally {
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
  }
}

/// 一张位图的绘制器：只负责把已经转好的 [ui.Image] 贴到画布上。
class RgbaUiImagePainter extends CustomPainter {
  RgbaUiImagePainter(this.image, {this.filterQuality = FilterQuality.none});

  final ui.Image? image;

  /// 墨水屏预览要保留硬边，默认不插值。
  final FilterQuality filterQuality;

  @override
  void paint(Canvas canvas, Size size) {
    final ui.Image? img = image;
    if (img == null) {
      return;
    }
    final Rect dst = Rect.fromLTWH(0, 0, size.width, size.height);
    final Rect src = Rect.fromLTWH(
      0,
      0,
      img.width.toDouble(),
      img.height.toDouble(),
    );
    canvas.drawImageRect(
      img,
      src,
      dst,
      Paint()
        ..isAntiAlias = false
        ..filterQuality = filterQuality,
    );
  }

  @override
  bool shouldRepaint(covariant RgbaUiImagePainter oldDelegate) {
    return !identical(oldDelegate.image, image) ||
        oldDelegate.filterQuality != filterQuality;
  }
}

/// 一张位图的展示组件：按图片宽高比铺满可用宽度。
///
/// 位图转贴图是**异步**的：转码期间显示上一帧（或空白），转完再 `setState`。
/// 这样即使图像很大、或者上层频繁重建，也不会阻塞界面线程。
class RgbaImagePreview extends StatefulWidget {
  const RgbaImagePreview({
    super.key,
    required this.image,
    this.version = 0,
    this.maxWidth = 360,
  });

  final RgbaImage image;

  /// 与 [image] 配套的版本号。
  ///
  /// 手绘时是**就地**改同一张 [RgbaImage]，对象身份不变，所以需要它来触发重新转码。
  final int version;

  final double maxWidth;

  @override
  State<RgbaImagePreview> createState() => _RgbaImagePreviewState();
}

class _RgbaImagePreviewState extends State<RgbaImagePreview> {
  ui.Image? _decoded;

  /// 最近一次提交过的输入，用来判断需要不需要重新转码。
  RgbaImage? _decodedSource;
  int _decodedVersion = -1;

  /// 转码是异步的，连续调用时以最后一次为准。
  int _decodeSerial = 0;

  @override
  void initState() {
    super.initState();
    _scheduleDecode();
  }

  @override
  void didUpdateWidget(covariant RgbaImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.image, widget.image) ||
        oldWidget.version != widget.version) {
      _scheduleDecode();
    }
  }

  @override
  void dispose() {
    _decodeSerial++;
    _decoded?.dispose();
    _decoded = null;
    super.dispose();
  }

  void _scheduleDecode() {
    final RgbaImage source = widget.image;
    final int version = widget.version;
    if (identical(_decodedSource, source) && _decodedVersion == version) {
      return;
    }
    _decodedSource = source;
    _decodedVersion = version;
    final int serial = ++_decodeSerial;
    // 关键：转码期间继续用旧贴图，界面不会闪白。
    unawaited(_decode(source, version, serial));
  }

  Future<void> _decode(RgbaImage source, int version, int serial) async {
    final ui.Image decoded;
    try {
      decoded = await decodeRgbaToUiImage(source);
    } catch (_) {
      // 转码失败就保持上一次的画面，不打断用户操作。
      return;
    }
    if (!mounted || serial != _decodeSerial) {
      decoded.dispose();
      return;
    }
    final ui.Image? previous = _decoded;
    setState(() {
      _decoded = decoded;
    });
    previous?.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.maxWidth),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: AspectRatio(
            aspectRatio: widget.image.width / math.max(1, widget.image.height),
            child: RepaintBoundary(
              child: CustomPaint(
                painter: RgbaUiImagePainter(_decoded),
                size: Size.infinite,
              ),
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
