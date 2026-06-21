import 'dart:io';
import 'package:yaml/yaml.dart';
import 'package:yaml_writer/yaml_writer.dart';

/// The [ReleaseConfig] class.
class ReleaseConfig {
  /// The [projectName] property.
  final String projectName;

  /// The [shared] property.
  final SharedConfig shared;

  /// The [environments] property.
  final Map<String, EnvironmentConfig> environments;

  /// Executes the [ReleaseConfig] operation.
  ReleaseConfig({
    required this.projectName,
    required this.shared,
    required this.environments,
  });

  /// Executes the [fromYaml] operation.
  factory ReleaseConfig.fromYaml(String yamlContent) {
    final doc = loadYaml(yamlContent) as YamlMap;
    final projectName = doc['project_name'] as String? ?? 'flutter_app';

    final sharedMap = doc['shared'] as YamlMap?;
    final shared = sharedMap != null
        ? SharedConfig.fromYaml(sharedMap)
        : SharedConfig();

    final envsMap = doc['environments'] as YamlMap?;
    final environments = <String, EnvironmentConfig>{};
    if (envsMap != null) {
      for (final entry in envsMap.entries) {
        final key = entry.key as String;
        final val = entry.value as YamlMap;
        environments[key] = EnvironmentConfig.fromYaml(key, val);
      }
    }

    return ReleaseConfig(
      projectName: projectName,
      shared: shared,
      environments: environments,
    );
  }

  /// Executes the [fromFile] operation.
  factory ReleaseConfig.fromFile(File file) {
    final content = file.readAsStringSync();
    return ReleaseConfig.fromYaml(content);
  }

  /// Executes the [toYamlString] operation.
  String toYamlString() {
    final writer = YamlWriter();
    final data = {
      'project_name': projectName,
      'shared': shared.toMap(),
      'environments': environments.map(
        (key, val) => MapEntry(key, val.toMap()),
      ),
    };
    return writer.write(data);
  }
}

/// The [SharedConfig] class.
class SharedConfig {
  /// The [android] property.
  final SharedAndroidConfig? android;

  /// The [ios] property.
  final SharedIOSConfig? ios;

  /// The [firebaseServiceJsonFile] property.
  final String? firebaseServiceJsonFile;

  /// The [firebaseGroups] property.
  final String? firebaseGroups;

  /// The [dartDefines] property.
  final Map<String, String>? dartDefines;

  /// The [dartDefineFromFile] property.
  final String? dartDefineFromFile;

  /// Executes the [SharedConfig] operation.
  SharedConfig({
    this.android,
    this.ios,
    this.firebaseServiceJsonFile,
    this.firebaseGroups,
    this.dartDefines,
    this.dartDefineFromFile,
  });

  /// Executes the [fromYaml] operation.
  factory SharedConfig.fromYaml(YamlMap map) {
    return SharedConfig(
      android: map['android'] != null
          ? SharedAndroidConfig.fromYaml(map['android'] as YamlMap)
          : null,
      ios: map['ios'] != null
          ? SharedIOSConfig.fromYaml(map['ios'] as YamlMap)
          : null,
      firebaseServiceJsonFile: map['firebase_service_json_file'] as String?,
      firebaseGroups: map['firebase_groups'] as String?,
      dartDefines: _parseDartDefines(map['dart_defines'] ?? map['dart-define']),
      dartDefineFromFile:
          map['dart_define_from_file'] as String? ??
          map['dart-define-from-file'] as String?,
    );
  }

  /// Executes the [toMap] operation.
  Map<String, dynamic> toMap() {
    return {
      if (android != null) 'android': android!.toMap(),
      if (ios != null) 'ios': ios!.toMap(),
      if (firebaseServiceJsonFile != null)
        'firebase_service_json_file': firebaseServiceJsonFile,
      if (firebaseGroups != null) 'firebase_groups': firebaseGroups,
      if (dartDefines != null) 'dart_defines': dartDefines,
      if (dartDefineFromFile != null)
        'dart_define_from_file': dartDefineFromFile,
    };
  }
}

