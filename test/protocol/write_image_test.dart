import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:epd_controller/protocol/epd_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/hex.dart';

Map<String, dynamic> _loadGolden(String name) =>
    jsonDecode(File('test/golden/$name').readAsStringSync()) as Map<String, dynamic>;

void main() {
  group('planWriteImage 与 web 版 writeImage() 逐块一致', () {
    final golden = _loadGolden('write_image.json');
    final cases = (golden['cases'] as List<dynamic>).cast<Map<String, dynamic>>();

    test('golden 向量非空', () {
      expect(cases, isNotEmpty);
    });

    for (final testCase in cases) {
      final inputHex = testCase['input'] as String;
      final mtu = testCase['mtu'] as int;
      final interleavedCount = testCase['interleavedCount'] as int;
      final step = testCase['step'] as String;
      final rleSupport = testCase['rleSupport'] as bool;
      final expectedUseRle = testCase['useRle'] as bool;
      final expectedChunkSize = testCase['chunkSize'] as int;
      final expectedChunks =
          (testCase['chunks'] as List<dynamic>).cast<Map<String, dynamic>>();

      test(
        'len=${inputHex.length ~/ 2} mtu=$mtu interleaved=$interleavedCount '
        'step=$step rle=$rleSupport',
        () {
          final plan = planWriteImage(
            data: hexToBytes(inputHex),
            mtu: mtu,
            plane: step == 'bw' ? ImagePlane.black : ImagePlane.red,
            rleSupported: rleSupport,
            interleavedCount: interleavedCount,
          );

          expect(plan.chunkSize, expectedChunkSize);
          expect(plan.useRle, expectedUseRle);
          expect(plan.totalChunks, expectedChunks.length);

          for (var i = 0; i < expectedChunks.length; i++) {
            final expected = expectedChunks[i];
            expect(plan.chunks[i].flag, expected['flag'], reason: '第 $i 块 flag');
            expect(
              plan.chunks[i].withResponse,
              expected['withResponse'],
              reason: '第 $i 块是否等应答',
            );
            expect(
              bytesToHex(plan.chunks[i].data),
              expected['data'],
              reason: '第 $i 块数据',
            );
          }
        },
      );
    }
  });

  group('命令拼接', () {
    test('无负载命令只有命令字', () {
      expect(buildCommand(EpdCmd.init), Uint8List.fromList(<int>[0x01]));
      expect(buildCommand(EpdCmd.refresh), Uint8List.fromList(<int>[0x05]));
      expect(buildCommand(EpdCmd.clear), Uint8List.fromList(<int>[0x02]));
    });

    test('带负载命令是 [cmd, ...data]', () {
      expect(
        buildCommand(EpdCmd.setPins, <int>[0x0a, 0x0b, 0x0c]),
        Uint8List.fromList(<int>[0x00, 0x0a, 0x0b, 0x0c]),
      );
    });

    test('WRITE_IMG 的完整负载 = [0x30, flag, ...data]', () {
      final chunk = WriteImageChunk(
        flag: 0x0f,
        data: Uint8List.fromList(<int>[0xaa, 0xbb]),
        withResponse: false,
      );
      expect(chunk.toPayload(), Uint8List.fromList(<int>[0x30, 0x0f, 0xaa, 0xbb]));
    });
  });

  group('SET_TIME 负载', () {
    test('4 字节大端时间戳 + 时区小时 + 模式', () {
      final payload = buildSetTimeData(
        unixSeconds: 0x01020304,
        utcOffsetHours: 8,
      );
      expect(
        payload,
        Uint8List.fromList(<int>[0x01, 0x02, 0x03, 0x04, 0x08, 0x01]),
      );
    });

    test('时钟模式对应 mode=2，西半球时区可为负', () {
      final payload = buildSetTimeData(
        unixSeconds: 1763500000,
        utcOffsetHours: -5,
        mode: EpdTimeMode.clock,
      );
      expect(payload.length, 6);
      expect(payload[4], 0xfb); // -5 的补码低字节
      expect(payload[5], 0x02);
    });
  });

  group('参数校验', () {
    test('mtu 小于 3 会报错（web 版这种情况会死循环）', () {
      expect(
        () => planWriteImage(
          data: Uint8List.fromList(<int>[1, 2, 3]),
          mtu: 2,
          plane: ImagePlane.black,
          rleSupported: false,
        ),
        throwsArgumentError,
      );
    });

    test('interleavedCount 至少为 1', () {
      expect(
        () => planWriteImage(
          data: Uint8List.fromList(<int>[1, 2, 3]),
          mtu: 20,
          plane: ImagePlane.black,
          rleSupported: false,
          interleavedCount: 0,
        ),
        throwsArgumentError,
      );
    });

    test('alwaysWithResponse 时每一条都等设备确认（真机防 GATT 133）', () {
      final Uint8List data = Uint8List.fromList(
        List<int>.generate(200, (int i) => i & 0xff),
      );
      final WriteImagePlan webLike = planWriteImage(
        data: data,
        mtu: 247,
        plane: ImagePlane.black,
        rleSupported: false,
        interleavedCount: 50,
      );
      final WriteImagePlan safe = planWriteImage(
        data: data,
        mtu: 247,
        plane: ImagePlane.black,
        rleSupported: false,
        interleavedCount: 50,
        alwaysWithResponse: true,
      );

      // 分块与字节完全一样，只有应答节奏不同。
      expect(safe.chunks.length, webLike.chunks.length);
      expect(safe.chunkSize, webLike.chunkSize);
      for (int i = 0; i < safe.chunks.length; i++) {
        expect(safe.chunks[i].flag, webLike.chunks[i].flag);
        expect(safe.chunks[i].data, webLike.chunks[i].data);
        expect(safe.chunks[i].withResponse, isTrue, reason: '第 $i 块要求应答');
      }
      // web 版节奏下一定有「无响应」的块，两者因此可以区分。
      expect(webLike.chunks.any((WriteImageChunk c) => !c.withResponse), isTrue);
    });
  });
}
