import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

/// One cached "released to store" entry: the version that was deployed and
/// when.
class CachedRelease {
  /// The app version (from pubspec.yaml) that was released.
  final String version;

  /// When the release was recorded.
  final DateTime releasedAt;

  /// Creates a new [CachedRelease].
  const CachedRelease({required this.version, required this.releasedAt});

  /// Executes the [toJson] operation.
  Map<String, dynamic> toJson() => {
    'version': version,
    'releasedAt': releasedAt.toIso8601String(),
  };

  /// Executes the [fromJson] operation.
  factory CachedRelease.fromJson(Map<String, dynamic> json) => CachedRelease(
    version: json['version'] as String,
    releasedAt: DateTime.parse(json['releasedAt'] as String),
  );
}

/// Tracks the most recent store (App Store / Play Store) release per
/// environment and platform, scoped to the target Flutter project (not the
/// user's home directory, since this is per-project state). Lets the
/// `remote-config` command pick up the just-released version without
/// re-reading pubspec.yaml at a different point in time.
class ReleaseCache {
  final File _file;

  /// Creates a new [ReleaseCache] rooted at [projectDir].
  ReleaseCache(Directory projectDir)
    : _file = File(
        p.join(projectDir.path, '.release_tool', 'latest_release_cache.json'),
      );

  Map<String, dynamic> _readRaw() {
    if (!_file.existsSync()) return {};
    try {
      final decoded = jsonDecode(_file.readAsStringSync());
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      return {};
    }
  }

  void _writeRaw(Map<String, dynamic> data) {
    _file.parent.createSync(recursive: true);
    _file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
  }

  /// Records that [version] was just released to the store for [platform]
  /// (`android` or `ios`) in environment [envName].
  void recordRelease({
    required String envName,
    required String platform,
    required String version,
  }) {
    final data = _readRaw();
    final envEntry = Map<String, dynamic>.from(
      data[envName] as Map<String, dynamic>? ?? {},
    );
    envEntry[platform] = CachedRelease(
      version: version,
      releasedAt: DateTime.now(),
    ).toJson();
    data[envName] = envEntry;
    _writeRaw(data);
  }

  /// Returns the cached releases for [envName], keyed by platform. Empty if
  /// none are cached, or if any entries are malformed.
  Map<String, CachedRelease> read(String envName) {
    final envEntry = _readRaw()[envName] as Map<String, dynamic>?;
    if (envEntry == null) return {};

    final result = <String, CachedRelease>{};
    for (final entry in envEntry.entries) {
      try {
        result[entry.key] = CachedRelease.fromJson(
          entry.value as Map<String, dynamic>,
        );
      } catch (_) {
        // Skip malformed entries rather than failing the whole read.
      }
    }
    return result;
  }

  /// Clears the cached release for [platform] in [envName]. If [platform]
  /// is `null`, clears every platform cached for that environment.
  void clear(String envName, {String? platform}) {
    final data = _readRaw();
    if (platform == null) {
      data.remove(envName);
    } else {
      final envEntry = Map<String, dynamic>.from(
        data[envName] as Map<String, dynamic>? ?? {},
      );
      envEntry.remove(platform);
      if (envEntry.isEmpty) {
        data.remove(envName);
      } else {
        data[envName] = envEntry;
      }
    }
    _writeRaw(data);
  }
}
