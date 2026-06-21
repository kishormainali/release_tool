import 'dart:convert';
import 'dart:io';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'base_command.dart';
import '../config/release_config.dart';
import '../utils/process_utils.dart';

/// Base class for certificate management commands.
abstract class CertificatesBaseCommand extends BaseCommand {
  /// Creates a new [CertificatesBaseCommand].
  CertificatesBaseCommand({required super.logger}) {
    argParser.addOption(
      'env',
      abbr: 'e',
      help: 'The environment configuration to manage certificates for.',
    );
    argParser.addFlag(
      'all',
      abbr: 'a',
      negatable: false,
      help: 'Manage certificates for all defined environments.',
    );
    argParser.addFlag(
      'dry-run',
      negatable: false,
      help: 'Verify configurations without running Fastlane match.',
    );
    argParser.addFlag(
      'yes',
      abbr: 'y',
      negatable: false,
      help: 'Skip confirmation prompts (useful in CI/CD).',
    );
  }

  /// Executes the [executeMatchPipeline] operation.
  Future<int> executeMatchPipeline(String action) async {
    if (!checkFlutterProject()) return 1;

    final config = loadConfig();
    if (config == null) return 1;

    if (config.environments.isEmpty) {
      logger.err(
        'No environments found in release_config.yaml. Please configure them first.',
      );
      return 1;
    }

    final isIosProject = Directory(p.join(projectDir.path, 'ios')).existsSync();
    if (!isIosProject) {
      logger.err(
        'iOS project directory not found. Certificates management is only available for iOS.',
      );
      return 1;
    }

    final isInteractive = stdin.hasTerminal;

    final allFlag = argResults?['all'] as bool? ?? false;
    final isDryRun = argResults?['dry-run'] as bool? ?? false;
    final skipConfirmation =
        (argResults?['yes'] as bool? ?? false) || !isInteractive;

    List<String> targetEnvs = [];

    String? envName = argResults?['env'] as String?;
    if (allFlag) {
      targetEnvs = config.environments.keys.toList();
    } else if (envName != null) {
      if (!config.environments.containsKey(envName)) {
        logger.err(
          'Environment "$envName" is not defined in release_config.yaml.',
        );
        return 1;
      }
      targetEnvs = [envName];
    } else {
      if (!isInteractive) {
        logger.err(
          'Either --env or --all must be specified in non-interactive mode.',
        );
        return 1;
      }
      // Interactive choice
      final choices = ['All Environments', ...config.environments.keys];
      final choice = logger.chooseOne(
        'Select environment to manage certificates for:',
        choices: choices,
      );
      if (choice == 'All Environments') {
        targetEnvs = config.environments.keys.toList();
      } else {
        targetEnvs = [choice];
      }
    }

    logger.info(
      '\n${lightCyan.wrap('Starting Certificates Management Pipeline:')}',
    );
    logger.info('  Action:        ${green.wrap(action.toUpperCase())}');
    logger.info('  Environments:  ${green.wrap(targetEnvs.join(', '))}');
    logger.info(
      '  Dry Run:       ${isDryRun ? yellow.wrap('Enabled') : 'Disabled'}\n',
    );

    var confirm = true;
    if (!skipConfirmation) {
      confirm = logger.confirm(
        'Proceed with certificates management?',
        defaultValue: true,
      );
    }
    if (!confirm) {
      logger.warn('Cancelled.');
      return 0;
    }

    int overallExitCode = 0;
    for (final env in targetEnvs) {
      final envConfig = config.environments[env]!;
      final envExitCode = await _runMatchForEnv(
        config,
        envConfig,
        action,
        isDryRun,
      );
      if (envExitCode != 0) {
        overallExitCode = envExitCode;
        logger.err('Failed to manage certificates for environment: $env');
      }
    }

    if (overallExitCode == 0) {
      logger.success(
        '\nCertificates management pipeline completed successfully!',
      );
    } else {
      logger.err('\nCertificates management pipeline failed.');
    }

    return overallExitCode;
  }

