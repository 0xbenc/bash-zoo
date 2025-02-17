# Bash Zoo 🐧🖥️⚡

Bash Zoo is a collection of powerful and useful Bash scripts designed to enhance productivity on Linux. It provides a set of handy tools that can be easily installed and accessed from anywhere in the terminal.

## Installation and Usage 📥⚙️🐧

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

### 3. Run the Installer

```bash
./wizard.sh
```

### 4. Follow the On-Screen Instructions

- Use `J` and `K` to navigate the script selection.
- Press `H` to toggle selection.
- Press `L` to confirm and proceed with installation.

### 5. Usage After Installation

Once installed, the selected scripts can be run from anywhere by simply typing their names (without `.sh` extension) in the terminal.

If your shell configuration supports auto-aliasing, restart your terminal or source your shell configuration:

```bash
source ~/.bashrc  # For Bash
source ~/.zshrc   # For Zsh
```

## Uninstallation ❌🗑️⚠️

To remove the aliases, open your shell configuration file (`~/.bashrc` or `~/.zshrc`) and remove the corresponding alias lines manually.

## Notes 📝📌📢

- Ensure the `installers` and `scripts` directories exist before running `wizard.sh`.
- The script works on both Bash and Zsh shells.
- If no scripts are selected, the installation will exit without modifying the system.

## Contributors 👥🤝🌍

- **Ben Chapman** ([0xbenc](https://github.com/0xbenc)) - Maintainer
- **Ben Cully** ([BenCully](https://github.com/BenCully))

## Models Used 🤖🧠⚡

- **ChatGPT 4o**

- **deepseekr1:7b**

- **llama3.2:3b**

Enjoy using Bash Zoo! 🐧🎉🔥
