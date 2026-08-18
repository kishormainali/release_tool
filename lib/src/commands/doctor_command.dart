import 'dart:io';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'base_command.dart';
import '../config/release_config.dart';
import '../utils/fastlane_utils.dart';

enum _Level { ok, warn, error }

class _Check {
  final _Level level;
  final String message;
  const _Check(this.level, this.message);
}

/// A command that validates release_config.yaml and the surrounding project
/// setup (tooling, credential files, required fields) before a real
/// deploy/certificates run, surfacing problems up front instead of mid-Fastlane-run.
class DoctorCommand extends BaseCommand {
  @override
  final String name = 'doctor';

  @override
  final String description =
      'Validate release_config.yaml and required tooling before deploying.';

  /// Creates a new [DoctorCommand].
  DoctorCommand({required super.logger}) {
    argParser.addOption(
      'env',
      abbr: 'e',
      help: 'Limit checks to a single environment (defaults to all).',
    );
  }

  @override
  Future<int> run() async {
    if (!checkFlutterProject()) return 1;

    final config = loadConfig();
    if (config == null) return 1;

    if (config.environments.isEmpty) {
      logger.err(
        'No environments found in release_config.yaml. Please configure them first.',
      );
      return 1;
    }

    final envFilter = argResults?['env'] as String?;
    if (envFilter != null && !config.environments.containsKey(envFilter)) {
      logger.err(
        'Environment "$envFilter" is not defined in release_config.yaml.',
      );
      return 1;
    }

    final targetEnvs = envFilter != null
        ? [envFilter]
        : config.environments.keys.toList();

    final hasAndroid = Directory(
      p.join(projectDir.path, 'android'),
    ).existsSync();
    final hasIos = Directory(p.join(projectDir.path, 'ios')).existsSync();

    logger.info('\n${lightCyan.wrap('Running release_tool doctor...')}\n');

    final checks = <_Check>[...await _checkTooling(hasAndroid, hasIos)];

    for (final envName in targetEnvs) {
      final envConfig = config.environments[envName]!;
      logger.info(lightCyan.wrap('Environment: $envName'));

      final envChecks = <_Check>[
        if (hasAndroid) ..._checkAndroid(config, envConfig),
        if (hasIos) ..._checkIos(config, envConfig),
      ];
      for (final check in envChecks) {
        _printCheck(check);
      }
      checks.addAll(envChecks);
      logger.info('');
    }

    final errorCount = checks.where((c) => c.level == _Level.error).length;
    final warnCount = checks.where((c) => c.level == _Level.warn).length;

    if (errorCount == 0 && warnCount == 0) {
      logger.success('All checks passed! Ready to deploy.');
      return 0;
    }
    if (errorCount == 0) {
      logger.warn(
        '$warnCount warning(s) found. Deploys may still succeed, but review them above.',
      );
      return 0;
    }

    logger.err(
      '$errorCount error(s) and $warnCount warning(s) found. Fix the errors above before deploying.',
    );
    return 1;
  }

  void _printCheck(_Check check) {
    switch (check.level) {
      case _Level.ok:
        logger.info('  ${green.wrap('✓')} ${check.message}');
      case _Level.warn:
        logger.info('  ${yellow.wrap('!')} ${check.message}');
      case _Level.error:
        logger.info('  ${red.wrap('✗')} ${check.message}');
    }
  }

  Future<List<_Check>> _checkTooling(bool hasAndroid, bool hasIos) async {
    final checks = <_Check>[];
    logger.info(lightCyan.wrap('Tooling'));

    final fastlaneAvailable = await _isOnPath('fastlane');
    final fastlaneCheck = fastlaneAvailable
        ? const _Check(_Level.ok, 'fastlane is available on PATH.')
        : const _Check(
            _Level.warn,
            'fastlane was not found on PATH. This is fine if every platform '
            'uses a Gemfile with `bundle exec fastlane` instead.',
          );
    _printCheck(fastlaneCheck);
    checks.add(fastlaneCheck);

    for (final platform in [if (hasAndroid) 'android', if (hasIos) 'ios']) {
      final gemfile = File(p.join(projectDir.path, platform, 'Gemfile'));
      if (!gemfile.existsSync()) continue;

      final bundleAvailable = await _isOnPath('bundle');
      final check = bundleAvailable
          ? _Check(
              _Level.ok,
              '$platform/Gemfile found and `bundle` is available on PATH.',
            )
          : _Check(
              _Level.error,
              '$platform/Gemfile found but `bundle` is not on PATH. Install Bundler or remove the Gemfile.',
            );
      _printCheck(check);
      checks.add(check);
    }
    logger.info('');
    return checks;
  }

