/// 应用全局状态：连接、驱动选择、抖动参数、日志。
///
/// 刻意不用第三方状态管理库（用户要求先不加依赖），用 Flutter 自带的
/// [ChangeNotifier] + [InheritedNotifier] 组合。UI 通过 [AppStateScope.of] 拿到状态，
/// 状态变化时自动重建。
///
/// 这一层把三方接通了：
/// 1. 纯 Dart 核心（对比度 → 抖动 → 位打包 → 传图编排）算出要发的每一个字节；
/// 2. [EpdBleService] 负责真链路的读写（测试注入 [FakeBleService]）；
/// 3. 通知解析复用 `lib/protocol/epd_protocol.dart` 里的 `parseConfigNotification` /
///    `parseTextNotification`，与 web 版逐字节一致。
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../devices/canvas_size.dart';
import '../devices/epd_driver.dart';
import '../image/canvas_editing.dart';
import '../image/crop_geometry.dart';
import '../image/dither.dart';
import '../image/epd_color.dart';
import '../image/rgba_image.dart';
import '../image/sample_image.dart';
import '../protocol/epd_protocol.dart';
import '../protocol/transfer.dart';
import '../services/ble_service.dart';
import '../services/image_pick_service.dart';
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
    EpdBleService? bleService,
    ImagePickService? imagePickService,
    Duration scanDelay = const Duration(milliseconds: 700),
    Duration connectDelay = const Duration(milliseconds: 450),
  })  : _scanDelay = scanDelay,
        _imagePick = imagePickService ?? GalleryImagePickService(),
        _ble = bleService ??
            FakeBleService(scanDelay: scanDelay, connectDelay: connectDelay) {
    _sourceImage =
        sampleImage(_driver.canvasSize.width, _driver.canvasSize.height);
    addLog(
      LogLevel.info,
      bleService == null
          ? '就绪：当前使用模拟蓝牙，可先熟悉界面与传图参数'
          : '就绪：已注入蓝牙实现',
    );
  }

  final EpdBleService _ble;
  final Duration _scanDelay;

  final ImagePickService _imagePick;

  /// 目标设备是 4.2 寸三色（驱动 0x03），所以默认选它而不是 web 版的第一项。
  static final EpdDriver _defaultDriver = driverById('03') ?? kEpdDrivers.first;

  // ---- 连接 ----
  bool _isScanning = false;
  bool _isConnecting = false;
  List<EpdBleDevice> _devices = const <EpdBleDevice>[];
  EpdBleDevice? _connected;
  int? _firmwareVersion;
  EpdConfig? _config;
  StreamSubscription<Uint8List>? _notificationSubscription;
  bool _sawConfigNotification = false;
  String _adapterStatusText = '未检查';
  int _writesSent = 0;
  final List<String> _notificationLog = <String>[];

  /// 通知日志上限。
  static const int _maxNotificationLog = 40;

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
  ImageTransferPlan? _planCache;
  Object? _planCacheKey;

  // ---- 外观与日志 ----
  ThemeMode _themeMode = ThemeMode.system;
  final List<LogEntry> _logs = <LogEntry>[];

  /// 日志上限，防止长时间使用后内存膨胀。
  static const int _maxLogs = 200;

  // ============ 只读访问 ============

  bool get isScanning => _isScanning;
  bool get isConnecting => _isConnecting;
  List<EpdBleDevice> get devices =>
      List<EpdBleDevice>.unmodifiable(_devices);
  EpdBleDevice? get connectedDevice => _connected;
  bool get isConnected => _connected != null;
  int? get firmwareVersion => _firmwareVersion;
  EpdConfig? get config => _config;
  int get mtu => _mtu;
  bool get rleSupported => _rleSupported;
  int get interleavedCount => _interleavedCount;

  /// 蓝牙子系统状态（诊断页用）。
  String get adapterStatusText => _adapterStatusText;

  /// 已成功写入的负载条数（诊断页用来确认链路真的通了）。
  int get writesSent => _writesSent;

  /// 最近收到的通知原文（诊断页用）。
  List<String> get notificationLog =>
      List<String>.unmodifiable(_notificationLog);

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
  ///
  /// 这条计算要跑位打包 + RLE 压缩，400×300 的图在千毫秒量级；而画布页一次
  /// build 会读好几次（统计行、警告列表、发送按钮），所以必须缓存 —— 否则单单
  /// 一次重绘就把主线程堵死，这正是之前"进页面就卡、拖滑块更卡"的根因。
  ImageTransferPlan get transferPlan {
    final RgbaImage image = previewImage;
    final Object key = Object.hash(image, _driver.id, canvasSize.name, colorMode,
        _mtu, _rleSupported, _interleavedCount);
    final ImageTransferPlan? cached = _planCache;
    if (cached != null && _planCacheKey == key) {
      return cached;
    }
    final ImageTransferPlan plan = planImageTransfer(
      image: image,
      driver: _driver,
      colorMode: colorMode,
      canvasSizeName: canvasSize.name,
      mtu: _mtu,
      rleSupported: _rleSupported,
      interleavedCount: _interleavedCount,
    );
    _planCache = plan;
    _planCacheKey = key;
    return plan;
  }

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
    addLog(LogLevel.info, '开始扫描附近设备 …');
    notifyListeners();
    try {
      _devices = await _ble.scan(timeout: _scanDelay + const Duration(seconds: 5));
      addLog(LogLevel.success, '扫描完成：发现 ${_devices.length} 台设备');
    } catch (error) {
      addLog(LogLevel.error, '扫描失败：$error');
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  /// 完整连接流程，顺序与 web 版 `connect()` 一致：
  /// 申请权限 → 建立连接 → 读固件版本 → 订阅通知 → 发 INIT（固件随后回配置/MTU 通知）。
  Future<void> connect(EpdBleDevice device) async {
    if (_isConnecting || isConnected) {
      return;
    }
    _isConnecting = true;
    notifyListeners();

    final BlePermissionResult permission = await _ble.ensurePermissions();
    addLog(
      permission.granted ? LogLevel.success : LogLevel.error,
      permission.message,
    );
    if (!permission.granted) {
      _isConnecting = false;
      notifyListeners();
      return;
    }

    addLog(LogLevel.info, '正在连接 ${device.name} …');
    notifyListeners();
    try {
      await _ble.connect(device.id);
    } catch (error) {
      addLog(LogLevel.error, '连接失败：$error');
      _isConnecting = false;
      notifyListeners();
      return;
    }

    _connected = device;
    _sawConfigNotification = false;
    _firmwareVersion = await _ble.readFirmwareVersion();
    _rleSupported =
        _firmwareVersion != null && _firmwareVersion! >= kMinRleFirmwareVersion;
    _notificationSubscription =
        _ble.notifications.listen(_handleNotification);

    addLog(LogLevel.success, '已连接 ${device.name}，固件版本 $firmwareVersionText');
    addLog(
      LogLevel.info,
      '已订阅命令特征通知，自动发送 INIT 命令 …',
    );
    await _writeSilently(<EpdWrite>[
      EpdWrite(payload: buildCommand(EpdCmd.init), withResponse: true),
    ]);
    _isConnecting = false;
    notifyListeners();
  }

  Future<void> disconnect() async {
    final EpdBleDevice? device = _connected;
    if (device == null) {
      return;
    }
    await _notificationSubscription?.cancel();
    _notificationSubscription = null;
    await _ble.disconnect();
    _connected = null;
    _firmwareVersion = null;
    _config = null;
    _rleSupported = false;
    _sawConfigNotification = false;
    addLog(LogLevel.warning, '已断开 ${device.name}');
    notifyListeners();
  }

  /// 处理固件通知：第一条按配置通知解析（7 引脚 + 驱动 id），其余按文本通知。
  ///
  /// 判定方式与 web 版一致：连接后的第一条通知就是配置通知。这里多一道保险 ——
  /// 如果第一条看起来是纯 ASCII 文本（`mtu=…`），就按文本处理，避免把乱序通知当配置。
  void _handleNotification(Uint8List value) {
    if (!_sawConfigNotification && !_looksLikeText(value) && value.length >= 8) {
      final EpdConfig config = parseConfigNotification(value);
      _sawConfigNotification = true;
      _config = config;
      _recordNotification(
        '配置通知：引脚 ${_hex(config.pins)}，驱动 0x'
        '${config.driver.toRadixString(16).toUpperCase().padLeft(2, '0')}',
      );
      final EpdDriver? byCode = driverByCode(config.driver);
      if (byCode != null && byCode.id != _driver.id) {
        _driver = byCode;
        _resampleSource();
        addLog(
          LogLevel.info,
          '按固件上报的驱动同步为 ${byCode.label}',
        );
      } else {
        addLog(LogLevel.info, '固件配置：引脚 $pinsText，驱动 id 0x'
            '${config.driver.toRadixString(16).toUpperCase().padLeft(2, '0')}');
      }
      notifyListeners();
      return;
    }

    final EpdTextNotification text = parseTextNotification(value);
    _recordNotification('文本通知：${text.text}');
    if (text.mtu != null) {
      setMtu(text.mtu!);
      addLog(LogLevel.info, '固件报告 MTU = ${text.mtu}');
    }
    if (text.rleSupported && !_rleSupported) {
      _rleSupported = true;
      addLog(LogLevel.success, '固件支持 RLE 压缩，已自动启用');
    }
    if (text.remoteUnixSeconds != null) {
      final DateTime remote = DateTime.fromMillisecondsSinceEpoch(
        text.remoteUnixSeconds! * 1000,
      );
      addLog(LogLevel.info, '设备时间：$remote');
    }
    if (text.mtu == null && !text.rleSupported && text.remoteUnixSeconds == null) {
      addLog(LogLevel.info, '设备消息：${text.text}');
    }
    notifyListeners();
  }

  void _recordNotification(String entry) {
    _notificationLog.add(entry);
    if (_notificationLog.length > _maxNotificationLog) {
      _notificationLog.removeRange(
        0,
        _notificationLog.length - _maxNotificationLog,
      );
    }
  }

  /// 刷新蓝牙子系统状态（诊断页用）。
  Future<void> refreshDiagnostics() async {
    _adapterStatusText = await _ble.describeAdapterStatus();
    addLog(LogLevel.info, '蓝牙状态：$_adapterStatusText');
    notifyListeners();
  }

  /// 主动申请一次运行权限（诊断页用）。
  Future<void> requestBlePermission() async {
    final BlePermissionResult result = await _ble.ensurePermissions();
    addLog(
      result.granted ? LogLevel.success : LogLevel.error,
      result.message,
    );
    _adapterStatusText = await _ble.describeAdapterStatus();
    notifyListeners();
  }

  /// 发一条 INIT 探测链路是否真的可写（诊断页用）。
  Future<void> sendDiagnosticInit() async {
    if (!_requireConnected('发送诊断命令')) {
      return;
    }
    await _writeSilently(<EpdWrite>[
      EpdWrite(payload: buildCommand(EpdCmd.init), withResponse: true),
    ]);
    addLog(LogLevel.success, '已发送 INIT（累计写入 $_writesSent 条）');
    notifyListeners();
  }

  // ============ 设备控制 ============

  Future<void> syncTime({required bool clockMode}) async {
    if (!_requireConnected('同步时间')) {
      return;
    }
    final DateTime now = DateTime.now();
    final List<EpdWrite> writes = planSyncTime(
      unixSeconds: now.millisecondsSinceEpoch ~/ 1000,
      utcOffsetHours: now.timeZoneOffset.inHours,
      mode: clockMode ? EpdTimeMode.clock : EpdTimeMode.calendar,
    );
    await _writeSilently(writes);
    addLog(
      LogLevel.success,
      '${clockMode ? '时钟' : '日历'}模式时间已下发：${_hex(writes.first.payload)}',
    );
    if (clockMode) {
      addLog(LogLevel.warning, '时钟模式是全屏刷新，会闪一下，只适合修正残影');
    }
    notifyListeners();
  }

  Future<void> clearScreen() => _sendSimple('清屏', planClearScreen());

  Future<void> refreshScreen() => _sendSimple('刷新', planRefresh());

  Future<void> sleepDevice() => _sendSimple('睡眠', planSleep());

  Future<void> _sendSimple(String label, List<EpdWrite> writes) async {
    if (!_requireConnected(label)) {
      return;
    }
    await _writeSilently(writes);
    addLog(LogLevel.success, '$label：${_hex(writes.first.payload)}');
    notifyListeners();
  }

  /// 把当前预览图真正发到设备：按 [transferPlan] 逐条写特征值。
  Future<void> sendPreview() async {
    if (!_requireConnected('发送图片')) {
      return;
    }
    final ImageTransferPlan plan = transferPlan;
    addLog(LogLevel.info, '开始发送：${plan.totalWrites} 条写指令，'
        '${plan.processedBytes} 字节');
    notifyListeners();

    int sent = 0;
    try {
      for (final EpdWrite write in plan.writes) {
        await _ble.write(write.payload, withResponse: write.withResponse);
        sent++;
        _writesSent++;
      }
    } catch (error) {
      addLog(
        LogLevel.error,
        '发送中断（已发 $sent/${plan.totalWrites} 条）：$error',
      );
      notifyListeners();
      return;
    }

    addLog(
      LogLevel.success,
      '发送完成：${plan.imageWrites} 条图像写指令'
      '${plan.usedRle ? '，已启用 RLE' : ''}',
    );
    notifyListeners();
  }

  /// 逐条写，不逐条打日志（避免一次传图刷几百条日志）。
  Future<void> _writeSilently(List<EpdWrite> writes) async {
    for (final EpdWrite write in writes) {
      await _ble.write(write.payload, withResponse: write.withResponse);
      _writesSent++;
    }
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
    _planCache = null;
    _planCacheKey = null;
  }

  // ============ 画布编辑 ============

  final ImageHistory _history = ImageHistory();

  bool get canUndo => _history.canUndo;

  bool get canRedo => _history.canRedo;

  /// 进入编辑会话：把当前底图作为撤销历史的起点。
  void beginEditing() {
    _history.reset(_sourceImage);
    notifyListeners();
  }

  /// 提交一次编辑结果（一笔、一段文字、一次填充）。
  void commitEdit(RgbaImage image) {
    _sourceImage = image;
    _history.push(image);
    _invalidatePreview();
    notifyListeners();
  }

  /// 撤销一步。
  void undoEdit() {
    final RgbaImage? image = _history.undo();
    if (image == null) {
      return;
    }
    _sourceImage = image;
    _invalidatePreview();
    notifyListeners();
  }

  /// 重做一步。
  void redoEdit() {
    final RgbaImage? image = _history.redo();
    if (image == null) {
      return;
    }
    _sourceImage = image;
    _invalidatePreview();
    notifyListeners();
  }

  /// 从相册选一张图（只负责选与解码，裁剪在 UI 层做）。取消返回 null。
  Future<RgbaImage?> pickImageFromGallery() async {
    final RgbaImage? image = await _imagePick.pickFromGallery();
    if (image == null) {
      addLog(LogLevel.info, '已取消选图');
      return null;
    }
    addLog(LogLevel.success, '已选择图片 ${image.width}×${image.height}');
    return image;
  }

  /// 直接换掉底图（导入图片用），并把历史重置到这张图。
  void replaceSource(RgbaImage image) {
    _sourceImage = image;
    _history.reset(image);
    _invalidatePreview();
    notifyListeners();
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

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    super.dispose();
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

  /// 判断一段通知是否看起来像可打印文本（固件文本通知都是 ASCII）。
  bool _looksLikeText(Uint8List value) {
    if (value.isEmpty) {
      return false;
    }
    for (final int byte in value) {
      if (byte < 0x20 || byte > 0x7E) {
        return false;
      }
    }
    return true;
  }
}