/// The [SharedAndroidConfig] class.
class SharedAndroidConfig {
  /// The [firebaseServiceJsonFile] property.
  final String? firebaseServiceJsonFile;

  /// The [googlePlayJsonKeyFile] property.
  final String? googlePlayJsonKeyFile;

  /// Executes the [SharedAndroidConfig] operation.
  SharedAndroidConfig({
    this.firebaseServiceJsonFile,
    this.googlePlayJsonKeyFile,
  });

  /// Executes the [fromYaml] operation.
  factory SharedAndroidConfig.fromYaml(YamlMap map) {
    return SharedAndroidConfig(
      firebaseServiceJsonFile: map['firebase_service_json_file'] as String?,
      googlePlayJsonKeyFile: map['google_play_json_key_file'] as String?,
    );
  }

  /// Executes the [toMap] operation.
  Map<String, dynamic> toMap() {
    return {
      if (firebaseServiceJsonFile != null)
        'firebase_service_json_file': firebaseServiceJsonFile,
      if (googlePlayJsonKeyFile != null)
        'google_play_json_key_file': googlePlayJsonKeyFile,
    };
  }
}

/// The [SharedIOSConfig] class.
class SharedIOSConfig {
  /// The [appStoreTeamId] property.
  final String? appStoreTeamId;

  /// The [firebaseServiceJsonFile] property.
  final String? firebaseServiceJsonFile;

  /// The [ascKeyId] property.
  final String? ascKeyId;

  /// The [ascIssuerId] property.
  final String? ascIssuerId;

  /// The [ascKeyFilepath] property.
  final String? ascKeyFilepath;

  /// The [match] property.
  final MatchConfig? match;

  /// Executes the [SharedIOSConfig] operation.
  SharedIOSConfig({
    this.appStoreTeamId,
    this.firebaseServiceJsonFile,
    this.ascKeyId,
    this.ascIssuerId,
    this.ascKeyFilepath,
    this.match,
  });

  /// Executes the [fromYaml] operation.
  factory SharedIOSConfig.fromYaml(YamlMap map) {
    return SharedIOSConfig(
      appStoreTeamId: map['app_store_team_id'] as String?,
      firebaseServiceJsonFile: map['firebase_service_json_file'] as String?,
      ascKeyId: map['asc_key_id'] as String?,
      ascIssuerId: map['asc_issuer_id'] as String?,
      ascKeyFilepath: map['asc_key_filepath'] as String?,
      match: map['match'] != null
          ? MatchConfig.fromYaml(map['match'] as YamlMap)
          : null,
    );
  }

  /// Executes the [toMap] operation.
  Map<String, dynamic> toMap() {
    return {
      if (appStoreTeamId != null) 'app_store_team_id': appStoreTeamId,
      if (firebaseServiceJsonFile != null)
        'firebase_service_json_file': firebaseServiceJsonFile,
      if (ascKeyId != null) 'asc_key_id': ascKeyId,
      if (ascIssuerId != null) 'asc_issuer_id': ascIssuerId,
      if (ascKeyFilepath != null) 'asc_key_filepath': ascKeyFilepath,
      if (match != null) 'match': match!.toMap(),
    };
  }
}

/// The [EnvironmentConfig] class.
class EnvironmentConfig {
  /// The [name] property.
  final String name;

  /// The [flavor] property.
  final String? flavor;

  /// The [entryPoint] property.
  final String? entryPoint;

  /// The [android] property.
  final AndroidConfig? android;

  /// The [ios] property.
  final IOSConfig? ios;

  /// The [dartDefines] property.
  final Map<String, String>? dartDefines;

  /// The [dartDefineFromFile] property.
  final String? dartDefineFromFile;

  /// Executes the [EnvironmentConfig] operation.
  EnvironmentConfig({
    required this.name,
    this.flavor,
    this.entryPoint,
    this.android,
    this.ios,
    this.dartDefines,
    this.dartDefineFromFile,
  });

