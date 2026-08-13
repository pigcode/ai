import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    exitCode = 64;
    return;
  }
  final root = Directory(arguments.single);
  final secret = await stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .first
      .timeout(const Duration(seconds: 3));
  if (secret.isEmpty) {
    exitCode = 65;
    return;
  }
  await File('${root.path}/journal.jsonl').writeAsString(
    '${jsonEncode(<String, Object?>{
          'event': 'credential-operation-started',
          'outcome': 'unknown',
        })}\n',
    flush: true,
  );
  await File('${root.path}/snapshot.json').writeAsString(
    jsonEncode(<String, Object?>{
      'credentialMaterialPersisted': false,
      'principalId': 'principal-current',
      'policyVersion': 2,
    }),
    flush: true,
  );
  await File('${root.path}/diagnostic.log').writeAsString(
    'credential operation pending; payload redacted\n',
    flush: true,
  );
  final evidenceId = '$pid-${DateTime.now().microsecondsSinceEpoch}';
  await File('${root.path}/boundary-evidence.json').writeAsString(
    jsonEncode(<String, Object?>{
      'evidenceId': evidenceId,
      'observerPid': pid,
      'phase': 'credential-injected-before-outcome',
      'secretBytesHeldInMemory': utf8.encode(secret).length,
    }),
    flush: true,
  );
  stdout.writeln('BOUNDARY credential-injected $evidenceId');
  await stdout.flush();
  await Completer<void>().future;
}
