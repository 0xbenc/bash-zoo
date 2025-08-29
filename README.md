# Bash Zoo 🐧🖥️⚡

Bash Zoo is a collection of powerful and useful Bash scripts designed to enhance productivity on Linux. It provides a set of handy tools that can be easily installed and accessed from anywhere in the terminal. Testing dev PRs.

## Installation and Usage

This project supports Debian-like Linux and macOS with different capabilities:

- Debian/Ubuntu/Pop: All scripts are available. Dependencies install via `apt`.
- macOS: Only `mfa` is available. Homebrew must be installed first.
- Other platforms: No installers or options are offered.

Follow these steps to clone the repository, grant execution permissions, and run the installer:

### 1. Clone the Repository

```bash
git clone https://github.com/0xbenc/bash-zoo
cd bash-zoo
```

### 2. Grant Execution Permissions to `wizard.sh`&#x20;

```bash
sudo chmod +x wizard.sh
```

### 3. macOS Prerequisite (if on macOS)

Ensure Homebrew is installed. If not, install from https://brew.sh or run:

```
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

On macOS, the wizard will only offer `mfa` and will install its dependencies using Homebrew.

### 4. Run the Installer

```bash
./wizard.sh
```

### 5. Follow the On-Screen Instructions

- Use `J` and `K` to navigate the script selection.
- Press `H` to toggle selection.
- Press `L` to confirm and proceed with installation.
 - The wizard auto-detects your platform and shows supported scripts only.

### 6. Usage After Installation

Once installed, the selected scripts can be run from anywhere by simply typing their names (without `.sh` extension) in the terminal.

If your shell configuration supports auto-aliasing, restart your terminal or source your shell configuration:

```bash
source ~/.bashrc  # For Bash
source ~/.zshrc   # For Zsh
```

## Uninstallation

To remove the aliases, open your shell configuration file (`~/.bashrc` or `~/.zshrc`) and remove the corresponding alias lines manually.

## Notes

- Ensure the `installers` and `scripts` directories exist before running `wizard.sh`.
- The script works on both Bash and Zsh shells.
- If no scripts are selected, the installation will exit without modifying the system.
- On macOS, only `mfa` is supported; Homebrew is required and must be present before running the wizard.
- On Debian-like Linux, dependencies are installed per script via `apt`.

## Contributors

- **Ben Chapman** ([0xbenc](https://github.com/0xbenc)) - Maintainer
- **Ben Cully** ([BenCully](https://github.com/BenCully)) - Contributor

## Models Used 🤖🧠⚡

- **ChatGPT: `4o`, `4.5`, `o3-mini`, `o3-mini-high`, `04-mini-high`, `5`, `5-pro`**

- **GPT OSS: `gpt-oss-20b`, `gpt-oss-120b`** 

- **deepseekr1:7b**

- **llama3.2:3b**

Enjoy using Bash Zoo! 🐧🎉🔥
