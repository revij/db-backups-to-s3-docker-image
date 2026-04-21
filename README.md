A Docker image that supports remotely backing up MySQL and PostgreSQL databases to S3-compatible storage buckets (e.g. Amazon S3, Backblaze B2, etc.).

Timing of the backups are determined by a cron job installed inside of the Docker image (located at [`image/conf/cron.conf`](./image/conf/cron.conf)) that executes a backup script written in Bash ([`image/scripts/backup.sh`](./image/scripts/backup.sh)). The backup script dumps the database `$DB_NAME` using the user `$DB_USER` (identified by the password `$DB_PASS`) to `/tmp/$DB_NAME.sql`. Afterwards, it uploads the database dump to the S3 storage bucket using [Duplicity](https://duplicity.us/) and deletes the local database dump.

The custom Docker image files are stored inside of the [`image/`](./image) directory. There is also a Docker Compose application example you can refer to and use inside of the [`example/`](./example) directory which shows how to utilize this image.

## Using Pre-Built Images from GitHub Container Registry
Pre-built Docker images are automatically published to GitHub Container Registry. You can pull and use them without building locally:

```bash
docker pull ghcr.io/YOUR_GITHUB_USERNAME/db-backups-to-s3-docker-image:latest
```

Available tags:
- `latest` - Latest build from the main branch
- `v*` - Specific version tags (e.g., `v1.0.0`)
- `main` - Latest main branch build

To use the pre-built image in Docker Compose, update your `image` reference:

```yaml
services:
  db-backups:
    image: ghcr.io/YOUR_GITHUB_USERNAME/db-backups-to-s3-docker-image:latest
    hostname: db-backups
    volumes:
      - ./backup-logs:/var/log/backups/
    env_file:
      - ./.env
```

## Building The Docker Image Locally
If you prefer to build the image yourself, the custom Docker image is stored inside of the [`image/`](./image) directory. You can use the `build_image.sh` Bash script to build the Docker image with customization support including the image name, tag, path, and more options.

The following arguments are supported when executing the script.

| Flag | Default | Description |
| ---- | ------- | ----------- |
| `--name=<NAME>` | `db-backups` | The name of the Docker image. |
| `--tag=<TAG>` | `latest` | The Docker image's tag. |
| `--path=<PATH>` | `image/` | Builds the Docker image inside of `<PATH>`. |
| `--base-name=<NAME>` | `debian` | The base Docker image (recommend using `debian` or `ubuntu` since we rely on the `apt` package manager). |
| `--base-tag=<TAG>` | `latest` | The base Docker image tag to use. |
| `--no-cache` | - | Builds the Docker image with no cache. |
| `--help` | - | Prints the help menu. |

By default, the cron job that executes the backup script is ran every night at *12:00* (midnight). You can easily change this by setting the `BACKUP_SCHEDULE` environment variable (see Environmental Configuration section below). You can use a cron generator tool such as [this](https://crontab.cronhub.io/) for assistance!

You may also build the image manually using the following command as root (or using `sudo`).

```bash
docker build -t db-backups:latest image/
```

## Utilizing The Docker Image
I'd recommend giving the ([`example/`](./example)) directory a look as it includes Docker Compose configuration files that shows how to use this custom Docker image.

I'd also recommend implementing this image using Docker Compose. For example, in your `docker-compose.yml` file, you can create the backups service like below.

```yaml
services:
  db-backups:
    image: db-backups:latest
    hostname: db-backups
    volumes:
      - ./backup-logs:/var/log/backups/
      - /root/.gnupg:/root/.gnupg:ro  # Optional: Mount GPG keyring for public key encryption
      - ./duplicity-cache:/root/.cache/duplicity  # Required: Preserve Duplicity metadata
    env_file:
      - ./.env
```

📝**NOTE**: The above configuration expects you to store the project's env variables inside a separate file (`./env`). You can replace the `env_file` section with `environment` and pass the env variables inside of the `docker-compose.yml` file directly in `<env_var>: "<value>"` format.

## Environmental Configuration
All configuration for the backup script is set using environmental variables inside of the Docker container. In the Docker Compose application example inside this repository ([`example/`](./example)), we store the environmental variables inside of the [`example/.env`](./example/.env.example) file. By default, the file is called `.env.example`. Therefore, make sure to rename or copy it to `.env`.

Here are a list of environmental variables that are supported.

| Name | Default | Description |
| ---- | ------- | ----------- |
| BACKUP_SCHEDULE | `0 0 * * *` | Cron schedule for automated backups (default: daily at midnight). Examples: `0 */6 * * *` (every 6 hours), `*/30 * * * *` (every 30 minutes), `0 * * * *` (hourly). |
| VERBOSE | `1` | The backup script's verbose level. Log messages go up to verbose level `4` currently. |
| LOG_DIR | `/var/log/backups` | The backup script's log directory inside of the Docker container. Leave blank to disable logging to files. |
| DEL_LOCAL | `1` | If 1 or higher, deletes the local database dump after uploading it to the S3 bucket. |
| S3_ENDPOINT | *N/A* | The S3 endpoint URL. |
| S3_KEY_ID | *N/A* | The S3 key ID to use for authentication to the bucket. |
| S3_APP_KEY | *N/A* | The S3 app key to use for authentication to the bucket. |
| S3_BUCKET | *N/A* | The name of the S3 bucket to store backups in. |
| S3_BUCKET_DIR | *N/A* | The directory to store backups in within the bucket. |
| DB_TYPE | `mysql` | The type of database backup (currently only supports `mysql` and `postgresql`). |
| DB_HOST | `localhost` | The database host. |
| DB_NAME | `test-db` | The name of the database to backup. |
| DB_USER | `root` | The user to authenticate with when performing the backup. |
| DB_PASS | `""` | The password to authenticate with when performing the backup. |
| DB_PORT | `3306` | The database port to use when connecting to the database. |
| EXCLUDE_TABLES | `""` | Comma-separated list of tables to exclude from backup. For MySQL, table names without a database prefix will automatically use `DB_NAME`. For PostgreSQL, specify schema if needed (e.g., `public.table`). Example: `cache,sessions,logs` |
| DUP_FORCE_INC | `0` | Set to `1` to force an incremental backup (fails if no full backup exists). |
| DUP_FORCE_FULL | `0` | Set to `1` to force a full backup. When both are `0` (default), Duplicity auto-detects: full on first run, incremental thereafter. |
| DUP_FULL_IF_OLDER_THAN | *N/A* | Automatically promote to a full backup when the last full backup is older than this interval. Accepts Duplicity time format: `7D` (7 days), `2W` (2 weeks), `1M` (1 month). Ignored when `DUP_FORCE_FULL` or `DUP_FORCE_INC` are set. |
| DUP_KEEP_N_FULL | *N/A* | Keep only the last N full backups and their associated incrementals. Older backup chains are deleted from S3 automatically after each successful backup. |
| GPG_KEY_ID | *N/A* | **Recommended.** GPG key ID for public key encryption. When set, backups are encrypted with your GPG public key (no passphrase needed on backup server). Requires mounting `/root/.gnupg` volume. See [GPG Encryption Setup](#gpg-encryption-setup) below. |
| DUP_PASS | `12345` | **Optional (if using GPG).** Passphrase for symmetric encryption. Used as fallback if `GPG_KEY_ID` is not set. Required for restoring symmetric-encrypted backups. |
| HC_PING_URL | *N/A* | Optional. The ping URL for monitoring backup status using [healthchecks.io](https://healthchecks.io/) or [self-hosted Healthchecks](https://github.com/healthchecks/healthchecks). When set, the script will send start/success/failure signals. |

## GPG Encryption Setup

This image supports two encryption methods for Duplicity backups:

### 1. GPG Public Key Encryption (Recommended)

**Advantages:**
- No passphrase needed on the backup server
- Better security - private key never leaves your local machine
- Even if backup server is compromised, existing backups remain encrypted

**Setup:**

1. **Create a GPG key pair** (on your local machine):
   ```bash
   gpg --full-generate-key
   # Follow prompts to create RSA key with your details
   ```

2. **Export only the public key:**
   ```bash
   # List your keys to get the key ID
   gpg --list-keys

   # Export public key (example key ID)
   gpg --armor --export 1DEC8742DC0444F467EBFA1A9530207BF925C664 > gpg-public.asc
   ```

3. **Import the public key on the backup server:**
   ```bash
   # Copy the public key to the server
   scp gpg-public.asc user@backup-server:/root/

   # Import it
   gpg --import /root/gpg-public.asc

   # Trust the key
   gpg --edit-key 1DEC8742DC0444F467EBFA1A9530207BF925C664 trust
   # Type: 5 (ultimate), y, quit
   ```

4. **Mount the GPG directory in docker-compose.yml:**
   ```yaml
   volumes:
     - /root/.gnupg:/root/.gnupg:ro
     - ./duplicity-cache:/root/.cache/duplicity
   ```

5. **Set the GPG_KEY_ID in your `.env` file:**
   ```bash
   GPG_KEY_ID="1DEC8742DC0444F467EBFA1A9530207BF925C664"
   ```

**Restoring backups:**

To restore, use your local machine where the **private key** is stored:
```bash
# Duplicity will prompt for your GPG passphrase to unlock the private key
duplicity restore s3://your-bucket/path /restore/destination
```

### 2. Symmetric Encryption (Passphrase - Less Secure)

Set `DUP_PASS` environment variable with a strong passphrase. This method requires the passphrase for both encryption and decryption.

```bash
DUP_PASS="your-strong-passphrase-here"
```

**Note:** If both `GPG_KEY_ID` and `DUP_PASS` are set, GPG public key encryption takes priority.

## Excluding Tables from Backup

You can exclude specific tables from the backup using the `EXCLUDE_TABLES` environment variable. This is useful for skipping cache tables, session tables, or other temporary data that doesn't need to be backed up.

**Format:** Comma-separated list of table names

**MySQL Example:**

```bash
# Simple table names (database prefix is added automatically)
EXCLUDE_TABLES="cache,sessions,logs"
```

**PostgreSQL Examples:**

```bash
# Simple table names
EXCLUDE_TABLES="cache,sessions,logs"

# With schema prefix
EXCLUDE_TABLES="public.cache,audit.logs,public.sessions"
```

## Credits
* [Christian Deacon](https://github.com/gamemann)
