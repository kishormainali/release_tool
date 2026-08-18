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

---

## `release_tool remote-config`
Publishes the version most recently deployed with `deploy --target store` to Firebase Remote Config's `fl_updater_latest_version` parameter (for apps using the [fl_updater](https://pub.dev/packages/fl_updater) package), then clears the cached release so it isn't published twice.

Every successful `deploy --target store` run caches the version Fastlane actually shipped (not `pubspec.yaml`'s version — the real one is computed live from the Play Store/App Store, which can differ) in a local, gitignored `.release_tool/latest_release_cache.json`. `remote-config` reads that cache, updates both the parameter's default value and its `fl_updater_android` / `fl_updater_ios` conditional values (creating those conditions in Firebase Console if they don't already exist), then clears the cache entries it published.

**Usage:**
```bash
release_tool remote-config --env prod

# Force every user below this version to update immediately (non-dismissible)
release_tool remote-config --env prod --force-update

# Publish an explicit version instead of the cached one (e.g. first-time setup,
# or republishing without a fresh store deploy). Requires --platform.
release_tool remote-config --env prod --platform android --version 2.5.0
```
**Options:**
- `-e, --env`: The environment whose cached release(s) to publish.
- `-p, --platform`: Limit the update to a single platform (`android` or `ios`); defaults to every cached platform for the environment. Required when using `--version`.
- `--version`: Publish this exact version instead of the cached release version. Useful when there's nothing cached yet, or to republish/correct a value without doing a fresh store deploy. Requires `--platform`.
- `--force-update`: Also set `fl_updater_min_version` to the same version being published, which fl_updater treats as an immediate, non-dismissible mandatory update for every user below it. Off by default — a normal release only nudges `fl_updater_latest_version`.
- `--dry-run`: Show what would be published without contacting Firebase or clearing the cache.
- `-y, --yes`: Skip confirmation prompts (useful in CI/CD). With `--force-update` and no `--yes`, the confirmation prompt defaults to "no" so a mandatory update is never triggered by an accidental Enter key.

**Requirements:**
- `firebase_project_id` set in `release_config.yaml` (see [Configuration Guide](configuration.md)).
- The service account behind `firebase_service_json_file` needs the **Firebase Remote Config Admin** IAM role in Google Cloud Console (the same file used for Firebase App Distribution can be reused — it just needs this role added).
