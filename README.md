# brew

Repository for generating Homebrew tarballs for redistribution on image-based systems via an OCI image.

This includes general settings you'd want to use when using Homebrew on a `bootc` system, including a tarball and services for setting it up.

## Overview

This repository builds an OCI container image that packages:
- A pre-installed Homebrew tarball (`homebrew.tar.zst`)
- Systemd services for automated setup, updates, and upgrades
- Shell integration scripts (bash, fish)
- Security limits and tmpfiles configuration

The image is designed to be consumed by custom bootc-based container images, providing a seamless way to include Homebrew package management in immutable Linux systems.

## What's Included

### Homebrew Tarball
- Pre-built Homebrew installation at `/usr/share/homebrew.tar.zst`
- Built from official Homebrew installer in a clean Wolfi container
- Compressed with zstd for efficient storage

### Systemd Services

#### brew-setup.service
Runs on first boot to extract and configure Homebrew:
- Extracts tarball to `/var/home/linuxbrew/.linuxbrew`
- Sets appropriate ownership (UID 1000)
- Creates marker file to prevent re-running

#### brew-update.timer & brew-update.service
Automatically keeps Homebrew up to date:
- Runs daily to update Homebrew itself
- Ensures formula database is current

#### brew-upgrade.timer & brew-upgrade.service
Automatically upgrades installed packages:
- Runs on a regular schedule
- Keeps installed packages up to date

### Shell Integration
- **Bash**: `/etc/profile.d/brew.sh` - Automatically configures Homebrew environment
- **Fish**: `/usr/share/fish/vendor_conf.d/ublue-brew.fish` - Fish shell support
- **Bash Completion**: `/etc/profile.d/brew-bash-completion.sh`

### Configuration Files
- **Security Limits**: `/etc/security/limits.d/30-brew-limits.conf`
- **Tmpfiles**: `/usr/lib/tmpfiles.d/homebrew.conf`
- **Systemd Presets**: `/usr/lib/systemd/system-preset/01-homebrew.preset`

## Using in Custom bootc Images

### Basic Example

To include Homebrew in your custom bootc image, copy the files from this repository's OCI image:

```dockerfile
FROM quay.io/fedora/fedora-bootc:41

# Copy Homebrew files from the brew image
COPY --from=ghcr.io/ublue-os/brew:latest /system_files /
```

This will:
1. Install the Homebrew tarball to `/usr/share/homebrew.tar.zst`
2. Install all systemd services and timers
3. Add shell integration scripts
4. Configure system limits and tmpfiles

On first boot, `brew-setup.service` will automatically:
1. Extract Homebrew to `/var/home/linuxbrew/.linuxbrew`
2. Set up proper permissions
3. Make Homebrew ready to use

### Advanced Example with Pre-installed Packages

If you want to pre-install Homebrew packages in your image:

```dockerfile
FROM quay.io/fedora/fedora-bootc:41

# Copy Homebrew files
COPY --from=ghcr.io/ublue-os/brew:latest /system_files /

# Install Homebrew packages during image build
RUN mkdir -p /var/home/linuxbrew && \
    tar --zstd -xvf /usr/share/homebrew.tar.zst -C /tmp && \
    mv /tmp/home/linuxbrew/.linuxbrew /var/home/linuxbrew/ && \
    eval "$(/var/home/linuxbrew/.linuxbrew/bin/brew shellenv)" && \
    brew install gcc neovim ripgrep && \
    brew cleanup && \
    tar --zstd -cvf /usr/share/homebrew.tar.zst /var/home/linuxbrew/.linuxbrew && \
    rm -rf /var/home/linuxbrew/.linuxbrew /tmp/home
```

This approach:
1. Extracts the Homebrew tarball during build
2. Installs desired packages
3. Re-compresses everything back into the tarball
4. Removes temporary files

On first boot, users get Homebrew with your pre-installed packages ready to use.

### Using with Universal Blue Images

For Universal Blue-based images, you can use this as a MODULE:

```dockerfile
FROM ghcr.io/ublue-os/bluefin-dx:latest

# Include Homebrew support
COPY --from=ghcr.io/ublue-os/brew:latest /system_files /
```

