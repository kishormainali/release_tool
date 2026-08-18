import 'dart:convert';
import 'dart:io';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

/// Resolved App Store Connect API credentials used to authenticate Fastlane
/// with the App Store Connect API (key id, issuer id, and the base64-encoded
/// `.p8` key content).
class AscCredentials {
  /// The App Store Connect API key id.
  final String keyId;

  /// The App Store Connect API issuer id.
  final String issuerId;

  /// The base64-encoded contents of the App Store Connect `.p8` key file.
  final String? keyContentBase64;

  /// Creates a new [AscCredentials].
  const AscCredentials({
    required this.keyId,
    required this.issuerId,
    required this.keyContentBase64,
  });

  /// Whether all three credential pieces were successfully resolved.
  bool get isComplete =>
      keyId.isNotEmpty &&
      issuerId.isNotEmpty &&
      keyContentBase64 != null &&
      keyContentBase64!.isNotEmpty;

  /// Resolves App Store Connect API credentials from explicit config values,
  /// falling back to the well-known environment variables supported by
  /// Fastlane's `app_store_connect_api_key` action (both the short
  /// `ASC_*` names and the longer `APP_STORE_CONNECT_API_KEY_*` names).
  ///
  /// [resolvePath] is used to turn [configKeyFilepath] (or its environment
  /// variable fallback) into an absolute path before reading the key file,
  /// typically [BaseCommand.makeAbsolutePath].
  static AscCredentials resolve({
    String? configKeyId,
    String? configIssuerId,
    String? configKeyFilepath,
    required String? Function(String?) resolvePath,
    Logger? logger,
    String logPrefix = '',
  }) {
    var keyId = configKeyId ?? '';
    if (keyId.isEmpty) {
      keyId =
          Platform.environment['ASC_KEY_ID'] ??
          Platform.environment['APP_STORE_CONNECT_API_KEY_KEY_ID'] ??
          '';
    }

    var issuerId = configIssuerId ?? '';
    if (issuerId.isEmpty) {
      issuerId =
          Platform.environment['ASC_ISSUER_ID'] ??
          Platform.environment['APP_STORE_CONNECT_API_KEY_ISSUER_ID'] ??
          '';
    }

    var keyFilepath = configKeyFilepath;
    if (keyFilepath == null || keyFilepath.isEmpty) {
      keyFilepath =
          Platform.environment['ASC_KEY_FILEPATH'] ??
          Platform.environment['APP_STORE_CONNECT_API_KEY_KEY_FILEPATH'];
    }

    String? keyContentBase64;
    if (keyFilepath != null && keyFilepath.isNotEmpty) {
      final keyFile = File(resolvePath(keyFilepath) ?? '');
      if (keyFile.existsSync()) {
        try {
          keyContentBase64 = base64.encode(keyFile.readAsBytesSync());
        } catch (_) {}
      } else {
        logger?.detail(
          '$logPrefix App Store Connect key file not found at: $keyFilepath',
        );
      }
    }

    if (keyContentBase64 == null || keyContentBase64.isEmpty) {
      final envKeyContent =
          Platform.environment['ASC_KEY_CONTENT'] ??
          Platform.environment['APP_STORE_CONNECT_API_KEY_KEY'];
      if (envKeyContent != null && envKeyContent.isNotEmpty) {
        if (envKeyContent.contains('-----BEGIN')) {
          try {
            keyContentBase64 = base64.encode(utf8.encode(envKeyContent.trim()));
          } catch (_) {}
        } else {
          keyContentBase64 = envKeyContent.trim();
        }
      }
    }

    return AscCredentials(
      keyId: keyId,
      issuerId: issuerId,
      keyContentBase64: keyContentBase64,
    );
  }
}

/// Determines the Fastlane invocation command for [platformDirName]
/// (`android` or `ios`) within [projectDir], preferring `bundle exec
/// fastlane` when a `Gemfile` is present and Bundler is available on PATH,
/// falling back to a bare `fastlane`.
Future<List<String>> resolveFastlaneCommand(
  Directory projectDir,
  String platformDirName,
) async {
  final gemfile = File(p.join(projectDir.path, platformDirName, 'Gemfile'));
  if (gemfile.existsSync()) {
    try {
      final result = await Process.run('bundle', [
        '--version',
      ], runInShell: true);
      if (result.exitCode == 0) {
        return ['bundle', 'exec', 'fastlane'];
      }
    } catch (_) {}
  }
  return ['fastlane'];
}

/// Merges dart-define maps, with entries in [envDefines] overriding any
/// matching keys from [sharedDefines].
Map<String, String> mergeDartDefines({
  Map<String, String>? sharedDefines,
  Map<String, String>? envDefines,
}) {
  return {...?sharedDefines, ...?envDefines};
}
