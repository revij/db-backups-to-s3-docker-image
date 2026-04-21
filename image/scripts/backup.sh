#!/bin/bash
PATH=$PATH:/usr/local/bin/

DATE_MORE=$(date +"%Y-%m-%d %H:%M:%S")
DATE_SIMPLE=$(date +"%Y-%m-%d")

# Log function.
log() {
    if [[ "$VERBOSE" -ge "$1" ]]; then
        echo "[$1][$DATE_MORE] $2"

        # Check for log file.
        if [[ -n "$LOG_DIR" ]]; then
            LOG_FILE="$LOG_DIR/$DATE_SIMPLE.log"

            echo "[$1][$DATE_MORE] $2" >> $LOG_FILE
        fi
    fi
}

# Healthchecks.io ping function.
hc_ping() {
    if [[ -n "$HC_PING_URL" ]]; then
        local endpoint="$1"
        local message="$2"

        if [[ -n "$message" ]]; then
            curl -fsS -m 10 --retry 3 --data-raw "$message" "${HC_PING_URL}${endpoint}" > /dev/null 2>&1
        else
            curl -fsS -m 10 --retry 3 "${HC_PING_URL}${endpoint}" > /dev/null 2>&1
        fi

        log 3 "Healthchecks.io ping sent: ${endpoint}"
    fi
}

# Parse comma-separated excluded tables into command-line arguments.
parse_excluded_tables() {
    local exclude_tables="$1"
    local db_type="$2"
    local db_name="$3"
    local result=""

    if [[ -n "$exclude_tables" ]]; then
        IFS=',' read -ra TABLES <<< "$exclude_tables"
        for table in "${TABLES[@]}"; do
            # Trim whitespace
            table=$(echo "$table" | xargs)

            # Skip empty entries
            if [[ -z "$table" ]]; then
                continue
            fi

            if [[ "$db_type" == "mysql" ]]; then
                # MySQL format: --ignore-table=database.table
                if [[ "$table" != *.* ]]; then
                    # Add database prefix if not present
                    table="${db_name}.${table}"
                fi
                result="$result --ignore-table=$table"
            elif [[ "$db_type" == "postgresql" ]]; then
                # PostgreSQL format: --exclude-table=table or --exclude-table=schema.table
                result="$result --exclude-table=$table"
            fi
        done
    fi

    echo "$result"
}

# Set database variables to default if not already set.
if [[ -z "$DB_TYPE" ]]; then
    log 1 "⚠️ Warning: 'DB_TYPE' env variable not set. Using 'mysql'..."

    DB_TYPE="mysql"
fi

if [[ -z "$DB_HOST" ]]; then
    log 1 "⚠️ Warning: 'DB_HOST' env variable not set. Using 'localhost'..."

    DB_HOST="localhost"
fi

if [[ -z "$DB_NAME" ]];  then
    log 1 "⚠️ Warning: 'DB_NAME' env variable not set. Using 'db01'..."

    DB_NAME="db01"
fi

if [[ -z "$DB_USER" ]]; then
    log 1 "⚠️ Warning: 'DB_USER' env variable not set. Using 'root'..."

    DB_USER="root"
fi

if [[ -z "$DB_PASS" ]]; then
    log 1 "⚠️ Warning: 'DB_PASS' env variable not set. Using ''..."

    DB_PASS=""
fi

if [[ -z "$DB_PORT" ]]; then
    log 1 "⚠️ Warning: 'DB_PORT' env variable not set. Using '3306'..."

    DB_PORT=3306
fi

# Optional: Tables to exclude from backup (comma-separated).
EXCLUDE_TABLES="${EXCLUDE_TABLES:-}"

# Ensure S3 variables are set.
if [[ -z "$S3_ENDPOINT" ]]; then
    log 0 "❌ Error: 'S3_ENDPOINT' env variable not set."

    exit 1
fi

if [[ -z "$S3_KEY_ID" ]]; then
    log 0 "❌ Error: 'S3_KEY_ID' env variable not set."

    exit 1
fi

if [[ -z "$S3_APP_KEY" ]]; then
    log 0 "❌ Error: 'S3_APP_KEY' env variable not set."

    exit 1
fi

if [[ -z "$S3_BUCKET" ]]; then
    log 0 "❌ Error: 'S3_BUCKET' env variable not set."

    exit 1
fi

if [[ -z "$S3_BUCKET_DIR" ]]; then
    log 1 "⚠️ Warning: 'S3_BUCKET_DIR' env variable not set. Using ''..."

    S3_BUCKET_DIR=""
fi

# Encryption validation - need either GPG key or passphrase.
if [[ -z "$GPG_KEY_ID" && -z "$DUP_PASS" ]]; then
    log 1 "⚠️ Warning: Neither 'GPG_KEY_ID' nor 'DUP_PASS' env variable is set. Your duplicity backup will not be encrypted!"
