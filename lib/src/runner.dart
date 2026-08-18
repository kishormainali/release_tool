import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cli_completion/cli_completion.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:pub_updater/pub_updater.dart';

import 'commands/init_command.dart';
import 'commands/version_command.dart';
import 'commands/deploy_command.dart';
import 'commands/update_command.dart';
import 'commands/certificates_command.dart';
import 'commands/doctor_command.dart';
import 'commands/remote_config_command.dart';
import 'commands/upgrade_command.dart';
import 'utils/update_check_cache.dart';
import 'version.dart';

/// The main command runner for the release_tool.
class ReleaseToolCommandRunner extends CompletionCommandRunner<int> {
  /// The logger used for outputting information.
  final Logger logger;

  /// The pub updater instance.
  final PubUpdater _pubUpdater;

  /// Caches the result of the last pub.dev update check.
  final UpdateCheckCache _updateCheckCache;

  /// Creates a new [ReleaseToolCommandRunner].
  ReleaseToolCommandRunner({
    Logger? logger,
    PubUpdater? pubUpdater,
    UpdateCheckCache? updateCheckCache,
  }) : logger = logger ?? Logger(),
       _pubUpdater = pubUpdater ?? PubUpdater(),
       _updateCheckCache = updateCheckCache ?? UpdateCheckCache(),
       super(
         'release_tool',
         'A centralized CLI tool to streamline Flutter releases on Android and iOS using Fastlane.',
       ) {
    argParser.addFlag(
      'verbose',
      abbr: 'v',
      negatable: false,
      help: 'Enable verbose (debug-level) logging output.',
    );

    // Add subcommands
    addCommand(InitCommand(logger: this.logger));
    addCommand(VersionCommand(logger: this.logger));
    addCommand(DeployCommand(logger: this.logger));
    addCommand(UpdateCommand(logger: this.logger));
    addCommand(UpgradeCommand(logger: this.logger));
    addCommand(CertificatesCommand(logger: this.logger));
    addCommand(DoctorCommand(logger: this.logger));
    addCommand(RemoteConfigCommand(logger: this.logger));
  }

  @override
  String get usage {
    final banner = [
      ' ╔══════════════════════════════════════════════════════════════╗',
      ' ║                                                              ║',
      ' ║        ╦═╗ ╦══ ╦   ╦══ ╦═╗ ╔══ ╦══    ╦══ ╔═╗ ╔═╗ ╦          ║',
      ' ║        ╠╦╝ ╠═  ║   ╠═  ╠═╣ ╚═╗ ╠═      ║  ║ ║ ║ ║ ║          ║',
      ' ║        ╩╚═ ╩══ ╩══ ╩══ ╩ ╩ ══╝ ╩══     ╩  ╚═╝ ╚═╝ ╩══        ║',
      ' ║                                                              ║',
      ' ╚══════════════════════════════════════════════════════════════╝',
    ].map((line) => lightCyan.wrap(line)).join('\n');

    final versionInfo =
        '  🚀 ${lightCyan.wrap('Centralized Flutter Release Tool')} ➔ ${green.wrap('v$packageVersion')}';

    var rawUsage = super.usage;

    // Highlight labels and commands in the usage instructions
    rawUsage = rawUsage
        .replaceAll(
          'Usage: release_tool',
          '${yellow.wrap('Usage:')} ${lightCyan.wrap('release_tool')}',
        )
        .replaceAll('Global options:', yellow.wrap('Global Options:')!)
        .replaceAll('Available commands:', yellow.wrap('Available Commands:')!)
        .replaceAll(
          'Run "release_tool help <command>"',
          'Run "${lightCyan.wrap('release_tool help <command>')}"',
        );

    // Dynamically colorize the command names in the "Available Commands:" section
    final lines = rawUsage.split('\n');
    var inCommandsSection = false;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.contains('Available Commands:')) {
        inCommandsSection = true;
        continue;
      }
      if (inCommandsSection) {
        if (line.trim().isEmpty) {
          continue;
        }
        if (line.startsWith('  ') && !line.startsWith('    ')) {
          final trimmed = line.trimLeft();
          final firstSpace = trimmed.indexOf(' ');
          if (firstSpace != -1) {
            final commandName = trimmed.substring(0, firstSpace);
            final rest = trimmed.substring(firstSpace);
            lines[i] = '  ${green.wrap(commandName)}$rest';
          }
        } else {
          if (line.trim().isNotEmpty && !line.startsWith('  ')) {
            inCommandsSection = false;
          }
        }
      }
    }
    rawUsage = lines.join('\n');

    return '''
$banner
$versionInfo

$rawUsage''';
  }

  @override
  Future<int> run(Iterable<String> args) async {
    final updateCheck = _checkForUpdates();
    try {
      final topLevelResults = parse(args);
      if (topLevelResults['verbose'] as bool? ?? false) {
        logger.level = Level.verbose;
      }
      final exitCode = await runCommand(topLevelResults);
      await updateCheck;
      return exitCode ?? 0;
    } on UsageException catch (e) {
      logger.err(e.message);
      logger.info(e.usage);
      await updateCheck;
      return 64; // Standard EX_USAGE exit code
    } catch (e, stackTrace) {
      logger.err('An unexpected error occurred: $e');
      logger.detail(stackTrace.toString());
      await updateCheck;
      return 1;
    }
  }

  /// Whether it's appropriate to check pub.dev for updates: interactive
  /// terminal sessions only, never CI (avoids noise and unnecessary network
  /// calls in automated pipelines).
  bool get _shouldCheckForUpdates =>
      stdin.hasTerminal && Platform.environment['CI'] == null;

  /// Asynchronously checks if a new version is available on pub.dev, using a
  /// local cache so the network is only hit at most once every
  /// [UpdateCheckCache.checkInterval]. Does not block the main command
  /// execution and fails silently on network errors.
  Future<void> _checkForUpdates() async {
    if (!_shouldCheckForUpdates) return;

    try {
      var latestVersion = _updateCheckCache.read();

      if (latestVersion == null) {
        final isUpToDate = await _pubUpdater
            .isUpToDate(
              packageName: 'fp_release_tool',
              currentVersion: packageVersion,
            )
            .timeout(const Duration(milliseconds: 1500));

        latestVersion = isUpToDate
            ? packageVersion
            : await _pubUpdater.getLatestVersion('fp_release_tool');
        _updateCheckCache.write(latestVersion);
      }

      if (latestVersion != packageVersion) {
        logger.info('');
        logger.info(
          "${lightYellow.wrap('Update available!')} ${lightCyan.wrap(packageVersion)} \u2192 ${green.wrap(latestVersion)}",
        );
        logger.info("Run ${lightCyan.wrap('release_tool upgrade')} to update.");
        logger.info('');
      }
    } catch (_) {
      // Ignore network errors or timeouts gracefully.
    }
  }
}
