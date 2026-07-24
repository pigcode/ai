// ignore_for_file: unnecessary_type_check

import 'package:pigcode_ai_dart/pigcode_ai_dart.dart' as umbrella;
import 'package:pigcode_ai_dart/pigcode_ai_dart_analysis_server.dart'
    as analysis;
import 'package:pigcode_ai_dart/pigcode_ai_dart_dtd.dart' as dtd;
import 'package:pigcode_ai_dart/pigcode_ai_dart_vm_service.dart' as vm;
import 'package:test/test.dart';

void main() {
  test('portable entrypoints expose separate protocol surfaces', () {
    const analysisVersion = analysis.AnalysisServerApiVersion(1, 40, 1);
    const dtdPolicy = dtd.DtdInventoryPolicy(
      inventoryRevision: 'dtd-inventory-v1',
    );
    const vmVersion = vm.VmServiceWireVersion(4, 21);

    expect(analysisVersion is analysis.AnalysisServerApiVersion, isTrue);
    expect(dtdPolicy is dtd.DtdInventoryPolicy, isTrue);
    expect(vmVersion is vm.VmServiceWireVersion, isTrue);
  });

  test('umbrella explicitly re-exports all three portable surfaces', () {
    const analysisVersion = umbrella.AnalysisServerApiVersion(1, 40, 1);
    const dtdPolicy = umbrella.DtdInventoryPolicy(
      inventoryRevision: 'dtd-inventory-v1',
    );
    const vmVersion = umbrella.VmServiceWireVersion(4, 21);

    expect(analysisVersion.toString(), '1.40.1');
    expect(dtdPolicy.inventoryRevision, 'dtd-inventory-v1');
    expect(vmVersion.toString(), '4.21');
  });
}
