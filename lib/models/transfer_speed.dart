/// 传图分块的档位：决定一条图像写指令最多携带多少字节有效负载。
///
/// 背景：nRF51 的 SoftDevice 链路层 PDU 只有 27 字节，一条大 ATT 写请求会被拆成
/// 十几个链路层包；外设接收缓冲一旦被顶满就不回 ATT 响应，Android 等 30 秒超时后
/// 以 GATT 133 拆掉连接。块越小越稳，越大越快。
///
/// - [conservative]：18 字节，**与 web 版默认值完全一致**（web 默认 MTU 20，
///   `chunkSize = mtu - 2 = 18`）。最慢但最保险，排查问题时应先回到这一档。
/// - [fast]：64 字节，日常可用的折中值。
/// - [extreme]：180 字节，实测能跑完 400×300 三色整屏，但对固件缓冲最不友好。
/// - [custom]：不设额外上限，按「偏好设置」里的 MTU 滑块推算
///   （`ATT_MTU - 3 - 2` 字节有效负载）。
enum TransferSpeed {
  conservative('稳妥', 18),
  fast('快速', 64),
  extreme('极限', 180),
  custom('自定义', 0);

  const TransferSpeed(this.label, this.presetChunkBytes);

  /// 下拉框里显示的中文名。
  final String label;

  /// 该档位固定的有效负载字节数；[TransferSpeed.custom] 为 0，表示由 MTU 决定。
  final int presetChunkBytes;

  /// 是否为自定义档（此时 MTU 滑块起作用）。
  bool get isCustom => this == TransferSpeed.custom;
}
