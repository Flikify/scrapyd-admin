#!/bin/bash

cleanup() {
    echo "开始清理进程..."
    pkill -P $$ || true
    pkill -f scrapyd || true、
    pkill -f waitress-serve || true
    rm -f /var/run/*.pid
    echo "清理完成"
}

trap cleanup EXIT

# 检查端口
check_port() {
    local port="$1"
    if lsof -i :$port > /dev/null 2>&1; then
        echo "端口 $port 已被占用，尝试清理..."
        fuser -k $port/tcp || true
        sleep 1
    fi
}

# 检查服务就绪
wait_for_service() {
    local host="$1"
    local port="$2"
    local service="$3"
    local max_attempts=30
    local attempt=1
    
    echo "等待 $service 就绪..."
    while ! nc -z "$host" "$port"; do
        if [ $attempt -ge $max_attempts ]; then
            echo "$service 在 $((max_attempts * 2)) 秒后仍未就绪"
            exit 1
        fi
        echo "尝试 $attempt: $service 未就绪. 等待中..."
        sleep 2
        attempt=$((attempt + 1))
    done
    echo "$service 已就绪!"
}


mkdir /app/scrapyd/project

# 检查并清理端口
check_port 6800
check_port 5000


# 配置用户名和密码
if [ ! -z "$SCRAPYD_USERNAME" ] && [ ! -z "$SCRAPYD_PASSWORD" ]; then
    sed -i "s/^username =.*/username = $SCRAPYD_USERNAME/" /app/config/scrapyd.conf
    sed -i "s/^password =.*/password = $SCRAPYD_PASSWORD/" /app/config/scrapyd.conf

    sed -i "s/^USERNAME =.*/USERNAME = $SCRAPYD_USERNAME/" /app/config/config.yml
    sed -i "s/^PASSWORD =.*/PASSWORD = $SCRAPYD_PASSWORD/" /app/config/config.yml
	sed -i "s/^SCRAPYD_USERNAME =.*/SCRAPYD_USERNAME = $SCRAPYD_USERNAME/" /app/config/config.yml
    sed -i "s/^SCRAPYD_PASSWORD =.*/SCRAPYD_PASSWORD = $SCRAPYD_PASSWORD/" /app/config/config.yml
fi

echo "启动服务..."

# 启动 Scrapyd
cd /app/config
scrapyd &
SCRAPYD_PID=$!

# 等待 Scrapyd 启动
wait_for_service "127.0.0.1" "6800" "Scrapyd"

# 启动 ScrapyWeb
gunicorn -b=0.0.0.0:5000 'spider_admin_pro:app' &
SpiderAdminPro_PID=$!

echo "所有服务已启动"
echo "Scrapyd PID: $SCRAPYD_PID"
echo "SpiderAdminPro_PID PID: $SCRAPYWEB_PID"

# 等待任意子进程退出
wait -n

# 如果任意进程退出，清理并退出
exit 1