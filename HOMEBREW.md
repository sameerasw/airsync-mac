# Homebrew Installation Guide

AirSync can be installed via Homebrew for easy installation and automatic quarantine removal.

## Installation

```bash
# Add the tap (if this becomes an official tap in the future)
brew tap sameerasw/airsync-mac

# Install AirSync
brew install airsync
```

## Manual Installation from this Repository

If you want to install directly from this repository:

```bash
# Install directly from the formula file
brew install --formula ./Formula/airsync.rb
```

## What the Formula Does

The Homebrew formula:

1. **Automatic Architecture Detection**: Downloads the correct version (ARM64 for Apple Silicon, x86_64 for Intel)
2. **Quarantine Removal**: Automatically removes the `com.apple.quarantine` attribute to prevent security dialogs
3. **Proper Installation**: Installs AirSync.app to the correct location
4. **Version Management**: Handles updates through Homebrew's standard update mechanism

## Post-Installation

After installation, you can:

```bash
# Open AirSync
open "$(brew --prefix)/AirSync.app"

# Or find it in your Applications folder
# (Homebrew creates a symlink there automatically)
```

## Troubleshooting

### Security Warnings

The formula automatically removes quarantine attributes, but if you still get security warnings:

1. Go to **System Preferences** → **Privacy & Security**
2. Look for AirSync in the blocked apps section
3. Click **"Open Anyway"**

### Network Permissions

On first launch, macOS will ask for network permissions:
- Allow **incoming connections** for the WebSocket server
- Allow **outgoing connections** for updates and Android communication

## Uninstallation

```bash
brew uninstall airsync
```

## Development

To test the formula locally:

```bash
# Test syntax
brew audit --formula Formula/airsync.rb

# Test installation (dry run)
brew install --formula --dry-run Formula/airsync.rb
```

## Release Process

1. **Tag a Release**: Create a git tag (e.g., `v2.0.20`)
2. **GitHub Actions**: The `homebrew-release.yml` workflow automatically:
   - Builds ARM64 and x86_64 versions
   - Creates release archives
   - Calculates SHA256 checksums
   - Updates the formula with correct hashes
   - Creates a GitHub release
3. **Formula Update**: The formula is automatically updated with each release