fi

# If GPG key is specified, validate it exists in keyring.
if [[ -n "$GPG_KEY_ID" ]]; then
    if ! gpg --list-keys "$GPG_KEY_ID" > /dev/null 2>&1; then
        echo "❌ Error: GPG key '$GPG_KEY_ID' not found in keyring."
        echo "Make sure you have mounted /root/.gnupg with the public key imported."

        hc_ping "/fail" "Error: GPG key '$GPG_KEY_ID' not found in keyring."
        exit 1
    fi
    log 2 "GPG public key found: $GPG_KEY_ID"
fi

if [[ -z "$DUP_FORCE_INC" ]]; then
    log 1 "⚠️ Warning: 'DUP_FORCE_INC' env variable not set. Using '0' (false)..."

    DUP_FORCE_INC=0
fi

if [[ -z "$DUP_FORCE_FULL" ]]; then
    log 1 "⚠️ Warning: 'DUP_FORCE_FULL' env variable not set. Using '0' (false)..."

    DUP_FORCE_FULL=0
fi

# Optional: force a full backup if the last full is older than this interval.
# Accepts duplicity time format: e.g. 7D (7 days), 2W (2 weeks), 1M (1 month).
# Ignored when DUP_FORCE_FULL or DUP_FORCE_INC are set.
DUP_FULL_IF_OLDER_THAN="${DUP_FULL_IF_OLDER_THAN:-}"

# Optional: keep only the last N full backups (and their incrementals).
# Older chains are removed automatically after each successful backup.
DUP_KEEP_N_FULL="${DUP_KEEP_N_FULL:-}"

# Print verbose information.
log 1 "Starting backup on '$DATE_MORE'..."

# Ping healthchecks.io to signal start.
hc_ping "/start"

log 3 "S3 Settings"
log 3 "\tEndpoint: $S3_ENDPOINT"
log 3 "\tKey ID: $S3_KEY_ID"
log 4 "\tApp Key: $S3_APP_KEY"
log 3 "\tBucket Name: $S3_BUCKET"
log 3 "\tBucket Directory: $S3_BUCKET_DIR"

log 3

log 2 "Database Settings"
log 2 "\tType: $DB_TYPE"
log 3 "\tHost: $DB_HOST"
log 3 "\tName: $DB_NAME"
log 3 "\tUser: $DB_USER"
log 4 "\tPass: $DB_PASS"
log 3 "\tPort: $DB_PORT"
if [[ -n "$EXCLUDE_TABLES" ]]; then
    log 2 "\tExcluding tables: $EXCLUDE_TABLES"
fi

log 2

log 2 "Duplicity Settings"
log 2 "\tForce Incremental: $DUP_FORCE_INC"
log 2 "\tForce Full: $DUP_FORCE_FULL"
log 2 "\tFull if older than: ${DUP_FULL_IF_OLDER_THAN:-not set}"
log 2 "\tKeep N full backups: ${DUP_KEEP_N_FULL:-not set (unlimited)}"
if [[ -n "$GPG_KEY_ID" ]]; then
    log 2 "\tEncryption: GPG public key"
    log 3 "\tGPG Key ID: $GPG_KEY_ID"
elif [[ -n "$DUP_PASS" ]]; then
    log 2 "\tEncryption: Symmetric (passphrase)"
    log 4 "\tPassphrase: $DUP_PASS"
else
    log 2 "\tEncryption: None (⚠️ NOT RECOMMENDED)"
fi

# Determine file extension.
FILE_EXT="sql"

# Dump database.
DUMP_FILE_NAME="${DB_NAME}.${FILE_EXT}"
FULL_DUMP_PATH="/tmp/${DUMP_FILE_NAME}"

log 2 "Backing up database to temporary file '$FULL_DUMP_PATH'..."

if [[ "$DB_TYPE" == "mysql" ]]; then
    MYSQL_EXCLUDE_OPTS=$(parse_excluded_tables "$EXCLUDE_TABLES" "mysql" "$DB_NAME")
    mysqldump --no-tablespaces -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" $MYSQL_EXCLUDE_OPTS "$DB_NAME" > "$FULL_DUMP_PATH"

    ret=$?
elif [[ "$DB_TYPE" == "postgresql" ]]; then
    export PGPASSFILE=/dev/null

    # Set PG password if set.
    if [[ -n "$DB_PASS" ]]; then
        export PGPASSWORD="$DB_PASS"
    fi

    PG_EXCLUDE_OPTS=$(parse_excluded_tables "$EXCLUDE_TABLES" "postgres" "$DB_NAME")
    pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" $PG_EXCLUDE_OPTS -d "$DB_NAME" > "$FULL_DUMP_PATH"

    ret=$?
