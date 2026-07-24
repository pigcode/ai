import 'dart:io';

import '../src/dart_tooling_inventory.dart';

void main() {
  final inventory = buildDartToolingInventory(Directory.current);
  final minimum = inventory.minimum;
  final current = inventory.current;

  _expect(minimum.sdkRelease == '3.6.0', 'Minimum Dart SDK drift.');
  _expect(minimum.analysisServer.apiVersion == '1.38.0', 'Minimum AS API.');
  _expect(minimum.analysisServer.requestCount == 59, 'Minimum AS requests.');
  _expect(
    minimum.analysisServer.notificationCount == 21,
    'Minimum AS notifications.',
  );
  _expect(minimum.analysisServer.typeCount == 55, 'Minimum AS types.');
  _expect(minimum.analysisServer.enumCount == 16, 'Minimum AS enums.');
  _expect(
    minimum.analysisServer.refactoringKindCount == 9,
    'Minimum AS refactoring kinds.',
  );

  _expect(current.sdkRelease == '3.12.2', 'Current Dart SDK drift.');
  _expect(current.analysisServer.apiVersion == '1.40.1', 'Current AS API.');
  _expect(current.analysisServer.requestCount == 59, 'Current AS requests.');
  _expect(
    current.analysisServer.notificationCount == 22,
    'Current AS notifications.',
  );
  _expect(current.analysisServer.typeCount == 55, 'Current AS types.');
  _expect(current.analysisServer.enumCount == 16, 'Current AS enums.');
  _expect(
    current.analysisServer.refactoringKindCount == 9,
    'Current AS refactoring kinds.',
  );
  _expect(
    current.analysisServer.notificationNames
            .difference(minimum.analysisServer.notificationNames)
            .length ==
        1,
    'Analysis Server union must classify the one current-only notification.',
  );

  _expect(
    minimum.dtd.fixedMethodNames.length == 11 &&
        current.dtd.fixedMethodNames.length == 11,
    'DTD fixed method inventory drift.',
  );
  _expect(
    minimum.dtd.typeNames.length == 3 && current.dtd.typeNames.length == 3,
    'DTD type inventory drift.',
  );
  _expect(
    minimum.dtd.errorCodes.length == 11 && current.dtd.errorCodes.length == 11,
    'DTD error inventory drift.',
  );
  _expect(
    minimum.dtd.hasDynamicServiceEnvelope &&
        current.dtd.hasDynamicServiceEnvelope,
    'DTD dynamic service envelope must remain explicit.',
  );

  _expect(minimum.vmService.authorityVersion == '4.16', 'Minimum VM version.');
  _expect(current.vmService.authorityVersion == '4.21', 'Current VM version.');
  _expect(
    current.vmService.documentedDescriptionVersion == '4.20',
    'Current VM upstream mismatch observation drift.',
  );
  _expect(
    current.vmService.hasDocumentVersionMismatch,
    'Current VM document mismatch must remain classified.',
  );
  _expect(
    minimum.vmService.rpcNames.length == 60 &&
        current.vmService.rpcNames.length == 61,
    'VM Service RPC inventory drift.',
  );
  _expect(
    minimum.vmService.typeNames.length == 81 &&
        current.vmService.typeNames.length == 83,
    'VM Service type inventory drift.',
  );

  stdout.writeln('Dart tooling inventory validation passed.');
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}
