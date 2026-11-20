import 'package:flutter_test/flutter_test.dart';

import 'package:epd_controller/services/permission_gate.dart';

/// 首次启动权限检查的门面。
void main() {
  test('申请成功后 granted 为 true，且只调一次', () async {
    int calls = 0;
    final PermissionGate gate = PermissionGate(request: () async {
      calls++;
      return true;
    });
    expect(gate.granted, isNull);
    expect(gate.hasPrompted, isFalse);

    expect(await gate.ensure(), isTrue);
    expect(gate.granted, isTrue);
    expect(gate.hasPrompted, isTrue);

    // 已获得后再 ensure 不会重复弹系统对话框。
    expect(await gate.ensure(), isTrue);
    expect(calls, 1);
  });

  test('申请被拒绝后 granted 为 false', () async {
    final PermissionGate gate = PermissionGate.alwaysDenied();
    expect(await gate.ensure(), isFalse);
    expect(gate.granted, isFalse);
  });

  test('被拒绝后 retry 会重新申请', () async {
    int calls = 0;
    bool granted = false;
    final PermissionGate gate = PermissionGate(request: () async {
      calls++;
      return granted;
    });

    expect(await gate.ensure(), isFalse);
    expect(calls, 1);

    granted = true;
    expect(await gate.retry(), isTrue);
    expect(calls, 2);
    expect(gate.granted, isTrue);
  });

  test('notifyListeners 在结果出来后被调用', () async {
    final PermissionGate gate = PermissionGate.alwaysGranted();
    int notified = 0;
    gate.addListener(() => notified++);
    await gate.ensure();
    expect(notified, 1);
  });
}
