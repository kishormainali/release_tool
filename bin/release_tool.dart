import 'dart:io';
import 'package:fp_release_tool/src/runner.dart';

/// Entry point for the release_tool CLI.
Future<void> main(List<String> arguments) async {
  final runner = ReleaseToolCommandRunner();
  final exitCode = await runner.run(arguments);
  exit(exitCode);
}