  /// Executes the [fromYaml] operation.
  factory EnvironmentConfig.fromYaml(String name, YamlMap map) {
    return EnvironmentConfig(
      name: name,
      flavor: map['flavor'] as String?,
      entryPoint: map['entry_point'] as String?,
      android: map['android'] != null
          ? AndroidConfig.fromYaml(map['android'] as YamlMap)
          : null,
      ios: map['ios'] != null
          ? IOSConfig.fromYaml(map['ios'] as YamlMap)
          : null,
      dartDefines: _parseDartDefines(map['dart_defines'] ?? map['dart-define']),
      dartDefineFromFile:
          map['dart_define_from_file'] as String? ??
          map['dart-define-from-file'] as String?,
    );
  }

  /// Executes the [toMap] operation.
  Map<String, dynamic> toMap() {
    return {
      if (flavor != null) 'flavor': flavor,
      if (entryPoint != null) 'entry_point': entryPoint,
      if (android != null) 'android': android!.toMap(),
      if (ios != null) 'ios': ios!.toMap(),
      if (dartDefines != null) 'dart_defines': dartDefines,
      if (dartDefineFromFile != null)
        'dart_define_from_file': dartDefineFromFile,
    };
  }
}

/// The [AndroidConfig] class.
class AndroidConfig {
  /// The [packageName] property.
  final String? packageName;

  /// The [firebaseAppId] property.
  final String? firebaseAppId;

  /// The [firebaseGroups] property.
  final String? firebaseGroups;

  /// The [firebaseServiceJsonFile] property.
  final String? firebaseServiceJsonFile;

  /// The [googlePlayJsonKeyFile] property.
  final String? googlePlayJsonKeyFile;

  /// Executes the [AndroidConfig] operation.
  AndroidConfig({
    this.packageName,
    this.firebaseAppId,
    this.firebaseGroups,
    this.firebaseServiceJsonFile,
    this.googlePlayJsonKeyFile,
  });

  /// Executes the [fromYaml] operation.
  factory AndroidConfig.fromYaml(YamlMap map) {
    return AndroidConfig(
      packageName: map['package_name'] as String?,
      firebaseAppId: map['firebase_app_id'] as String?,
      firebaseGroups: map['firebase_groups'] as String?,
      firebaseServiceJsonFile: map['firebase_service_json_file'] as String?,
      googlePlayJsonKeyFile: map['google_play_json_key_file'] as String?,
    );
  }

  /// Executes the [toMap] operation.
  Map<String, dynamic> toMap() {
    return {
      if (packageName != null) 'package_name': packageName,
      if (firebaseAppId != null) 'firebase_app_id': firebaseAppId,
      if (firebaseGroups != null) 'firebase_groups': firebaseGroups,
      if (firebaseServiceJsonFile != null)
        'firebase_service_json_file': firebaseServiceJsonFile,
      if (googlePlayJsonKeyFile != null)
        'google_play_json_key_file': googlePlayJsonKeyFile,
    };
  }
}

/// The [IOSConfig] class.
class IOSConfig {
  /// The [bundleId] property.
  final String? bundleId;

  /// The [firebaseAppId] property.
  final String? firebaseAppId;

  /// The [firebaseGroups] property.
  final String? firebaseGroups;

  /// The [scheme] property.
  final String? scheme;

  /// The [appStoreTeamId] property.
  final String? appStoreTeamId;

  /// The [firebaseServiceJsonFile] property.
  final String? firebaseServiceJsonFile;

  /// The [ascKeyId] property.
  final String? ascKeyId;

  /// The [ascIssuerId] property.
  final String? ascIssuerId;

  /// The [ascKeyFilepath] property.
  final String? ascKeyFilepath;

  /// The [match] property.
  final MatchConfig? match;

