import 'package:flutter/foundation.dart';

import '../state/app_state.dart';

/// 首次启动时的权限检查。
///
/// Android 12+ 上不授「附近的设备」权限，扫描会静默返回空列表、没有任何报错，
/// 用户只会看到「找不到设备」。所以启动后主动申请一次，并把结果反馈到界面。
///
/// 测试里用 [PermissionGate.alwaysGranted] / [PermissionGate.alwaysDenied]
/// 直接构造，避开平台通道。
class PermissionGate extends ChangeNotifier {
  PermissionGate({required this.request});

  /// 真实实现：走 [AppState] 申请 BLUETOOTH_SCAN / BLUETOOTH_CONNECT。
  factory PermissionGate.fromAppState(AppState state) {
    return PermissionGate(request: state.requestPermissions);
  }

  /// 测试用：始终授予。
  factory PermissionGate.alwaysGranted() {
    return PermissionGate(request: () async => true);
  }

  /// 测试用：始终拒绝。
  factory PermissionGate.alwaysDenied() {
    return PermissionGate(request: () async => false);
  }

  /// 申请权限，返回是否已获得。
  final Future<bool> Function() request;

  bool? _granted;

  /// 最近一次申请结果；还没申请过时为 null。
  bool? get granted => _granted;

  bool get hasPrompted => _granted != null;

  /// 发起申请。已获得就直接返回，避免每次进页面都弹一次系统对话框。
  Future<bool> ensure() async {
    final bool? previous = _granted;
    if (previous == true) {
      return true;
    }
    final bool result = await request();
    _granted = result;
    notifyListeners();
    return result;
  }

  /// 手动重新申请（用户点了「重新申请」）。
  Future<bool> retry() async {
    _granted = null;
    return ensure();
  }
}
