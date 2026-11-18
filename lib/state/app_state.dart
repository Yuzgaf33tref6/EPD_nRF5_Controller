/// 应用全局状态：连接、驱动选择、抖动参数、日志。
///
/// 刻意不用第三方状态管理库（用户要求先不加依赖），用 Flutter 自带的
/// [ChangeNotifier] + [InheritedNotifier] 组合。UI 通过 [AppStateScope.of] 拿到状态，
/// 状态变化时自动重建。
///
/// 这一层已经把纯 Dart 核心接通了：画布预览会真的跑对比度 → 抖动 → 传图编排，
/// 所以界面上的「共 N 条写指令 / M 字节」是真算出来的，不是假数字。
library;

import 'package:flutter/material.dart';

import '../devices/canvas_size.dart';
import '../devices/epd_driver.dart';
import '../image/crop_geometry.dart';
import '../image/dither.dart';
import '../image/epd_color.dart';
import '../image/rgba_image.dart';
import '../image/sample_image.dart';
import '../protocol/epd_protocol.dart';
import '../protocol/transfer.dart';
import '../services/fake_ble_service.dart';

/// 日志级别，决定日志面板里的颜色。
enum LogLevel { info, success, warning, error }

/// 一条日志。
class LogEntry {
  LogEntry(this.level, this.message) : time = DateTime.now();

  final LogLevel level;
  final String message;
  final DateTime time;

  /// `HH:mm:ss`，不引 `intl` 包。
  String get timeText {
    String two(int v) => v < 10 ? '0$v' : '$v';
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }
}

/// 把 [AppState] 挂到 widget 树上，子 widget 用 [AppStateScope.of] 读取并订阅变化。
class AppStateScope extends InheritedNotifier<AppState> {
  const AppStateScope({
    Key? key,
    required AppState state,
    required Widget child,
  }) : super(key: key, notifier: state, child: child);

  static AppState of(BuildContext context) {
    final AppStateScope? scope =
        context.dependOnInheritedWidgetOfExactType<AppStateScope>();
    assert(scope != null, 'AppStateScope 没有挂到 widget 树上');
    return scope!.notifier!;
  }
}

/// 全局应用状态。
class AppState extends ChangeNotifier {
  AppState({
    Duration scanDelay = const Duration(milliseconds: 700),
    Duration connectDelay = const Duration(milliseconds: 450),
    Duration sendDelay = const Duration(milliseconds: 600),
  })  : _scanDelay = scanDelay,
        _connectDelay = connectDelay,
        _sendDelay = sendDelay {
    _sourceImage = sampleImage(_driver.canvasSize.width, _driver.canvasSize.height);
    addLog(LogLevel.info, '就绪：纯 Dart 核心已接通，蓝牙层尚未接入');
  }

  final FakeBleService _ble = FakeBleService();
  final Duration _scanDelay;
  final Duration _connectDelay;
  final Duration _sendDelay;

  /// 目标设备是 4.2 寸三色（驱动 0x03），所以默认选它而不是 web 版的第一项。
  static final EpdDriver _defaultDriver = driverById('03') ?? kEpdDrivers.first;

  // ---- 连接 ----
  bool _isScanning = false;
  List<FakeEpdDevice> _devices = const <FakeEpdDevice>[];
  FakeEpdDevice? _connected;
  int? _firmwareVersion;
  EpdConfig? _config;

  // ---- 传输参数 ----
  int _mtu = FakeBleService.mtu;
  bool _rleSupported = false;
  bool _interleavedCountOverride = false;
  int _interleavedCount = 50;

  // ---- 图像与驱动 ----
  EpdDriver _driver = _defaultDriver;
  late RgbaImage _sourceImage;
  DitherAlgorithm _algorithm = DitherAlgorithm.floydSteinberg;
  double _strength = 1.0;
  double _contrast = 1.2;

  RgbaImage? _previewCache;
  Object? _previewCacheKey;

  // ---- 外观与日志 ----
  ThemeMode _themeMode = ThemeMode.system;
  final List<LogEntry> _logs = <LogEntry>[];

  /// 日志上限，防止长时间使用后内存膨胀。
  static const int _maxLogs = 200;

  // ============ 只读访问 ============

  bool get isScanning => _isScanning;
  List<FakeEpdDevice> get devices => List<FakeEpdDevice>.unmodifiable(_devices);
  FakeEpdDevice? get connectedDevice => _connected;
  bool get isConnected => _connected != null;
  int? get firmwareVersion => _firmwareVersion;
  EpdConfig? get config => _config;
  int get mtu => _mtu;
  bool get rleSupported => _rleSupported;
  int get interleavedCount => _interleavedCount;

  EpdDriver get driver => _driver;
  EpdCanvasSize get canvasSize => _driver.canvasSize;
  EpdColorMode get colorMode => _driver.colorMode;
  RgbaImage get sourceImage => _sourceImage;
  DitherAlgorithm get algorithm => _algorithm;
  double get strength => _strength;
  double get contrast => _contrast;

