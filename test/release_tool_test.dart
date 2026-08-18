import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:path/path.dart' as p;
import 'package:fp_release_tool/src/config/release_config.dart';
import 'package:fp_release_tool/src/utils/version_utils.dart';
import 'package:fp_release_tool/src/utils/project_utils.dart';
import 'package:fp_release_tool/src/commands/update_command.dart';
import 'package:fp_release_tool/src/utils/release_cache.dart';
import 'package:fp_release_tool/src/utils/update_check_cache.dart';
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

  group('Version Command Non-Interactive Behavior', () {
    late Directory tempDir;
    late String scriptPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync(
        'release_tool_test_version_cmd',
      );
      scriptPath = p.join(Directory.current.path, 'bin/release_tool.dart');
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: test_app
version: 1.0.0+1
''');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test(
      'fails with a clear error instead of hanging when no bump type is given',
      () async {
        final result = await Process.run('dart', [
          'run',
          scriptPath,
          'version',
        ], workingDirectory: tempDir.path);

        expect(result.exitCode, 1);
        expect(
          result.stderr as String,
          contains('Missing bump type argument in non-interactive environment'),
        );
      },
    );

    test(
      'bumps the version without prompting for confirmation when a bump type is given',
      () async {
        final result = await Process.run('dart', [
          'run',
          scriptPath,
          'version',
          'patch',
        ], workingDirectory: tempDir.path);

        expect(result.exitCode, 0);
        final pubspec = File('${tempDir.path}/pubspec.yaml').readAsStringSync();
        expect(pubspec, contains('version: 1.0.1+2'));
      },
    );
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

  group('Deploy Release Notes File', () {
    late Directory tempDir;
    late String scriptPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync(
        'release_tool_test_release_notes',
      );
      scriptPath = p.join(Directory.current.path, 'bin/release_tool.dart');
      Directory('${tempDir.path}/android').createSync(recursive: true);
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: test_app
version: 1.0.0+1
''');
      File('${tempDir.path}/release_config.yaml').writeAsStringSync('''
environments:
  dev:
    android:
      package_name: com.example.dev
      firebase_app_id: 1:android:dev
''');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    Future<ProcessResult> runDeploy(List<String> extraArgs) =>
        Process.run('dart', [
          'run',
          scriptPath,
          'deploy',
          '--env',
          'dev',
          '--platform',
          'android',
          '--target',
          'firebase',
          '--dry-run',
          '--yes',
          ...extraArgs,
        ], workingDirectory: tempDir.path);

    test('--release-notes-file overrides the default release notes', () async {
      File(
        '${tempDir.path}/notes.txt',
      ).writeAsStringSync('- Fixed the thing\n- Added the other thing\n');

      final result = await runDeploy(['--release-notes-file', 'notes.txt']);

      expect(result.exitCode, 0);
      expect(
        result.stdout as String,
        contains('- Fixed the thing\n- Added the other thing'),
      );
    });

    test(
      'fails with a clear error when the release notes file is missing',
      () async {
        final result = await runDeploy(['--release-notes-file', 'missing.txt']);

        expect(result.exitCode, 1);
        expect(
          result.stderr as String,
          contains('Release notes file not found: missing.txt'),
        );
      },
    );

    test(
      '--release-notes-file takes precedence over --release-notes with a warning',
      () async {
        File('${tempDir.path}/notes.txt').writeAsStringSync('from the file');

        final result = await runDeploy([
          '--release-notes',
          'from the flag',
          '--release-notes-file',
          'notes.txt',
        ]);

        expect(result.exitCode, 0);
        expect(result.stdout as String, contains('"from the file"'));
        expect(
          result.stderr as String,
          contains(
            'Both --release-notes and --release-notes-file were provided',
          ),
        );
      },
    );
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

  group('Update Check Cache', () {
    late Directory tempDir;
    late File cacheFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('release_tool_test_cache');
      cacheFile = File(p.join(tempDir.path, 'update_check.json'));
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('read returns null when no cache file exists', () {
      final cache = UpdateCheckCache(file: cacheFile);
      expect(cache.read(), isNull);
    });

    test('write then read round-trips the latest version', () {
      final cache = UpdateCheckCache(file: cacheFile);
      cache.write('9.9.9');
      expect(cache.read(), '9.9.9');
    });

    test(
      'read returns null when the cached entry is older than the check interval',
      () {
        cacheFile.createSync(recursive: true);
        cacheFile.writeAsStringSync(
          jsonEncode({
            'checkedAt': DateTime.now()
                .subtract(UpdateCheckCache.checkInterval * 2)
                .toIso8601String(),
            'latestVersion': '9.9.9',
          }),
        );

        final cache = UpdateCheckCache(file: cacheFile);
        expect(cache.read(), isNull);
      },
    );

    test('read returns null when the cache file contents are invalid', () {
      cacheFile.createSync(recursive: true);
      cacheFile.writeAsStringSync('not valid json');

      final cache = UpdateCheckCache(file: cacheFile);
      expect(cache.read(), isNull);
    });
  });

  group('Doctor Command', () {
    late Directory tempDir;
    late String scriptPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('release_tool_test_doctor');
      scriptPath = p.join(Directory.current.path, 'bin/release_tool.dart');
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: test_app
version: 1.0.0+1
''');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test(
      'fails with exit code 1 when android package_name is missing',
      () async {
        Directory('${tempDir.path}/android').createSync(recursive: true);
        File('${tempDir.path}/release_config.yaml').writeAsStringSync('''
environments:
  dev:
    flavor: dev
    android: {}
''');

        final result = await Process.run('dart', [
          'run',
          scriptPath,
          'doctor',
          '--env',
          'dev',
        ], workingDirectory: tempDir.path);

        expect(result.exitCode, 1);
        final stdout = result.stdout as String;
        expect(stdout, contains('Android: package_name is required.'));
      },
    );

    test(
      'exits 0 with warnings only when the ios environment is valid',
      () async {
        Directory('${tempDir.path}/ios').createSync(recursive: true);
        File('${tempDir.path}/release_config.yaml').writeAsStringSync('''
environments:
  dev:
    flavor: dev
    ios:
      bundle_id: com.example.dev
      app_store_team_id: "TEAM_123"
      match:
        git_url: git@github.com:example/certs.git
''');

        final result = await Process.run(
          'dart',
          ['run', scriptPath, 'doctor', '--env', 'dev'],
          environment: {
            'ASC_KEY_ID': 'env-key-id-123',
            'ASC_ISSUER_ID': 'env-issuer-id-456',
            'ASC_KEY_CONTENT': 'env-key-content-789',
          },
          workingDirectory: tempDir.path,
        );

        expect(result.exitCode, 0);
        final stdout = result.stdout as String;
        expect(
          stdout,
          contains('iOS: App Store Connect API credentials resolved.'),
        );
        // The summary is logged via logger.warn, which mason_logger writes to stderr.
        final stderr = result.stderr as String;
        expect(stderr, contains('warning(s) found'));
      },
    );
  });

  group('Global --verbose Flag', () {
    late Directory tempDir;
    late String scriptPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync(
        'release_tool_test_verbose',
      );
      scriptPath = p.join(Directory.current.path, 'bin/release_tool.dart');
      Directory('${tempDir.path}/ios').createSync(recursive: true);
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: test_app
version: 1.0.0+1
''');
      File('${tempDir.path}/release_config.yaml').writeAsStringSync('''
environments:
  dev:
    ios:
      bundle_id: com.example.dev
      app_store_team_id: "TEAM_123"
      match:
        git_url: git@github.com:example/certs.git
      asc_key_filepath: does/not/exist.p8
''');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('detail logs are hidden by default', () async {
      final result = await Process.run('dart', [
        'run',
        scriptPath,
        'doctor',
        '--env',
        'dev',
      ], workingDirectory: tempDir.path);

      expect(result.stdout, isNot(contains('key file not found')));
    });

    test('--verbose surfaces detail logs', () async {
      final result = await Process.run('dart', [
        'run',
        scriptPath,
        '--verbose',
        'doctor',
        '--env',
        'dev',
      ], workingDirectory: tempDir.path);

      expect(
        result.stdout,
        contains('App Store Connect key file not found at: does/not/exist.p8'),
      );
    });
  });

  group('Release Cache', () {
    late Directory tempDir;
    late ReleaseCache cache;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync(
        'release_tool_test_release_cache',
      );
      cache = ReleaseCache(tempDir);
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('read returns empty map when nothing is cached', () {
      expect(cache.read('dev'), isEmpty);
    });

    test('recordRelease then read round-trips version per platform', () {
      cache.recordRelease(
        envName: 'dev',
        platform: 'android',
        version: '1.2.3+45',
      );
      cache.recordRelease(envName: 'dev', platform: 'ios', version: '1.2.3+46');

      final result = cache.read('dev');
      expect(result['android']!.version, '1.2.3+45');
      expect(result['ios']!.version, '1.2.3+46');
    });

    test('recordRelease does not affect other environments', () {
      cache.recordRelease(
        envName: 'dev',
        platform: 'android',
        version: '1.0.0+1',
      );
      cache.recordRelease(
        envName: 'prod',
        platform: 'android',
        version: '2.0.0+1',
      );

      expect(cache.read('dev')['android']!.version, '1.0.0+1');
      expect(cache.read('prod')['android']!.version, '2.0.0+1');
    });

    test('clear removes only the specified platform', () {
      cache.recordRelease(
        envName: 'dev',
        platform: 'android',
        version: '1.0.0+1',
      );
      cache.recordRelease(envName: 'dev', platform: 'ios', version: '1.0.0+1');

      cache.clear('dev', platform: 'android');

      final result = cache.read('dev');
      expect(result.containsKey('android'), false);
      expect(result.containsKey('ios'), true);
    });

    test('clear with no platform removes the whole environment entry', () {
      cache.recordRelease(
        envName: 'dev',
        platform: 'android',
        version: '1.0.0+1',
      );
      cache.recordRelease(envName: 'dev', platform: 'ios', version: '1.0.0+1');

      cache.clear('dev');

      expect(cache.read('dev'), isEmpty);
    });

    test('malformed cache file is treated as empty rather than throwing', () {
      final file = File(
        p.join(tempDir.path, '.release_tool', 'latest_release_cache.json'),
      );
      file.createSync(recursive: true);
      file.writeAsStringSync('not valid json');

      expect(cache.read('dev'), isEmpty);
      // Should not throw when writing over a corrupt file either.
      cache.recordRelease(
        envName: 'dev',
        platform: 'android',
        version: '1.0.0+1',
      );
      expect(cache.read('dev')['android']!.version, '1.0.0+1');
    });
  });

  group('Remote Config Command', () {
    late Directory tempDir;
    late String scriptPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync(
        'release_tool_test_remote_config',
      );
      scriptPath = p.join(Directory.current.path, 'bin/release_tool.dart');
      Directory('${tempDir.path}/android').createSync(recursive: true);
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: test_app
version: 1.0.0+1
''');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    void seedCache(String json) {
      final dir = Directory(p.join(tempDir.path, '.release_tool'))
        ..createSync(recursive: true);
      File(
        p.join(dir.path, 'latest_release_cache.json'),
      ).writeAsStringSync(json);
    }

    test('fails when no release is cached for the environment', () async {
      File('${tempDir.path}/release_config.yaml').writeAsStringSync('''
environments:
  dev:
    android:
      package_name: com.example.dev
''');

      final result = await Process.run('dart', [
        'run',
        scriptPath,
        'remote-config',
        '--env',
        'dev',
      ], workingDirectory: tempDir.path);

      expect(result.exitCode, 1);
      expect(
        result.stderr as String,
        contains('No cached release found for environment "dev"'),
      );
    });

    test('fails when firebase_project_id is not configured', () async {
      File('${tempDir.path}/release_config.yaml').writeAsStringSync('''
environments:
  dev:
    android:
      package_name: com.example.dev
''');
      seedCache(
        '{"dev":{"android":{"version":"1.2.3+45","releasedAt":"2026-01-01T00:00:00.000Z"}}}',
      );

      final result = await Process.run('dart', [
        'run',
        scriptPath,
        'remote-config',
        '--env',
        'dev',
      ], workingDirectory: tempDir.path);

      expect(result.exitCode, 1);
      expect(
        result.stderr as String,
        contains('firebase_project_id is not configured'),
      );
    });

    test('dry-run shows cached versions without clearing the cache', () async {
      File('${tempDir.path}/release_config.yaml').writeAsStringSync('''
shared:
  firebase_project_id: my-firebase-project
  firebase_service_json_file: firebase.json
environments:
  dev:
    android:
      package_name: com.example.dev
''');
      File('${tempDir.path}/firebase.json').writeAsStringSync('{}');
      const cacheJson =
          '{"dev":{"android":{"version":"1.2.3+45","releasedAt":"2026-01-01T00:00:00.000Z"}}}';
      seedCache(cacheJson);

      final result = await Process.run('dart', [
        'run',
        scriptPath,
        'remote-config',
        '--env',
        'dev',
        '--dry-run',
      ], workingDirectory: tempDir.path);

      expect(result.exitCode, 0);
      expect(result.stdout as String, contains('android: 1.2.3+45'));
      expect(result.stdout as String, contains('[Dry Run]'));

      final cacheFile = File(
        p.join(tempDir.path, '.release_tool', 'latest_release_cache.json'),
      );
      expect(cacheFile.readAsStringSync(), cacheJson);
    });

    test(
      '--force-update dry-run mentions fl_updater_min_version and the mandatory-update warning',
      () async {
        File('${tempDir.path}/release_config.yaml').writeAsStringSync('''
shared:
  firebase_project_id: my-firebase-project
  firebase_service_json_file: firebase.json
environments:
  dev:
    android:
      package_name: com.example.dev
''');
        File('${tempDir.path}/firebase.json').writeAsStringSync('{}');
        seedCache(
          '{"dev":{"android":{"version":"1.2.3+45","releasedAt":"2026-01-01T00:00:00.000Z"}}}',
        );

        final result = await Process.run('dart', [
          'run',
          scriptPath,
          'remote-config',
          '--env',
          'dev',
          '--force-update',
          '--dry-run',
        ], workingDirectory: tempDir.path);

        expect(result.exitCode, 0);
        final stdout = result.stdout as String;
        expect(
          stdout,
          contains('fl_updater_latest_version and fl_updater_min_version'),
        );
        expect(stdout, contains('mandatory, non-dismissible update prompt'));
      },
    );

    test(
      'without --force-update, only fl_updater_latest_version is mentioned',
      () async {
        File('${tempDir.path}/release_config.yaml').writeAsStringSync('''
shared:
  firebase_project_id: my-firebase-project
  firebase_service_json_file: firebase.json
environments:
  dev:
    android:
      package_name: com.example.dev
''');
        File('${tempDir.path}/firebase.json').writeAsStringSync('{}');
        seedCache(
          '{"dev":{"android":{"version":"1.2.3+45","releasedAt":"2026-01-01T00:00:00.000Z"}}}',
        );

        final result = await Process.run('dart', [
          'run',
          scriptPath,
          'remote-config',
          '--env',
          'dev',
          '--dry-run',
        ], workingDirectory: tempDir.path);

        expect(result.exitCode, 0);
        final stdout = result.stdout as String;
        expect(stdout, isNot(contains('fl_updater_min_version')));
        expect(stdout, isNot(contains('mandatory, non-dismissible')));
      },
    );

    test('--version requires --platform', () async {
      File('${tempDir.path}/release_config.yaml').writeAsStringSync('''
shared:
  firebase_project_id: my-firebase-project
  firebase_service_json_file: firebase.json
environments:
  dev:
    android:
      package_name: com.example.dev
''');
      File('${tempDir.path}/firebase.json').writeAsStringSync('{}');

      final result = await Process.run('dart', [
        'run',
        scriptPath,
        'remote-config',
        '--env',
        'dev',
        '--version',
        '3.0.0',
      ], workingDirectory: tempDir.path);

      expect(result.exitCode, 1);
      expect(
        result.stderr as String,
        contains('--version requires --platform'),
      );
    });

    test(
      '--version with --platform publishes without needing a cached release',
      () async {
        File('${tempDir.path}/release_config.yaml').writeAsStringSync('''
shared:
  firebase_project_id: my-firebase-project
  firebase_service_json_file: firebase.json
environments:
  dev:
    android:
      package_name: com.example.dev
''');
        File('${tempDir.path}/firebase.json').writeAsStringSync('{}');
        // Deliberately no cache seeded — --version should bypass it entirely.

        final result = await Process.run('dart', [
          'run',
          scriptPath,
          'remote-config',
          '--env',
          'dev',
          '--version',
          '3.0.0',
          '--platform',
          'android',
          '--dry-run',
        ], workingDirectory: tempDir.path);

        expect(result.exitCode, 0);
        final stdout = result.stdout as String;
        expect(
          stdout,
          contains('android: 3.0.0 (fl_updater_android, from --version)'),
        );
      },
    );
  });
}
