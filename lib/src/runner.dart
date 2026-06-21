import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

import 'commands/init_command.dart';
import 'commands/version_command.dart';
import 'commands/deploy_command.dart';
import 'commands/update_command.dart';
import 'commands/certificates_command.dart';

/// The main command runner for the release_tool.
class ReleaseToolCommandRunner extends CommandRunner<int> {
  /// The logger used for outputting information.
  final Logger logger;

  /// The current version of the tool.
  static const String packageVersion = '0.0.1';

  /// Creates a new [ReleaseToolCommandRunner].
  ReleaseToolCommandRunner({Logger? logger})
    : logger = logger ?? Logger(),
      super(
        'release_tool',
        'A centralized CLI tool to streamline Flutter releases on Android and iOS using Fastlane.',
      ) {
    // Add subcommands
    addCommand(InitCommand(logger: this.logger));
    addCommand(VersionCommand(logger: this.logger));
    addCommand(DeployCommand(logger: this.logger));
    addCommand(UpdateCommand(logger: this.logger));
    addCommand(CertificatesCommand(logger: this.logger));
  }

  @override
  String get usage {
    final banner = [
      ' ╔══════════════════════════════════════════════════════════════╗',
      ' ║                                                              ║',
      ' ║        ╦═╗ ╦══ ╦   ╦══ ╦═╗ ╔══ ╦══    ╦══ ╔═╗ ╔═╗ ╦         ║',
      ' ║        ╠╦╝ ╠═  ║   ╠═  ╠═╣ ╚═╗ ╠═      ║  ║ ║ ║ ║ ║         ║',
      ' ║        ╩╚═ ╩══ ╩══ ╩══ ╩ ╩ ══╝ ╩══     ╩  ╚═╝ ╚═╝ ╩══         ║',
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
    try {
      final exitCode = await runCommand(parse(args));
      return exitCode ?? 0;
    } on UsageException catch (e) {
      logger.err(e.message);
      logger.info(e.usage);
      return 64; // Standard EX_USAGE exit code
    } catch (e, stackTrace) {
      logger.err('An unexpected error occurred: $e');
      logger.detail(stackTrace.toString());
      return 1;
    }
  }
}
