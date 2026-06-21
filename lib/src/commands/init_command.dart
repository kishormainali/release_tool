import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:mason/mason.dart';
import 'base_command.dart';
import '../templates/fastlane_bundle.dart';
import '../utils/project_utils.dart';

/// A command to initialize the project with release_tool configuration and templates.
class InitCommand extends BaseCommand {
  @override
  final String name = 'init';

  @override
  final String description =
      'Initialize release_config.yaml and Fastlane templates in the project.';

  /// Creates a new [InitCommand].
  InitCommand({required super.logger}) {
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

    final progress = logger.progress(
      'Initializing Release Tool configuration...',
    );

    try {
      // 1. Auto-detect project flavor configuration
      progress.update(
        'Scanning project for Android flavors and iOS schemes...',
      );
      final detected = ProjectUtils.detectFlavors(projectDir);
      final androidFlavors = detected['android'] ?? [];
      final iosSchemes = detected['ios'] ?? [];

      logger.info(
        '\n${lightCyan.wrap('Auto-detected platforms & configurations:')}',
      );
      logger.info(
        '  Android product flavors: ${androidFlavors.isEmpty ? 'None' : androidFlavors.join(', ')}',
      );
      logger.info(
        '  iOS schemes: ${iosSchemes.isEmpty ? 'None' : iosSchemes.join(', ')}',
      );

      // 2. Read project name from pubspec.yaml
      final pubspecContent = pubspecFile.readAsStringSync();
      final nameMatch = RegExp(
        r'^name:\s*([a-zA-Z0-9_-]+)',
        multiLine: true,
      ).firstMatch(pubspecContent);
      final projectName = nameMatch?.group(1) ?? 'flutter_app';

      // 3. Write release_config.yaml check
      if (configFile.existsSync()) {
        progress.fail();
        final isInteractive = stdin.hasTerminal;
        final skipConfirmation =
            (argResults?['yes'] as bool? ?? false) || !isInteractive;
        var overwrite = true;
        if (!skipConfirmation) {
          overwrite = logger.confirm(
            'release_config.yaml already exists. Overwrite?',
            defaultValue: false,
          );
        }
        if (!overwrite) {
          logger.info('Initialization aborted.');
          return 0;
        }
        progress.update('Overwriting existing configuration and templates...');
      }

      final androidDir = Directory(p.join(projectDir.path, 'android'));
      final iosDir = Directory(p.join(projectDir.path, 'ios'));
      final hasAndroid = androidDir.existsSync();
      final hasIos = iosDir.existsSync();

      // Form environments list
      final environments = <Map<String, String>>[];
      final distinctNames = <String>{};
      distinctNames.addAll(androidFlavors);
      for (final scheme in iosSchemes) {
        if (scheme != 'Runner') {
          distinctNames.add(scheme);
        }
      }

      for (final env in distinctNames) {
        environments.add({'name': env, 'flavor': env, 'scheme': env});
      }

      // Generate files using the mason brick bundle
      progress.update('Generating configuration and templates via Mason...');
      final generator = await MasonGenerator.fromBundle(fastlaneBundle);
      final target = DirectoryGeneratorTarget(projectDir);

      final filesGenerated = await generator.generate(
        target,
        vars: <String, dynamic>{
          'project_name': projectName,
          'project_name_flat': projectName
              .replaceAll('_', '')
              .replaceAll('-', ''),
          'android': hasAndroid,
          'ios': hasIos,
          'has_environments': environments.isNotEmpty,
          'environments': environments,
        },
        fileConflictResolution: FileConflictResolution.overwrite,
      );

      for (final file in filesGenerated) {
        logger.info(
          '  Created ${p.relative(file.path, from: projectDir.path)}',
        );
      }

      // 3.5 Run bundler for both platforms
      if (hasAndroid) {
        progress.update('Configuring Android bundler...');
        await _runBundler(androidDir, 'Android');
      }
      if (hasIos) {
        progress.update('Configuring iOS bundler...');
        await _runBundler(iosDir, 'iOS');
      }

      // 4. Update .gitignore to ignore sensitive files
      progress.update('Updating .gitignore to secure credentials...');
      _updateGitignore();

      progress.complete('Initialization completed successfully!');
      logger.info('\n${green.wrap('🎉 Centralized Release Tool is set up!')}');
      logger.info('Next steps:');
      logger.info(
        '  1. Open ${lightCyan.wrap('release_config.yaml')} and populate your Firebase App IDs, Package Names/Bundle IDs, and tracks.',
      );
      logger.info(
        '  2. Configure credentials (such as Google Play service credentials or App Store credentials) via your environment variables.',
      );
      logger.info(
        '  3. Run: ${lightCyan.wrap('release_tool deploy')} to build and deploy!',
      );
      return 0;
    } catch (e) {
      progress.fail('Failed to initialize: $e');
      return 1;
    }
  }

  void _updateGitignore() {
    final gitignoreFile = File(p.join(projectDir.path, '.gitignore'));
    if (!gitignoreFile.existsSync()) return;

    try {
      final content = gitignoreFile.readAsStringSync();
      const ignoreSection = '''

# Centralized Release Tool Secrets
*-credentials.json
*-credentials.json.enc
secrets/

# Fastlane Bundler Dependencies
vendor/
.bundle/
''';

      if (!content.contains('Centralized Release Tool Secrets')) {
        gitignoreFile.writeAsStringSync(content + ignoreSection);
        logger.info(
          '  Updated .gitignore to ignore sensitive credential files.',
        );
      }
    } catch (_) {}
  }

  Future<void> _runBundler(Directory dir, String platform) async {
    final bundlerProgress = logger.progress(
      'Installing $platform dependencies via bundler...',
    );
    final configRes = await Process.run('bundle', [
      'config',
      'set',
      'path',
      '../vendor/bundle',
    ], workingDirectory: dir.path);
    if (configRes.exitCode != 0) {
      bundlerProgress.fail('Failed to configure bundler');
      throw Exception(configRes.stderr);
    }

    final installRes = await Process.run('bundle', [
      'install',
    ], workingDirectory: dir.path);
    if (installRes.exitCode != 0) {
      bundlerProgress.fail('Failed to install dependencies');
      throw Exception(installRes.stderr);
    }
    bundlerProgress.complete('$platform dependencies installed.');
  }
}
