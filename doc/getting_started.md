# Getting Started

Welcome to the `release_tool`! This guide will help you get your Flutter project configured for automated builds and deployments using Fastlane.

## 1. Installation

Install the `release_tool` globally via pub.dev:

```bash
dart pub global activate fp_release_tool
```

> **Note**: Ensure that your system's `PATH` includes the Dart pub cache directory so you can run the `release_tool` executable from anywhere.

Verify the installation:
```bash
release_tool --help
```

## 2. Initialization

Navigate to your Flutter project's root directory and run:

```bash
release_tool init
```

This command will:
1. Generate a `release_config.yaml` file in the root of your project.
2. Bootstrap generic, zero-maintenance Fastlane templates in both `android/fastlane` and `ios/fastlane`.

## 3. Configuration

After running `init`, open `release_config.yaml` and fill out your project details.
This file maps your environments (dev, staging, prod) to App IDs, Bundle Identifiers, and Firebase configurations.

See [Configuration Guide](configuration.md) for a detailed breakdown of all fields.

## 4. Deploying

Once configured, you can start building and deploying your app:

```bash
# Interactive mode (prompts you for environment and platform)
release_tool deploy

# Non-interactive mode (for CI/CD)
release_tool deploy --env dev --platform android --target firebase --yes
```

The tool will parse your `release_config.yaml`, inject the necessary environment variables, and execute the underlying Fastlane processes automatically.

## Next Steps
- Learn more about the available commands in the [Commands Reference](commands_reference.md).
- Understand how Fastlane works under the hood in the [Fastlane Setup Guide](fastlane_setup.md).
