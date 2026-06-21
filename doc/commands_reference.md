# Commands Reference

This is a comprehensive reference for all `release_tool` commands.

## Global Options
- `-h, --help`: Print usage information.

---

## `release_tool init`
Initializes the project by generating a `release_config.yaml` and placing generic Fastlane templates in the `android/` and `ios/` folders.

**Usage:**
```bash
release_tool init [arguments]
```
**Options:**
- `-y, --yes`: Skip confirmation prompts (useful in CI/CD).

---

## `release_tool deploy`
Build and deploy Flutter applications using Fastlane. It automatically injects credentials and configuration from `release_config.yaml` into the Fastlane environment.

**Usage:**
```bash
release_tool deploy [arguments]
```
**Options:**
- `-e, --env`: The environment configuration to deploy (e.g. `dev`, `staging`, `prod`).
- `-p, --platform`: The platform to build and deploy (`android`, `ios`, `both`).
- `-t, --target`: The deployment target (`firebase` for App Distribution or `store` for App Store / Play Store).
- `-b, --bump`: Version bump type to execute in Fastlane (`major`, `minor`, `patch`, `build`). Defaults to build number increment.
- `-r, --release-notes`: Release notes to display in Firebase App Distribution or store changelogs. Defaults to "New build uploaded via Centralized Release Tool."
- `--dry-run`: Verify configurations and build outputs without running Fastlane deployment.
- `-y, --yes`: Skip confirmation prompts (useful in CI/CD).

---

## `release_tool version`
Manage and bump the Flutter project's semantic versioning. It automatically updates your `pubspec.yaml` file while preserving comments and layout.

**Usage:**
```bash
release_tool version [arguments]
```
**Options:**
- `-y, --yes`: Skip confirmation prompts.

*If run interactively, it will prompt you to select the version bump type (Major, Minor, Patch, or Build).*

---

## `release_tool certificates`
Manage iOS certificates and provisioning profiles using Fastlane Match. This is a wrapper around `fastlane match` that utilizes the configurations defined in `release_config.yaml`.

**Usage:**
```bash
release_tool certificates <subcommand> [arguments]
```
**Subcommands:**
- `create`: Create new certificates.
- `get`: Fetch/retrieve existing certificates.
- `nuke`: Nuke all certificates and create fresh ones.

---

## `release_tool update`
Update generated Fastlane templates and merge new config fields without overwriting existing custom settings in `release_config.yaml`.

**Usage:**
```bash
release_tool update [arguments]
```
