import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:path/path.dart' as p;
import 'package:fp_release_tool/src/config/release_config.dart';
import 'package:fp_release_tool/src/utils/version_utils.dart';
import 'package:fp_release_tool/src/utils/project_utils.dart';
import 'package:fp_release_tool/src/commands/update_command.dart';
import 'package:mason_logger/mason_logger.dart';

void main() {
  group('Semantic Versioning Engine', () {
    test('parseVersion extracts semver and build number correctly', () {
      final (semver1, build1) = VersionUtils.parseVersion('1.0.0+1');
      expect(semver1, Version(1, 0, 0));
      expect(build1, 1);

      final (semver2, build2) = VersionUtils.parseVersion('2.1.3-beta+45');
      expect(semver2, Version(2, 1, 3, pre: 'beta'));
      expect(build2, 45);

      final (semver3, build3) = VersionUtils.parseVersion('1.0.0');
      expect(semver3, Version(1, 0, 0));
      expect(build3, null);
    });

    test('bumpVersion bumps correctly based on type', () {
      expect(VersionUtils.bumpVersion('1.0.0+1', 'patch'), '1.0.1+2');
      expect(VersionUtils.bumpVersion('1.0.0+1', 'minor'), '1.1.0+2');
      expect(VersionUtils.bumpVersion('1.0.0+1', 'major'), '2.0.0+2');
      expect(VersionUtils.bumpVersion('1.0.0+1', 'build'), '1.0.0+2');
      expect(VersionUtils.bumpVersion('1.0.0', 'build'), '1.0.0+1');
    });

    test('writeVersionToPubspec regex works and preserves rest of file', () {
      final tempDir = Directory.systemTemp.createTempSync();
      final testPubspec = File('${tempDir.path}/pubspec.yaml');
      testPubspec.writeAsStringSync('''
name: my_test_app
# This is a comment we must preserve
version: 1.0.0+5 # Another comment
dependencies:
  flutter:
    sdk: flutter
''');

      VersionUtils.writeVersionToPubspec(testPubspec, '1.1.0+6');

      final content = testPubspec.readAsStringSync();
      expect(content, contains('version: 1.1.0+6'));
      expect(content, contains('# This is a comment we must preserve'));
      expect(content, contains('# Another comment'));
      expect(content, contains('name: my_test_app'));

      tempDir.deleteSync(recursive: true);
    });
  });

  group('Configuration Parser', () {
    test('ReleaseConfig.fromYaml parses valid config correctly', () {
      const yamlContent = '''
project_name: test_release_app
environments:
  dev:
    flavor: dev
    entry_point: lib/main_dev.dart
    android:
      package_name: com.test.dev
      firebase_app_id: 1:android:dev
      firebase_groups: dev-testers
      firebase_service_json_file: android/firebase.json
      google_play_json_key_file: android/play.json
    ios:
      bundle_id: com.test.dev
      firebase_app_id: 1:ios:dev
      scheme: dev
      app_store_team_id: TEAM123
      match:
        git_url: git@github.com:test/certs.git
        git_branch: staging
      firebase_service_json_file: ios/firebase.json
''';

      final config = ReleaseConfig.fromYaml(yamlContent);
      expect(config.projectName, 'test_release_app');
      expect(config.environments.containsKey('dev'), true);

      final dev = config.environments['dev']!;
      expect(dev.flavor, 'dev');
      expect(dev.entryPoint, 'lib/main_dev.dart');

      expect(dev.android?.packageName, 'com.test.dev');
      expect(dev.android?.firebaseAppId, '1:android:dev');
      expect(dev.android?.firebaseGroups, 'dev-testers');
      expect(dev.android?.firebaseServiceJsonFile, 'android/firebase.json');
      expect(dev.android?.googlePlayJsonKeyFile, 'android/play.json');

      expect(dev.ios?.bundleId, 'com.test.dev');
      expect(dev.ios?.firebaseAppId, '1:ios:dev');
      expect(dev.ios?.scheme, 'dev');
      expect(dev.ios?.appStoreTeamId, 'TEAM123');
      expect(dev.ios?.match?.gitUrl, 'git@github.com:test/certs.git');
      expect(dev.ios?.match?.gitBranch, 'staging');
      expect(dev.ios?.firebaseServiceJsonFile, 'ios/firebase.json');
    });

    test('ReleaseConfig parses shared config and environments correctly', () {
      const yamlContent = '''
project_name: test_release_app
shared:
  android:
    firebase_service_json_file: shared/firebase.json
    google_play_json_key_file: shared/play.json
  ios:
    app_store_team_id: SHARED_TEAM
    match:
      git_url: git@github.com:shared/certs.git
      git_branch: master
    firebase_service_json_file: shared/firebase.json
environments:
  dev:
    flavor: dev
    android:
      package_name: com.test.dev
      firebase_service_json_file: override/firebase.json
    ios:
      bundle_id: com.test.dev
      scheme: dev
''';

      final config = ReleaseConfig.fromYaml(yamlContent);
      expect(
        config.shared.android?.firebaseServiceJsonFile,
        'shared/firebase.json',
      );
      expect(config.shared.android?.googlePlayJsonKeyFile, 'shared/play.json');
      expect(config.shared.ios?.appStoreTeamId, 'SHARED_TEAM');
      expect(
        config.shared.ios?.match?.gitUrl,
        'git@github.com:shared/certs.git',
      );
      expect(config.shared.ios?.match?.gitBranch, 'master');

      final dev = config.environments['dev']!;
      expect(dev.android?.packageName, 'com.test.dev');
      // Overridden
      expect(dev.android?.firebaseServiceJsonFile, 'override/firebase.json');
      // Inherited (fallback from shared)
      expect(
        dev.android?.googlePlayJsonKeyFile ??
            config.shared.android?.googlePlayJsonKeyFile,
        'shared/play.json',
      );
      expect(
        dev.ios?.appStoreTeamId ?? config.shared.ios?.appStoreTeamId,
        'SHARED_TEAM',
      );
    });

    test(
      'ReleaseConfig parses global shared firebaseServiceJsonFile and firebaseGroups correctly',
      () {
        const yamlContent = '''
project_name: test_release_app
shared:
  firebase_service_json_file: global/firebase.json
  firebase_groups: global-testers
  android:
    google_play_json_key_file: shared/play.json
  ios:
    app_store_team_id: SHARED_TEAM
environments:
  dev:
    flavor: dev
    android:
      package_name: com.test.dev
    ios:
      bundle_id: com.test.dev
      scheme: dev
''';

        final config = ReleaseConfig.fromYaml(yamlContent);
        expect(config.shared.firebaseServiceJsonFile, 'global/firebase.json');
        expect(config.shared.firebaseGroups, 'global-testers');
        expect(
          config.shared.android?.googlePlayJsonKeyFile,
          'shared/play.json',
        );

        final dev = config.environments['dev']!;
        expect(dev.android?.packageName, 'com.test.dev');
        expect(
          dev.android?.firebaseServiceJsonFile ??
              config.shared.firebaseServiceJsonFile,
          'global/firebase.json',
        );
        expect(
          dev.ios?.firebaseGroups ?? config.shared.firebaseGroups,
          'global-testers',
        );
      },
    );
  });

  group('Flavor Auto-Detection Engine', () {
    test('detectAndroidFlavors parses groovy productFlavors correctly', () {
      final tempDir = Directory.systemTemp.createTempSync();
      final gradleFile = File('${tempDir.path}/android/app/build.gradle');
      gradleFile.createSync(recursive: true);
      gradleFile.writeAsStringSync('''
android {
    defaultConfig {
        applicationId "com.example.app"
    }
    
    // Some comments inside
    productFlavors {
        dev {
            dimension "default"
            applicationIdSuffix ".dev"
        }
        staging {
            dimension "default"
            applicationIdSuffix ".staging"
        }
        prod {
            dimension "default"
        }
    }
}
''');

      final flavors = ProjectUtils.detectAndroidFlavors(tempDir);
      expect(flavors, ['dev', 'prod', 'staging']);

      tempDir.deleteSync(recursive: true);
    });

    test('detectAndroidFlavors parses kotlin DSL productFlavors correctly', () {
      final tempDir = Directory.systemTemp.createTempSync();
      final gradleKtsFile = File(
        '${tempDir.path}/android/app/build.gradle.kts',
      );
      gradleKtsFile.createSync(recursive: true);
      gradleKtsFile.writeAsStringSync('''
android {
    productFlavors {
        create("dev") {
            dimension = "default"
        }
        register("staging") {
            dimension = "default"
        }
    }
}
''');

      final flavors = ProjectUtils.detectAndroidFlavors(tempDir);
      expect(flavors, ['dev', 'staging']);

      tempDir.deleteSync(recursive: true);
    });
  });

  group('Deploy Command Environment Fallbacks', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('release_tool_test_deploy');
      Directory('${tempDir.path}/ios').createSync(recursive: true);
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: test_app
version: 1.0.0+1
''');
      File('${tempDir.path}/release_config.yaml').writeAsStringSync('''
shared:
  ios:
    bundle_id: com.example.app
    app_store_team_id: "TEAM_123"
environments:
  dev:
    flavor: dev
    entry_point: lib/main.dart
    ios:
      bundle_id: com.example.dev
''');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test(
      'resolves App Store Connect credentials from environment variables',
      () async {
        final scriptPath = p.join(
          Directory.current.path,
          'bin/release_tool.dart',
        );
        final result = await Process.run(
          'dart',
          [
            'run',
            scriptPath,
            'deploy',
            '--env',
            'dev',
            '--platform',
            'ios',
            '--target',
            'store',
            '--dry-run',
            '--yes',
          ],
          environment: {
            'ASC_KEY_ID': 'env-key-id-123',
            'ASC_ISSUER_ID': 'env-issuer-id-456',
            'ASC_KEY_CONTENT': 'env-key-content-789',
          },
          workingDirectory: tempDir.path,
        );

        expect(result.exitCode, 0);
        final stdout = result.stdout as String;
        expect(stdout, contains('ASC_KEY_ID: env-key-id-123'));
        expect(stdout, contains('ASC_ISSUER_ID: env-issuer-id-456'));
        expect(stdout, contains('ASC_KEY_CONTENT: env-key-content-789'));
      },
    );

    test('base64 encodes raw PEM keys from environment variables', () async {
      final scriptPath = p.join(
        Directory.current.path,
        'bin/release_tool.dart',
      );
      final rawPem =
          '-----BEGIN PRIVATE KEY-----\nMY_PRIVATE_KEY_DATA\n-----END PRIVATE KEY-----';
      final expectedBase64 = base64.encode(utf8.encode(rawPem.trim()));

      final result = await Process.run(
        'dart',
        [
          'run',
          scriptPath,
          'deploy',
          '--env',
          'dev',
          '--platform',
          'ios',
          '--target',
          'store',
          '--dry-run',
          '--yes',
        ],
        environment: {
          'ASC_KEY_ID': 'env-key-id-123',
          'ASC_ISSUER_ID': 'env-issuer-id-456',
          'ASC_KEY_CONTENT': rawPem,
        },
        workingDirectory: tempDir.path,
      );

      expect(result.exitCode, 0);
      final stdout = result.stdout as String;
      expect(stdout, contains('ASC_KEY_ID: env-key-id-123'));
      expect(stdout, contains('ASC_ISSUER_ID: env-issuer-id-456'));
      final expectedPrefix = expectedBase64.substring(0, 15);
      final expectedSuffix = expectedBase64.substring(
        expectedBase64.length - 15,
      );
      expect(
        stdout,
        contains(
          'ASC_KEY_CONTENT: $expectedPrefix... [TRUNCATED] ...$expectedSuffix',
        ),
      );
    });
  });

  group('Dart Defines Support', () {
    test('ReleaseConfig.fromYaml parses map format dart_defines', () {
      const yamlContent = '''
project_name: test_app
shared:
  dart_defines:
    DEFINE_A: valueA
    DEFINE_B: valueB
environments:
  dev:
    dart_defines:
      DEFINE_B: valueB_override
      DEFINE_C: valueC
''';
      final config = ReleaseConfig.fromYaml(yamlContent);
      expect(config.shared.dartDefines, {
        'DEFINE_A': 'valueA',
        'DEFINE_B': 'valueB',
      });

      final dev = config.environments['dev']!;
      expect(dev.dartDefines, {
        'DEFINE_B': 'valueB_override',
        'DEFINE_C': 'valueC',
      });
    });

    test('ReleaseConfig.fromYaml parses list format dart_defines', () {
      const yamlContent = '''
project_name: test_app
shared:
  dart_defines:
    - DEFINE_A=valueA
    - DEFINE_B=valueB
''';
      final config = ReleaseConfig.fromYaml(yamlContent);
      expect(config.shared.dartDefines, {
        'DEFINE_A': 'valueA',
        'DEFINE_B': 'valueB',
      });
    });

    test('ReleaseConfig.fromYaml parses dart_define_from_file', () {
      const yamlContent = '''
project_name: test_app
shared:
  dart_define_from_file: secrets/shared.env
environments:
  dev:
    dart_define_from_file: secrets/dev.env
''';
      final config = ReleaseConfig.fromYaml(yamlContent);
      expect(config.shared.dartDefineFromFile, 'secrets/shared.env');
      expect(config.environments['dev']!.dartDefineFromFile, 'secrets/dev.env');
    });
  });

  group('Update Command Config Merging', () {
    test('deepMerge merges new keys and preserves user overrides', () {
      final mockLogger = Logger();
      final updateCmd = UpdateCommand(logger: mockLogger);

      final target = {
        'project_name': 'my_custom_app',
        'shared': {'firebase_service_json_file': 'custom/firebase.json'},
        'environments': {
          'dev': {
            'flavor': 'dev',
            'android': {'package_name': 'com.custom.dev'},
          },
        },
      };

      final source = {
        'project_name': 'flutter_app',
        'shared': {
          'firebase_service_json_file': 'secrets/firebase-credentials.json',
          'firebase_groups': 'qa-testers',
          'dart_defines': {'KEY': 'VAL'},
        },
        'environments': {
          'default': {
            'entry_point': 'lib/main.dart',
            'dart_defines': {'KEY': 'VAL'},
          },
        },
      };

      final merged = updateCmd.deepMergeForTesting(target, source);

      // Preserved values
      expect(merged['project_name'], 'my_custom_app');
      expect(
        (merged['shared'] as Map)['firebase_service_json_file'],
        'custom/firebase.json',
      );
      expect(((merged['environments'] as Map)['dev'] as Map)['flavor'], 'dev');
      expect(
        (((merged['environments'] as Map)['dev'] as Map)['android']
            as Map)['package_name'],
        'com.custom.dev',
      );

      // Added values
      expect((merged['shared'] as Map)['firebase_groups'], 'qa-testers');
      expect((merged['shared'] as Map)['dart_defines'], {'KEY': 'VAL'});

      // dev environment should get target merged keys (like dart_defines)
      expect(((merged['environments'] as Map)['dev'] as Map)['dart_defines'], {
        'KEY': 'VAL',
      });
      expect(
        ((merged['environments'] as Map)['dev'] as Map)['entry_point'],
        'lib/main.dart',
      );

      // default environment should NOT be added since dev already existed
      expect((merged['environments'] as Map).containsKey('default'), false);
    });
  });
}
