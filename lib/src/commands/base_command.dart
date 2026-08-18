import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import '../config/release_config.dart';

/// Base class for all release_tool commands.
abstract class BaseCommand extends Command<int> {
  /// The logger used for outputting information.
  final Logger logger;

  /// Creates a new [BaseCommand] with the given [logger].
  BaseCommand({required this.logger});

  /// The root directory of the project.
  Directory get projectDir => Directory.current;

  /// The pubspec.yaml file of the project.
  File get pubspecFile => File(p.join(projectDir.path, 'pubspec.yaml'));

  /// The release_config.yaml file of the project.
  File get configFile => File(p.join(projectDir.path, 'release_config.yaml'));

  /// Checks if the current directory is a valid Flutter project.
  bool checkFlutterProject() {
    if (!pubspecFile.existsSync()) {
      logger.err(
        'This command must be run in the root of a Flutter project (missing pubspec.yaml).',
      );
      return false;
    }
    return true;
  }

  /// Lazy-loads the configuration.
  ReleaseConfig? loadConfig() {
    if (!configFile.existsSync()) {
      logger.err(
        'Configuration file release_config.yaml not found. Please run: release_tool init',
      );
      return null;
    }
    try {
      return ReleaseConfig.fromFile(configFile);
    } catch (e) {
      logger.err('Failed to parse release_config.yaml: $e');
      return null;
    }
  }

  /// Resolves [relativeOrAbsolutePath] to an absolute path relative to
  /// [projectDir]. Returns `null` if [relativeOrAbsolutePath] is `null` or empty.
  String? makeAbsolutePath(String? relativeOrAbsolutePath) {
    if (relativeOrAbsolutePath == null || relativeOrAbsolutePath.isEmpty) {
      return null;
    }
    if (p.isAbsolute(relativeOrAbsolutePath)) return relativeOrAbsolutePath;
    return p.normalize(p.join(projectDir.path, relativeOrAbsolutePath));
  }

  /// Whether this command is running in an interactive terminal session.
  /// `false` on a real TTY that also has a `CI` environment variable set,
  /// so pipelines running under a pseudo-TTY (some self-hosted runners,
  /// `docker run -it`) don't hang waiting for prompts that will never come.
  bool get isInteractiveSession =>
      stdin.hasTerminal && Platform.environment['CI'] == null;
}
