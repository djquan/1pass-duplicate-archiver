# 1Password Duplicate Detector

A Ruby script to detect and remove duplicate items in your 1Password vault. It identifies duplicates based on:

- Normalized URLs (e.g., `account.example.com` and `example.com` are considered the same)
- Usernames
- Passwords

## Prerequisites

- Ruby 2.7 or higher
- 1Password CLI installed and configured
- 1Password account with access to the vault you want to check

## Installation

1. Clone this repository
2. Install dependencies:

   ```bash
   bundle install
   ```

## Usage

### Basic Usage

To detect duplicates in a vault (dry run mode - no items will be archived):

```bash
ruby lib/1pass_duplicate.rb detect --vault "Your Vault Name"
```

### Command Options

- `--vault NAME` (required): The name of your 1Password vault to check
- `--no-dry-run`: Actually archive duplicates instead of just detecting them
- `--clear-cache`: Clear the cached item details before running

### Examples

Check for duplicates (safe, read-only mode):

```bash
ruby lib/1pass_duplicate.rb detect --vault "Personal"
```

Archive duplicates:

```bash
ruby lib/1pass_duplicate.rb detect --vault "Personal" --no-dry-run
```

Force a fresh scan by clearing the cache:

```bash
ruby lib/1pass_duplicate.rb detect --vault "Personal" --clear-cache
```

## How it Works

The script will:

1. Cache item details locally for faster subsequent runs
2. Scan your specified 1Password vault
3. Normalize URLs by:
   - Removing common subdomains (www, account, login, app, my, secure, member, auth)
   - Ignoring URL paths
4. Group items by their normalized URL, username, and password
5. Display found duplicates with their details
6. If not in dry-run mode, archive all but the most recently updated item in each duplicate set

## Performance

- First run will be slower as it needs to fetch and cache all item details
- Subsequent runs will be much faster, using the cached data
- Cache is stored in `~/.cache/1pass_duplicate`
- Cached items are automatically removed when archived
- Use `--clear-cache` to force a fresh scan

## Safety Features

- By default, runs in dry-run mode to show duplicates without archiving them
- Keeps the most recently updated version of duplicate items
- Archives items instead of deleting them, allowing for recovery if needed
- Caches item details to prevent unnecessary API calls

## Contributing

Feel free to open issues or submit pull requests for improvements!