  /// Executes the [IOSConfig] operation.
  IOSConfig({
    this.bundleId,
    this.firebaseAppId,
    this.firebaseGroups,
    this.scheme,
    this.appStoreTeamId,
    this.firebaseServiceJsonFile,
    this.ascKeyId,
    this.ascIssuerId,
    this.ascKeyFilepath,
    this.match,
  });

  /// Executes the [fromYaml] operation.
  factory IOSConfig.fromYaml(YamlMap map) {
    return IOSConfig(
      bundleId: map['bundle_id'] as String?,
      firebaseAppId: map['firebase_app_id'] as String?,
      firebaseGroups: map['firebase_groups'] as String?,
      scheme: map['scheme'] as String?,
      appStoreTeamId: map['app_store_team_id'] as String?,
      firebaseServiceJsonFile: map['firebase_service_json_file'] as String?,
      ascKeyId: map['asc_key_id'] as String?,
      ascIssuerId: map['asc_issuer_id'] as String?,
      ascKeyFilepath: map['asc_key_filepath'] as String?,
      match: map['match'] != null
          ? MatchConfig.fromYaml(map['match'] as YamlMap)
          : null,
    );
  }

  /// Executes the [toMap] operation.
  Map<String, dynamic> toMap() {
    return {
      if (bundleId != null) 'bundle_id': bundleId,
      if (firebaseAppId != null) 'firebase_app_id': firebaseAppId,
      if (firebaseGroups != null) 'firebase_groups': firebaseGroups,
      if (scheme != null) 'scheme': scheme,
      if (appStoreTeamId != null) 'app_store_team_id': appStoreTeamId,
      if (firebaseServiceJsonFile != null)
        'firebase_service_json_file': firebaseServiceJsonFile,
      if (ascKeyId != null) 'asc_key_id': ascKeyId,
      if (ascIssuerId != null) 'asc_issuer_id': ascIssuerId,
      if (ascKeyFilepath != null) 'asc_key_filepath': ascKeyFilepath,
      if (match != null) 'match': match!.toMap(),
    };
  }
}

Map<String, String>? _parseDartDefines(dynamic value) {
  if (value == null) return null;
  final map = <String, String>{};
  if (value is YamlMap) {
    for (final entry in value.entries) {
      map[entry.key.toString()] = entry.value.toString();
    }
  } else if (value is YamlList) {
    for (final item in value) {
      final itemStr = item.toString();
      final idx = itemStr.indexOf('=');
      if (idx != -1) {
        final key = itemStr.substring(0, idx).trim();
        final val = itemStr.substring(idx + 1).trim();
        map[key] = val;
      } else {
        map[itemStr.trim()] = '';
      }
    }
  } else if (value is Map) {
    for (final entry in value.entries) {
      map[entry.key.toString()] = entry.value.toString();
    }
  } else if (value is List) {
    for (final item in value) {
      final itemStr = item.toString();
      final idx = itemStr.indexOf('=');
      if (idx != -1) {
        final key = itemStr.substring(0, idx).trim();
        final val = itemStr.substring(idx + 1).trim();
        map[key] = val;
      } else {
        map[itemStr.trim()] = '';
      }
    }
  }
  return map.isEmpty ? null : map;
}

/// The [MatchConfig] class.
class MatchConfig {
  /// The [gitUrl] property.
  final String? gitUrl;

  /// The [gitBranch] property.
  final String? gitBranch;

  /// The [password] property.
  final String? password;

  /// Executes the [MatchConfig] operation.
  MatchConfig({this.gitUrl, this.gitBranch, this.password});

  /// Executes the [fromYaml] operation.
  factory MatchConfig.fromYaml(YamlMap map) {
    return MatchConfig(
      gitUrl: map['git_url'] as String?,
      gitBranch: map['git_branch'] as String?,
      password: map['password'] as String?,
    );
  }

  /// Executes the [toMap] operation.
  Map<String, dynamic> toMap() {
    return {
      if (gitUrl != null) 'git_url': gitUrl,
      if (gitBranch != null) 'git_branch': gitBranch,
      if (password != null) 'password': password,
    };
  }
}
