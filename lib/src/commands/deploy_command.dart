import 'dart:convert';
import 'dart:io';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'base_command.dart';
import '../config/release_config.dart';
import '../utils/process_utils.dart';
import '../utils/version_utils.dart';

/// A command to build and deploy Flutter applications.
class DeployCommand extends BaseCommand {
  @override
  final String name = 'deploy';

  @override
  final String description =
      'Build and deploy Flutter applications using Fastlane.';

  /// Creates a new [DeployCommand].
  DeployCommand({required super.logger}) {
    argParser.addOption(
      'env',
      abbr: 'e',
      help:
          'The environment configuration to deploy (e.g. dev, staging, prod).',
    );
    argParser.addOption(
      'platform',
      abbr: 'p',
      allowed: ['android', 'ios', 'both'],
      help: 'The platform to build and deploy.',
    );
    argParser.addOption(
      'target',
      abbr: 't',
      allowed: ['firebase', 'store'],
      help:
          'The deployment target (firebase app distribution or app store / play store).',
    );
    argParser.addOption(
      'bump',
      abbr: 'b',
      allowed: ['major', 'minor', 'patch', 'build'],
      help:
          'Version bump type to execute in Fastlane (defaults to build number increment).',
    );
    argParser.addOption(
      'release-notes',
      abbr: 'r',
      defaultsTo: 'New build uploaded via Centralized Release Tool.',
      help:
          'Release notes to display in Firebase App Distribution or store changelogs.',
    );
    argParser.addFlag(
      'dry-run',
      negatable: false,
      help:
          'Verify configurations and build outputs without running Fastlane deployment.',
    );
    argParser.addFlag(
      'yes',
      abbr: 'y',
      negatable: false,
      help: 'Skip confirmation prompts (useful in CI/CD).',
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

    final isInteractive = stdin.hasTerminal;

    // 1. Resolve Environment
    String? envName = argResults?['env'] as String?;
    if (envName == null) {
      if (!isInteractive) {
        logger.err(
          'Missing required option --env in non-interactive environment.',
        );
        return 1;
      }
      envName = logger.chooseOne(
        'Select target environment:',
        choices: config.environments.keys.toList(),
      );
    }

    final envConfig = config.environments[envName];
    if (envConfig == null) {
      logger.err(
        'Environment "$envName" is not defined in release_config.yaml.',
      );
      return 1;
    }

    // 2. Resolve Platform
    String? platform = argResults?['platform'] as String?;
    if (platform == null) {
      if (!isInteractive) {
        logger.err(
          'Missing required option --platform in non-interactive environment.',
        );
        return 1;
      }
      platform = logger.chooseOne(
        'Select target platform:',
        choices: ['android', 'ios', 'both'],
      );
    }

    // 3. Resolve Target
    String? deployTarget = argResults?['target'] as String?;
    if (deployTarget == null) {
      if (!isInteractive) {
        logger.err(
          'Missing required option --target in non-interactive environment.',
        );
        return 1;
      }
      deployTarget = logger.chooseOne(
        'Select deployment target:',
        choices: ['firebase', 'store'],
      );
    }

    final selectedPlatform = platform!;
    final target = deployTarget!;
    final bump = argResults?['bump'] as String?;
    final releaseNotes = argResults?['release-notes'] as String;
    final isDryRun = argResults?['dry-run'] as bool? ?? false;

    // Platform validation checks
    if ((selectedPlatform == 'android' || selectedPlatform == 'both') &&
        !Directory(p.join(projectDir.path, 'android')).existsSync()) {
      logger.err('Android project folder not found, but android was targeted.');
      return 1;
    }
    if ((selectedPlatform == 'ios' || selectedPlatform == 'both') &&
        !Directory(p.join(projectDir.path, 'ios')).existsSync()) {
      logger.err('iOS project folder not found, but ios was targeted.');
      return 1;
    }

    final currentVersion = VersionUtils.readVersionFromPubspec(pubspecFile);
    logger.info('\n${lightCyan.wrap('Starting deployment pipeline:')}');
    logger.info('  Environment:   ${green.wrap(envName)}');
    logger.info('  Platform(s):   ${green.wrap(selectedPlatform)}');
    logger.info('  Target:        ${green.wrap(target)}');
    logger.info(
      '  Bump Type:     ${bump != null ? green.wrap(bump) : yellow.wrap('build (default)')}',
    );
    logger.info('  App Version:   ${green.wrap(currentVersion)}');
    logger.info(
      '  Dry Run:       ${isDryRun ? yellow.wrap('Enabled') : 'Disabled'}',
    );
    logger.info('  Release Notes: "$releaseNotes"\n');

    final skipConfirmation =
        (argResults?['yes'] as bool? ?? false) || !isInteractive;
    var confirm = true;
    if (!skipConfirmation) {
      confirm = logger.confirm('Proceed with deployment?', defaultValue: true);
    }
    if (!confirm) {
      logger.info('Deployment aborted.');
      return 0;
    }

    final stopWatch = Stopwatch()..start();

    if (selectedPlatform == 'both') {
      logger.info(
        'Initiating parallel builds and deployments for Android and iOS...',
      );

      final results = await Future.wait([
        _deployAndroid(config, envConfig, target, releaseNotes, bump, isDryRun),
        _deployIos(config, envConfig, target, releaseNotes, bump, isDryRun),
      ]);

      stopWatch.stop();

      if (results.any((code) => code != 0)) {
        logger.err(
          '\nDeployment completed with errors (Duration: ${stopWatch.elapsed.inMinutes}m).',
        );
        return 1;
      }
    } else if (selectedPlatform == 'android') {
      final code = await _deployAndroid(
        config,
        envConfig,
        target,
        releaseNotes,
        bump,
        isDryRun,
      );
      stopWatch.stop();
      if (code != 0) return code;
    } else if (selectedPlatform == 'ios') {
      final code = await _deployIos(
        config,
        envConfig,
        target,
        releaseNotes,
        bump,
        isDryRun,
      );
      stopWatch.stop();
      if (code != 0) return code;
    }

    logger.success(
      '\n🎉 Deployment pipeline successfully finished! (Total Duration: ${stopWatch.elapsed.inMinutes}m)',
    );
    return 0;
  }

  // ==========================================
  // Android Deploy Pipeline
  // ==========================================
  Future<int> _deployAndroid(
    ReleaseConfig releaseConfig,
    EnvironmentConfig envConfig,
    String target,
    String releaseNotes,
    String? bump,
    bool isDryRun,
  ) async {
    final prefix = '\x1B[32m[Android]\x1B[0m';
    final androidConfig = envConfig.android;
    final sharedAndroid = releaseConfig.shared.android;

    // Inheritance: environment config overrides shared config
    final firebaseServiceJsonFile =
        androidConfig?.firebaseServiceJsonFile ??
        sharedAndroid?.firebaseServiceJsonFile ??
        releaseConfig.shared.firebaseServiceJsonFile;
    final googlePlayJsonKeyFile =
        androidConfig?.googlePlayJsonKeyFile ??
        sharedAndroid?.googlePlayJsonKeyFile;

    final firebaseGroups =
        androidConfig?.firebaseGroups ??
        releaseConfig.shared.firebaseGroups ??
        '';

    final dartDefines = <String, String>{};
    if (releaseConfig.shared.dartDefines != null) {
      dartDefines.addAll(releaseConfig.shared.dartDefines!);
    }
    if (envConfig.dartDefines != null) {
      dartDefines.addAll(envConfig.dartDefines!);
    }

    final dartDefineFromFile =
        envConfig.dartDefineFromFile ??
        releaseConfig.shared.dartDefineFromFile ??
        (envConfig.flavor != null && envConfig.flavor!.isNotEmpty
            ? '.env.${envConfig.flavor}'
            : '.env');

    final envVars = <String, String>{
      ...Platform.environment,
      'GOOGLE_PLAY_JSON_KEY_FILE':
          makeAbsolutePath(googlePlayJsonKeyFile) ?? '',
      'SKIP_PLAY_STORE_CHECK': 'false',
      'RELEASE_STATUS': 'completed',
      'PACKAGE_NAME': androidConfig?.packageName ?? '',
      'FLUTTER_TARGET': envConfig.entryPoint ?? 'lib/main.dart',
      'FLUTTER_FLAVOR': envConfig.flavor ?? '',
      'FIREBASE_SERVICE_JSON_FILE':
          makeAbsolutePath(firebaseServiceJsonFile) ?? '',
      'FIREBASE_APP_ID': androidConfig?.firebaseAppId ?? '',
      'FIREBASE_TESTERS_GROUPS': firebaseGroups,
      'RELEASE_NOTES': releaseNotes,
      'DART_DEFINES': jsonEncode(dartDefines),
      'DART_DEFINE_FROM_FILE': makeAbsolutePath(dartDefineFromFile) ?? '',
    };

    final fastlaneLane = target == 'store' ? 'play_store' : 'firebase';

    // Configuration Validations
    if (androidConfig?.packageName == null ||
        androidConfig!.packageName!.isEmpty) {
      logger.err(
        '$prefix Validation failed: android.package_name is required.',
      );
      return 1;
    }
    if (target == 'firebase' &&
        (androidConfig.firebaseAppId == null ||
            androidConfig.firebaseAppId!.isEmpty)) {
      logger.err(
        '$prefix Validation failed: target "firebase" requires android.firebase_app_id.',
      );
      return 1;
    }
    if (target == 'store' &&
        (googlePlayJsonKeyFile == null || googlePlayJsonKeyFile.isEmpty)) {
      logger.err(
        '$prefix Validation failed: target "store" requires android.google_play_json_key_file.',
      );
      return 1;
    }

    final fastlaneCmd = await _getFastlaneCommand('android');

    final arguments = [
      ...fastlaneCmd.sublist(1),
      fastlaneLane,
      if (bump != null && bump.isNotEmpty) 'release:$bump',
    ];

    if (isDryRun) {
      logger.info(
        '$prefix [Dry Run] Would run command: ${fastlaneCmd.first} ${arguments.join(' ')}',
      );
      logger.info(
        '$prefix [Dry Run] In directory: ${p.join(projectDir.path, 'android')}',
      );
      logger.info('$prefix [Dry Run] With environment variables:');
      envVars.forEach((key, val) {
        if (key.startsWith('GOOGLE_PLAY') ||
            key.startsWith('FIREBASE') ||
            key.startsWith('PACKAGE') ||
            key.startsWith('FLUTTER') ||
            key == 'RELEASE_STATUS') {
          logger.info('  $key: $val');
        }
      });
      return 0;
    }

    logger.info(
      '$prefix Launching Fastlane deployment (lane: $fastlaneLane)...',
    );

    final fastlaneCode = await ProcessUtils.runWithPrefix(
      executable: fastlaneCmd.first,
      arguments: arguments,
      prefix: prefix,
      workingDirectory: p.join(projectDir.path, 'android'),
      environment: envVars,
    );

    if (fastlaneCode != 0) {
      logger.err(
        '$prefix Fastlane deployment failed with exit code $fastlaneCode.',
      );
    } else {
      logger.success('$prefix Deployment completed successfully!');
    }

    return fastlaneCode;
  }

  // ==========================================
  // iOS Deploy Pipeline
  // ==========================================
  Future<int> _deployIos(
    ReleaseConfig releaseConfig,
    EnvironmentConfig envConfig,
    String target,
    String releaseNotes,
    String? bump,
    bool isDryRun,
  ) async {
    final prefix = '\x1B[36m[iOS]\x1B[0m';
    final iosConfig = envConfig.ios;
    final sharedIos = releaseConfig.shared.ios;

    // Inheritance: environment config overrides shared config
    final firebaseServiceJsonFile =
        iosConfig?.firebaseServiceJsonFile ??
        sharedIos?.firebaseServiceJsonFile ??
        releaseConfig.shared.firebaseServiceJsonFile;
    final appStoreTeamId =
        iosConfig?.appStoreTeamId ?? sharedIos?.appStoreTeamId ?? '';
    final certificateGitUrl =
        iosConfig?.match?.gitUrl ?? sharedIos?.match?.gitUrl ?? '';
    final certificateGitBranch =
        iosConfig?.match?.gitBranch ?? sharedIos?.match?.gitBranch ?? 'master';
    final scheme = iosConfig?.scheme ?? envConfig.flavor ?? '';

    String ascKeyId = iosConfig?.ascKeyId ?? sharedIos?.ascKeyId ?? '';
    if (ascKeyId.isEmpty) {
      ascKeyId =
          Platform.environment['ASC_KEY_ID'] ??
          Platform.environment['APP_STORE_CONNECT_API_KEY_KEY_ID'] ??
          '';
    }

    String ascIssuerId = iosConfig?.ascIssuerId ?? sharedIos?.ascIssuerId ?? '';
    if (ascIssuerId.isEmpty) {
      ascIssuerId =
          Platform.environment['ASC_ISSUER_ID'] ??
          Platform.environment['APP_STORE_CONNECT_API_KEY_ISSUER_ID'] ??
          '';
    }

    String? ascKeyFilepath =
        iosConfig?.ascKeyFilepath ?? sharedIos?.ascKeyFilepath;
    if (ascKeyFilepath == null || ascKeyFilepath.isEmpty) {
      ascKeyFilepath =
          Platform.environment['ASC_KEY_FILEPATH'] ??
          Platform.environment['APP_STORE_CONNECT_API_KEY_KEY_FILEPATH'];
    }

    String? ascKeyContentBase64;
    if (ascKeyFilepath != null && ascKeyFilepath.isNotEmpty) {
      final keyFile = File(makeAbsolutePath(ascKeyFilepath) ?? '');
      if (keyFile.existsSync()) {
        try {
          final bytes = keyFile.readAsBytesSync();
          ascKeyContentBase64 = base64.encode(bytes);
        } catch (_) {}
      } else {
        logger.detail(
          '$prefix App Store Connect key file not found at: $ascKeyFilepath',
        );
      }
    }

    if (ascKeyContentBase64 == null || ascKeyContentBase64.isEmpty) {
      final envKeyContent =
          Platform.environment['ASC_KEY_CONTENT'] ??
          Platform.environment['APP_STORE_CONNECT_API_KEY_KEY'];
      if (envKeyContent != null && envKeyContent.isNotEmpty) {
        if (envKeyContent.contains('-----BEGIN')) {
          try {
            ascKeyContentBase64 = base64.encode(
              utf8.encode(envKeyContent.trim()),
            );
          } catch (_) {}
        } else {
          ascKeyContentBase64 = envKeyContent.trim();
        }
      }
    }

    final firebaseGroups =
        iosConfig?.firebaseGroups ?? releaseConfig.shared.firebaseGroups ?? '';

    final dartDefines = <String, String>{};
    if (releaseConfig.shared.dartDefines != null) {
      dartDefines.addAll(releaseConfig.shared.dartDefines!);
    }
    if (envConfig.dartDefines != null) {
      dartDefines.addAll(envConfig.dartDefines!);
    }

    final dartDefineFromFile =
        envConfig.dartDefineFromFile ??
        releaseConfig.shared.dartDefineFromFile ??
        (envConfig.flavor != null && envConfig.flavor!.isNotEmpty
            ? '.env.${envConfig.flavor}'
            : '.env');

    final envVars = <String, String>{
      ...Platform.environment,
      'APP_IDENTIFIER': iosConfig?.bundleId ?? '',
      'APPSTORE_TEAM_ID': appStoreTeamId,
      'APP_STORE_TEAM_ID': appStoreTeamId,
      'APP_TARGET': 'Runner',
      'FLUTTER_TARGET': envConfig.entryPoint ?? 'lib/main.dart',
      'FLUTTER_FLAVOR': envConfig.flavor ?? '',
      'SKIP_APP_STORE_CHECK': 'false',
      'WORKSPACE_FILE': 'Runner.xcworkspace',
      'FIREBASE_SERVICE_JSON_FILE':
          makeAbsolutePath(firebaseServiceJsonFile) ?? '',
      'FIREBASE_APP_ID': iosConfig?.firebaseAppId ?? '',
      'FIREBASE_TESTERS_GROUPS': firebaseGroups,
      'CERTIFICATE_GIT_URL': certificateGitUrl,
      'CERTIFICATE_GIT_BRANCH': certificateGitBranch,
      'BUILD_SCHEME': scheme,
      'RELEASE_NOTES': releaseNotes,
      if (ascKeyId.isNotEmpty) 'ASC_KEY_ID': ascKeyId,
      if (ascIssuerId.isNotEmpty) 'ASC_ISSUER_ID': ascIssuerId,
      'ASC_KEY_CONTENT': ?ascKeyContentBase64,
      'DART_DEFINES': jsonEncode(dartDefines),
      'DART_DEFINE_FROM_FILE': makeAbsolutePath(dartDefineFromFile) ?? '',
    };

    final fastlaneLane = target == 'store' ? 'test_flight' : 'firebase';

    // Configuration Validations
    if (iosConfig?.bundleId == null || iosConfig!.bundleId!.isEmpty) {
      logger.err('$prefix Validation failed: ios.bundle_id is required.');
      return 1;
    }
    if (target == 'firebase' &&
        (iosConfig.firebaseAppId == null || iosConfig.firebaseAppId!.isEmpty)) {
      logger.err(
        '$prefix Validation failed: target "firebase" requires ios.firebase_app_id.',
      );
      return 1;
    }
    // App Store Team ID validation
    if (appStoreTeamId.isEmpty) {
      logger.err(
        '$prefix Validation failed: app_store_team_id is strictly required for iOS deployment.',
      );
      return 1;
    }

    // App Store Connect API keys validation
    final hasAscKeys =
        ascKeyId.isNotEmpty &&
        ascIssuerId.isNotEmpty &&
        ascKeyContentBase64 != null;
    if (!hasAscKeys) {
      logger.err(
        '$prefix Validation failed: App Store Connect API keys (asc_key_id, asc_issuer_id, asc_key_filepath) are strictly required for iOS deployment.',
      );
      return 1;
    }

    final fastlaneCmd = await _getFastlaneCommand('ios');

    final arguments = [
      ...fastlaneCmd.sublist(1),
      fastlaneLane,
      if (bump != null && bump.isNotEmpty) 'release:$bump',
    ];

    if (isDryRun) {
      logger.info(
        '$prefix [Dry Run] Would run command: ${fastlaneCmd.first} ${arguments.join(' ')}',
      );
      logger.info(
        '$prefix [Dry Run] In directory: ${p.join(projectDir.path, 'ios')}',
      );
      logger.info('$prefix [Dry Run] With environment variables:');
      envVars.cast<String, String>().forEach((key, val) {
        if (key.startsWith('APP_') ||
            key.startsWith('FIREBASE') ||
            key.startsWith('CERTIFICATE') ||
            key.startsWith('BUILD_') ||
            key.startsWith('FLUTTER') ||
            key == 'WORKSPACE_FILE' ||
            key.startsWith('ASC_')) {
          // Truncate base64 content in log for clean display and security
          final displayVal = (key == 'ASC_KEY_CONTENT' && val.length > 30)
              ? '${val.substring(0, 15)}... [TRUNCATED] ...${val.substring(val.length - 15)}'
              : val;
          logger.info('  $key: $displayVal');
        }
      });
      return 0;
    }

    logger.info(
      '$prefix Launching Fastlane deployment (lane: $fastlaneLane)...',
    );

    final fastlaneCode = await ProcessUtils.runWithPrefix(
      executable: fastlaneCmd.first,
      arguments: arguments,
      prefix: prefix,
      workingDirectory: p.join(projectDir.path, 'ios'),
      environment: envVars,
    );

    if (fastlaneCode != 0) {
      logger.err(
        '$prefix Fastlane deployment failed with exit code $fastlaneCode.',
      );
    } else {
      logger.success('$prefix Deployment completed successfully!');
    }

    return fastlaneCode;
  }

  // ==========================================
  // Helper Utility
  // ==========================================

  /// Executes the [makeAbsolutePath] operation.
  String? makeAbsolutePath(String? relativeOrAbsolutePath) {
    if (relativeOrAbsolutePath == null || relativeOrAbsolutePath.isEmpty) {
      return null;
    }
    if (p.isAbsolute(relativeOrAbsolutePath)) return relativeOrAbsolutePath;
    return p.normalize(p.join(projectDir.path, relativeOrAbsolutePath));
  }

  // ==========================================
  // Gemfile & Bundler Helpers
  // ==========================================

  /// Checks if Bundler (bundle) is available and if Gemfile exists,
  /// returns ['bundle', 'exec', 'fastlane'] or ['fastlane'].
  Future<List<String>> _getFastlaneCommand(String platformDirName) async {
    final gemfile = File(p.join(projectDir.path, platformDirName, 'Gemfile'));
    if (gemfile.existsSync()) {
      try {
        final result = await Process.run('bundle', [
          '--version',
        ], runInShell: true);
        if (result.exitCode == 0) {
          return ['bundle', 'exec', 'fastlane'];
        }
      } catch (_) {}
    }
    return ['fastlane'];
  }
}