  ThemeMode get themeMode => _themeMode;
  List<LogEntry> get logs => List<LogEntry>.unmodifiable(_logs);

  /// 固件版本展示用，例如 `0x1A`。
  String get firmwareVersionText {
    final int? version = _firmwareVersion;
    if (version == null) {
      return '未知';
    }
    return '0x${version.toRadixString(16).toUpperCase().padLeft(2, '0')}';
  }

  /// 引脚展示用，例如 `0A 0B 0C 0D 0E 0F 10`。
  String get pinsText {
    final EpdConfig? config = _config;
    if (config == null) {
      return '—';
    }
    return config.pins
        .map((int b) => b.toRadixString(16).toUpperCase().padLeft(2, '0'))
        .join(' ');
  }

  /// 抖动后的预览图。按参数做缓存，参数没变就不重算。
  RgbaImage get previewImage {
    final Object key = Object.hash(_sourceImage, _algorithm, _strength,
        _contrast, colorMode, _sourceImage.width, _sourceImage.height);
    final RgbaImage? cached = _previewCache;
    if (cached != null && _previewCacheKey == key) {
      return cached;
    }
    RgbaImage image = _sourceImage.clone();
    image = adjustContrast(image, _contrast);
    image = ditherImage(image, _algorithm, _strength, colorMode);
    _previewCache = image;
    _previewCacheKey = key;
    return image;
  }

  /// 当前参数下应发送的完整写指令序列（真算出来的）。
  ImageTransferPlan get transferPlan => planImageTransfer(
        image: previewImage,
        driver: _driver,
        colorMode: colorMode,
        canvasSizeName: canvasSize.name,
        mtu: _mtu,
        rleSupported: _rleSupported,
        interleavedCount: _interleavedCount,
      );

  /// 传图统计，一行文字。
  String get transferSummary {
    final ImageTransferPlan plan = transferPlan;
    final StringBuffer buffer = StringBuffer()
      ..write('${plan.totalWrites} 条写指令')
      ..write(' / ${plan.processedBytes} 字节')
      ..write(plan.usedRle ? '（RLE 压缩）' : '（未压缩）');
    if (plan.usedUc8159) {
      buffer.write(' / UC8159 合并');
    }
    return buffer.toString();
  }

  /// 参数与驱动不匹配时的提示（例如选了四色驱动却用三色模式）。
  List<String> get warnings {
    final List<String> result = <String>[];
    for (final TransferWarning warning in transferPlan.warnings) {
      switch (warning) {
        case TransferWarning.canvasSizeMismatch:
          result.add('画布尺寸与驱动不匹配：驱动是 ${_driver.canvasSizeName}，'
              '当前画布 ${canvasSize.name}');
        case TransferWarning.colorModeMismatch:
          result.add('颜色模式与驱动不匹配：驱动是 ${_driver.colorMode.jsName}，'
              '当前 ${colorMode.jsName}');
      }
    }
    return result;
  }

  // ============ 连接 ============

  Future<void> scan() async {
    if (_isScanning) {
      return;
    }
    _isScanning = true;
    addLog(LogLevel.info, '开始扫描（模拟数据，真实蓝牙尚未接入）');
    await Future<void>.delayed(_scanDelay);
    _devices = _ble.discover();
    _isScanning = false;
    addLog(LogLevel.success, '扫描完成：发现 ${_devices.length} 台设备');
    notifyListeners();
  }

  Future<void> connect(FakeEpdDevice device) async {
    addLog(LogLevel.info, '正在连接 ${device.name} …');
    notifyListeners();
    await Future<void>.delayed(_connectDelay);

    _connected = device;
    _firmwareVersion = FakeBleService.firmwareVersion;
    _config = _ble.configFor(device, driverCode: _driver.code);
    _rleSupported = _firmwareVersion! >= kMinRleFirmwareVersion;

    addLog(LogLevel.success, '已连接 ${device.name}');
    addLog(LogLevel.info, '固件版本 $firmwareVersionText，'
        '驱动 id 0x${_driver.id.toUpperCase()}，引脚 $pinsText');
    addLog(
      LogLevel.info,
      '固件通知：${_ble.textNotification(mtuValue: _mtu, rle: _rleSupported)}',
    );
    notifyListeners();
  }

  void disconnect() {
    if (_connected == null) {
      return;
    }
    final String name = _connected!.name;
    _connected = null;
    _firmwareVersion = null;
    _config = null;
    _rleSupported = false;
    addLog(LogLevel.warning, '已断开 $name');
    notifyListeners();
  }

  // ============ 设备控制 ============

  void syncTime({required bool clockMode}) {
    if (!_requireConnected('同步时间')) {
      return;
    }
    final DateTime now = DateTime.now();
    final List<EpdWrite> writes = planSyncTime(
      unixSeconds: now.millisecondsSinceEpoch ~/ 1000,
      utcOffsetHours: now.timeZoneOffset.inHours,
      mode: clockMode ? EpdTimeMode.clock : EpdTimeMode.calendar,
    );
    addLog(
      LogLevel.success,
      '${clockMode ? '时钟' : '日历'}模式时间已下发：${_hex(writes.first.payload)}',
    );
    if (clockMode) {
      addLog(LogLevel.warning, '时钟模式是全屏刷新，会闪一下，只适合修正残影');
    }
    notifyListeners();
  }

