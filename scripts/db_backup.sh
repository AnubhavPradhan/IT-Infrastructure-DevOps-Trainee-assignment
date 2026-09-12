#!/usr/bin/env bash

# db_backup.sh
#
# Dumps the MySQL database running in the 'mysql-db' container,
# compresses it, and stores it in /var/backups/db/ as:
#  db_backup_YYYYMMDD.sql.gz
#
# Restore command (documented, not run automatically):
#  gunzip < /var/backups/db/db_backup_YYYYMMDD.sql.gz | \
#    docker exec -i mysql-db mysql -udevops -pdevopspass devopsdb
#

set -euo pipefail

DB_CONTAINER="mysql-db"

DB_NAME="devopsdb"
DB_USER="devops"
DB_PASSWORD="devopspass"   # move to a .env / docker secret for real use

BACKUP_DIR="/var/backups/db"

DATE_STAMP="$(date '+%Y%m%d')"
BACKUP_FILE="${BACKUP_DIR}/db_backup_${DATE_STAMP}.sql.gz"

mkdir -p "${BACKUP_DIR}"

echo "Dumping database '${DB_NAME}' from container '${DB_CONTAINER}'..."

docker exec "${DB_CONTAINER}" \
    mysqldump -u"${DB_USER}" -p"${DB_PASSWORD}" "${DB_NAME}" \
    | gzip > "${BACKUP_FILE}"

if [ -s "${BACKUP_FILE}" ]; then
    echo "Backup successful: ${BACKUP_FILE} ($(du -h "${BACKUP_FILE}" | cut -f1))"
else
    echo "ERROR: Backup file is empty or was not created." >&2
    exit 1
fi

# Retention: keep only the last 7 daily backups
find "${BACKUP_DIR}" -name "db_backup_*.sql.gz" -mtime +7 -delete
