# Scripts Directory

This directory contains utility scripts for the Wine Prefix Manager project.

## Version Sync Checker (`check_version_sync.sh`)

A shell script that ensures the version in `pubspec.yaml` stays synchronized with git tags.

### Usage

```bash
# Check if versions are in sync
./scripts/check_version_sync.sh

# Automatically create git tag if versions are out of sync
./scripts/check_version_sync.sh --fix

# Show help
./scripts/check_version_sync.sh --help
```

### Via Makefile

```bash
# Check version sync
make version-check

# Auto-fix version sync (creates git tag)
make version-fix

# Show version information
make version-info
```

### Exit Codes

- `0` - Versions are in sync
- `1` - Versions are out of sync
- `2` - Error occurred (file not found, git not available, etc.)

### Features

- ✅ Compares `pubspec.yaml` version with latest git tag
- ✅ Handles version normalization (removes build info after `+`)
- ✅ Supports both `v1.0.0` and `1.0.0` tag formats
- ✅ Colorized output for better readability
- ✅ Provides helpful suggestions when versions are out of sync
- ✅ Can automatically create git tags with `--fix` option
- ✅ Integrated with GitHub Actions for CI/CD

### Examples

#### Versions in sync:
```bash
$ ./scripts/check_version_sync.sh
🔍 Checking version synchronization...

📄 Reading pubspec.yaml version...
   Pubspec version: 1.0.0+1
   Normalized: 1.0.0

🏷️  Checking latest git tag...
   Latest git tag: 1.0.0
   Normalized: 1.0.0

✅ Versions are in sync!
   Both pubspec.yaml and git tag reference version: 1.0.0
```

#### Versions out of sync:
```bash
$ ./scripts/check_version_sync.sh
🔍 Checking version synchronization...

📄 Reading pubspec.yaml version...
   Pubspec version: 1.1.0
   Normalized: 1.1.0

🏷️  Checking latest git tag...
   Latest git tag: 1.0.0
   Normalized: 1.0.0

❌ Versions are out of sync!
   Pubspec version: 1.1.0
   Git tag version: 1.0.0

💡 Suggestions:
   1. Update pubspec.yaml version to match git tag: 1.0.0
   2. Create new git tag to match pubspec.yaml: v1.1.0
   3. Run with --fix to automatically create the git tag

Commands:
   Create tag: git tag -a v1.1.0 -m "Release version 1.1.0"
   Push tag:   git push origin v1.1.0
```

#### Auto-fix mode:
```bash
$ ./scripts/check_version_sync.sh --fix
🔍 Checking version synchronization...

📄 Reading pubspec.yaml version...
   Pubspec version: 1.1.0
   Normalized: 1.1.0

🏷️  Checking latest git tag...
   Latest git tag: 1.0.0
   Normalized: 1.0.0

❌ Versions are out of sync!
   Pubspec version: 1.1.0
   Git tag version: 1.0.0

🔧 Fix mode enabled. Creating git tag...
Creating git tag: v1.1.0
✓ Git tag 'v1.1.0' created successfully
Don't forget to push the tag: git push origin v1.1.0
```

## GitHub Actions Integration

The script is automatically run in CI/CD via `.github/workflows/version_check.yml`:

- ✅ Runs on push to `main` and `develop` branches
- ✅ Runs on pull requests
- ✅ Automatically comments on PRs when versions are out of sync
- ✅ Provides detailed job summaries
- ✅ Can be triggered manually via workflow dispatch

## Release Management

Use the Makefile for streamlined release management:

```bash
# Create a new release (updates pubspec.yaml, commits, tags, and pushes)
make tag-release VERSION=1.2.0
```

This will:
1. Update `pubspec.yaml` with the new version
2. Commit the version change
3. Create an annotated git tag
4. Push both the commit and tag to the remote repository

## Prerequisites

- Git repository with version tags
- `bash` shell
- `grep`, `sed`, `tr` commands (standard on Linux/macOS)
- Flutter project with `pubspec.yaml`

## Best Practices

1. **Always check version sync before releases**
2. **Use semantic versioning** (MAJOR.MINOR.PATCH)
3. **Tag releases consistently** with `v` prefix (e.g., `v1.0.0`)
4. **Run version check in CI/CD** to catch issues early
5. **Use `--fix` option carefully** - only when you're sure you want to create a new tag 