import 'dart:convert';

import 'package:test/test.dart';

import '../run_workspace_tests.dart';

void main() {
  test('package inactivity budget resets when structured progress arrives', () {
    var now = DateTime.utc(2026);
    final activity = WorkspaceTestActivity(now: () => now);

    now = now.add(const Duration(minutes: 1, seconds: 59));
    expect(activity.hasExpired(const Duration(minutes: 2)), isFalse);

    activity.recordProgress();
    now = now.add(const Duration(minutes: 1, seconds: 59));
    expect(activity.hasExpired(const Duration(minutes: 2)), isFalse);

    now = now.add(const Duration(seconds: 2));
    expect(activity.hasExpired(const Duration(minutes: 2)), isTrue);
  });

  test('non-JSON shutdown status is retained instead of crashing the runner',
      () {
    final diagnostics = <String>[];

    expect(
      decodeWorkspaceTestEvent(
        'Waiting for current test(s) to finish.',
        diagnostics,
      ),
      isNull,
    );
    expect(diagnostics, <String>['Waiting for current test(s) to finish.']);
    expect(
      decodeWorkspaceTestEvent(
        jsonEncode(<String, Object?>{'type': 'done', 'success': false}),
        diagnostics,
      ),
      <String, Object?>{'type': 'done', 'success': false},
    );
  });
}
