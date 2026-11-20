/// 传图分块的档位。
///
/// 背景：nRF51 的蓝牙链路层单包只有 27 字节，一条 ATT 写会被拆成十几个链路包。
/// 一条指令写得越大，外设接收缓冲越容易被灌满；灌满之后它就不再回 ATT 响应，
/// Android 等 30 秒报 GATT 133 并把连接拆掉（真机上确实撞到过）。
///
/// 真机验证结论（4.2 寸三色 + 固件 0x19）：242 字节（MTU 247 下的理论上限）也能
/// 稳定传完，所以档位只影响速度，不再作为稳定性保险。
enum TransferSpeed {
  /// 最保守：18 字节，与 web 版默认（`mtu-2`，mtu=20）一致。
  stable('稳定', 18),

  /// 日常推荐。
  normal('正常', 64),

  /// 快一些。
  fast('快速', 128),

  /// 吃满 ATT 上限：`MTU-3-2`（MTU 247 时是 242）。
  max('最大', -1),

  /// 自己填字节数。
  custom('自定义', -2);

  const TransferSpeed(this.label, this.presetChunkBytes);

  final String label;

  /// 预设的每块有效负载字节数；-1 表示吃满上限，-2 表示用自定义值。
  final int presetChunkBytes;

  bool get isCustom => this == TransferSpeed.custom;

  bool get isMax => this == TransferSpeed.max;
}

/// 驱动的选择方式：自动按固件上报的驱动号匹配，或由用户手动指定。
enum DriverSelectionMode {
  /// 自动：连上设备后按固件推送的配置通知自动匹配（推荐）。
  auto('自动'),

  /// 手动：忽略固件上报，始终使用用户选中的驱动。
  manual('手动');

  const DriverSelectionMode(this.label);

  final String label;
}
