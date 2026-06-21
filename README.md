<div align="center">
  <h1>🚀 Flutter Release Tool</h1>
  <p>A centralized command-line interface (CLI) tool designed to automate, streamline, and parallelize iOS and Android build and deployment pipelines for Flutter apps using Fastlane.</p>
</div>

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

---

## ⚡ Quick Start

You can run this tool directly using the Dart SDK:

```bash
# Activate locally from source
dart pub global activate --source path <path_to_release_tool>

# Initialize the config in your project
release_tool init

# Start a deployment!
release_tool deploy
```

*For more detailed instructions, please check the [Getting Started Guide](doc/getting_started.md).*

---

## 🤝 Contributing

Contributions are welcome! Feel free to open an issue or submit a pull request if you have ideas to improve this tool.

## 📝 License

This project is licensed under the MIT License.