else
    echo "❌ Error: 'DB_TYPE' env variable set to incorrect value (only accepts 'mysql' or 'postgresql' as values)."

    hc_ping "/fail" "Error: Invalid DB_TYPE value '$DB_TYPE'. Only 'mysql' or 'postgresql' are supported."
    exit 1
fi

# Check output of dump command.
if [[ $ret -ne 0 ]]; then
    echo "❌ Error: Failed to dump database for '$DB_TYPE'."
    echo "Error Code: $ret"

    hc_ping "/fail" "Error: Failed to dump database for '$DB_TYPE'. Exit code: $ret"
    exit 1
fi

# Upload to S3.
log 2 "Uploading database backup to S3 storage..."

# Compile part of the duplicity command.
if [[ "$DUP_FORCE_FULL" -ge 1 ]]; then
    DUP_CMD_ARGS=("full")
elif [[ "$DUP_FORCE_INC" -ge 1 ]]; then
    DUP_CMD_ARGS=("incremental")
else
    # Auto-detect: full if no backup exists, incremental otherwise.
    # Optionally promote to full when last full is older than DUP_FULL_IF_OLDER_THAN.
    DUP_CMD_ARGS=()
    if [[ -n "$DUP_FULL_IF_OLDER_THAN" ]]; then
        DUP_CMD_ARGS+=("--full-if-older-than=$DUP_FULL_IF_OLDER_THAN")
    fi
fi

# We need to export some things for duplicity.
export AWS_ACCESS_KEY_ID="$S3_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$S3_APP_KEY"
export AWS_ENDPOINT_URL="https://${S3_ENDPOINT}"

# Compile full S3 URL.
S3_URL="s3://${S3_BUCKET}/${S3_BUCKET_DIR}"

# Choose encryption method: GPG public key (preferred) or symmetric passphrase (fallback).
if [[ -n "$GPG_KEY_ID" ]]; then
    # Use GPG public key encryption (no passphrase needed on backup server).
    log 2 "Encrypting with GPG public key..."
    duplicity "${DUP_CMD_ARGS[@]}" --encrypt-key="$GPG_KEY_ID" --allow-source-mismatch "$FULL_DUMP_PATH" "$S3_URL"
    ret=$?
elif [[ -n "$DUP_PASS" ]]; then
    # Use symmetric encryption with passphrase (less secure).
    log 2 "Encrypting with passphrase..."
    env PASSPHRASE="$DUP_PASS" duplicity "${DUP_CMD_ARGS[@]}" --allow-source-mismatch "$FULL_DUMP_PATH" "$S3_URL"
    ret=$?
else
    # No encryption configured - upload without encryption (not recommended).
    log 1 "⚠️ Warning: Uploading backup WITHOUT encryption!"
    duplicity "${DUP_CMD_ARGS[@]}" --no-encryption --allow-source-mismatch "$FULL_DUMP_PATH" "$S3_URL"
    ret=$?
fi

# Remove local backup.
if [[ "$DEL_LOCAL" -ge 1 ]]; then
    log 3 "Removing local backup file '$FULL_DUMP_PATH'..."
    rm -f "$FULL_DUMP_PATH"
fi

if [[ $ret -ne 0 ]]; then
    echo "❌ Error: Failed to upload backup to S3 bucket. Duplicity command failed."
    echo "Error Code: $ret"

    hc_ping "/fail" "Error: Failed to upload backup to S3 bucket. Duplicity exit code: $ret"
    exit 1
fi

log 1 "✅ Backup completed!"

# Prune old backup chains if DUP_KEEP_N_FULL is set.
if [[ -n "$DUP_KEEP_N_FULL" ]]; then
    log 2 "Removing old backups, keeping last $DUP_KEEP_N_FULL full backup(s) and their incrementals..."

    if [[ -n "$GPG_KEY_ID" ]]; then
        duplicity remove-all-but-n-full "$DUP_KEEP_N_FULL" --force --encrypt-key="$GPG_KEY_ID" "$S3_URL"
        cleanup_ret=$?
    elif [[ -n "$DUP_PASS" ]]; then
        env PASSPHRASE="$DUP_PASS" duplicity remove-all-but-n-full "$DUP_KEEP_N_FULL" --force "$S3_URL"
        cleanup_ret=$?
    else
        duplicity remove-all-but-n-full "$DUP_KEEP_N_FULL" --force "$S3_URL"
        cleanup_ret=$?
    fi

    if [[ $cleanup_ret -ne 0 ]]; then
        log 1 "⚠️ Warning: Failed to remove old backups (exit code: $cleanup_ret). Backup itself succeeded."
    else
        log 2 "Old backups removed successfully."
    fi
fi

# Ping healthchecks.io to signal success.
hc_ping "" "Backup completed successfully for database '$DB_NAME' on $DATE_MORE"