  Future<int> _runMatchForEnv(
    ReleaseConfig releaseConfig,
    EnvironmentConfig envConfig,
    String action, // 'get', 'create', 'nuke'
    bool isDryRun,
  ) async {
    final prefix = '\x1B[36m[iOS - ${envConfig.name}]\x1B[0m';
    final iosConfig = envConfig.ios;
    final sharedIos = releaseConfig.shared.ios;

    final appStoreTeamId =
        iosConfig?.appStoreTeamId ?? sharedIos?.appStoreTeamId ?? '';
    final certificateGitUrl =
        iosConfig?.match?.gitUrl ?? sharedIos?.match?.gitUrl ?? '';
    final certificateGitBranch =
        iosConfig?.match?.gitBranch ?? sharedIos?.match?.gitBranch ?? 'master';
    final matchPassword =
        iosConfig?.match?.password ??
        sharedIos?.match?.password ??
        Platform.environment['MATCH_PASSWORD'] ??
        '';

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

    // Configuration Validations (Strict iOS validation)
    if (appStoreTeamId.isEmpty) {
      logger.err(
        '$prefix Validation failed: app_store_team_id is strictly required for iOS certificates management.',
      );
      return 1;
    }

    final hasAscKeys =
        ascKeyId.isNotEmpty &&
        ascIssuerId.isNotEmpty &&
        ascKeyContentBase64 != null;
    if (!hasAscKeys) {
      logger.err(
        '$prefix Validation failed: App Store Connect API keys (asc_key_id, asc_issuer_id, asc_key_filepath) are strictly required for iOS certificates management.',
      );
      return 1;
    }

    if (iosConfig?.bundleId == null || iosConfig!.bundleId!.isEmpty) {
      logger.err('$prefix Validation failed: ios.bundle_id is required.');
      return 1;
    }
    if (certificateGitUrl.isEmpty) {
      logger.err('$prefix Validation failed: ios.match.git_url is required.');
      return 1;
    }
    if (certificateGitBranch.isEmpty) {
      logger.err(
        '$prefix Validation failed: ios.match.git_branch is required.',
      );
      return 1;
    }
    if (matchPassword.isEmpty) {
      logger.err(
        '$prefix Validation failed: ios.match.password or MATCH_PASSWORD environment variable is required.',
      );
      return 1;
    }

    final envVars = <String, String>{
      ...Platform.environment,
      'APP_IDENTIFIER': iosConfig.bundleId ?? '',
      'APPSTORE_TEAM_ID': appStoreTeamId,
      'APP_STORE_TEAM_ID': appStoreTeamId,
      'CERTIFICATE_GIT_URL': certificateGitUrl,
      'CERTIFICATE_GIT_BRANCH': certificateGitBranch,
      'MATCH_PASSWORD': matchPassword,
      'ASC_KEY_ID': ascKeyId,
      'ASC_ISSUER_ID': ascIssuerId,
      'ASC_KEY_CONTENT': ascKeyContentBase64,
    };

    final fastlaneCmd = await _getFastlaneCommand('ios');

    Future<int> runLane(String fastlaneLane) async {
      final arguments = [...fastlaneCmd.sublist(1), fastlaneLane];

      if (isDryRun) {
        logger.info(
          '$prefix [Dry Run] Would run command: ${fastlaneCmd.first} ${arguments.join(' ')}',
        );
        logger.info(
          '$prefix [Dry Run] In directory: ${p.join(projectDir.path, 'ios')}',
        );
        logger.info('$prefix [Dry Run] With environment variables:');
        envVars.forEach((key, val) {
          if (key == 'APP_IDENTIFIER' ||
              key == 'APP_STORE_TEAM_ID' ||
              key == 'CERTIFICATE_GIT_URL' ||
              key == 'CERTIFICATE_GIT_BRANCH' ||
              key == 'ASC_KEY_ID' ||
              key == 'ASC_ISSUER_ID') {
            logger.info('  $key: $val');
          } else if (key == 'MATCH_PASSWORD') {
            logger.info('  $key: ********');
          } else if (key == 'ASC_KEY_CONTENT') {
            logger.info('  $key: [BASE64_KEY_CONTENT_PRESENT]');
          }
        });
        return 0;
      }

      logger.info(
        '$prefix Launching Fastlane match (lane: $fastlaneLane) for bundle ID: ${iosConfig.bundleId}...',
      );

      return await ProcessUtils.runWithPrefix(
        executable: fastlaneCmd.first,
        arguments: arguments,
        prefix: prefix,
        workingDirectory: p.join(projectDir.path, 'ios'),
        environment: envVars,
      );
    }

    if (action == 'nuke') {
      final nukeCode = await runLane('nuke_cert');
      if (nukeCode != 0) return nukeCode;

      // Followed by create_cert
      return await runLane('create_cert');
    } else if (action == 'create') {
      return await runLane('create_cert');
    } else {
      // get
      return await runLane('get_cert');
    }
  }

  /// Executes the [makeAbsolutePath] operation.
  String? makeAbsolutePath(String? relativeOrAbsolutePath) {
    if (relativeOrAbsolutePath == null || relativeOrAbsolutePath.isEmpty) {
      return null;
    }
    if (p.isAbsolute(relativeOrAbsolutePath)) return relativeOrAbsolutePath;
    return p.normalize(p.join(projectDir.path, relativeOrAbsolutePath));
  }

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

/// The [CertificatesCommand] class.
class CertificatesCommand extends BaseCommand {
  @override
  final String name = 'certificates';

  @override
  List<String> get aliases => ['certs'];

  @override
  final String description =
      'Manage iOS certificates and provisioning profiles using Fastlane Match.';

  /// Executes the [CertificatesCommand] operation.
  CertificatesCommand({required super.logger}) {
    addSubcommand(GetCertificatesCommand(logger: logger));
    addSubcommand(CreateCertificatesCommand(logger: logger));
    addSubcommand(NukeCertificatesCommand(logger: logger));
  }

  @override
  Future<int> run() async {
    printUsage();
    return 0;
  }
}

/// The [GetCertificatesCommand] class.
class GetCertificatesCommand extends CertificatesBaseCommand {
  @override
  final String name = 'get';

  @override
  final String description = 'Fetch/retrieve existing certificates.';

  /// Executes the [GetCertificatesCommand] operation.
  GetCertificatesCommand({required super.logger});

  @override
  Future<int> run() async => executeMatchPipeline('get');
}

/// The [CreateCertificatesCommand] class.
class CreateCertificatesCommand extends CertificatesBaseCommand {
  @override
  final String name = 'create';

  @override
  final String description = 'Create new certificates.';

  /// Executes the [CreateCertificatesCommand] operation.
  CreateCertificatesCommand({required super.logger});

  @override
  Future<int> run() async => executeMatchPipeline('create');
}

/// The [NukeCertificatesCommand] class.
class NukeCertificatesCommand extends CertificatesBaseCommand {
  @override
  final String name = 'nuke';

  @override
  final String description = 'Nuke all certificates and create fresh ones.';

  /// Executes the [NukeCertificatesCommand] operation.
  NukeCertificatesCommand({required super.logger});

  @override
  Future<int> run() async => executeMatchPipeline('nuke');
}
