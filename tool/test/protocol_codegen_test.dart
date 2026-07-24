import 'dart:convert';
import 'dart:io';

import '../src/protocol_codegen.dart';

void main() {
  final result = checkProtocolGeneratedOutputs(Directory.current);
  if (!result.isClean) {
    throw StateError(
      'Expected generated protocol outputs to be clean: '
      '${result.differences.join('; ')}',
    );
  }
  final inventoryText = File(
    'compatibility/upstream/phase-2b-tooling-inventory.json',
  ).readAsStringSync();
  final inventory = jsonDecode(inventoryText) as Map<String, Object?>;
  if (inventory['formatVersion'] != 1 ||
      !inventory.containsKey('lsp') ||
      !inventory.containsKey('dap') ||
      !inventory.containsKey('dartTooling')) {
    throw StateError('Phase 2b generated inventory is incomplete.');
  }
  if (inventoryText.contains(Directory.current.absolute.path) ||
      RegExp(r'\d{4}-\d{2}-\d{2}T\d{2}:').hasMatch(inventoryText)) {
    throw StateError(
      'Generated Phase 2b inventory contains unstable local metadata.',
    );
  }
  final analysisInventory = File(
    'packages/dart/lib/src/analysis_server/generated/inventory.g.dart',
  ).readAsStringSync();
  final analysisModels = File(
    'packages/dart/lib/src/analysis_server/generated/models.g.dart',
  ).readAsStringSync();
  if (!analysisInventory.contains('"apiVersion": "1.38.0"') ||
      !analysisInventory.contains('"apiVersion": "1.40.1"') ||
      !analysisInventory.contains('"server.pluginError"') ||
      RegExp(r'final class AnalysisServer').allMatches(analysisModels).length !=
          55) {
    throw StateError(
      'Generated Analysis Server union inventory is incomplete.',
    );
  }
  final dtdInventory = File(
    'packages/dart/lib/src/dtd/generated/inventory.g.dart',
  ).readAsStringSync();
  if (!dtdInventory.contains("dtd-fixed-inventory-v1") ||
      !dtdInventory.contains('"FileSystem.setIDEWorkspaceRoots"') ||
      !dtdInventory.contains('"streamNotify"') ||
      dtdInventory.contains('wireVersion')) {
    throw StateError('Generated DTD fixed inventory is incomplete.');
  }
  final vmInventory = File(
    'packages/dart/lib/src/vm_service/generated/inventory.g.dart',
  ).readAsStringSync();
  final vmModels = File(
    'packages/dart/lib/src/vm_service/generated/models.g.dart',
  ).readAsStringSync();
  if (!vmInventory.contains('"runtimeVersion":"4.16"') ||
      !vmInventory.contains('"runtimeVersion":"4.21"') ||
      !vmInventory.contains('"descriptionVersion":"4.20"') ||
      !vmInventory.contains('"getQueuedMicrotasks"') ||
      RegExp(r'final class VmService').allMatches(vmModels).length != 83) {
    throw StateError('Generated VM Service union inventory is incomplete.');
  }
  stdout.writeln('Protocol generated outputs are deterministic.');
}