  Future<bool> _isOnPath(String executable) async {
    try {
      final result = await Process.run(executable, [
        '--version',
      ], runInShell: true);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  List<_Check> _checkAndroid(
    ReleaseConfig config,
    EnvironmentConfig envConfig,
  ) {
    final checks = <_Check>[];
    final androidConfig = envConfig.android;
    final sharedAndroid = config.shared.android;

    if (androidConfig?.packageName == null ||
        androidConfig!.packageName!.isEmpty) {
      checks.add(
        const _Check(_Level.error, 'Android: package_name is required.'),
      );
      return checks;
    }
    checks.add(
      _Check(
        _Level.ok,
        'Android: package_name (${androidConfig.packageName}).',
      ),
    );

    final firebaseServiceJsonFile =
        androidConfig.firebaseServiceJsonFile ??
        sharedAndroid?.firebaseServiceJsonFile ??
        config.shared.firebaseServiceJsonFile;
    final hasFirebaseAppId =
        androidConfig.firebaseAppId != null &&
        androidConfig.firebaseAppId!.isNotEmpty;
    if (!hasFirebaseAppId) {
      checks.add(
        const _Check(
          _Level.warn,
          'Android: firebase_app_id not set — `deploy --target firebase` will fail for this environment.',
        ),
      );
    } else if (!_fileExists(firebaseServiceJsonFile)) {
      checks.add(
        _Check(
          _Level.error,
          'Android: firebase_service_json_file not found at "${firebaseServiceJsonFile ?? '(unset)'}".',
        ),
      );
    } else {
      checks.add(
        const _Check(
          _Level.ok,
          'Android: Firebase App Distribution is configured.',
        ),
      );
    }

    final googlePlayJsonKeyFile =
        androidConfig.googlePlayJsonKeyFile ??
        sharedAndroid?.googlePlayJsonKeyFile;
    if (googlePlayJsonKeyFile == null || googlePlayJsonKeyFile.isEmpty) {
      checks.add(
        const _Check(
          _Level.warn,
          'Android: google_play_json_key_file not set — `deploy --target store` will fail for this environment.',
        ),
      );
    } else if (!_fileExists(googlePlayJsonKeyFile)) {
      checks.add(
        _Check(
          _Level.error,
          'Android: google_play_json_key_file not found at "$googlePlayJsonKeyFile".',
        ),
      );
    } else {
      checks.add(
        const _Check(_Level.ok, 'Android: Play Store upload is configured.'),
      );
    }

    return checks;
  }

  List<_Check> _checkIos(ReleaseConfig config, EnvironmentConfig envConfig) {
    final checks = <_Check>[];
    final iosConfig = envConfig.ios;
    final sharedIos = config.shared.ios;

    if (iosConfig?.bundleId == null || iosConfig!.bundleId!.isEmpty) {
      checks.add(const _Check(_Level.error, 'iOS: bundle_id is required.'));
      return checks;
    }
    checks.add(_Check(_Level.ok, 'iOS: bundle_id (${iosConfig.bundleId}).'));

    final appStoreTeamId =
        iosConfig.appStoreTeamId ?? sharedIos?.appStoreTeamId ?? '';
    if (appStoreTeamId.isEmpty) {
      checks.add(
        const _Check(_Level.error, 'iOS: app_store_team_id is required.'),
      );
    } else {
      checks.add(const _Check(_Level.ok, 'iOS: app_store_team_id is set.'));
    }

    final certificateGitUrl =
        iosConfig.match?.gitUrl ?? sharedIos?.match?.gitUrl ?? '';
    if (certificateGitUrl.isEmpty) {
      checks.add(
        const _Check(
          _Level.error,
          'iOS: match.git_url is required for code signing.',
        ),
      );
    } else {
      checks.add(const _Check(_Level.ok, 'iOS: match.git_url is set.'));
    }

    final ascCredentials = AscCredentials.resolve(
      configKeyId: iosConfig.ascKeyId ?? sharedIos?.ascKeyId,
      configIssuerId: iosConfig.ascIssuerId ?? sharedIos?.ascIssuerId,
      configKeyFilepath: iosConfig.ascKeyFilepath ?? sharedIos?.ascKeyFilepath,
      resolvePath: makeAbsolutePath,
    );
    if (ascCredentials.isComplete) {
      checks.add(
        const _Check(
          _Level.ok,
          'iOS: App Store Connect API credentials resolved.',
        ),
      );
    } else {
      checks.add(
        const _Check(
          _Level.error,
          'iOS: App Store Connect API credentials incomplete (checked asc_key_id/asc_issuer_id/'
          'asc_key_filepath in config, and ASC_*/APP_STORE_CONNECT_API_KEY_* environment variables).',
        ),
      );
    }

    final firebaseServiceJsonFile =
        iosConfig.firebaseServiceJsonFile ??
        sharedIos?.firebaseServiceJsonFile ??
        config.shared.firebaseServiceJsonFile;
    final hasFirebaseAppId =
        iosConfig.firebaseAppId != null && iosConfig.firebaseAppId!.isNotEmpty;
    if (!hasFirebaseAppId) {
      checks.add(
        const _Check(
          _Level.warn,
          'iOS: firebase_app_id not set — `deploy --target firebase` will fail for this environment.',
        ),
      );
    } else if (!_fileExists(firebaseServiceJsonFile)) {
      checks.add(
        _Check(
          _Level.error,
          'iOS: firebase_service_json_file not found at "${firebaseServiceJsonFile ?? '(unset)'}".',
        ),
      );
    } else {
      checks.add(
        const _Check(
          _Level.ok,
          'iOS: Firebase App Distribution is configured.',
        ),
      );
    }

    return checks;
  }

  bool _fileExists(String? path) {
    if (path == null || path.isEmpty) return false;
    final resolved = makeAbsolutePath(path);
    return resolved != null && File(resolved).existsSync();
  }
}
