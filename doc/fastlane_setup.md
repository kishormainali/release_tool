# Fastlane Setup & Credentials

The `release_tool` acts as an orchestrator that drives Fastlane. Fastlane must have access to specific credentials and API keys in order to interact with Firebase, the App Store, and Google Play.

When you run `release_tool deploy`, the tool automatically passes variables from `release_config.yaml` to Fastlane using standard environment variables (e.g., `FIREBASE_APP_ID`, `APP_IDENTIFIER`).

However, for authentication, you need to provide the following keys in your host environment or CI/CD system.

## Required Environment Variables

### Android Deployments

**Deploying to Firebase App Distribution:**
- `FIREBASE_CLI_TOKEN` (or a Firebase Service Account JSON file depending on your Firebase CLI setup).

**Deploying to Google Play Store:**
- `PLAY_STORE_JSON_KEY_PATH`: Absolute path to the Google Play Console Service Account JSON key.

### iOS Deployments

**Deploying to Firebase App Distribution:**
- `FIREBASE_CLI_TOKEN`

**Deploying to Apple App Store / TestFlight:**
You should preferably use the App Store Connect API Key:
- `APP_STORE_API_KEY_PATH`: Absolute path to the `.p8` API key file.
- `APP_STORE_KEY_ID`: The ID of the API Key.
- `APP_STORE_ISSUER_ID`: The Issuer ID.

*Alternative (Apple ID):*
- `APPLE_ID`
- `FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD`

## How it works under the hood

When you run `release_tool init`, the tool copies boilerplate `Fastfile`, `Appfile`, `Gemfile`, and `Pluginfile` into your `android/fastlane` and `ios/fastlane` directories.

These boilerplate files are designed to be "zero-maintenance". They do not hardcode any App IDs or Bundle Identifiers. Instead, they read them directly from the environment variables injected by the `release_tool`.

If you ever need to customize the Fastlane behavior (e.g., adding a custom build step, running tests before deployment, etc.), you can edit the generated `Fastfile` directly.
