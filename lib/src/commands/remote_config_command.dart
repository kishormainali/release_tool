import 'dart:convert';
import 'dart:io';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'base_command.dart';
import '../utils/fastlane_utils.dart';
import '../utils/process_utils.dart';
import '../utils/release_cache.dart';

/// A command to publish the latest cached store release(s) to Firebase
/// Remote Config's `fl_updater_latest_version`, then clear the cache.
class RemoteConfigCommand extends BaseCommand {
  @override
  final String name = 'remote-config';

  @override
  final String description =
      'Publish the latest cached store release to Firebase Remote Config '
      '(fl_updater_latest_version) and clear the release cache.';

  /// Creates a new [RemoteConfigCommand].
  RemoteConfigCommand({required super.logger}) {
    argParser.addOption(
      'env',
      abbr: 'e',
      help: 'The environment whose cached release(s) to publish.',
    );
    argParser.addOption(
      'platform',
      abbr: 'p',
      allowed: ['android', 'ios'],
      help:
          'Limit the update to a single platform (defaults to every cached platform). '
          'Required when using --version.',
    );
    argParser.addOption(
      'version',
      help:
          'Publish this exact version instead of the cached release version '
          '(requires --platform, since there is no cache to infer platform scope from).',
    );
    argParser.addFlag(
      'force-update',
      negatable: false,
      help:
          'Also set fl_updater_min_version to the same version, forcing an immediate, '
          'non-dismissible update for every user below it.',
    );
    argParser.addFlag(
      'dry-run',
      negatable: false,
      help:
          'Show what would be published without contacting Firebase or clearing the cache.',
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

    final isInteractive = isInteractiveSession;

    String? envName = argResults?['env'] as String?;
    if (envName == null) {
      if (!isInteractive) {
        logger.err(
          'Missing required option --env in non-interactive environment.',
        );
        return 1;
      }
      envName = logger.chooseOne(
        'Select environment to publish remote config for:',
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

    final platformFilter = argResults?['platform'] as String?;
    final explicitVersion = argResults?['version'] as String?;
    final usingExplicitVersion =
        explicitVersion != null && explicitVersion.isNotEmpty;

    if (usingExplicitVersion && platformFilter == null) {
      logger.err(
        '--version requires --platform, since there is no cache to infer which platform it applies to.',
      );
      return 1;
    }

    final cache = ReleaseCache(projectDir);
    Map<String, String> updates;

    if (usingExplicitVersion) {
      updates = {platformFilter!: explicitVersion};
    } else {
      var cachedReleases = cache.read(envName!);
      if (platformFilter != null) {
        final entry = cachedReleases[platformFilter];
        cachedReleases = entry == null ? {} : {platformFilter: entry};
      }

      if (cachedReleases.isEmpty) {
        final platformHint = platformFilter != null
            ? ' --platform $platformFilter'
            : '';
        logger.err(
          'No cached${platformFilter != null ? ' $platformFilter' : ''} release found for '
          'environment "$envName". Run `release_tool deploy --env $envName$platformHint '
          '--target store` first, or pass --version explicitly (with --platform).',
        );
        return 1;
      }

      updates = {
        for (final entry in cachedReleases.entries)
          entry.key: entry.value.version,
      };
    }

    final firebaseProjectId =
        envConfig.firebaseProjectId ?? config.shared.firebaseProjectId;
    if (firebaseProjectId == null || firebaseProjectId.isEmpty) {
      logger.err(
        'firebase_project_id is not configured for environment "$envName" (checked env and shared config).',
      );
      return 1;
    }

    final firebaseServiceJsonFile =
        config.shared.firebaseServiceJsonFile ??
        envConfig.android?.firebaseServiceJsonFile ??
        envConfig.ios?.firebaseServiceJsonFile ??
        config.shared.android?.firebaseServiceJsonFile ??
        config.shared.ios?.firebaseServiceJsonFile;
    final resolvedServiceJsonPath = makeAbsolutePath(firebaseServiceJsonFile);
    if (resolvedServiceJsonPath == null ||
        !File(resolvedServiceJsonPath).existsSync()) {
      logger.err(
        'Firebase service account file not found at "${firebaseServiceJsonFile ?? '(unset)'}". '
        'This account also needs the "Firebase Remote Config Admin" IAM role.',
      );
      return 1;
    }

    final forceUpdate = argResults?['force-update'] as bool? ?? false;

    final targetParams = forceUpdate
        ? 'fl_updater_latest_version and fl_updater_min_version'
        : 'fl_updater_latest_version';
    final versionSource = usingExplicitVersion ? '--version' : 'cached release';

    logger.info('\n${lightCyan.wrap('Publishing to Firebase Remote Config:')}');
    logger.info('  Environment:      ${green.wrap(envName)}');
    logger.info('  Firebase Project: ${green.wrap(firebaseProjectId)}');
    logger.info('  Parameter(s):     ${green.wrap(targetParams)}');
    for (final entry in updates.entries) {
      logger.info(
        '  ${entry.key}: ${green.wrap(entry.value)} (fl_updater_${entry.key}, from $versionSource)',
      );
    }
    if (forceUpdate) {
      logger.info(
        '  ${yellow.wrap('Force update: every user below this version will see a mandatory, non-dismissible update prompt.')}',
      );
    }
    logger.info('');

    final isDryRun = argResults?['dry-run'] as bool? ?? false;
    if (isDryRun) {
      logger.info(
        '[Dry Run] Would update $targetParams with the values above and clear the release cache.',
      );
      return 0;
    }

    final skipConfirmation =
        (argResults?['yes'] as bool? ?? false) || !isInteractive;
    var confirm = true;
    if (!skipConfirmation) {
      confirm = logger.confirm(
        forceUpdate
            ? 'This forces an immediate, non-dismissible update for every user below this version. Proceed?'
            : 'Proceed with updating Remote Config?',
        defaultValue: !forceUpdate,
      );
    }
    if (!confirm) {
      logger.info('Cancelled.');
      return 0;
    }

    // Remote Config isn't platform-specific — this just needs *a* Ruby/
    // Fastlane environment to run the lane in, so use whichever platform
    // folder exists.
    final hasAndroid = Directory(
      p.join(projectDir.path, 'android'),
    ).existsSync();
    final hasIos = Directory(p.join(projectDir.path, 'ios')).existsSync();
    final platformDir = hasAndroid ? 'android' : (hasIos ? 'ios' : null);
    if (platformDir == null) {
      logger.err(
        'Neither android/ nor ios/ project folders were found; cannot run the Fastlane lane.',
      );
      return 1;
    }

    final fastlaneCmd = await resolveFastlaneCommand(projectDir, platformDir);
    final arguments = [...fastlaneCmd.sublist(1), 'update_remote_config'];

    final envVars = <String, String>{
      ...Platform.environment,
      'FIREBASE_PROJECT_ID': firebaseProjectId,
      'FIREBASE_SERVICE_JSON_FILE': resolvedServiceJsonPath,
      'REMOTE_CONFIG_UPDATES': jsonEncode(updates),
      'REMOTE_CONFIG_FORCE_UPDATE': forceUpdate.toString(),
    };

    logger.info('Launching Fastlane (lane: update_remote_config)...');
    final exitCode = await ProcessUtils.runWithPrefix(
      executable: fastlaneCmd.first,
      arguments: arguments,
      prefix: '\x1B[35m[Remote Config]\x1B[0m',
      workingDirectory: p.join(projectDir.path, platformDir),
      environment: envVars,
    );

    if (exitCode != 0) {
      logger.err(
        'Failed to update Remote Config (exit code $exitCode). '
        'The release cache was left untouched — retry once fixed.',
      );
      return exitCode;
    }

    for (final platform in updates.keys) {
      cache.clear(envName!, platform: platform);
    }
    logger.success(
      'Remote Config updated and release cache cleared for: ${updates.keys.join(', ')}.',
    );
    return 0;
  }
}
