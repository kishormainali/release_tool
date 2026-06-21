import 'package:mason_logger/mason_logger.dart';
import 'base_command.dart';
import '../utils/version_utils.dart';

/// A command for printing the current version of the tool.
class VersionCommand extends BaseCommand {
  @override
  final String name = 'version';

  @override
  final String description =
      'Manage and bump Flutter project semantic versioning.';

  /// Creates a new [VersionCommand].
  VersionCommand({required super.logger}) {
    argParser.addFlag(
      'yes',
      abbr: 'y',
      negatable: false,
      help: 'Skip confirmation prompts.',
    );
  }

  @override
  Future<int> run() async {
    if (!checkFlutterProject()) return 1;

    try {
      final currentVersion = VersionUtils.readVersionFromPubspec(pubspecFile);
      logger.info('Current version: ${lightCyan.wrap(currentVersion)}');

      // Resolve bump type from arguments or interactive selection
      String? bumpType;
      final remainingArgs = argResults?.rest.toList() ?? [];

      if (remainingArgs.isNotEmpty) {
        bumpType = remainingArgs.first.toLowerCase();
        final allowedTypes = {'major', 'minor', 'patch', 'build'};
        if (!allowedTypes.contains(bumpType)) {
          logger.err(
            'Invalid bump type: "$bumpType". Supported: major, minor, patch, build',
          );
          return 1;
        }
      } else {
        // Build preview choices for interactive selector
        final patchPreview = VersionUtils.bumpVersion(currentVersion, 'patch');
        final minorPreview = VersionUtils.bumpVersion(currentVersion, 'minor');
        final majorPreview = VersionUtils.bumpVersion(currentVersion, 'major');
        final buildPreview = VersionUtils.bumpVersion(currentVersion, 'build');

        final choice = logger.chooseOne<String>(
          'Select version bump type:',
          choices: [
            'patch ($patchPreview)',
            'minor ($minorPreview)',
            'major ($majorPreview)',
            'build ($buildPreview)',
            'Exit / Cancel',
          ],
        );

        if (choice == 'Exit / Cancel') {
          logger.info('Version bump cancelled.');
          return 0;
        }

        // Parse chosen type out of choices
        bumpType = choice.split(' ').first;
      }

      final newVersion = VersionUtils.bumpVersion(currentVersion, bumpType);

      final skipConfirmation = argResults?['yes'] as bool? ?? false;
      if (!skipConfirmation) {
        final confirm = logger.confirm(
          'Are you sure you want to bump version from ${lightCyan.wrap(currentVersion)} to ${green.wrap(newVersion)}?',
          defaultValue: true,
        );
        if (!confirm) {
          logger.info('Version bump cancelled.');
          return 0;
        }
      }

      final progress = logger.progress('Bumping version in pubspec.yaml...');
      VersionUtils.writeVersionToPubspec(pubspecFile, newVersion);
      progress.complete('Successfully bumped version to: $newVersion');

      return 0;
    } catch (e) {
      logger.err('Failed to manage version: $e');
      return 1;
    }
  }
}
