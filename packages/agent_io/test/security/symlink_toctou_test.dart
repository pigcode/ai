import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:test/test.dart';

void main() {
  test('P4-TM-PATH-02 Host rejects symlink and hardlink aliases', () {
    final temp = Directory.systemTemp.createTempSync('pigcode_link_');
    try {
      final root = Directory('${temp.path}/root')..createSync();
      final outside = File('${temp.path}/outside')..writeAsStringSync('secret');
      Link('${root.path}/symlink').createSync(outside.path);
      _createHardLink(outside.path, '${root.path}/hardlink');
      final fs = HostWorkspaceFileSystem(<HostWorkspaceRoot>[
        HostWorkspaceRoot(
          name: 'workspace',
          path: root.path,
          access: SandboxPathAccess.readWrite,
        ),
      ]);

      expect(
        () => fs.readText('workspace', 'symlink'),
        throwsA(isA<HostCapabilityException>()),
      );
      expect(
        () => fs.readText('workspace', 'hardlink'),
        throwsA(isA<HostCapabilityException>()),
      );
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

  test('P4-TM-PATH-02 hardlink alias is rejected before truncation', () {
    final temp = Directory.systemTemp.createTempSync('pigcode_link_');
    try {
      final root = Directory('${temp.path}/root')..createSync();
      final outside = File('${temp.path}/outside')
        ..writeAsStringSync('linked-secret');
      _createHardLink(outside.path, '${root.path}/alias');
      final fs = HostWorkspaceFileSystem(<HostWorkspaceRoot>[
        HostWorkspaceRoot(
          name: 'workspace',
          path: root.path,
          access: SandboxPathAccess.readWrite,
        ),
      ]);

      expect(
        () => fs.writeText('workspace', 'alias', 'overwritten'),
        throwsA(
          isA<HostCapabilityException>().having(
            (error) => error.rule,
            'rule',
            'hardlink-denied',
          ),
        ),
      );
      // The denial must happen before any destructive open: the linked
      // inode outside the workspace keeps its original content.
      expect(outside.readAsStringSync(), 'linked-secret');
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

  test('P4-TM-PATH-03 openat/no-follow defeats check-then-swap', () async {
    final temp = Directory.systemTemp.createTempSync('pigcode_swap_');
    ReceivePort? events;
    StreamIterator<Object?>? iterator;
    Isolate? swapper;
    try {
      final root = Directory('${temp.path}/root')..createSync();
      final target = File('${root.path}/target')..writeAsStringSync('safe');
      final outside = File('${temp.path}/outside')..writeAsStringSync('secret');
      final fs = HostWorkspaceFileSystem(<HostWorkspaceRoot>[
        HostWorkspaceRoot(
          name: 'workspace',
          path: root.path,
          access: SandboxPathAccess.readWrite,
        ),
      ]);
      events = ReceivePort();
      swapper = await Isolate.spawn<List<Object>>(
        _swapFixture,
        <Object>[target.path, outside.path, events.sendPort],
      );
      iterator = StreamIterator<Object?>(events);
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current, 'ready');
      for (var attempt = 0; attempt < 300; attempt += 1) {
        try {
          expect(fs.readText('workspace', 'target'), isNot(contains('secret')));
        } on HostCapabilityException catch (error) {
          expect(error.code, HostCapabilityError.pathDenied);
        }
      }
      expect(
        await iterator.moveNext().timeout(const Duration(seconds: 3)),
        isTrue,
      );
      expect(iterator.current, 'done');
    } finally {
      await iterator?.cancel();
      events?.close();
      swapper?.kill(priority: Isolate.immediate);
      temp.deleteSync(recursive: true);
    }
  });

  test(
    'P4-TM-PATH-02 Seatbelt kernel rejects outside symlink with Host bypassed',
    () async {
      final temp = Directory.systemTemp.createTempSync('pigcode_link_');
      try {
        final root = Directory('${temp.path}/root')..createSync();
        final outside = File('${temp.path}/outside')
          ..writeAsStringSync('kernel-secret');
        final link = Link('${root.path}/link')..createSync(outside.path);
        final process = await SeatbeltSandboxBackend(
          unsafeStandaloneStart: true,
        ).start(
          SandboxPolicy(
            roots: <SandboxPathRule>[
              SandboxPathRule(
                path: root.path,
                access: SandboxPathAccess.readOnly,
              ),
            ],
          ),
          HostCommand(
            executable: '/bin/cat',
            arguments: <String>[link.path],
          ),
        );
        final output = utf8.decoder.bind(process.stdout).join();
        process.stderr.drain<void>();
        expect(await process.exitCode, isNot(0));
        expect(await output, isNot(contains('kernel-secret')));
      } finally {
        temp.deleteSync(recursive: true);
      }
    },
    skip: Platform.isMacOS
        ? false
        : 'SKIP-MANIFEST PATH-03 platform=${Platform.operatingSystem} '
            'backend=seatbelt-required',
  );
}

void _swapFixture(List<Object> arguments) {
  final target = arguments[0] as String;
  final outside = arguments[1] as String;
  final events = arguments[2] as SendPort;
  events.send('ready');
  for (var attempt = 0; attempt < 500; attempt += 1) {
    try {
      File(target).deleteSync();
    } on FileSystemException {
      try {
        Link(target).deleteSync();
      } on FileSystemException {
        // The reader can hold the previous inode while the alias is swapped.
      }
    }
    try {
      Link(target).createSync(outside);
      Link(target).deleteSync();
    } on FileSystemException {
      // Continue racing until the bounded fixture completes.
    }
    try {
      File(target).writeAsStringSync('safe');
    } on FileSystemException {
      // Continue racing until the bounded fixture completes.
    }
  }
  events.send('done');
}

void _createHardLink(String source, String target) {
  final library = DynamicLibrary.process();
  final calloc = library.lookupFunction<Pointer<Void> Function(Uint64, Uint64),
      Pointer<Void> Function(int, int)>('calloc');
  final free = library.lookupFunction<Void Function(Pointer<Void>),
      void Function(Pointer<Void>)>('free');
  final link = library.lookupFunction<
      Int32 Function(Pointer<Uint8>, Pointer<Uint8>),
      int Function(Pointer<Uint8>, Pointer<Uint8>)>('link');
  Pointer<Uint8> native(String value) {
    final bytes = <int>[...utf8.encode(value), 0];
    final pointer = calloc(bytes.length, 1).cast<Uint8>();
    pointer.asTypedList(bytes.length).setAll(0, bytes);
    return pointer;
  }

  final sourcePointer = native(source);
  final targetPointer = native(target);
  try {
    if (link(sourcePointer, targetPointer) != 0) {
      throw StateError('hardlink fixture creation failed');
    }
  } finally {
    free(sourcePointer.cast<Void>());
    free(targetPointer.cast<Void>());
  }
}
