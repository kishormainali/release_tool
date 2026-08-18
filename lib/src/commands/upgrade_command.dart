import 'package:pub_updater/pub_updater.dart';

import 'base_command.dart';
import '../version.dart';

/// A command to upgrade the CLI to the latest version on pub.dev.
class UpgradeCommand extends BaseCommand {
  @override
  final String name = 'upgrade';

  @override
  final String description =
      'Upgrade the CLI to the latest version published on pub.dev.';

  final PubUpdater _pubUpdater;

  /// Creates a new [UpgradeCommand].
  UpgradeCommand({required super.logger, PubUpdater? pubUpdater})
    : _pubUpdater = pubUpdater ?? PubUpdater();

  @override
  Future<int> run() async {
    final progress = logger.progress('Checking for updates');
    try {
      final isUpToDate = await _pubUpdater.isUpToDate(
        packageName: 'fp_release_tool',
        currentVersion: packageVersion,
      );

      if (isUpToDate) {
        progress.complete(
          'release_tool is already at the latest version ($packageVersion).',
        );
        return 0;
      }

      final latestVersion = await _pubUpdater.getLatestVersion(
        'fp_release_tool',
      );
      progress.update('Upgrading from $packageVersion to $latestVersion');

      await _pubUpdater.update(packageName: 'fp_release_tool');
      progress.complete('Successfully upgraded to $latestVersion!');
      return 0;
    } catch (e) {
      progress.fail('An error occurred while checking for updates.');
      logger.err(e.toString());
      return 1;
    }
  }
}
