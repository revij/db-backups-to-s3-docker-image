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

# Duplicity password is recommended.
if [[ -z "$DUP_PASS" ]]; then
    log 1 "⚠️ Warning: 'DUP_PASS' env variable not set. This means your duplicity backup is not password-protected!"
fi

if [[ -z "$DUP_FORCE_INC" ]]; then
    log 1 "⚠️ Warning: 'DUP_FORCE_INC' env variable not set. Using '0' (false)..."

    DUP_FORCE_INC=0
fi

if [[ -z "$DUP_FORCE_FULL" ]]; then
    log 1 "⚠️ Warning: 'DUP_FORCE_FULL' env variable not set. Using '0' (false)..."

    DUP_FORCE_FULL=0
fi

# Print verbose information.
log 1 "Starting backup on '$DATE_MORE'..."

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

log 2

log 2 "Duplicity Settings"
log 2 "\tForce Incremental: $DUP_FORCE_INC"
log 2 "\tForce Full: $DUP_FORCE_FULL"
log 4 "\tFile Password: $DUP_PASS"

# Determine file extension.
FILE_EXT="sql"

# Dump database.
DUMP_FILE_NAME="${DB_NAME}.${FILE_EXT}"
FULL_DUMP_PATH="/tmp/${DUMP_FILE_NAME}"

log 2 "Backing up database to temporary file '$FULL_DUMP_PATH'..."

if [[ "$DB_TYPE" == "mysql" ]]; then
    mysqldump --no-tablespaces -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" > "$FULL_DUMP_PATH"

    ret=$?
elif [[ "$DB_TYPE" == "postgresql" ]]; then
    pg_dump -h "$DB_HOST" -p $DB_PORT -U "$DB_USER" -d "$DB_NAME" > $FULL_DUMP_PATH

    ret=$?
else
    echo "❌ Error: 'DB_TYPE' env variable set to incorrect value (only accepts 'mysql' or 'postgresql' as values)."

    exit 1
fi

# Check output of dump command.
if [[ $ret -ne 0 ]]; then
    echo "❌ Error: Failed to dump database for '$DB_TYPE'."
    echo "Error code: $ret"

    exit 1
fi

# Upload to S3.
log 2 "Uploading database backup to S3 storage..."

# Compile part of the duplicity command.
DUP_CMD_ARGS=("backup")

if [[ "$DUP_FORCE_FULL" -ge 1 ]]; then
    DUP_CMD_ARGS+=("full")
elif [[ "$DUP_FORCE_INC" -ge 1 ]]; then
    DUP_CMD_ARGS+=("incremental")
fi

# We need to export some things for duplicity.
export AWS_ACCESS_KEY_ID="$S3_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$S3_APP_KEY"
export AWS_ENDPOINT_URL="https://${S3_ENDPOINT}"

# Compile full S3 URL.
S3_URL="s3://${S3_BUCKET}/${S3_BUCKET_DIR}"

env PASSPHRASE="$DUP_PASS" duplicity "${DUP_CMD_ARGS[@]}" --allow-source-mismatch "$FULL_DUMP_PATH" "$S3_URL"

# Remove local backup.
if [[ "$DEL_LOCAL" -ge 1 ]]; then
    log 3 "Removing local backup file '$FULL_DUMP_PATH'..."
    rm -f "$FULL_DUMP_PATH"
fi

log 1 "✅ Backup completed!"