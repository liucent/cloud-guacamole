#!/bin/bash
set -e

PGDATA="/var/lib/postgresql/data"

# 1. 确保目录与权限正确
mkdir -p "$PGDATA" /run/postgresql
chown -R postgres:postgres /var/lib/postgresql /run/postgresql
chmod 0700 "$PGDATA" || true

# 2. 数据库首次启动自动初始化
if [ ! -d "$PGDATA/base" ]; then
    echo "[Init] Initializing ultra-light PostgreSQL for single-user..."
    su-exec postgres initdb -D "$PGDATA" --auth=trust
fi

# 3. 每次启动强制重写 postgresql.conf
cat << 'EOF' > "$PGDATA/postgresql.conf"
listen_addresses = '127.0.0.1'
shared_buffers = 8MB
work_mem = 640kB
maintenance_work_mem = 4MB
autovacuum = off
max_connections = 5
max_worker_processes = 1
max_parallel_workers = 0
fsync = off
synchronous_commit = off
full_page_writes = off
wal_level = minimal
max_wal_senders = 0
max_replication_slots = 0
max_wal_size = 32MB
logging_collector = off
EOF

# 4. 启动临时 PostgreSQL 进行初始化
su-exec postgres pg_ctl -D "$PGDATA" -w start

# 检查 guacamole 数据库是否存在，不存在才进行建表和导数据
if ! su-exec postgres psql -U postgres -lqt | cut -d \| -f 1 | grep -qw guacamole; then
    echo "[Init] Creating guacamole database..."
    su-exec postgres psql -U postgres -d postgres -c "CREATE DATABASE guacamole;"
    
    echo "[Init] Importing 001-create-schema.sql..."
    su-exec postgres psql -U postgres -d guacamole -v ON_ERROR_STOP=1 -f /opt/guacamole/schema/001-create-schema.sql

    echo "[Init] Importing 002-create-admin-user.sql..."
    su-exec postgres psql -U postgres -d guacamole -v ON_ERROR_STOP=1 -f /opt/guacamole/schema/002-create-admin-user.sql
fi

# 【关键修复】使用 -m fast 确保内存数据彻底落盘刷写回文件！
echo "[Init] Flushing data to disk and stopping temporary PostgreSQL..."
su-exec postgres pg_ctl -D "$PGDATA" -m fast stop

echo "[Init] PostgreSQL setup completed successfully!"

# 5. 纯 IPv4 极限 JVM 参数
export CATALINA_OPTS="\
  -Xms32m \
  -Xmx64m \
  -XX:MaxMetaspaceSize=64m \
  -XX:+UseSerialGC \
  -XX:MinHeapFreeRatio=10 \
  -XX:MaxHeapFreeRatio=20 \
  -Djava.net.preferIPv4Stack=true"

# 6. 启动 Supervisor
echo "[Start] Starting Supervisor..."
exec /usr/bin/supervisord -c /etc/supervisord.conf
