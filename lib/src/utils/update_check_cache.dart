import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

/// Persists the result of the last pub.dev update check so the CLI doesn't
/// hit the network on every single invocation.
class UpdateCheckCache {
  /// How often to re-check pub.dev for a new version.
  static const checkInterval = Duration(hours: 24);

  final File _file;

  /// Creates a new [UpdateCheckCache]. Defaults to
  /// `~/.release_tool/update_check.json`.
  UpdateCheckCache({File? file}) : _file = file ?? _defaultFile();

  static File _defaultFile() {
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    return File(p.join(home, '.release_tool', 'update_check.json'));
  }

  /// Reads the last known latest version, or `null` if there is no cached
  /// result, it is older than [checkInterval], or it can't be read.
  String? read() {
    try {
      if (!_file.existsSync()) return null;
      final data = jsonDecode(_file.readAsStringSync()) as Map<String, dynamic>;
      final checkedAt = DateTime.parse(data['checkedAt'] as String);
      if (DateTime.now().difference(checkedAt) > checkInterval) return null;
      return data['latestVersion'] as String;
    } catch (_) {
      return null;
    }
  }

  /// Persists [latestVersion] as the result of a successful check performed now.
  void write(String latestVersion) {
    try {
      _file.parent.createSync(recursive: true);
      _file.writeAsStringSync(
        jsonEncode({
          'checkedAt': DateTime.now().toIso8601String(),
          'latestVersion': latestVersion,
        }),
      );
    } catch (_) {
      // Non-critical: failing to persist the cache shouldn't break the CLI.
    }
  }
}
