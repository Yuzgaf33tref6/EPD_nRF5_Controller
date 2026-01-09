import 'dart:typed_data';
import '../services/bluetooth_service.dart';

class ProtocolService {
  final BluetoothService _bt;
  ProtocolService(this._bt);

  Future<bool> sendCommand(int cmd, List<int>? data) async {
    return _bt.writeCmd(cmd, data);
  }

  Future<bool> sendImage(Uint8List data, {int mtu = 20, int interleaved = 50, String step = 'bw'}) async {
    return _bt.writeImageChunks(data, mtu: mtu, interleavedCount: interleaved, step: step);
  }
}
