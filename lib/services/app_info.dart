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
  static const String version = '0.2.1';

  /// 构建号，与 `pubspec.yaml` 里 `version: x.y.z+N` 的 N 一致。
  static const int buildNumber = 3;

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
    version: '0.2.1',
    date: '2026-11-20',
    highlights: <String>[
      '修复：检查更新一直失败 —— release 包缺少联网权限（INTERNET）。',
      '修复：裁剪页预览图缩小偏在左上角、和实际出图不一致（预览尺寸误用了原图尺寸）。',
      '裁剪页重做取景模型：缩放 0.1~5 倍，可以缩到比取景框小，四周按底色（白/黑）补齐；'
          '缩小后可在画面内自由摆放，不再被顶到边缘。',
      '导入图片上限从 2400 提到 4096，裁剪预览从 720 提到 1080，放大细看更清楚。',
      '竖图导入横屏画布时会提示“建议先旋转 90°”，并在裁剪页提供旋转按钮。',
      '预览绘制改到后台 isolate，图像发送页与画布编辑页不再因抖动计算卡顿。',
      '新增「权限检查」页：集中查看并申请本应用需要的全部系统权限，可跳转系统设置。',
      '关于与更新页：仓库 / 固件地址可点击、可复制，作者名可点击；与设置页的「关于」统一为同一份内容。',
      '新增「设备指令 · 调试」页：0x03 发送命令、0x04 写数据、0x21 周起始日、'
          '0x90 自定义配置、0x91 系统重启、0x92 系统睡眠、0x99 恢复默认配置，'
          '以及全黑 / 全白 / 全红纯色测试，全部使用十六进制输入。',
      '0x92 系统睡眠按配置里的唤醒引脚做安全判定：未配置唤醒引脚时直接禁用；'
          '没收到配置时需勾选确认才能发送。',
      '设备指令面板重新排版：0x20 时间同步（日历 / 时钟）与常用 0x0X 指令分栏显示，指令编号独立成行。',
      '连接设备后自动折叠扫描区；折叠提示改为“扫描到 N 个设备”。',
      '蓝牙诊断页与首页设备信息新增信号强度（RSSI），可手动刷新。',
    ],
  ),
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
