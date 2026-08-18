# 🚀 Flutter Release Tool

A centralized command-line interface (CLI) tool designed to automate, streamline, and parallelize iOS and Android build and deployment pipelines for Flutter apps using Fastlane.

---

## 📖 Documentation

Welcome to the comprehensive guide for the `release_tool`. Whether you're setting up a new project or debugging a deployment, you'll find everything you need here.

- 🚀 **[Getting Started](doc/getting_started.md)**: Installation, initialization, and your first deployment.
- ⚙️ **[Configuration Guide](doc/configuration.md)**: Detailed breakdown of the `release_config.yaml` file.
- 📚 **[Commands Reference](doc/commands_reference.md)**: A complete list of all CLI commands and arguments.
- 🔐 **[Fastlane Setup & Credentials](doc/fastlane_setup.md)**: How the tool drives Fastlane under the hood and necessary environment variables.

---

## ✨ Key Features

- **Interactive Prompts (`mason_logger`)**: Colorful outputs, loading spinners, select menus, and confirmation prompts for a seamless local developer experience.
- **CI/CD Compatibility**: Detects non-interactive terminals automatically, bypassing prompts and letting you specify options via arguments and flags.
- **Flavor & Scheme Auto-Detection**: Reads Gradle configurations and Xcode schemes to automatically pre-configure your environment parameters.
- **Semantic Versioning**: Parse and bump `pubspec.yaml` versions (major, minor, patch, build number) directly from the CLI while preserving formatting and comments.
- **Parallel Deployment Pipeline**: Concurrently builds and runs Fastlane deployments for iOS and Android, streaming logs with color-coded platform labels.
- **Zero-Maintenance generic Fastlane**: Automatically bootstraps local Fastfiles, Appfiles, Gemfiles, and Pluginfiles that dynamically consume injected environment variables.
- **Pre-flight Validation**: `release_tool doctor` checks your config, tooling, and credential files before a real deploy runs.
- **Remote Config Publishing**: `release_tool remote-config` pushes the version you just shipped to Firebase Remote Config for apps using [fl_updater](https://pub.dev/packages/fl_updater), including forced/mandatory update support.

---

## ⚡ Quick Start

### 1. Install

Install the tool globally from pub.dev:

```bash
dart pub global activate fp_release_tool
```

> **Note**: Ensure your `PATH` is configured for Dart global executables.

### 2. Initialize your project

From the root of your Flutter project:

```bash
release_tool init
```

This detects your Android product flavors and iOS schemes, then generates `release_config.yaml` plus zero-maintenance Fastlane files in `android/fastlane` and `ios/fastlane`.

### 3. Configure `release_config.yaml`

Fill in the generated file with your app's identifiers. Fields under `shared:` apply to every environment unless overridden per-environment.

```yaml
project_name: my_awesome_app

shared:
  firebase_service_json_file: "secrets/firebase-credentials.json"
  firebase_groups: "qa-testers"
  firebase_project_id: "my-firebase-project" # used by `remote-config`
  android:
    google_play_json_key_file: "secrets/play-credentials.json"
  ios:
    app_store_team_id: "TEAM_ID_HERE"
    match:
      git_url: "git@github.com:myorg/certificates.git"
      git_branch: "master"
      # asc_key_id / asc_issuer_id / asc_key_filepath, or their env var
      # equivalents below, are also required for iOS deploys and certs.

environments:
  dev:
    flavor: dev
    entry_point: lib/main_dev.dart
    android:
      package_name: com.example.app.dev
      firebase_app_id: "1:12345:android:dev_app_id"
    ios:
      bundle_id: com.example.app.dev
      firebase_app_id: "1:12345:ios:dev_app_id"
      scheme: "dev"

  prod:
    flavor: prod
    entry_point: lib/main_prod.dart
    android:
      package_name: com.example.app
    ios:
      bundle_id: com.example.app
      scheme: "prod"
```

See the [Configuration Guide](doc/configuration.md) for the full field reference (Android/iOS/Match blocks, `dart_defines`, per-environment overrides).

### 4. Provide credentials

Secrets are never stored in `release_config.yaml` itself — point config fields at file paths (populated locally or by your CI secrets step), or supply the iOS App Store Connect key and Match password via environment variables instead:

| Purpose | Config field | Environment variable equivalent |
|---|---|---|
| Firebase App Distribution | `firebase_service_json_file` | — (file path only) |
| Google Play upload | `android.google_play_json_key_file` | — (file path only) |
| App Store Connect API key | `ios.asc_key_id` / `asc_issuer_id` / `asc_key_filepath` | `ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_FILEPATH` or `ASC_KEY_CONTENT` |
| Fastlane Match passphrase | `ios.match.password` | `MATCH_PASSWORD` |

The environment variables are the more CI-friendly route for iOS — inject the App Store Connect `.p8` key content directly via `ASC_KEY_CONTENT` (raw PEM or base64) instead of writing it to disk first.

### 5. Validate before you deploy

```bash
release_tool doctor --env prod
```

Checks required fields, that `fastlane`/`bundle` are on `PATH`, and that referenced credential files actually exist — before Fastlane ever runs.

### 6. Deploy

```bash
# Interactive (prompts for environment, platform, target)
release_tool deploy

# Non-interactive / CI
release_tool deploy --env prod --platform both --target store --yes
```

### 7. Optional: certificates & Remote Config

```bash
# Fetch or create iOS signing certificates via Fastlane Match
release_tool certificates get --env prod

# After a store release, publish the shipped version to Firebase Remote
# Config for apps using fl_updater (https://pub.dev/packages/fl_updater)
release_tool remote-config --env prod
```

*For the complete command list and every flag, see the [Commands Reference](doc/commands_reference.md).*

---

## 🤝 Contributing

Contributions are welcome! Feel free to open an issue or submit a pull request if you have ideas to improve this tool.

## 📝 License

This project is licensed under the MIT License.
