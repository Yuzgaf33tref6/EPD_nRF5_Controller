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
import 'package:permission_handler/permission_handler.dart';

import '../devices/canvas_size.dart';
import '../devices/epd_driver.dart';
import '../image/canvas_editing.dart';
import '../image/crop_geometry.dart';
import '../image/dither.dart';
import '../image/epd_color.dart';
import '../image/noise_mask.dart' as noise;
import '../image/preview_computer.dart';
import '../image/process.dart';
import '../image/rgba_image.dart';
import '../image/sample_image.dart';
import '../models/transfer_speed.dart';
import '../protocol/debug_commands.dart';
import '../protocol/epd_protocol.dart';
import '../protocol/transfer.dart';
import '../services/ble_service.dart';
import '../services/image_pick_service.dart';
import '../services/fake_ble_service.dart';
import '../services/settings_store.dart';

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

  /// 取状态但不建立依赖（用于首帧回调里的一次性读取，避免多余重建）。
  static AppState? maybeOf(BuildContext context) {
    return context
        .getInheritedWidgetOfExactType<AppStateScope>()
        ?.notifier;
  }
}

/// 全局应用状态。
class AppState extends ChangeNotifier {
  AppState({
    EpdBleService? bleService,
    ImagePickService? imagePickService,
    SettingsStore? settingsStore,
    Duration scanDelay = const Duration(milliseconds: 700),
    Duration connectDelay = const Duration(milliseconds: 450),
    bool autoReconnect = true,
  })  : _scanDelay = scanDelay,
        _autoReconnect = autoReconnect,
        _imagePick = imagePickService ?? GalleryImagePickService(),
        _settings = settingsStore ?? MemorySettingsStore(),
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
    unawaited(_restoreSettings());
  }

  final EpdBleService _ble;
  final Duration _scanDelay;

  /// 设置持久化（默认内存实现，真机由 main.dart 注入文件实现）。
  final SettingsStore _settings;

  /// 保存设置时用的版本号，将来改结构时可以据此迁移。
  static const int kSettingsVersion = 1;

  bool _disposed = false;

  /// 意外断开后是否自动重连（默认真机开启，测试里关掉以保证确定性）。
  final bool _autoReconnect;
  bool _reconnecting = false;

  final ImagePickService _imagePick;

  /// 目标设备是 4.2 寸三色（驱动 0x03），所以默认选它而不是 web 版的第一项。
  static final EpdDriver _defaultDriver = driverById('03') ?? kEpdDrivers.first;

  // ---- 连接 ----
  bool _isScanning = false;
  bool _isConnecting = false;
  List<EpdBleDevice> _devices = const <EpdBleDevice>[];
  EpdBleDevice? _connected;
  int? _firmwareVersion;

  /// 连接后实时读到的信号强度（dBm）。扫描时的值是连上那一刻的旧值。
  int? _liveRssi;
  bool _readingRssi = false;
  EpdConfig? _config;
  StreamSubscription<Uint8List>? _notificationSubscription;
  StreamSubscription<bool>? _connectionChangeSubscription;
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

  /// 连接后主动请求的 ATT MTU。默认 23 每次只能写 20 字节，一次传图要上千条
  /// 写指令，在 nRF51 上既慢又会把蓝牙缓冲撑爆（GATT 133 后系统直接拆连接）。
  static const int _targetMtu = 247;

  /// 分块档位：稳定 18 / 正常 64 / 快速 128 / 最大吃满 / 自定义。
  ///
  /// 默认用「最大」：真机验证 242 字节（MTU 247 下的理论上限）稳定可传，
  /// 400×300 三色从 1600 多条写降到 130 条左右，明显快。
  TransferSpeed _speed = TransferSpeed.max;

  /// 自定义档每块的字节数（只在 [TransferSpeed.custom] 下生效）。
  int _customChunkBytes = 128;

  /// 排查开关：调换黑白/红白两个显存平面。
  bool _swapPlanes = false;

  /// 排查开关：红白平面整体取反。
  bool _invertRedPlane = false;

  /// 单条图像写指令最多带多少字节有效负载。见 [writeChunkBytes] 的说明。
  static const int kMaxChunkDataBytes = 180;

  /// 两条写指令之间的最小间隔，给外设留出把数据吞下去的时间。
  static const Duration kInterChunkDelay = Duration(milliseconds: 12);

  /// 单条写指令的超时：超过这个时间没有任何应答就认为链路已经废了。
  ///
  /// Android 自己会在 30 秒后抛 GATT 133 并拆掉连接 —— 那太晚了，等待期间界面
  /// 完全没反馈。8 秒足够覆盖最慢的一次写（实测约 90ms），又不至于让人干等。
  static const Duration kWriteTimeout = Duration(seconds: 8);

  /// 是否往 logcat 打印每条写指令（设置页开关，会被持久化）。
  ///
  /// 默认关闭：逐条打印一次传图会刷上百行，日常使用没必要。排查问题时在
  /// 设置 → 诊断 里打开即可。
  bool _verboseTransfers = false;

  // ---- 驱动选择与连接记忆 ----
  /// 驱动选择方式：自动（按固件上报匹配）/ 手动（用户指定，忽略固件）。
  DriverSelectionMode _driverMode = DriverSelectionMode.auto;

  /// 上次成功连接的设备 id，用于首页「连接 / 重连」快捷按钮。
  String? _lastDeviceId;

  /// 上次成功连接的设备名（仅用于界面展示）。
  String? _lastDeviceName;

  // ---- 驱动可能错误提示 ----
  /// 本次启动内是否已经提示过「驱动可能错误」。
  bool _driverWarningShownThisSession = false;

  /// 用户勾选了「不再提示」（持久化）。
  bool _driverWarningMuted = false;

  // ---- 权限 ----
  /// 启动后是否已经做过权限检查（避免每次重建首页都弹系统对话框）。
  bool _permissionChecked = false;

  /// 最近一次权限申请的结果；null 表示还未知。
  bool? _permissionGranted;

  // ---- 图像与驱动 ----
  EpdDriver _driver = _defaultDriver;
  late RgbaImage _sourceImage;
  DitherAlgorithm _algorithm = DitherAlgorithm.floydSteinberg;
  double _strength = 1.0;
  double _contrast = 1.2;

  /// 误差扩散是否走蛇形扫描（奇数行反向），能打散斜向纹路。
  bool _serpentine = false;

  /// 蓝噪声阈值表（64×64）。由 `loadNoiseMask()` 从 assets 解码后缓存。
  Uint8List? _noiseMask;
  bool _noiseMaskLoading = false;

  // ---- 处理阶段（原图 → 处理 → 抖动）----
  bool _autoBrightness = true;
  double _brightness = 0;
  bool _simplifyColors = false;
  int _simplifyColorCount = 8;

  RgbaImage? _previewCache;
  Object? _previewCacheKey;
  RgbaImage? _processedCache;
  Object? _processedCacheKey;
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

  /// 传给 `planWriteImage` 的 mtu 参数：它内部按 `mtu - 2` 分块，块内再加上
  /// 命令字与 flag 两个字节，所以这个参数就是「一条 ATT 写请求的总字节数上限」。
  ///
  /// ATT 写请求最多只能带 `ATT_MTU - 3` 字节（1 字节 opcode + 2 字节 handle）。
  /// 一旦超过这个长度，Android 的 BLE 栈会自动改用「长写」（Prepare Write + Execute
  /// Write）把它拆成多个 ATT 包；而固件的写回调是按「整包就是一条命令」实现的，
  /// 会把拆出来的碎片当成独立命令处理 —— 于是 RLE 流被切断、固件卡住不应答，
  /// 30 秒后 Android 以 GATT 133 拆掉连接（用户看到的就是「连接莫名其妙断开」）。
  /// 因此这里必须严格用 `ATT_MTU - 3`，多一个字节都不行。
  int get writeMtu => _mtu > 3 ? _mtu - 3 : 20;

  /// 每块最多写多少字节有效负载（展示用）：总上限再减去命令字与 flag。
  ///
  /// 上限由 [speed] 决定：稳定 18 / 正常 64 / 快速 128 / 最大吃满（`MTU-3-2`）/
  /// 自定义按用户填的字节数。真机验证过 242（MTU 247 的理论上限）也能稳定传完，
  /// 所以档位现在只影响速度，不再是稳定性保险。
  int get writeChunkBytes {
    final int byMtu = writeMtu - 2;
    if (_speed.isCustom) {
      final int custom = _customChunkBytes;
      return custom > byMtu ? byMtu : (custom < 8 ? 8 : custom);
    }
    if (_speed.isMax) {
      return byMtu;
    }
    final int preset = _speed.presetChunkBytes;
    return preset > byMtu ? byMtu : preset;
  }

  /// 传给 `planWriteImage` 的实测值：每块数据 + 命令字 + flag。
  int get planMtu => writeChunkBytes + 2;

  /// 是否把每条写指令打到 logcat。
  bool get verboseTransfers => _verboseTransfers;

  /// 切换详细传输日志。
  void setVerboseTransfers(bool value) {
    if (value == _verboseTransfers) {
      return;
    }
    _verboseTransfers = value;
    addLog(LogLevel.info, value ? '已开启详细传输日志（logcat 可见每条报文）' : '已关闭详细传输日志');
    _persistSettings();
    notifyListeners();
  }

  /// 蓝牙子系统状态（诊断页用）。
  String get adapterStatusText => _adapterStatusText;

  /// 已成功写入的负载条数（诊断页用来确认链路真的通了）。
  int get writesSent => _writesSent;

  /// 连接后实时读到的信号强度（dBm）。还没读过时退回扫描时的值。
  int? get liveRssi => _liveRssi ?? _connected?.rssi;

  /// 是否正在读信号强度（按钮转圈用）。
  bool get isReadingRssi => _readingRssi;

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

  /// 处理阶段的参数。
  ProcessSettings get process => ProcessSettings(
        autoBrightness: _autoBrightness,
        brightness: _brightness,
        simplifyColors: _simplifyColors,
        simplifyColorCount: _simplifyColorCount,
      );

  bool get autoBrightness => _autoBrightness;
  double get brightness => _brightness;
  bool get simplifyColors => _simplifyColors;
  int get simplifyColorCount => _simplifyColorCount;

  /// 处理阶段的短描述，给界面显示用。
  String get processSummary => describeProcess(process);

  /// 驱动选择方式。
  DriverSelectionMode get driverMode => _driverMode;

  /// 上次连接的设备 id（没有记录时为 null）。
  String? get lastDeviceId => _lastDeviceId;

  /// 上次连接的设备名（没有记录时为 null）。
  String? get lastDeviceName => _lastDeviceName;

  /// 是否有可用的「上次设备」记录（首页连接/重连按钮据此决定可用性）。
  bool get hasLastDevice => _lastDeviceId != null;

  /// 是否收到了固件的配置通知（引脚 + 驱动 id）。
  bool get hasConfig => _config != null;

  /// 是否需要提示「驱动可能错误」。
  ///
  /// 规则：已连接、没有收到配置通知、用户没勾「不再提示」、本次启动还没提示过。
  /// 收到配置就说明驱动是固件自己报的，没有猜错的可能。
  bool get shouldWarnDriverMismatch =>
      isConnected &&
      _config == null &&
      !_driverWarningMuted &&
      !_driverWarningShownThisSession;

  /// 标记「驱动可能错误」已提示（本次启动内不再重复弹）。
  void markDriverWarningShown() {
    if (_driverWarningShownThisSession) {
      return;
    }
    _driverWarningShownThisSession = true;
    notifyListeners();
  }

  /// 设置「不再提示驱动可能错误」。
  void setDriverWarningMuted(bool value) {
    if (value == _driverWarningMuted) {
      return;
    }
    _driverWarningMuted = value;
    addLog(
      LogLevel.info,
      value ? '已关闭「驱动可能错误」提示' : '已重新开启「驱动可能错误」提示',
    );
    _persistSettings();
    notifyListeners();
  }

  /// 用户勾选过「不再提示驱动可能错误」。
  bool get driverWarningMuted => _driverWarningMuted;

  ThemeMode get themeMode => _themeMode;
  List<LogEntry> get logs => List<LogEntry>.unmodifiable(_logs);

  /// 最新一条日志（底部状态条用），没有日志时为 null。
  LogEntry? get latestLog => _logs.isEmpty ? null : _logs.last;

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

  /// 只经过「处理」阶段、还没抖动的图。界面的「处理」预览档用它。
  ///
  /// 同步版本，参数没变时有缓存；界面上仍建议走后台 isolate。
  RgbaImage get processedImage {
    final Object key =
        Object.hash(_sourceImage, process.key, _sourceImage.width, _sourceImage.height);
    final RgbaImage? cached = _processedCache;
    if (cached != null && _processedCacheKey == key) {
      return cached;
    }
    final RgbaImage image = processImage(_sourceImage, process);
    _processedCache = image;
    _processedCacheKey = key;
    return image;
  }

  /// 抖动后的预览图（= 处理 + 对比度 + 抖动）。按参数做缓存，参数没变就不重算。
  ///
  /// **注意**：这是**同步**版本，会占用当前线程算完（400×300 约几十毫秒）。
  /// 界面上的实时预览请用 `previewComputer`（后台 isolate）算出来的结果，
  /// 只有「发送」这种本来就该等的地方才调这里。
  RgbaImage get previewImage {
    final Object key = Object.hash(_sourceImage, _algorithm, _strength,
        _contrast, colorMode, process.key, _sourceImage.width, _sourceImage.height,
        _serpentine, identityHashCode(_noiseMask));
    final RgbaImage? cached = _previewCache;
    if (cached != null && _previewCacheKey == key) {
      return cached;
    }
    RgbaImage image = processImage(_sourceImage, process);
    image = adjustContrast(image, _contrast);
    image = ditherImage(
      image,
      _algorithm,
      _strength,
      colorMode,
      serpentine: _serpentine,
      noiseMask: _noiseMask,
    );
    _previewCache = image;
    _previewCacheKey = key;
    return image;
  }

  /// 当前抖动/处理用参数。界面把它交给 [PreviewComputer] 去后台算，避免卡顿。
  ///
  /// [stage] 决定算到哪一步：原图 / 只处理 / 处理+抖动。
  DitherJob previewJob(PreviewStage stage) => DitherJob(
        width: _sourceImage.width,
        height: _sourceImage.height,
        rgba: _sourceImage.data,
        algorithm: _algorithm,
        strength: _strength,
        contrast: _contrast,
        mode: colorMode,
        process: process,
        stage: stage,
        serpentine: _serpentine,
        noiseMask: _noiseMask,
      );

  /// 抖动阶段的完整参数（默认按「抖动」档算）。
  DitherJob get currentDitherJob => previewJob(PreviewStage.dithered);

  /// 当前参数下应发送的完整写指令序列（真算出来的）。
  ///
  /// 这条计算要跑位打包 + RLE 压缩，400×300 的图在千毫秒量级；而画布页一次
  /// build 会读好几次（统计行、警告列表、发送按钮），所以必须缓存 —— 否则单单
  /// 一次重绘就把主线程堵死，这正是之前"进页面就卡、拖滑块更卡"的根因。
  ImageTransferPlan get transferPlan {
    final RgbaImage image = previewImage;
    final Object key = Object.hash(image, _driver.id, canvasSize.name, colorMode,
        _mtu, _rleSupported, _interleavedCount, _speed, _swapPlanes,
        _invertRedPlane);
    final ImageTransferPlan? cached = _planCache;
    if (cached != null && _planCacheKey == key) {
      return cached;
    }
    final ImageTransferPlan plan = planImageTransfer(
      image: image,
      driver: _driver,
      colorMode: colorMode,
      canvasSizeName: canvasSize.name,
      mtu: planMtu,
      rleSupported: _rleSupported,
      interleavedCount: _interleavedCount,
      // 真机上必须一条一条等确认：连续几十条无响应写会撑爆蓝牙缓冲，
      // Android 回 GATT 133 并直接拆连接（这就是「命令发不完 + 假连接」的根因）。
      alwaysWithResponse: true,
      swapPlanes: _swapPlanes,
      invertRedPlane: _invertRedPlane,
    );
    _planCache = plan;
    _planCacheKey = key;
    return plan;
  }

  /// 排查开关：把黑白平面与红白平面调换（有些面板把两片显存的含义弄反了）。
  bool get swapPlanes => _swapPlanes;

  void setSwapPlanes(bool value) {
    if (_swapPlanes == value) {
      return;
    }
    _swapPlanes = value;
    addLog(LogLevel.info, '平面调换：${value ? '已开启' : '已关闭'}');
    _invalidatePreview();
    notifyListeners();
  }

  /// 排查开关：把红白平面整体取反（有些面板 0 表示红、1 表示白，与 web 版相反）。
  bool get invertRedPlane => _invertRedPlane;

  void setInvertRedPlane(bool value) {
    if (_invertRedPlane == value) {
      return;
    }
    _invertRedPlane = value;
    addLog(LogLevel.info, '红平面取反：${value ? '已开启' : '已关闭'}');
    _invalidatePreview();
    notifyListeners();
  }

  /// 传图统计，一行文字。
  String get transferSummary {
    final ImageTransferPlan plan = transferPlan;
    final StringBuffer buffer = StringBuffer()
      ..write('${plan.totalWrites} 条写指令')
      ..write(' / ${plan.processedBytes} 字节')
      ..write(plan.usedRle ? '（RLE 压缩）' : '（未压缩）')
      ..write(' / 每块 $writeChunkBytes 字节');
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
      // 扫描前必须先拿到运行时权限：Android 12+ 没授「附近设备」权限时，
      // 系统不会报错，只会静默扫不到任何设备。
      final BlePermissionResult permission = await _ble.ensurePermissions();
      if (!permission.granted) {
        addLog(LogLevel.error, '扫描需要蓝牙权限：${permission.message}');
        return;
      }
      final String adapterStatus = await _ble.describeAdapterStatus();
      _adapterStatusText = adapterStatus;
      addLog(LogLevel.info, '蓝牙状态：$adapterStatus');
      if (adapterStatus != '蓝牙可用') {
        addLog(LogLevel.warning, '蓝牙状态不理想，扫描可能扫不到设备');
      }
      _devices = await _ble.scan(
        timeout: _scanDelay + const Duration(seconds: 5),
      );
      if (_devices.isEmpty) {
        addLog(
          LogLevel.warning,
          '没有扫到设备：确认墨水屏已开机（按一下唤醒）、没连着别的手机，'
          '并已允许「附近的设备」权限；部分机型还需要打开定位。',
        );
      } else {
        addLog(LogLevel.success, '扫描完成：发现 ${_devices.length} 台设备');
      }
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

    // 通知监听要抢在一切 await 之前挂上：固件往往在连接成功的瞬间就推一条
    // 「配置通知」（7 字节引脚 + 驱动 id），如果先去协商 MTU / 读版本再订阅，
    // 这条通知就丢了 —— 表现是驱动号一直停在默认值、引脚也不对。
    _rleSupported = false;
    await _notificationSubscription?.cancel();
    _notificationSubscription =
        _ble.notifications.listen(_handleNotification);

    // 先协商 MTU 再传图：默认 ATT MTU 只有 23（每次写 20 字节），400×300 三色
    // 一次要发上千条，既慢又容易让 nRF51 的蓝牙缓冲溢出。
    int negotiatedMtu = _mtu;
    try {
      negotiatedMtu = await _ble.requestMtu(_targetMtu);
    } catch (error) {
      addLog(LogLevel.warning, 'MTU 协商失败：$error（继续用 $_mtu）');
    }
    if (negotiatedMtu >= 23) {
      _mtu = negotiatedMtu > 517 ? 517 : negotiatedMtu;
    }
    addLog(
      LogLevel.info,
      'MTU 协商结果：$_mtu（每条最多写 $writeChunkBytes 字节有效负载）',
    );

    _firmwareVersion = await _ble.readFirmwareVersion();
    // 新链路读到的第一个实测信号强度（读到之前界面显示扫描时的旧值）。
    _liveRssi = await _ble.readRssi();
    // RLE 只认固件在通知里明确说的 `rle=1`（web 版就是这么判的，见
    // `html/js/main.js:404`）。以前这里按版本号猜「>= 0x16 就支持 RLE」，
    // 结果在 0x19 的固件上打开了 RLE，而该固件并不支持 —— 屏幕刷出来
    // 全是乱块（每行的空白被当成 run code 吞掉）。默认关，等通知再说。

    // 监听意外断开：设备被写爆 / 走远 / 面板忙都会让系统静默拆连接，
    // 不监听的话界面会一直显示「已连接」，实际已经发不出去了。
    await _connectionChangeSubscription?.cancel();
    _connectionChangeSubscription = _ble.connectionChanges.listen(
      (bool stillConnected) {
        if (stillConnected) {
          return;
        }
        _handleUnexpectedDisconnect();
      },
    );

    addLog(LogLevel.success, '已连接 ${device.name}，固件版本 $firmwareVersionText');
    // 记住这次连的设备，首页的「连接 / 重连」按钮下次直接用。
    _lastDeviceId = device.id;
    _lastDeviceName = device.name;
    _persistSettings();
    addLog(
      LogLevel.info,
      '已订阅命令特征通知，自动发送 INIT 命令 …',
    );
    try {
      await _writeSilently(<EpdWrite>[
        EpdWrite(payload: buildCommand(EpdCmd.init), withResponse: true),
      ]);
    } catch (error) {
      addLog(LogLevel.error, '发送 INIT 失败：$error');
    }
    // 固件只在「开启通知」那一刻推一次配置（引脚 + 驱动 id）。真机上这条通知
    // 时不时会被系统吞掉，表现为驱动号停在默认值、引脚是 `-`。漏了就重开一次
    // CCCD 让固件重发 —— 这是唯一能补救的办法。
    await _ensureConfigNotification();
    _isConnecting = false;
    notifyListeners();
  }

  /// 意外断开（不是用户点「断开」）：清掉连接态并给出可执行的提示。
  void _handleUnexpectedDisconnect() {
    if (_connected == null) {
      return;
    }
    final EpdBleDevice device = _connected!;
    final String name = device.name;
    _connected = null;
    _firmwareVersion = null;
    _liveRssi = null;
    _config = null;
    _rleSupported = false;
    _sawConfigNotification = false;
    _notificationSubscription?.cancel();
    _notificationSubscription = null;
    addLog(
      LogLevel.error,
      '与 $name 的连接已断开（设备主动断开或蓝牙链路中断）。'
      '写入过快、距离过远、屏幕正在刷新都可能触发。',
    );
    notifyListeners();
    if (_autoReconnect) {
      unawaited(_tryAutoReconnect(device));
    } else {
      addLog(LogLevel.info, '请到「设备连接」页手动重新连接。');
    }
  }

  /// 意外断开后自动重连（最多 3 次，间隔递增）。
  ///
  /// Android 不会主动维持 BLE 连接，链路一断 App 就成了「假连接」；
  /// 与其让人手动点，不如自己重试几次，多数情况下第一次就能接回来。
  Future<void> _tryAutoReconnect(EpdBleDevice device) async {
    if (_reconnecting) {
      return;
    }
    _reconnecting = true;
    try {
      for (int attempt = 1; attempt <= 3; attempt++) {
        if (_connected != null) {
          return;
        }
        addLog(LogLevel.info, '尝试自动重连 $attempt/3 …');
        notifyListeners();
        await Future<void>.delayed(Duration(milliseconds: 800 * attempt));
        if (_connected != null) {
          return;
        }
        await connect(device);
        if (_connected != null) {
          addLog(LogLevel.success, '已自动重连 ${device.name}');
          return;
        }
      }
      addLog(LogLevel.error, '自动重连失败，请到「设备连接」页手动连接。');
      notifyListeners();
    } finally {
      _reconnecting = false;
    }
  }

  Future<void> disconnect() async {
    final EpdBleDevice? device = _connected;
    if (device == null) {
      return;
    }
    await _notificationSubscription?.cancel();
    _notificationSubscription = null;
    await _connectionChangeSubscription?.cancel();
    _connectionChangeSubscription = null;
    await _ble.disconnect();
    _connected = null;
    _firmwareVersion = null;
    _liveRssi = null;
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
    if (_verboseTransfers) {
      debugPrint('[EPD] <notify len=${value.length} hex=${_hex(value)}');
    }
    if (!_sawConfigNotification && !_looksLikeText(value) && value.length >= 8) {
      final EpdConfig config = parseConfigNotification(value);
      _sawConfigNotification = true;
      _config = config;
      _recordNotification(
        '配置通知：引脚 ${_hex(config.pins)}，驱动 0x'
        '${config.driver.toRadixString(16).toUpperCase().padLeft(2, '0')}',
      );
      final EpdDriver? byCode = driverByCode(config.driver);
      if (byCode != null && _driverMode == DriverSelectionMode.auto) {
        if (byCode.id != _driver.id) {
          _driver = byCode;
          _resampleSource();
          addLog(
            LogLevel.info,
            '按固件上报的驱动同步为 ${byCode.label}',
          );
        }
      } else if (_driverMode == DriverSelectionMode.manual) {
        addLog(
          LogLevel.info,
          '固件上报驱动 id 0x'
          '${config.driver.toRadixString(16).toUpperCase().padLeft(2, '0')}，'
          '但当前为手动选择（${_driver.label}），不自动切换',
        );
      } else if (byCode == null) {
        addLog(
          LogLevel.warning,
          '固件上报的驱动 id 0x'
          '${config.driver.toRadixString(16).toUpperCase().padLeft(2, '0')}'
          ' 不在已知列表里，请到设置页手动选择驱动',
        );
      }
      notifyListeners();
      return;
    }

    final EpdTextNotification text = parseTextNotification(value);
    _recordNotification('文本通知：${text.text}');
    if (text.mtu != null) {
      // 固件把软设备里的 MTU 报回来。我们已经主动协商过一次，只接受「更大」的
      // 值：否则一条过时的 mtu=20 会把协商好的 247 打回原形，又开始上千条写。
      final int reported = text.mtu!;
      addLog(LogLevel.info, '固件报告 MTU = $reported');
      if (reported > _mtu) {
        setMtu(reported);
      }
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

  /// 等到固件的「配置通知」（引脚 + 驱动 id）；等不到就重开一次 CCCD 让它重发。
  Future<void> _ensureConfigNotification() async {
    if (_config != null) {
      return;
    }
    for (int attempt = 1; attempt <= 3; attempt++) {
      if (await _waitForConfig(const Duration(milliseconds: 900))) {
        return;
      }
      if (attempt == 3) {
        break;
      }
      addLog(
        LogLevel.warning,
        '还没收到固件的配置通知（引脚/驱动），第 $attempt 次重新打开通知 …',
      );
      try {
        await _ble.resubscribeNotifications();
      } catch (error) {
        addLog(LogLevel.warning, '重新打开通知失败：$error');
      }
    }
    addLog(
      LogLevel.warning,
      '固件始终没推配置通知：引脚与驱动未知，请到设置页手动确认驱动。',
    );
    notifyListeners();
  }

  /// 在 [timeout] 内轮询等待配置通知到达。
  Future<bool> _waitForConfig(Duration timeout) async {
    final DateTime deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_config != null) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    return _config != null;
  }

  void _recordNotification(String entry) {    _notificationLog.add(entry);
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

  /// 读一次当前链路的信号强度（诊断页 / 设备信息卡用）。
  ///
  /// 信号强度是瞬时的，读完不缓存成「常量」——下次进页面或点刷新再读。
  Future<void> refreshRssi() async {
    if (!isConnected || _readingRssi) {
      return;
    }
    _readingRssi = true;
    notifyListeners();
    try {
      final int? value = await _ble.readRssi();
      if (value != null) {
        _liveRssi = value;
      }
    } finally {
      _readingRssi = false;
    }
    if (_disposed) {
      return;
    }
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

  /// 申请蓝牙运行时权限，返回是否已获得（启动时的权限检查用）。
  ///
  /// 与 [requestBlePermission] 的区别：这里不写日志（启动阶段日志面板还是空的），
  /// 结果交给界面自己展示；同时顺手把蓝牙子系统状态刷一次，供首页显示。
  Future<bool> requestPermissions() async {
    // 只要真的问过一次系统，就算「检查过」——界面据此决定是否显示提醒横幅。
    // 不能依赖调用方（ensurePermissionsOnce / retryPermissions）记得打这个标记，
    // 否则直接调 requestPermissions 时 permissionDenied 永远是 false。
    _permissionChecked = true;
    final BlePermissionResult result = await _ble.ensurePermissions();
    try {
      _adapterStatusText = await _ble.describeAdapterStatus();
    } catch (_) {
      // 拿不到适配器状态不影响权限结果，界面会显示「未知」。
    }
    _permissionGranted = result.granted;
    if (!_disposed) {
      notifyListeners();
    }
    return result.granted;
  }

  /// 启动后自动做一次权限检查（只在首次启动时真正弹系统对话框）。
  ///
  /// 由 `EpdControllerApp` 在首帧后调用；之后再调不会重复申请。
  Future<void> ensurePermissionsOnce() async {
    if (_permissionChecked) {
      return;
    }
    await requestPermissions();
  }

  /// 重新申请权限（用户点了横幅上的「重新申请」）。
  Future<bool> retryPermissions() async {
    _permissionChecked = true;
    return requestPermissions();
  }

  /// 权限是否已被拒绝（界面据此显示提醒横幅）。
  bool get permissionDenied =>
      _permissionChecked && _permissionGranted == false;

  /// 查询当前所有权限的状态（只读，不弹系统对话框），供「权限检查」页展示。
  Future<List<AppPermissionStatus>> checkPermissions() async {
    try {
      return await _ble.checkPermissions();
    } catch (error) {
      addLog(LogLevel.warning, '查询权限状态失败：$error');
      return const <AppPermissionStatus>[];
    }
  }

  /// 打开本应用的系统设置页，让用户手动补授被永久拒绝的权限。
  Future<void> openSystemSettings() async {
    try {
      final bool opened = await openAppSettings();
      if (!opened && !_disposed) {
        addLog(LogLevel.warning, '打不开系统设置页，请到「设置 → 应用 → EPD Controller → 权限」手动开启。');
      }
    } catch (error) {
      addLog(LogLevel.warning, '打不开系统设置页：$error');
    }
  }

  /// 发一条 INIT 探测链路是否真的可写（诊断页用）。
  Future<void> sendDiagnosticInit() async {
    if (!_requireConnected('发送诊断命令')) {
      return;
    }
    try {
      await _writeSilently(<EpdWrite>[
        EpdWrite(payload: buildCommand(EpdCmd.init), withResponse: true),
      ]);
    } catch (error) {
      addLog(LogLevel.error, 'INIT 发送失败：$error');
      notifyListeners();
      return;
    }
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
    try {
      await _writeSilently(writes);
    } catch (error) {
      addLog(LogLevel.error, '时间下发失败：$error');
      notifyListeners();
      return;
    }
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
    try {
      await _writeSilently(writes);
    } catch (error) {
      addLog(LogLevel.error, '$label失败：$error');
      notifyListeners();
      return;
    }
    addLog(LogLevel.success, '$label：${_hex(writes.first.payload)}');
    notifyListeners();
  }

  /// 发送一条自定义单指令（`0x03` / `0x04` / `0x21` / `0x90` / `0x91` / `0x92` / `0x99`）。
  ///
  /// [payload] 已经是完整的「命令字 + 数据」，界面层用
  /// `lib/protocol/debug_commands.dart` 里的构造函数拼好再传进来。
  /// 参数是否合理由调用方先行校验（不合规也允许发，只是要提示用户），
  /// 这里只负责真的把字节写下去。
  Future<void> sendRawCommand(String label, Uint8List payload) async {
    if (!_requireConnected(label)) {
      return;
    }
    await _sendSimple(label, <EpdWrite>[
      EpdWrite(payload: payload, withResponse: true),
    ]);
  }

  /// `0x03`：把 1 字节命令码写进屏幕控制器的命令寄存器。
  Future<void> sendScreenCommand(Uint8List data) =>
      sendRawCommand('发送屏幕命令', buildSendCommand(data));

  /// `0x04`：把数据写进屏幕控制器的数据寄存器。
  Future<void> sendScreenData(Uint8List data) =>
      sendRawCommand('发送屏幕数据', buildSendData(data));

  /// `0x21`：设置日历的周起始日（0=周日 … 6=周六）。
  Future<void> setWeekStart(int weekStart) =>
      sendRawCommand('设置周起始日', buildWeekStart(weekStart));

  /// `0x90`：写配置。只写前 [byteCount] 项，其余字段保持设备上的原值。
  ///
  /// 固件不会重载 GPIO/驱动，写完必须再发 `0x91` 重启才生效。
  Future<void> writeConfig(EpdConfigPayload config, {int? byteCount}) {
    final Uint8List bytes = config.firstBytes(byteCount ?? EpdConfigPayload.size);
    return sendRawCommand(
      '写配置（${bytes.length} 项）',
      buildCommand(EpdCmd.setConfig, bytes),
    );
  }

  /// `0x91`：重启芯片，链路会断，需要重新连接。
  Future<void> systemReset() async {
    await sendRawCommand('系统重启', buildSystemReset());
  }

  /// `0x92`：深度睡眠。发送后设备只能靠唤醒引脚唤醒，**无法通过网络唤醒**。
  Future<void> systemSleep() async {
    await sendRawCommand('系统睡眠', buildSystemSleep());
  }

  /// `0x99`：抹掉配置并重启，等于恢复出厂默认。
  Future<void> eraseConfig() async {
    await sendRawCommand('恢复默认配置', buildConfigErase());
  }

  /// 固件配置通知里的唤醒引脚；还没收到配置时是 null。
  int? get wakeupPin => _config?.wakeupPin;

  /// `0x92` 的安全判断，界面据此决定是禁用还是要用户二次确认。
  SleepSafety get sleepSafety => evaluateSleepSafety(wakeupPin);

  /// 把当前预览图真正发到设备：按 [transferPlan] 逐条写特征值。
  Future<void> sendPreview() async {
    if (!_requireConnected('发送图片')) {
      return;
    }
    await _sendPlan(transferPlan);
  }

  /// 发一张纯色图（诊断用）。
  ///
  /// 三色屏只有黑/白/红三种颜色，所以「纯黑 / 纯白 / 纯红」三个测试就能把
  /// 平面极性和打包顺序全部定死：
  /// - 发纯黑却出现红色 → 红白平面与黑白平面搞反了（或红平面极性相反）；
  /// - 发纯红却出现白色 → 红平面极性相反；
  /// - 三个都正常 → 说明数据链路对，问题在抖动后的图本身。
  Future<void> sendSolidColor(EpdColor color) async {
    final String name = '纯色测试 ${color.name}';
    if (!_requireConnected(name)) {
      return;
    }
    final int w = canvasSize.width;
    final int h = canvasSize.height;
    final RgbaImage image = RgbaImage(w, h);
    for (int i = 0; i < w * h; i++) {
      final int offset = i * 4;
      image.data[offset] = color.r;
      image.data[offset + 1] = color.g;
      image.data[offset + 2] = color.b;
      image.data[offset + 3] = 255;
    }
    final ImageTransferPlan plan = planImageTransfer(
      image: image,
      driver: _driver,
      colorMode: colorMode,
      canvasSizeName: canvasSize.name,
      mtu: planMtu,
      rleSupported: _rleSupported,
      interleavedCount: _interleavedCount,
      alwaysWithResponse: true,
      swapPlanes: _swapPlanes,
      invertRedPlane: _invertRedPlane,
    );
    addLog(
      LogLevel.info,
      '$name：RGB(${color.r},${color.g},${color.b}) 值=0x'
      '${color.value.toRadixString(16).padLeft(2, '0')} / '
      '${plan.totalWrites} 条写指令 / ${plan.processedBytes} 字节',
    );
    await _sendPlan(plan);
  }

  /// 把一份传图计划真正写到设备上（发送、重试、进度、刷新说明都在这里）。
  Future<void> _sendPlan(ImageTransferPlan plan) async {
    addLog(
      LogLevel.info,
      '开始发送：${plan.totalWrites} 条写指令 / ${plan.processedBytes} 字节 / '
      'MTU $_mtu（每块 $writeChunkBytes 字节）',
    );
    notifyListeners();

    int sent = 0;
    final int total = plan.totalWrites;
    final int progressStep = total > 40 ? total ~/ 10 : 0;
    try {
      for (final EpdWrite write in plan.writes) {
        final int index = sent + 1;
        // 先打「即将发」这一行：万一这条卡住，logcat 最后一行就是卡住的那条。
        if (_verboseTransfers) {
          debugPrint(
            '[EPD] > #$index/$total cmd=0x'
            '${write.payload.first.toRadixString(16).padLeft(2, '0')} '
            'len=${write.payload.length} reply=${write.withResponse}',
          );
        }
        await _writeWithRetry(write);
        sent++;
        _writesSent++;
        if (_verboseTransfers) {
          debugPrint(
            '[EPD] < #$sent/$total ok bytes=${_hex(write.payload)}',
          );
        }
        if (progressStep > 0 && sent % progressStep == 0 && sent < total) {
          addLog(LogLevel.info, '发送中 $sent/$total');
          notifyListeners();
        }
        // 给外设留喘气时间：nRF51 一次连接事件里吞不下太多数据，
        // 连着灌会把它的接收缓冲顶满，然后它就再也不回 ATT 响应了。
        if (sent < total) {
          await Future<void>.delayed(kInterChunkDelay);
        }
      }
    } catch (error) {
      addLog(
        LogLevel.error,
        '发送中断（已发 $sent/$total 条）：$error '
        '${_connected == null ? '连接已断开，正在尝试自动重连。' : '可以重试一次；仍失败就缩短距离。'}',
      );
      notifyListeners();
      // 卡住的写指令意味着链路已经废了：主动断开把挂起的 GATT 事务丢掉，
      // 再走「意外断开」那条路，让自动重连接管恢复。
      if (_connected != null) {
        await _ble.disconnect();
        _handleUnexpectedDisconnect();
      }
      return;
    }

    addLog(
      LogLevel.success,
      '发送完成：${plan.imageWrites} 条图像写指令'
      '${plan.usedRle ? '，已启用 RLE' : ''}',
    );
    addLog(
      LogLevel.info,
      '刷新命令已发送。墨水屏整屏刷新通常需要 2~10 秒，'
      '期间屏幕闪烁/变灰是正常的，别急着断电。',
    );
    notifyListeners();
  }

  /// 写一条负载，失败自动重试。
  ///
  /// Android 上 GATT 133 常常是瞬时的（蓝牙缓冲瞬间满），重试一次往往就过去了；
  /// 连续三次仍失败说明链路真的不行，交给上层报错。
  ///
  /// 另外每条写都套 [kWriteTimeout]：真机上出现过「写出去、设备不回、Android
  /// 干等 30 秒才报 133」的情况，期间界面完全卡住没有反馈。超时不重试（那条
  /// ATT 事务还挂在那儿，重试只会排队），直接抛出去让上层断开重连。
  Future<void> _writeWithRetry(EpdWrite write, {int attempts = 3}) async {
    Object? lastError;
    for (int attempt = 1; attempt <= attempts; attempt++) {
      try {
        await _ble
            .write(write.payload, withResponse: write.withResponse)
            .timeout(kWriteTimeout);
        return;
      } on TimeoutException catch (error) {
        throw StateError('设备 ${kWriteTimeout.inSeconds} 秒内没有确认这条写指令'
            '（payload ${write.payload.length} 字节），链路已经不可用：$error');
      } catch (error) {
        lastError = error;
        if (attempt < attempts) {
          await Future<void>.delayed(Duration(milliseconds: 60 * attempt));
        }
      }
    }
    throw StateError('写入失败（已重试 $attempts 次）：$lastError');
  }

  /// 逐条写，不逐条打日志（避免一次传图刷几百条日志）。
  Future<void> _writeSilently(List<EpdWrite> writes) async {
    for (final EpdWrite write in writes) {
      await _writeWithRetry(write);
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
    _persistSettings();
    notifyListeners();
  }

  /// 切换驱动选择方式。
  ///
  /// 切到手动后，固件再上报驱动号也不会覆盖用户的选择；切回自动时立即按
  /// 已收到的配置通知（如果有）同步一次。
  void setDriverMode(DriverSelectionMode mode) {
    if (mode == _driverMode) {
      return;
    }
    _driverMode = mode;
    addLog(
      LogLevel.info,
      mode == DriverSelectionMode.auto
          ? '驱动选择：自动（按固件上报匹配）'
          : '驱动选择：手动（忽略固件上报，使用手动选定的驱动）',
    );
    final EpdConfig? config = _config;
    if (mode == DriverSelectionMode.auto && config != null) {
      final EpdDriver? byCode = driverByCode(config.driver);
      if (byCode != null && byCode.id != _driver.id) {
        _driver = byCode;
        _resampleSource();
        addLog(LogLevel.info, '按固件上报的驱动同步为 ${byCode.label}');
      }
    }
    _persistSettings();
    notifyListeners();
  }

  void setAlgorithm(DitherAlgorithm algorithm) {
    if (algorithm == _algorithm) {
      return;
    }
    _algorithm = algorithm;
    if (algorithm == DitherAlgorithm.blueNoise) {
      // 蓝噪声需要那 4 KB 阈值表；第一次选中时在后台加载，不阻塞界面。
      unawaited(loadNoiseMask());
    }
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

  // ---- 0.3.0：现代抖动的附加参数 ----

  /// 误差扩散是否走蛇形扫描。
  bool get serpentine => _serpentine;

  /// 蓝噪声阈值表是否已就绪（没就绪时选 blueNoise 会退回散列噪声）。
  bool get noiseMaskReady => _noiseMask != null;

  /// 蓝噪声阈值表是否正在加载。
  bool get noiseMaskLoading => _noiseMaskLoading;

  void setSerpentine(bool value) {
    if (value == _serpentine) {
      return;
    }
    _serpentine = value;
    _persistSettings();
    addLog(
      LogLevel.info,
      value ? '抖动改为蛇形扫描（奇数行反向）' : '抖动改回逐行扫描',
    );
    notifyListeners();
  }

  /// 加载内置的 64×64 蓝噪声纹理。重复调用是安全的（已有就跳过）。
  Future<void> loadNoiseMask() async {
    if (_noiseMask != null || _noiseMaskLoading) {
      return;
    }
    _noiseMaskLoading = true;
    notifyListeners();
    final Uint8List? mask = await noise.loadNoiseMask();
    _noiseMaskLoading = false;
    if (_disposed) {
      return;
    }
    if (mask == null) {
      addLog(
        LogLevel.warning,
        '蓝噪声纹理加载失败，将退回程序生成的散列噪声；画面会略差一些。',
      );
    } else {
      _noiseMask = mask;
      addLog(LogLevel.info, '蓝噪声纹理已就绪（${mask.length} 个阈值）');
    }
    _invalidatePreview();
    notifyListeners();
  }

  // ---- 处理阶段（原图 → 处理 → 抖动）----

  /// 是否做自动亮度（直方图拉伸）。
  void setAutoBrightness(bool value) {
    if (value == _autoBrightness) {
      return;
    }
    _autoBrightness = value;
    _invalidatePreview();
    _persistSettings();
    notifyListeners();
  }

  /// 手动亮度补偿，-100 ~ 100（会夹取）。
  void setBrightness(double value) {
    final double clamped =
        value < -100 ? -100 : (value > 100 ? 100 : value);
    if (clamped == _brightness) {
      return;
    }
    _brightness = clamped;
    _invalidatePreview();
    _persistSettings();
    notifyListeners();
  }

  /// 是否做色彩简化。
  void setSimplifyColors(bool value) {
    if (value == _simplifyColors) {
      return;
    }
    _simplifyColors = value;
    _invalidatePreview();
    _persistSettings();
    notifyListeners();
  }

  /// 色彩简化的目标颜色数，2 ~ 64（会夹取）。
  void setSimplifyColorCount(int value) {
    final int clamped = value < 2 ? 2 : (value > 64 ? 64 : value);
    if (clamped == _simplifyColorCount) {
      return;
    }
    _simplifyColorCount = clamped;
    _invalidatePreview();
    _persistSettings();
    notifyListeners();
  }

  /// 恢复处理阶段的默认值（只做自动亮度）。
  void resetProcess() {
    if (_autoBrightness &&
        _brightness == 0 &&
        !_simplifyColors &&
        _simplifyColorCount == 8) {
      return;
    }
    _autoBrightness = true;
    _brightness = 0;
    _simplifyColors = false;
    _simplifyColorCount = 8;
    _invalidatePreview();
    _persistSettings();
    notifyListeners();
  }

  void setMtu(int value) {
    final int clamped = value < 20 ? 20 : (value > 247 ? 247 : value);
    if (clamped == _mtu) {
      return;
    }
    _mtu = clamped;
    _persistSettings();
    notifyListeners();
  }

  /// 分块档位：稳定 / 正常 / 快速 / 最大 / 自定义。
  TransferSpeed get speed => _speed;

  /// 切换分块档位。切到自定义时使用 [customChunkBytes]。
  void setSpeed(TransferSpeed value) {
    if (value == _speed) {
      return;
    }
    _speed = value;
    addLog(
      LogLevel.info,
      '分块档位：${value.label}（每块 $writeChunkBytes 字节）',
    );
    _persistSettings();
    notifyListeners();
  }

  /// 自定义档每块的字节数。
  int get customChunkBytes => _customChunkBytes;

  /// 设置自定义档每块的字节数（夹到 8..当前 MTU 上限）。
  void setCustomChunkBytes(int value) {
    final int max = writeMtu - 2;
    final int clamped = value < 8 ? 8 : (value > max ? max : value);
    if (clamped == _customChunkBytes) {
      return;
    }
    _customChunkBytes = clamped;
    addLog(LogLevel.info, '自定义分块：每块 $clamped 字节');
    _persistSettings();
    notifyListeners();
  }

  void setInterleavedCount(int value) {
    final int clamped = value < 1 ? 1 : (value > 100 ? 100 : value);
    _interleavedCountOverride = true;
    if (clamped == _interleavedCount) {
      _persistSettings();
      return;
    }
    _interleavedCount = clamped;
    _persistSettings();
    notifyListeners();
  }

  bool get interleavedCountOverridden => _interleavedCountOverride;

  void setRleSupported(bool value) {
    if (value == _rleSupported) {
      return;
    }
    _rleSupported = value;
    addLog(LogLevel.info, value ? '已假定固件支持 RLE' : '已关闭 RLE');
    _persistSettings();
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
    _processedCache = null;
    _processedCacheKey = null;
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
    _persistSettings();
    notifyListeners();
  }

  /// 组装要保存的设置快照。
  Map<String, Object?> _settingsSnapshot() => <String, Object?>{
        'version': kSettingsVersion,
        'themeMode': _themeMode.name,
        'driverId': _driver.id,
        'driverMode': _driverMode.name,
        'speed': _speed.name,
        'customChunkBytes': _customChunkBytes,
        'interleavedCount': _interleavedCount,
        'interleavedOverride': _interleavedCountOverride,
        'rleSupported': _rleSupported,
        'verboseTransfers': _verboseTransfers,
        'lastDeviceId': _lastDeviceId,
        'lastDeviceName': _lastDeviceName,
        'driverWarningMuted': _driverWarningMuted,
        'autoBrightness': _autoBrightness,
        'brightness': _brightness,
        'simplifyColors': _simplifyColors,
        'simplifyColorCount': _simplifyColorCount,
        'serpentine': _serpentine,
      };

  /// 把当前设置写出去（异步、失败只记日志，不影响使用）。
  void _persistSettings() {
    final Map<String, Object?> snapshot = _settingsSnapshot();
    unawaited(
      _settings.save(snapshot).catchError((Object error) {
        if (!_disposed) {
          addLog(LogLevel.warning, '保存设置失败：$error');
        }
      }),
    );
  }

  /// 启动时读取上次保存的设置。[SettingsStore.load] 不会抛异常，读不到就用默认值。
  Future<void> _restoreSettings() async {
    final Map<String, Object?>? data = await _settings.load();
    if (data == null || _disposed) {
      return;
    }

    final Object? themeName = data['themeMode'];
    if (themeName is String) {
      _themeMode = switch (themeName) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    }

    final Object? driverId = data['driverId'];
    if (driverId is String) {
      final EpdDriver? driver = driverById(driverId);
      if (driver != null && driver.id != _driver.id) {
        _driver = driver;
        // 启动阶段底图永远是示例图，按新画布尺寸重生成即可。
        _sourceImage =
            sampleImage(_driver.canvasSize.width, _driver.canvasSize.height);
        _invalidatePreview();
      }
    }

    final Object? speedName = data['speed'];
    if (speedName is String) {
      for (final TransferSpeed candidate in TransferSpeed.values) {
        if (candidate.name == speedName) {
          _speed = candidate;
          break;
        }
      }
    }

    final Object? customChunkBytes = data['customChunkBytes'];
    if (customChunkBytes is int) {
      _customChunkBytes = customChunkBytes;
    }

    final Object? interleavedCount = data['interleavedCount'];
    if (interleavedCount is int) {
      _interleavedCount = interleavedCount < 1
          ? 1
          : (interleavedCount > 100 ? 100 : interleavedCount);
      _interleavedCountOverride = data['interleavedOverride'] == true;
    }

    final Object? rleSupported = data['rleSupported'];
    if (rleSupported is bool) {
      _rleSupported = rleSupported;
    }

    final Object? verboseTransfers = data['verboseTransfers'];
    if (verboseTransfers is bool) {
      _verboseTransfers = verboseTransfers;
    }

    final Object? driverModeName = data['driverMode'];
    if (driverModeName is String) {
      for (final DriverSelectionMode candidate in DriverSelectionMode.values) {
        if (candidate.name == driverModeName) {
          _driverMode = candidate;
          break;
        }
      }
    }

    final Object? lastDeviceId = data['lastDeviceId'];
    if (lastDeviceId is String && lastDeviceId.isNotEmpty) {
      _lastDeviceId = lastDeviceId;
    }

    final Object? lastDeviceName = data['lastDeviceName'];
    if (lastDeviceName is String && lastDeviceName.isNotEmpty) {
      _lastDeviceName = lastDeviceName;
    }

    final Object? driverWarningMuted = data['driverWarningMuted'];
    if (driverWarningMuted is bool) {
      _driverWarningMuted = driverWarningMuted;
    }

    // ---- 处理阶段 ----
    final Object? autoBrightness = data['autoBrightness'];
    if (autoBrightness is bool) {
      _autoBrightness = autoBrightness;
    }
    final Object? brightness = data['brightness'];
    if (brightness is num) {
      final double value = brightness.toDouble();
      _brightness = value < -100 ? -100 : (value > 100 ? 100 : value);
    }
    final Object? simplifyColors = data['simplifyColors'];
    if (simplifyColors is bool) {
      _simplifyColors = simplifyColors;
    }
    final Object? simplifyColorCount = data['simplifyColorCount'];
    if (simplifyColorCount is int) {
      _simplifyColorCount = simplifyColorCount < 2
          ? 2
          : (simplifyColorCount > 64 ? 64 : simplifyColorCount);
    }

    // ---- 现代抖动 ----
    final Object? serpentine = data['serpentine'];
    if (serpentine is bool) {
      _serpentine = serpentine;
    }
    // 蓝噪声掩膜不持久化（4 KB 字节数组没必要进 JSON），启动后按需加载。
    if (_algorithm == DitherAlgorithm.blueNoise) {
      unawaited(loadNoiseMask());
    }

    if (_disposed) {
      return;
    }
    _invalidatePreview();
    addLog(LogLevel.info, '已恢复上次的设置');
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
    _disposed = true;
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
