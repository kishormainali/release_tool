import 'dart:convert';
import 'dart:io';

/// Utility class for running external processes.
class ProcessUtils {
  /// Runs a command asynchronously and streams the stdout/stderr line-by-line with a prefix.
  static Future<int> runWithPrefix({
    required String executable,
    required List<String> arguments,
    required String prefix,
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    try {
      final process = await Process.start(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        runInShell: true,
      );

      // Stream stdout
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            stdout.writeln('$prefix $line');
          });

      // Stream stderr
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            stderr.writeln('$prefix \x1B[31m$line\x1B[0m');
          });

      return await process.exitCode;
    } catch (e) {
      stderr.writeln(
        '$prefix \x1B[31mFailed to start process: $executable. Error: $e\x1B[0m',
      );
      return -1;
    }
  }
}
