A Docker image that supports remotely backing up MySQL and PostgreSQL databases to S3-compatible storage buckets (e.g. Amazon S3, Backblaze B2, etc.).

Timing of the backups are determined by a cron job installed inside of the Docker image (located at [`image/conf/cron.conf`](./image/conf/cron.conf)) that executes a backup script written in Bash ([`image/scripts/backup.sh`](./image/scripts/backup.sh)). The backup script dumps the database `$DB_NAME` using the user `$DB_USER` (identified by the password `$DB_PASS`) to `/tmp/$DB_NAME.sql`. Afterwards, it uploads the database dump to the S3 storage bucket using [Duplicity](https://duplicity.us/) and deletes the local database dump.

The custom Docker image files are stored inside of the [`image/`](./image) directory. There is also a Docker Compose application example you can refer to and use inside of the [`example/`](./example) directory which shows how to utilize this image.

## Building The Docker Image
The custom Docker image is stored inside of the [`image/`](./image) directory. You can use the `build_image.sh` Bash script to build the Docker image with customization support including the image name, tag, path, and more options.

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

By default, the cron job that executes the backup script is ran every night at *12:00* (midnight). However, you can easily change this by editing the [`image/conf/cron.conf`](./image/conf/cron.conf) file and rebuilding the image. You can use a cron generator tool such as [this](https://crontab.cronhub.io/) for assistance!

You may also build the image manually using the following command as root (or using `sudo`).

```bash
docker build -t db-backups:latest image/
```

## Utilizing The Docker Image
I'd recommend giving the ([`example/`](./example)) directory a look as it includes Docker Compose configuration files that shows how to use this custom Docker image.

I'd also recommend implementing this image using Docker Compose. For example, in your `docker-compose.yml` file, you can create the backups service like below.

```yaml
version: "3.9"

services:
  db-backups:
    image: db-backups:latest
    hostname: db-backups
    volumes:
      - ./backup-logs:/var/log/backups/
    env_file:
      - ./.env
```

## Environmental Configuration
All configuration for the backup script is set using environmental variables inside of the Docker container. In the Docker Compose application example inside this repository ([`example/`](./example)), we store the environmental variables inside of the [`example/.env`](./example/.env.example) file. By default, the file is called `.env.example`. Therefore, make sure to rename or copy it to `.env`.

Here are a list of environmental variables that are supported.

| Name | Default | Description |
| ---- | ------- | ----------- |
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
| DUP_FORCE_INC | `0` | Forces Duplicity to perform an incremental backup. |
| DUP_FORCE_FULL | `0` | Forces Duplicity to perform a full backup. |
| DUP_PASS | `12345` | This is the GnuPG passphrase which is required for restoring the backup. It is recommended you set and change this value! |

## Credits
* [Christian Deacon](https://github.com/gamemann)