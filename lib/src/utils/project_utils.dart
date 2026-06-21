import 'dart:io';
import 'package:path/path.dart' as p;

/// Utility class for detecting and managing project configurations like flavors and schemes.
class ProjectUtils {
  /// Detects flavors by combining Android product flavors and iOS schemes.
  static Map<String, List<String>> detectFlavors(Directory projectDir) {
    final androidFlavors = detectAndroidFlavors(projectDir);
    final iosSchemes = detectIosSchemes(projectDir);

    return {'android': androidFlavors, 'ios': iosSchemes};
  }

  /// Parses `android/app/build.gradle` or `android/app/build.gradle.kts` to find product flavors.
  static List<String> detectAndroidFlavors(Directory projectDir) {
    final flavors = <String>{};

    final gradleFile = File(
      p.join(projectDir.path, 'android', 'app', 'build.gradle'),
    );
    final gradleKtsFile = File(
      p.join(projectDir.path, 'android', 'app', 'build.gradle.kts'),
    );

    File? targetFile;
    if (gradleFile.existsSync()) {
      targetFile = gradleFile;
    } else if (gradleKtsFile.existsSync()) {
      targetFile = gradleKtsFile;
    }

    if (targetFile == null) return [];

    try {
      var content = targetFile.readAsStringSync();
      // Remove comments to prevent false matches
      content = content.replaceAll(RegExp(r'\/\/.*'), '');
      content = content.replaceAll(RegExp(r'\/\*[\s\S]*?\*\/'), '');

      // Find the productFlavors block
      final index = content.indexOf('productFlavors');
      if (index != -1) {
        // Extract the block using brace matching
        final blockContent = _extractBraceBlock(content, index);
        if (blockContent != null) {
          // Look for flavor declarations
          // In Groovy: flavorName {
          // In Kotlin DSL: create("flavorName") { or register("flavorName") { or flavorName {

          // Pattern for create("flavorName") or register("flavorName")
          final ktsPattern = RegExp(
            r'(?:create|register)\s*\(\s*["\x27]([^"\x27]+)["\x27]\s*\)',
          );
          for (final match in ktsPattern.allMatches(blockContent)) {
            flavors.add(match.group(1)!);
          }

          // Pattern for standard groovy/kotlin flavorName {
          // Avoid matching keywords like dimension, signingConfig, manifestPlaceholders, etc.
          final excludedKeywords = {
            'dimension',
            'signingConfig',
            'manifestPlaceholders',
            'applicationId',
            'applicationIdSuffix',
            'versionName',
            'versionNameSuffix',
            'versionCode',
            'buildConfigField',
            'resValue',
            'proguardFiles',
            'minifyEnabled',
            'create',
            'register',
          };

          final groovyPattern = RegExp(
            r'^\s*([a-zA-Z0-9_-]+)\s*\{',
            multiLine: true,
          );
          for (final match in groovyPattern.allMatches(blockContent)) {
            final name = match.group(1)!;
            if (!excludedKeywords.contains(name)) {
              flavors.add(name);
            }
          }
        }
      }
    } catch (_) {
      // Return empty list if reading/parsing fails
    }

    return flavors.toList()..sort();
  }

  /// Finds iOS schemes under `ios/Runner.xcodeproj/xcshareddata/xcschemes/`
  static List<String> detectIosSchemes(Directory projectDir) {
    final schemes = <String>{};
    final schemesDir = Directory(
      p.join(
        projectDir.path,
        'ios',
        'Runner.xcodeproj',
        'xcshareddata',
        'xcschemes',
      ),
    );

    if (schemesDir.existsSync()) {
      try {
        final files = schemesDir.listSync();
        for (final file in files) {
          if (file is File && file.path.endsWith('.xcscheme')) {
            final schemeName = p.basenameWithoutExtension(file.path);
            // Ignore standard build scheme if there are others
            if (schemeName != 'Runner') {
              schemes.add(schemeName);
            }
          }
        }
      } catch (_) {}
    }

    // If no custom schemes found, we fall back to checking if iOS folder exists
    // and if so, return 'Runner' as default.
    if (schemes.isEmpty) {
      final iosDir = Directory(p.join(projectDir.path, 'ios'));
      if (iosDir.existsSync()) {
        schemes.add('Runner');
      }
    }

    return schemes.toList()..sort();
  }

  /// Extracts the content of a curly brace block starting from a given index.
  static String? _extractBraceBlock(String content, int startIndex) {
    var openBraces = 0;
    var firstBraceFound = false;
    var blockStart = -1;

    for (var i = startIndex; i < content.length; i++) {
      final char = content[i];
      if (char == '{') {
        if (!firstBraceFound) {
          firstBraceFound = true;
          blockStart = i + 1;
        }
        openBraces++;
      } else if (char == '}') {
        if (firstBraceFound) {
          openBraces--;
          if (openBraces == 0) {
            return content.substring(blockStart, i);
          }
        }
      }
    }
    return null;
  }
}
