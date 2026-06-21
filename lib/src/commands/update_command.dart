import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:mason/mason.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_writer/yaml_writer.dart';
import 'base_command.dart';
import '../config/release_config.dart';
import '../templates/fastlane_bundle.dart';

/// A command to update Fastlane templates and merge configurations.
class UpdateCommand extends BaseCommand {
  @override
  final String name = 'update';

  @override
  final String description =
      'Update generated Fastlane templates and merge new config fields without overwriting existing settings.';

  /// Creates a new [UpdateCommand].
  UpdateCommand({required super.logger});

  @override
  Future<int> run() async {
    if (!checkFlutterProject()) return 1;

    if (!configFile.existsSync()) {
      logger.err(
        'No release_config.yaml found. Please run "release_tool init" first.',
      );
      return 1;
    }

    final progress = logger.progress(
      'Updating Fastlane templates and configuration...',
    );

    try {
      // 1. Read and parse existing release_config.yaml into Map
      final existingYamlContent = configFile.readAsStringSync();
      final existingDoc = loadYaml(existingYamlContent);
      if (existingDoc is! YamlMap) {
        progress.fail('Existing release_config.yaml is not a valid YAML Map.');
        return 1;
      }

      // 2. Load release config model to extract variables for templates
      final config = ReleaseConfig.fromYaml(existingYamlContent);
      final projectName = config.projectName;

      final androidDir = Directory(p.join(projectDir.path, 'android'));
      final iosDir = Directory(p.join(projectDir.path, 'ios'));
      final hasAndroid = androidDir.existsSync();
      final hasIos = iosDir.existsSync();

      // Form environments list from existing configuration to regenerate templates
      final environments = <Map<String, String>>[];
      for (final entry in config.environments.entries) {
        environments.add({
          'name': entry.key,
          'flavor': entry.value.flavor ?? '',
          'scheme': entry.value.ios?.scheme ?? entry.value.flavor ?? '',
        });
      }

      // 3. Generate fresh templates in-place (this will overwrite release_config.yaml temporarily)
      progress.update('Regenerating templates via Mason...');
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

      // Log generated files (skipping release_config.yaml since we will merge and rewrite it)
      for (final file in filesGenerated) {
        final relativePath = p.relative(file.path, from: projectDir.path);
        if (relativePath != 'release_config.yaml') {
          logger.info('  Updated $relativePath');
        }
      }

      // 4. Read newly generated release_config.yaml template
      final templateYamlContent = configFile.readAsStringSync();
      final templateDoc = loadYaml(templateYamlContent);
      if (templateDoc is! YamlMap) {
        progress.fail(
          'Generated release_config.yaml template is not a valid YAML Map.',
        );
        return 1;
      }

      // 5. Deep merge existing config into the new template
      progress.update('Merging configuration changes...');
      final mergedMap = _deepMerge(existingDoc, templateDoc);

      // 6. Write merged map back to release_config.yaml
      final writer = YamlWriter();
      configFile.writeAsStringSync(writer.write(mergedMap));
      logger.info('  Merged updates into release_config.yaml');

      progress.complete('Update completed successfully!');
      return 0;
    } catch (e) {
      progress.fail('Failed to update: $e');
      return 1;
    }
  }

  Map<String, dynamic> _deepMerge(
    Map<dynamic, dynamic> target,
    Map<dynamic, dynamic> source,
  ) {
    final result = Map<String, dynamic>.from(
      target.map((k, v) => MapEntry(k.toString(), v)),
    );

    for (final entry in source.entries) {
      final key = entry.key.toString();
      final value = entry.value;

      if (key == 'environments') {
        if (value is Map && result[key] is Map) {
          final targetEnvs = result[key] as Map;
          final templateEnvs = value;

          dynamic templateEnv;
          for (final e in templateEnvs.values) {
            if (e is Map || e is YamlMap) {
              templateEnv = e;
              break;
            }
          }

          if (templateEnv != null) {
            final mergedEnvs = <String, dynamic>{};
            for (final envEntry in targetEnvs.entries) {
              final envName = envEntry.key.toString();
              final envVal = envEntry.value;
              if (envVal is Map) {
                mergedEnvs[envName] = _deepMerge(envVal, templateEnv as Map);
              } else if (envVal is YamlMap) {
                mergedEnvs[envName] = _deepMerge(envVal, templateEnv as Map);
              } else {
                mergedEnvs[envName] = envVal;
              }
            }
            result[key] = mergedEnvs;
          }
        }
        continue;
      }

      if (!result.containsKey(key)) {
        result[key] = value;
      } else {
        final existingValue = result[key];
        if (existingValue is Map && value is Map) {
          result[key] = _deepMerge(existingValue, value);
        } else if (existingValue is YamlMap && value is Map) {
          result[key] = _deepMerge(existingValue, value);
        }
      }
    }

    return result;
  }

  /// Executes the [deepMergeForTesting] operation.
  Map<String, dynamic> deepMergeForTesting(
    Map<dynamic, dynamic> target,
    Map<dynamic, dynamic> source,
  ) => _deepMerge(target, source);
}
