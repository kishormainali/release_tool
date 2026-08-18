# Fastlane Setup & Credentials

The `release_tool` acts as an orchestrator that drives Fastlane. Fastlane must have access to specific credentials and API keys in order to interact with Firebase, the App Store, and Google Play.

When you run `release_tool deploy`, the tool automatically passes variables from `release_config.yaml` to Fastlane using standard environment variables (e.g., `FIREBASE_APP_ID`, `APP_IDENTIFIER`, `PACKAGE_NAME`).

Some credentials are always read from a config-specified **file path**; others can additionally come from environment variables, which is usually the more CI-friendly option since it avoids writing secrets to disk first.

## Credentials by Deployment Target

### Android — Firebase App Distribution (`--target firebase`)
- `shared.firebase_service_json_file` (or the Android-specific override): path to the Firebase service account JSON.

### Android — Google Play Store (`--target store`)
- `android.google_play_json_key_file`: path to the Google Play Console service account JSON. File path only — no environment variable equivalent.

### iOS — Firebase App Distribution (`--target firebase`)
- `shared.firebase_service_json_file` (or the iOS-specific override), same as Android.

### iOS — TestFlight / App Store (`--target store`) and Certificates
Requires an App Store Connect API key, resolved in this order: config field, then environment variable.

| Value | Config field | Environment variable(s) |
|---|---|---|
| Key ID | `ios.asc_key_id` | `ASC_KEY_ID` or `APP_STORE_CONNECT_API_KEY_KEY_ID` |
| Issuer ID | `ios.asc_issuer_id` | `ASC_ISSUER_ID` or `APP_STORE_CONNECT_API_KEY_ISSUER_ID` |
| Key file path | `ios.asc_key_filepath` | `ASC_KEY_FILEPATH` or `APP_STORE_CONNECT_API_KEY_KEY_FILEPATH` |
| Raw key content (alternative to a file path) | — | `ASC_KEY_CONTENT` or `APP_STORE_CONNECT_API_KEY_KEY` (raw PEM or already base64-encoded) |

Also requires `ios.app_store_team_id` (or the `APPSTORE_TEAM_ID`/`APP_STORE_TEAM_ID` env vars are what Fastlane itself sees, populated from that config field).

### iOS — Fastlane Match (certificates)
- `ios.match.git_url` and `ios.match.git_branch`: where signing certificates are stored.
- `ios.match.password` or the `MATCH_PASSWORD` environment variable: passphrase to decrypt them.
- Uses the same App Store Connect API key as above.

Run `release_tool doctor --env <name>` to check which of these are missing for a given environment before running a real deploy.

## How it works under the hood

When you run `release_tool init`, the tool copies boilerplate `Fastfile`, `Appfile`, `Gemfile`, and `Pluginfile` into your `android/fastlane` and `ios/fastlane` directories.

These boilerplate files are designed to be "zero-maintenance". They do not hardcode any App IDs or Bundle Identifiers. Instead, they read them directly from the environment variables injected by the `release_tool`.

If you ever need to customize the Fastlane behavior (e.g., adding a custom build step, running tests before deployment, etc.), you can edit the generated `Fastfile` directly. Running `release_tool update` later will regenerate the templates and merge new config fields without discarding your customizations to `release_config.yaml` (though direct `Fastfile` edits are overwritten — keep those in source control if you rely on them).
