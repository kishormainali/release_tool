# Configuration (`release_config.yaml`)

The `release_config.yaml` file acts as the source of truth for your deployment environments. The `release_tool` parses this file, extracting the values for the specified environment, and injects them into Fastlane via standard environment variables.

## Example Structure

```yaml
project_name: my_awesome_app

environments:
  dev:
    flavor: dev
    entry_point: lib/main_dev.dart
    android:
      package_name: com.example.app.dev
      firebase_app_id: "1:12345:android:dev_app_id"
      firebase_groups: "qa-testers"
      google_play_track: "internal"
    ios:
      bundle_id: com.example.app.dev
      firebase_app_id: "1:12345:ios:dev_app_id"
      firebase_groups: "qa-testers"
      export_method: "ad-hoc" # app-store, ad-hoc, development
      scheme: "dev"
      match:
        git_url: "git@github.com:myorg/certificates.git"
        git_branch: "master"
        password: "your_match_password"
```

## Field Breakdown

### Global Settings
- `project_name`: The name of your Flutter project.

### Environment Level
Under `environments`, you can define as many keys as you need (e.g. `dev`, `staging`, `prod`, `qa`).

- `flavor`: The product flavor used by `flutter build` commands.
- `entry_point`: The dart file used as the entry point (e.g., `lib/main_dev.dart`).

### Android Configuration (`android:`)
- `package_name`: The application ID / package name.
- `firebase_app_id`: The Firebase App ID, found in the Firebase Console.
- `firebase_groups`: Comma-separated list of Firebase App Distribution tester groups (e.g., `qa-testers, pm-team`).
- `google_play_track`: The track to deploy to in the Play Store (`internal`, `alpha`, `beta`, `production`).

### iOS Configuration (`ios:`)
- `bundle_id`: The iOS Bundle Identifier.
- `firebase_app_id`: The iOS Firebase App ID.
- `firebase_groups`: Comma-separated list of Firebase App Distribution tester groups.
- `export_method`: The method used to sign the iOS app. Typically `ad-hoc` or `development` for Firebase, and `app-store` for TestFlight / App Store.
- `scheme`: The Xcode scheme to use during the build.
- `match`: Configuration block for Fastlane Match (used by the `certificates` command).
  - `git_url`: The repository URL where certificates are stored.
  - `git_branch`: The branch used for Match.
  - `password`: The passphrase used to decrypt the certificates.