### Disabling Auto-Updates

If you want Homebrew installed but prefer manual updates:

```dockerfile
FROM quay.io/fedora/fedora-bootc:41

COPY --from=ghcr.io/ublue-os/brew:latest /system_files /

# Disable automatic update timers
RUN systemctl disable brew-update.timer && \
    systemctl disable brew-upgrade.timer
```

## Building the Image

### Prerequisites
- Podman or Docker
- Make (optional, for using Justfile)

### Build Command

```bash
podman build -t brew:latest -f ./Containerfile .
```

Or using just:

```bash
just build
```

### Multi-Architecture Builds

The GitHub Actions workflow builds for both amd64 and arm64 architectures automatically.

## How It Works

### Build Process

1. **Builder Stage**: Uses Wolfi base image to create a minimal, secure build environment
   - Installs necessary tools (curl, git, zstd, tar, etc.)
   - Downloads official Homebrew installer
   - Runs Homebrew installation in isolated environment
   - Compresses installation to tarball with zstd

2. **Final Stage**: Creates a scratch image with just the necessary files
   - Copies system configuration files
   - Includes compressed Homebrew tarball
   - No runtime dependencies

### Runtime Behavior

When a bootc system using this image boots:

1. **First Boot**:
   - `brew-setup.service` detects no existing Homebrew installation
   - Extracts tarball to `/var/home/linuxbrew/.linuxbrew`
   - Sets ownership to first user (UID 1000)
   - Creates marker file to prevent re-extraction

2. **Subsequent Boots**:
   - `brew-setup.service` skips (marker file exists)
   - `brew-update.timer` runs daily to update Homebrew
   - `brew-upgrade.timer` runs to upgrade packages
   - Shell integration automatically available to users

## Environment Variables

When users log in, the shell integration scripts set up:

```bash
HOMEBREW_PREFIX="/home/linuxbrew/.linuxbrew"
HOMEBREW_CELLAR="/home/linuxbrew/.linuxbrew/Cellar"
HOMEBREW_REPOSITORY="/home/linuxbrew/.linuxbrew/Homebrew"
PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:$PATH"
MANPATH="/home/linuxbrew/.linuxbrew/share/man:$MANPATH"
INFOPATH="/home/linuxbrew/.linuxbrew/share/info:$INFOPATH"
```

## File Locations

| Path | Purpose |
|------|---------|
| `/usr/share/hobrew.tar.zst` | Compressed Homebrew installation |
| `/var/home/linuxbrew/.linuxbrew` | Extracted Homebrew (runtime) |
| `/etc/.linuxbrew` | Marker file indicating setup cn| `/etc/profile.d/brew.sh` | Bash shell integration |
| `/usr/share/fish/vendor_conf.d/ublue-brew.fish` | Fish shell integration |

## Systemd Service Details

### brew-setup.service

**Type**: oneshot  
**When**: First boot only  
**Conditions**:
- `/etc/.linuxbrew` does not exist
- `/var/home/linuxbrew/.linuxbrew` does not exist
- `/usr/share/homst` exists

### brew-update.timer

**Schedule**: Daily  
**Purpose**: Update Homebrew repository and formula database

### brew-upgrade.timer

**Schedule**: Regular intervals  
**Purpose**: Upgrade installed Homebrew packages

## Troubleshooting

### Homebrew not in PATH

Make sure your shell is properly loading the profile scripts:
```bash
source /etc/profile.d/brew.sh
```

Or manually:
```bash
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
```

### Permission Issues

Homebrew expects to be owned by the first user (UID 1000). If you have permission issues:
```bash
sudo chown -R $(id -u):$(id -g) /var/home/linuxbrew
```

### Force Re-extraction

If you need to re-extract the Homebrew tarball:
```bash
sudo rm /etc/.linuxbrew
sudo systemctl start brew-setup.service
```

## License

See [LICENSE](LICENSE) file for details.

## Contributing

This repository is part of the Universal Blue project. Contributions are welcome via pull requests.

## Related Projects

- [Universal Blue](https://universal-blue.org/)
- [Homebrew](https://brew.sh/)
- [bootc](https://containers.github.io/bootc/)
