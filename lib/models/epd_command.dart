class EpdCommand {
  final int cmd;
  final List<int> data;

  const EpdCommand(this.cmd, [this.data = const []]);

  // 命令定义 (对应Web端的EpdCmd)
  static const EpdCommand setPins = EpdCommand(0x00);
  static const EpdCommand init = EpdCommand(0x01);
  static const EpdCommand clear = EpdCommand(0x02);
  static const EpdCommand sendCmd = EpdCommand(0x03);
  static const EpdCommand sendData = EpdCommand(0x04);
  static const EpdCommand refresh = EpdCommand(0x05);
  static const EpdCommand sleep = EpdCommand(0x06);
  static const EpdCommand setTime = EpdCommand(0x20);
  static const EpdCommand writeImg = EpdCommand(0x30);
  static const EpdCommand setConfig = EpdCommand(0x90);
  static const EpdCommand sysReset = EpdCommand(0x91);
  static const EpdCommand sysSleep = EpdCommand(0x92);
  static const EpdCommand cfgErase = EpdCommand(0x99);

  // 创建带数据的命令
  EpdCommand withData(List<int> newData) => EpdCommand(cmd, newData);

  // 转换为字节数组
  List<int> toBytes() {
    return [cmd, ...data];
  }

  // 转换为十六进制字符串
  String toHexString() {
    return toBytes().map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}