  void clearScreen() => _sendSimple('清屏', planClearScreen());

  void refreshScreen() => _sendSimple('刷新', planRefresh());

  void sleepDevice() => _sendSimple('睡眠', planSleep());

  void _sendSimple(String label, List<EpdWrite> writes) {
    if (!_requireConnected(label)) {
      return;
    }
    addLog(LogLevel.success, '$label：${_hex(writes.first.payload)}');
    notifyListeners();
  }

  /// 模拟把预览图发到设备。
  ///
  /// 真机上这里要按 [transferPlan] 逐条写特征值；现在只把统计打进日志。
  Future<void> sendPreview() async {
    if (!_requireConnected('发送图片')) {
      return;
    }
    final ImageTransferPlan plan = transferPlan;
    addLog(LogLevel.info, '开始发送：${plan.totalWrites} 条写指令，'
        '${plan.processedBytes} 字节');
    notifyListeners();
    await Future<void>.delayed(_sendDelay);
    addLog(
      LogLevel.success,
      '发送完成（模拟）：${plan.imageWrites} 条图像写指令'
      '${plan.usedRle ? '，已启用 RLE' : ''}',
    );
    notifyListeners();
  }

  // ============ 图像与参数 ============

  void setDriver(EpdDriver driver) {
    if (driver.id == _driver.id) {
      return;
    }
    _driver = driver;
    _resampleSource();
    addLog(
      LogLevel.info,
      '驱动切换为 ${driver.label}（${driver.canvasSize.width}×'
      '${driver.canvasSize.height}，${driver.colorMode.jsName}）',
    );
    notifyListeners();
  }

  void setAlgorithm(DitherAlgorithm algorithm) {
    if (algorithm == _algorithm) {
      return;
    }
    _algorithm = algorithm;
    notifyListeners();
  }

  void setStrength(double value) {
    if (value == _strength) {
      return;
    }
    _strength = value;
    notifyListeners();
  }

  void setContrast(double value) {
    if (value == _contrast) {
      return;
    }
    _contrast = value;
    notifyListeners();
  }

  void setMtu(int value) {
    final int clamped = value < 20 ? 20 : (value > 247 ? 247 : value);
    if (clamped == _mtu) {
      return;
    }
    _mtu = clamped;
    notifyListeners();
  }

  void setInterleavedCount(int value) {
    final int clamped = value < 1 ? 1 : (value > 100 ? 100 : value);
    _interleavedCountOverride = true;
    if (clamped == _interleavedCount) {
      return;
    }
    _interleavedCount = clamped;
    notifyListeners();
  }

  bool get interleavedCountOverridden => _interleavedCountOverride;

  void setRleSupported(bool value) {
    if (value == _rleSupported) {
      return;
    }
    _rleSupported = value;
    addLog(LogLevel.info, value ? '已假定固件支持 RLE' : '已关闭 RLE');
    notifyListeners();
  }

  /// 旋转画布 90°（宽高互换，与 web 版 `rotateCanvas` 一致）。
  void rotateSource() {
    _sourceImage = rotateImage90Clockwise(_sourceImage);
    _invalidatePreview();
    addLog(LogLevel.info, '画布已旋转：${_sourceImage.width}×${_sourceImage.height}');
    notifyListeners();
  }

  /// 按当前驱动的画布尺寸重新生成示例图。
  void resetSource() {
    _resampleSource();
    addLog(LogLevel.info, '已按画布尺寸重置示例图');
    notifyListeners();
  }

  bool get aspectMatchesCanvas => imageMatchesCanvasAspect(
        imageWidth: _sourceImage.width,
        imageHeight: _sourceImage.height,
        canvasWidth: canvasSize.width,
        canvasHeight: canvasSize.height,
      );

  void _resampleSource() {
    _sourceImage = sampleImage(canvasSize.width, canvasSize.height);
    _invalidatePreview();
  }

  void _invalidatePreview() {
    _previewCache = null;
    _previewCacheKey = null;
  }

  // ============ 外观与日志 ============

  void setThemeMode(ThemeMode mode) {
    if (mode == _themeMode) {
      return;
    }
    _themeMode = mode;
    notifyListeners();
  }

  void addLog(LogLevel level, String message) {
    _logs.add(LogEntry(level, message));
    if (_logs.length > _maxLogs) {
      _logs.removeRange(0, _logs.length - _maxLogs);
    }
    notifyListeners();
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  // ============ 内部 ============

  bool _requireConnected(String action) {
    if (_connected != null) {
      return true;
    }
    addLog(LogLevel.warning, '未连接设备，无法$action');
    return false;
  }

  String _hex(List<int> bytes) {
    return bytes
        .map((int b) => b.toRadixString(16).toUpperCase().padLeft(2, '0'))
        .join(' ');
  }
}
