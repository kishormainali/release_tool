## 1.1.0

- Added `release_tool doctor` to validate `release_config.yaml`, required tooling (`fastlane`/`bundle`), and referenced credential files before a real deploy.
- Added `release_tool remote-config` to publish the last store-deployed version to Firebase Remote Config's `fl_updater_latest_version` for apps using the [fl_updater](https://pub.dev/packages/fl_updater) package, with `--force-update` (also sets `fl_updater_min_version`) and an explicit `--version` override.
- Added a `firebase_project_id` config field (shared or per-environment), used by the new `remote-config` command.
- Added a global `--verbose` flag for debug-level logging output.
- Added `--release-notes-file` to `deploy` to read release notes from a file instead of `--release-notes`.
- The pub.dev update check now only runs in interactive, non-CI sessions and is cached for 24 hours instead of hitting the network on every invocation.
- Fixed `version` hanging or crashing when run in a non-interactive session without a bump type argument or `--yes`.
- CI now runs `dart test` and a strict format check, and regenerates `version.dart` before publishing so the CLI's self-reported version always matches the published package.

## 1.0.1

- Full API documentation for public members.
- Configured dynamic version reading via `build_version`.
- Added the `upgrade` command to easily check for and install new versions from pub.dev.

## 1.0.0

- Initial version.
