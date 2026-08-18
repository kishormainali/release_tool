# Configuration (`release_config.yaml`)

The `release_config.yaml` file acts as the source of truth for your deployment environments. The `release_tool` parses this file, extracting the values for the specified environment, and injects them into Fastlane via standard environment variables.

Fields under `shared:` apply to every environment; the equivalent field under a specific environment overrides it.

## Example Structure

```yaml
project_name: my_awesome_app

shared:
  firebase_service_json_file: "secrets/firebase-credentials.json"
  firebase_groups: "qa-testers"
  firebase_project_id: "my-firebase-project"
  dart_defines:
    API_BASE_URL: "https://api.example.com"
  dart_define_from_file: "secrets/.env"
  android:
    google_play_json_key_file: "secrets/play-credentials.json"
  ios:
    app_store_team_id: "TEAM_ID_HERE"
    asc_key_id: ""
    asc_issuer_id: ""
    asc_key_filepath: "secrets/appstore-connect-key.p8"
    match:
      git_url: "git@github.com:myorg/certificates.git"
      git_branch: "master"
      password: ""

environments:
  dev:
    flavor: dev
    entry_point: lib/main_dev.dart
    android:
      package_name: com.example.app.dev
      firebase_app_id: "1:12345:android:dev_app_id"
      firebase_groups: "qa-testers"
    ios:
      bundle_id: com.example.app.dev
      firebase_app_id: "1:12345:ios:dev_app_id"
      firebase_groups: "qa-testers"
      scheme: "dev"

  prod:
    flavor: prod
    entry_point: lib/main_prod.dart
    firebase_project_id: "my-firebase-project-prod" # overrides shared, if different
    android:
      package_name: com.example.app
    ios:
      bundle_id: com.example.app
      scheme: "prod"
      match:
        git_branch: "prod-certs" # overrides shared.ios.match.git_branch
```

## Field Breakdown

### Global Settings
- `project_name`: The name of your Flutter project.

### Shared Settings (`shared:`)
Anything here is used as the fallback for every environment unless the same field is set on that environment directly.

- `firebase_service_json_file`: Path to the Firebase service account JSON, used for Firebase App Distribution (and, with the **Firebase Remote Config Admin** IAM role added, by `remote-config`).
- `firebase_groups`: Comma-separated list of Firebase App Distribution tester groups.
- `firebase_project_id`: The Firebase project id used by [`release_tool remote-config`](commands_reference.md#release_tool-remote-config) to update `fl_updater_latest_version`/`fl_updater_min_version`. Can be overridden per-environment.
- `dart_defines`: A map (or list of `KEY=value` strings) passed through as `--dart-define` flags during the Fastlane build.
- `dart_define_from_file`: Path to an env file passed as `--dart-define-from-file`.
- `android.google_play_json_key_file`: Path to the Google Play Console service account JSON, required for `deploy --target store` on Android.
- `ios.app_store_team_id`: Your Apple Developer Team ID.
- `ios.asc_key_id` / `ios.asc_issuer_id` / `ios.asc_key_filepath`: App Store Connect API key, required for TestFlight/App Store deploys and certificate management. Can be supplied via environment variables instead — see [Fastlane Setup & Credentials](fastlane_setup.md).
- `ios.match`: Configuration block for Fastlane Match (used by the `deploy` and `certificates` commands).
  - `git_url`: The repository URL where certificates are stored.
  - `git_branch`: The branch used for Match (defaults to `master` if unset).
  - `password`: The passphrase used to decrypt the certificates. Can also come from the `MATCH_PASSWORD` environment variable.

### Environment Level
Under `environments`, define as many keys as you need (e.g. `dev`, `staging`, `prod`, `qa`).

- `flavor`: The product flavor used by `flutter build` commands.
- `entry_point`: The dart file used as the entry point (e.g., `lib/main_dev.dart`).
- `firebase_project_id`: Overrides `shared.firebase_project_id` for this environment.
- `dart_defines` / `dart_define_from_file`: Same meaning as under `shared:`, merged with (and overriding) the shared values.

### Android Configuration (`android:`)
- `package_name`: The application ID / package name. **Required** for any Android deploy.
- `firebase_app_id`: The Firebase App ID, required for `--target firebase`.
- `firebase_groups`: Overrides `shared.firebase_groups` for this environment.
- `firebase_service_json_file`: Overrides `shared.firebase_service_json_file` / `shared.android.firebase_service_json_file`.
- `google_play_json_key_file`: Overrides `shared.android.google_play_json_key_file`. Required for `--target store`.

### iOS Configuration (`ios:`)
- `bundle_id`: The iOS Bundle Identifier. **Required** for any iOS deploy.
- `firebase_app_id`: The iOS Firebase App ID, required for `--target firebase`.
- `firebase_groups`: Overrides `shared.firebase_groups` for this environment.
- `scheme`: The Xcode scheme to build (falls back to `flavor` if unset).
- `app_store_team_id`, `asc_key_id`, `asc_issuer_id`, `asc_key_filepath`: Override the equivalent `shared.ios.*` fields.
- `match`: Overrides `shared.ios.match.*` fields (e.g. a different cert repo branch per environment).

Run `release_tool doctor --env <name>` any time to check whether an environment is fully configured for a real deploy.
