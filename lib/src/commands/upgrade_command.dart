import 'dart:convert';
import 'dart:io';
import 'package:pub_semver/pub_semver.dart';

import 'base_command.dart';
import '../version.dart';

/// A command to upgrade the CLI to the latest version on pub.dev.
class UpgradeCommand extends BaseCommand {
  @override
  final String name = 'upgrade';

  @override
  final String description =
      'Upgrade the CLI to the latest version published on pub.dev.';

  /// Creates a new [UpgradeCommand].
  UpgradeCommand({required super.logger});

  @override
  Future<int> run() async {
    final progress = logger.progress('Checking for updates');
    try {
      final client = HttpClient();
      final request = await client.getUrl(
        Uri.parse('https://pub.dev/api/packages/fp_release_tool'),
      );
      final response = await request.close();

      if (response.statusCode != 200) {
        progress.fail(
          'Failed to check for updates (HTTP ${response.statusCode}).',
        );
        return 1;
      }

      final responseBody = await response.transform(utf8.decoder).join();
      final data = jsonDecode(responseBody) as Map<String, dynamic>;
      final latest = data['latest'] as Map<String, dynamic>;
      final latestVersionStr = latest['version'] as String;

      final currentVersion = Version.parse(packageVersion);
      final latestVersion = Version.parse(latestVersionStr);

      if (currentVersion >= latestVersion) {
        progress.complete(
          'release_tool is already at the latest version ($packageVersion).',
        );
        return 0;
      }

      progress.update('Upgrading from $packageVersion to $latestVersionStr');

      final result = await Process.run('dart', [
        'pub',
        'global',
        'activate',
        'fp_release_tool',
      ]);

      if (result.exitCode == 0) {
        progress.complete('Successfully upgraded to $latestVersionStr!');
        return 0;
      } else {
        progress.fail('Failed to upgrade.');
        logger.err(result.stderr.toString());
        return result.exitCode;
      }
    } catch (e) {
      progress.fail('An error occurred while checking for updates.');
      logger.err(e.toString());
      return 1;
    }
  }
}
