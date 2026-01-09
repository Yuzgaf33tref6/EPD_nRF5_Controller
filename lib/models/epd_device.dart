class EpdDevice {
  final String id;
  final String name;
  final String? manufacturerData;
  bool isConnected;
  int? rssi;

  EpdDevice({
    required this.id,
    required this.name,
    this.manufacturerData,
    this.isConnected = false,
    this.rssi,
  });

  // 从蓝牙扫描结果创建设备
  factory EpdDevice.fromScanResult(dynamic scanResult) {
    return EpdDevice(
      id: scanResult.device.id.id,
      name: scanResult.device.advName.isEmpty ? '未知设备' : scanResult.device.advName,
      rssi: scanResult.rssi,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'isConnected': isConnected,
  };

  factory EpdDevice.fromJson(Map<String, dynamic> json) => EpdDevice(
    id: json['id'],
    name: json['name'],
    isConnected: json['isConnected'] ?? false,
  );
}