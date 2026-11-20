import 'package:flutter/foundation.dart';

/// 应用版本信息。
///
/// 这里**手写**而不是从 `package_info_plus` 之类读：本项目的版本号只在发版时变，
/// 写死一份 const 反而更省事、零依赖，也能让「更新日志」页与版本号天然对齐。
class AppVersion {
  const AppVersion._();

  /// 版本号（与 `pubspec.yaml` 的 version 保持一致，发布前手工核对）。
  ///
  /// `test/app_version_test.dart` 会读 `pubspec.yaml` 校验两边一致，
  /// 忘记同步时 CI 会直接失败。
  static const String version = '0.2.0';

  /// 构建号，与 `pubspec.yaml` 里 `version: x.y.z+N` 的 N 一致。
  static const int buildNumber = 2;

  /// 完整版本串，例如 `0.2.0+2`。
  static String get fullVersion => '$version+$buildNumber';

  /// 应用名。
  static const String appName = 'EPD Controller';

  /// 作者。
  static const String authors = 'Noyield、蓝色大肥鱼';

  /// 上游固件项目。
  static const String upstreamUrl = 'https://github.com/tsl0922/EPD-nRF5';

  /// 本仓库地址（更新检查与「去下载」都用它）。
  static const String repoOwner = 'Yuzgaf33tref6';
  static const String repoName = 'EPD_nRF5_Controller';
  static const String repoUrl =
      'https://github.com/$repoOwner/$repoName';
  static const String latestReleaseApi =
      'https://api.github.com/repos/$repoOwner/$repoName/releases/latest';

  /// 比较两个版本号（形如 `0.2.0` 或 `v0.2.0`）。
  ///
  /// 返回正数表示 [a] 比 [b] 新，0 表示相同，负数表示更旧。
  /// 规则：按 `.` 拆成数字段逐段比较，缺少的段按 0 处理；
  /// 非数字后缀（例如 `0.2.0-rc1`）一律忽略 —— 我们不发预发布版。
  static int compareVersions(String a, String b) {
    final List<int> pa = _parseVersion(a);
    final List<int> pb = _parseVersion(b);
    final int length = pa.length > pb.length ? pa.length : pb.length;
    for (int i = 0; i < length; i++) {
      final int va = i < pa.length ? pa[i] : 0;
      final int vb = i < pb.length ? pb[i] : 0;
      if (va != vb) {
        return va - vb;
      }
    }
    return 0;
  }

  static List<int> _parseVersion(String raw) {
    String text = raw.trim();
    if (text.startsWith('v') || text.startsWith('V')) {
      text = text.substring(1);
    }
    final int plus = text.indexOf('+');
    if (plus >= 0) {
      text = text.substring(0, plus);
    }
    final List<int> out = <int>[];
    for (final String part in text.split('.')) {
      final Match? match = RegExp(r'^\d+').firstMatch(part);
      out.add(match == null ? 0 : int.parse(match.group(0)!));
    }
    return out;
  }
}

/// 版本更新日志。
///
/// 刻意**硬编码**而不是联网拉：保证每个版本都有一份随包发布的说明，
/// 离线也能看。发版时在这里追加一条即可（最新的放最前面）。
class ReleaseNote {
  const ReleaseNote({
    required this.version,
    required this.date,
    required this.highlights,
  });

  final String version;

  /// 形如 `2026-11-20`。
  final String date;

  final List<String> highlights;
}

/// 全部更新日志，最新在前。
const List<ReleaseNote> kReleaseNotes = <ReleaseNote>[
  ReleaseNote(
    version: '0.2.0',
    date: '2026-11-20',
    highlights: <String>[
      '界面重构：底部导航改为「首页 / 发送 / 设置」三页，操作路径更短。',
      '首页顶部换成大号连接状态卡，显示设备名、信号强度、固件版本、驱动与画布。',
      '首页提供「连接 / 断开 / 重连」三个快捷按钮，会记住上次连接的设备。',
      '设备扫描列表收进折叠区，默认收起，减少首页干扰。',
      '发送页整合设备指令（时间同步 / 清屏 / 刷新 / 睡眠）与图像发送，可切换查看原图与抖动预览。',
      '设置页分为「应用 / 传输 / 驱动 / 诊断 / 关于」五组；MTU 默认自动协商，切换手动时会有风险提示。',
      '日志面板改为可折叠的状态条，不再长期占据半屏；完整日志移到独立的日志查看器页面。',
      '详细传输日志默认关闭（可在设置页开启）。',
      '未收到固件配置通知时会弹出「驱动可能错误」提示，可本次启动不再提示或永久不再提示。',
      '新增「更新日志」页面与「检查更新」（手动查询 GitHub Releases 最新版本）。',
      '作者信息：Noyield、蓝色大肥鱼。',
    ],
  ),
  ReleaseNote(
    version: '0.1.0',
    date: '2026-11-19',
    highlights: <String>[
      '首个正式版本：把 EPD-nRF5 的 Web 上位机完整搬到 Android。',
      'BLE 扫描 / 连接、时间同步、清屏刷新、传图。',
      '图片导入 + 裁剪（拖动平移、双指缩放、旋转 90°）。',
      '手绘画布：画笔、橡皮、撤销/重做、填白、6 种颜色、文字工具。',
      '6 种抖动算法、对比度与强度调节、黑白/三色/四色/六色色彩模式。',
      '传图分块档位（稳定/正常/快速/最大/自定义）、写入重试、断线自动重连。',
      '蓝牙诊断页：权限、适配器状态、原始通知、纯色测试、平面排查。',
      '设置持久化到 App 私有目录；release 签名固定，可覆盖升级。',
    ],
  ),
];

/// 更新检查结果。
@immutable
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.currentVersion,
    this.latestVersion,
    this.releaseName,
    this.releaseUrl,
    this.publishedAt,
    this.error,
  });

  /// 当前版本号。
  final String currentVersion;

  /// GitHub 上最新 release 的 tag（去掉前缀 `v`）。
  final String? latestVersion;

  /// release 标题。
  final String? releaseName;

  /// release 页面地址。
  final String? releaseUrl;

  /// 发布时间原文（ISO8601，没解析成 DateTime 是为了少一层时区麻烦）。
  final String? publishedAt;

  /// 出错时的可读信息；为 null 表示查询成功。
  final String? error;

  /// 是否有新版本。
  bool get hasUpdate {
    final String? latest = latestVersion;
    if (latest == null) {
      return false;
    }
    return AppVersion.compareVersions(latest, currentVersion) > 0;
  }

  /// 查询成功但没有更新。
  bool get isUpToDate => error == null && latestVersion != null && !hasUpdate;
}
