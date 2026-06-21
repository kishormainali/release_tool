import 'dart:io';
import 'package:pub_semver/pub_semver.dart';

/// Utility class for parsing and bumping versions in pubspec.yaml.
class VersionUtils {
  /// Parsed representation of a Flutter version (semver + build number)
  static (Version, int?) parseVersion(String versionStr) {
    final parts = versionStr.split('+');
    final semverPart = parts[0];
    final buildPart = parts.length > 1 ? parts[1] : null;

    final semver = Version.parse(semverPart);
    final buildNumber = buildPart != null ? int.tryParse(buildPart) : null;

    return (semver, buildNumber);
  }

  /// Read the current version string from pubspec.yaml
  static String readVersionFromPubspec(File pubspecFile) {
    if (!pubspecFile.existsSync()) {
      throw FileSystemException(
        'pubspec.yaml does not exist at ${pubspecFile.path}',
      );
    }

    final content = pubspecFile.readAsStringSync();
    final match = RegExp(
      r'^version:\s*([^\s#]+)',
      multiLine: true,
    ).firstMatch(content);
    if (match == null) {
      throw FormatException('Could not find version field in pubspec.yaml');
    }

    return match.group(1)!;
  }

  /// Write the new version string back to pubspec.yaml preserving formatting and comments
  static void writeVersionToPubspec(File pubspecFile, String newVersion) {
    if (!pubspecFile.existsSync()) {
      throw FileSystemException(
        'pubspec.yaml does not exist at ${pubspecFile.path}',
      );
    }

    final content = pubspecFile.readAsStringSync();
    final updatedContent = content.replaceAllMapped(
      RegExp(r'^version:\s*([^\s#]+)', multiLine: true),
      (match) => 'version: $newVersion',
    );

    pubspecFile.writeAsStringSync(updatedContent);
  }

  /// Bumps the version based on type: major, minor, patch, build
  static String bumpVersion(String currentVersionStr, String bumpType) {
    final (semver, buildNumber) = parseVersion(currentVersionStr);

    Version newSemver = semver;
    int newBuildNumber = (buildNumber ?? 0) + 1;

    switch (bumpType.toLowerCase()) {
      case 'major':
        newSemver = semver.nextMajor;
        break;
      case 'minor':
        newSemver = semver.nextMinor;
        break;
      case 'patch':
        newSemver = semver.nextPatch;
        break;
      case 'build':
        // Semantic version remains the same, build number is bumped
        newSemver = semver;
        break;
      default:
        throw ArgumentError(
          'Invalid bump type: $bumpType. Use major, minor, patch, or build.',
        );
    }

    return newBuildNumber > 0 ? '$newSemver+$newBuildNumber' : '$newSemver';
  }
}
