import 'dart:io';
import 'package:path/path.dart' as p;

void main() async {
  final projectRoot = Directory.current.path;
  final templatesDir = p.join(projectRoot, 'lib', 'src', 'templates');
  final brickDir = p.join(templatesDir, 'fastlane_brick');
  final brickYamlFile = File(p.join(brickDir, 'brick.yaml'));
  final brickTemplatesDir = Directory(p.join(brickDir, '__brick__'));

  print('Building Mason Brick from template folders...');

  // 1. Recreate clean brick directories
  if (Directory(brickDir).existsSync()) {
    Directory(brickDir).deleteSync(recursive: true);
  }
  brickTemplatesDir.createSync(recursive: true);

  // 2. Write brick.yaml
  brickYamlFile.writeAsStringSync('''name: fastlane
description: Fastlane templates for Android and iOS in a Flutter project.
version: 0.1.0
environment:
  mason: ">=0.1.0-dev.26 <0.2.0"
vars:
  project_name:
    type: string
    description: The name of the Flutter project.
    default: flutter_app
  project_name_flat:
    type: string
    description: The project name without underscores for package/bundle IDs.
    default: flutterapp
  android:
    type: boolean
    description: Whether to generate Android Fastlane files.
    default: true
  ios:
    type: boolean
    description: Whether to generate iOS Fastlane files.
    default: true
  has_environments:
    type: boolean
    description: Whether the project has custom flavor environments.
    default: false
  environments:
    type: list
    description: List of flavor environment objects containing name, flavor, and scheme.
''');

  // 3. Write release_config.yaml template
  final configTemplate = File(
    p.join(brickTemplatesDir.path, 'release_config.yaml'),
  );
  configTemplate.writeAsStringSync('''project_name: {{project_name}}
shared:
  firebase_service_json_file: "secrets/firebase-credentials.json"
  firebase_groups: "qa-testers"
  dart_defines:
    # DEFINE_KEY: "value"
  dart_define_from_file: "secrets/.env"
  android:
    google_play_json_key_file: "secrets/play-credentials.json"
  ios:
    app_store_team_id: ""
    asc_key_id: ""
    asc_issuer_id: ""
    asc_key_filepath: "secrets/appstore-connect-key.p8"
    match:
      git_url: "git@github.com:myorg/certificates.git"
      git_branch: "master"
      password: ""
environments:
{{#has_environments}}
{{#environments}}
  {{name}}:
    flavor: {{flavor}}
    entry_point: lib/main_{{name}}.dart
    android:
      package_name: com.example.{{project_name_flat}}.{{name}}
      firebase_app_id: ""
    ios:
      bundle_id: com.example.{{project_name_flat}}.{{name}}
      firebase_app_id: ""
      scheme: "{{scheme}}"
{{/environments}}
{{/has_environments}}
{{^has_environments}}
  default:
    entry_point: lib/main.dart
    android:
      package_name: com.example.{{project_name_flat}}
      firebase_app_id: ""
    ios:
      bundle_id: com.example.{{project_name_flat}}
      firebase_app_id: ""
{{/has_environments}}
''');

  // 4. Copy templates
  final androidSourceDir = p.join(templatesDir, 'android');

  // Let's create helper to copy with conditional wrapping
  void copyConditional(String srcPath, String destRelPath, String condition) {
    // destRelPath: e.g. "android/Gemfile"
    // condition: e.g. "android"
    // Resulting path: "__brick__/{{#android}}android/Gemfile{{/android}}"
    // If the path contains multiple segments, e.g. "android/fastlane/Fastfile", we wrap it as:
    // "__brick__/{{#android}}android/fastlane/Fastfile{{/android}}"
    final segments = p.split(destRelPath);
    segments[0] = '{{#$condition}}${segments[0]}';
    segments[segments.length - 1] =
        '${segments[segments.length - 1]}{{/$condition}}';

    final fullDestPath = p.joinAll([brickTemplatesDir.path, ...segments]);
    Directory(p.dirname(fullDestPath)).createSync(recursive: true);
    File(srcPath).copySync(fullDestPath);
  }

  // Copy Android files with correct conditional wrapping
  copyConditional(
    p.join(androidSourceDir, 'Gemfile'),
    'android/Gemfile',
    'android',
  );
  copyConditional(
    p.join(androidSourceDir, '.bundle', 'config'),
    'android/.bundle/config',
    'android',
  );
  copyConditional(
    p.join(androidSourceDir, 'Fastfile'),
    'android/fastlane/Fastfile',
    'android',
  );
  copyConditional(
    p.join(androidSourceDir, 'Appfile'),
    'android/fastlane/Appfile',
    'android',
  );
  copyConditional(
    p.join(androidSourceDir, 'Pluginfile'),
    'android/fastlane/Pluginfile',
    'android',
  );

  // Copy iOS files with correct conditional wrapping
  final iosSourceDir = p.join(templatesDir, 'ios');
  copyConditional(p.join(iosSourceDir, 'Gemfile'), 'ios/Gemfile', 'ios');
  copyConditional(
    p.join(iosSourceDir, '.bundle', 'config'),
    'ios/.bundle/config',
    'ios',
  );
  copyConditional(
    p.join(iosSourceDir, 'Fastfile'),
    'ios/fastlane/Fastfile',
    'ios',
  );
  copyConditional(
    p.join(iosSourceDir, 'Appfile'),
    'ios/fastlane/Appfile',
    'ios',
  );
  copyConditional(
    p.join(iosSourceDir, 'Gymfile'),
    'ios/fastlane/Gymfile',
    'ios',
  );
  copyConditional(
    p.join(iosSourceDir, 'Matchfile'),
    'ios/fastlane/Matchfile',
    'ios',
  );
  copyConditional(
    p.join(iosSourceDir, 'Pluginfile'),
    'ios/fastlane/Pluginfile',
    'ios',
  );

  print('Running mason bundle...');
  // 5. Run mason bundle
  final bundleResult = await Process.run('mason', [
    'bundle',
    brickDir,
    '-t',
    'dart',
    '-o',
    templatesDir,
  ], runInShell: true);

  if (bundleResult.exitCode != 0) {
    print('Failed to bundle brick: ${bundleResult.stderr}');
    exit(1);
  }

  print(bundleResult.stdout);

  // 6. Cleanup temporary brick directory
  Directory(brickDir).deleteSync(recursive: true);
  print('Successfully bundled templates from android & ios source folders!');
}
