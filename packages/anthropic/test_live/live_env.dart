import 'dart:io';

/// 读取仓库根 `.env`(用户提供,gitignored)的极简解析:`KEY=VALUE` 行,
/// `#` 开头与空行跳过,VALUE 不去引号(约定值裸写)。文件缺失返回空表。
Map<String, String> loadLiveEnv() {
  // test_live/ 在 packages/anthropic/ 下,仓库根为上两级。
  final file = File('../../.env');
  if (!file.existsSync()) {
    final fromRoot = File('.env');
    if (!fromRoot.existsSync()) return const {};
    return _parse(fromRoot.readAsLinesSync());
  }
  return _parse(file.readAsLinesSync());
}

Map<String, String> _parse(List<String> lines) {
  final env = <String, String>{};
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final eq = trimmed.indexOf('=');
    if (eq <= 0) continue;
    env[trimmed.substring(0, eq).trim()] = trimmed.substring(eq + 1).trim();
  }
  return env;
}
