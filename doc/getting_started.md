# Getting Started

Welcome to the `release_tool`! This guide will help you get your Flutter project configured for automated builds and deployments using Fastlane.

## 1. Installation

You have two options for running the `release_tool`:

### Option A: Use it globally (Recommended)
This allows you to run `release_tool` from anywhere on your machine.
```bash
# Activate locally from source
dart pub global activate --source path <path_to_release_tool>

# Verify installation
release_tool --help
```

### Option B: Run it directly
```bash
dart run <path_to_release_tool>/bin/release_tool.dart <command>
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
