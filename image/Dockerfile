ARG IMG_NAME=debian
ARG IMG_TAG=latest

FROM ${IMG_NAME}:${IMG_TAG}

RUN apt update

# Update and install system dependencies
RUN apt update && apt install -y \
    cron \
    curl \
    gpg \
    python3 \
    python3-pip \
    librsync-dev \
    gettext \
    default-mysql-client postgresql-client \
 && apt clean \
 && rm -rf /var/lib/apt/lists/*

# Install Python packages
RUN pip3 install --break-system-packages duplicity b2sdk fasteners

# Copy cron job.
COPY --chmod=0644 ./conf/cron.conf /etc/cron.d/backup

# Run crontab.
RUN crontab /etc/cron.d/backup

# Copy backup script.
COPY --chmod=0700 ./scripts/backup.sh /opt

# Create backup logs directory.
RUN mkdir -p /var/log/backups

CMD ["/bin/bash", "-c", "printenv > /etc/environment && cron -f"]