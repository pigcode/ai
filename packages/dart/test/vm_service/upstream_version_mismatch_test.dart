import 'package:pigcode_ai_dart/pigcode_ai_dart_vm_service.dart';
import 'package:test/test.dart';

void main() {
  test('runtime 4.21 authority does not hide upstream 4.20 prose drift', () {
    expect(vmServiceCurrentRuntimeVersion.toString(), '4.21');
    expect(vmServiceCurrentDocumentTitleVersion, '4.21');
    expect(vmServiceCurrentDocumentDescriptionVersion, '4.20');
    expect(vmServiceCurrentHasDocumentVersionMismatch, isTrue);
    expect(vmServiceMinimumHasDocumentVersionMismatch, isFalse);
  });
}
