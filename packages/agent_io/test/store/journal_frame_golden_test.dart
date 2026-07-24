import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:test/test.dart';

import 'store_test_support.dart';

void main() {
  test('sealed segment matches the checked-in v1 binary golden', () {
    final golden = File.fromUri(
      _packageRoot().uri.resolve('test/fixtures/store/segment-v1.bin'),
    ).readAsBytesSync();

    expect(testSealedSegment(), golden);
    expect(golden.sublist(0, 4), ascii.encode('PIGJ'));
    expect(
      _u32(golden, 4),
      agentSegmentHeaderLength,
    );
    expect(
      golden.sublist(
        golden.length - agentSegmentFooterLength,
        golden.length - agentSegmentFooterLength + 4,
      ),
      ascii.encode('PIGF'),
    );
  });

  test('segment digest uses the independent ADR preimage', () {
    final bytes = testSealedSegment();
    final footerOffset = bytes.length - agentSegmentFooterLength;
    const footerPrefixLength = 60;
    final independent = sha256.convert(<int>[
      ...ascii.encode('pigcode-agent-segment-v1'),
      0,
      ...bytes.sublist(0, footerOffset),
      ...bytes.sublist(
        footerOffset,
        footerOffset + footerPrefixLength,
      ),
    ]).bytes;
    final stored = bytes.sublist(
      footerOffset + footerPrefixLength,
      footerOffset + footerPrefixLength + 32,
    );

    expect(stored, independent);
    expect(
      const JournalFrameCodec()
          .decodeSegment(bytes, requireSealed: true)
          .segmentDigest,
      independent,
    );
  });
}

Directory _packageRoot() {
  var current = Directory.current.absolute;
  while (true) {
    final nested = Directory.fromUri(
      current.uri.resolve('packages/agent_io/'),
    );
    if (File.fromUri(nested.uri.resolve('pubspec.yaml')).existsSync()) {
      return nested;
    }
    if (current.path.endsWith('agent_io') &&
        File.fromUri(current.uri.resolve('pubspec.yaml')).existsSync()) {
      return current;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('Unable to locate agent_io package root.');
    }
    current = parent;
  }
}

int _u32(Uint8List bytes, int offset) =>
    ByteData.sublistView(bytes, offset, offset + 4).getUint32(0, Endian.big);
