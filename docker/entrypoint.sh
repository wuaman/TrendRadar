#!/bin/bash
set -e

# 检查配置文件
if [ ! -f "/app/config/config.yaml" ] || [ ! -f "/app/config/frequency_words.txt" ]; then
    echo "❌ 配置文件缺失"
    exit 1
fi

# 保存环境变量
env >> /etc/environment

# Polling相关变量
ENABLE_POLLING=${ENABLE_POLLING:-true}
POLLING_RESTART_DELAY=${POLLING_RESTART_DELAY:-5}
POLLING_LOG_FILE="/app/output/polling.log"

# PID文件路径
POLLING_PID_FILE="/tmp/polling.pid"
MAIN_PID_FILE="/tmp/main.pid"

# 创建输出目录
mkdir -p /app/output

# 信号处理函数
cleanup() {
    echo "🛑 收到停止信号，正在清理进程..."
    
    # 停止polling进程
    if [ -f "$POLLING_PID_FILE" ]; then
        POLLING_PID=$(cat "$POLLING_PID_FILE")
        if kill -0 "$POLLING_PID" 2>/dev/null; then
            echo "📱 停止Telegram polling服务 (PID: $POLLING_PID)"
            kill -TERM "$POLLING_PID" 2>/dev/null || true
            # 等待进程优雅退出
            for i in {1..10}; do
                if ! kill -0 "$POLLING_PID" 2>/dev/null; then
                    break
                fi
                sleep 1
            done
            # 如果还没退出，强制杀死
            kill -KILL "$POLLING_PID" 2>/dev/null || true
        fi
        rm -f "$POLLING_PID_FILE"
    fi
    
    # 停止主进程
    if [ -f "$MAIN_PID_FILE" ]; then
        MAIN_PID=$(cat "$MAIN_PID_FILE")
        if kill -0 "$MAIN_PID" 2>/dev/null; then
            echo "🏠 停止主程序服务 (PID: $MAIN_PID)"
            kill -TERM "$MAIN_PID" 2>/dev/null || true
            wait "$MAIN_PID" 2>/dev/null || true
        fi
        rm -f "$MAIN_PID_FILE"
    fi
    
    echo "✅ 清理完成"
    exit 0
}

# 启动polling服务函数
start_polling() {
    if [ "$ENABLE_POLLING" != "true" ]; then
        echo "📱 Polling服务已禁用"
        return
    fi
    
    echo "🚀 启动Telegram polling服务..."
    
    # 后台启动polling服务，重定向输出到日志文件
    nohup /usr/local/bin/python telegram_polling_daemon.py > "$POLLING_LOG_FILE" 2>&1 &
    POLLING_PID=$!
    echo $POLLING_PID > "$POLLING_PID_FILE"
    
    echo "📱 Telegram polling服务已启动 (PID: $POLLING_PID)"
    echo "📝 日志文件: $POLLING_LOG_FILE"
}

# 监控polling进程函数
monitor_polling() {
    while true; do
        sleep 30  # 每30秒检查一次
        
        if [ "$ENABLE_POLLING" != "true" ]; then
            continue
        fi
        
        if [ -f "$POLLING_PID_FILE" ]; then
            POLLING_PID=$(cat "$POLLING_PID_FILE")
            if ! kill -0 "$POLLING_PID" 2>/dev/null; then
                echo "⚠️ Polling进程异常退出，准备重启..."
                rm -f "$POLLING_PID_FILE"
                sleep "$POLLING_RESTART_DELAY"
                start_polling
            fi
        else
            echo "⚠️ Polling PID文件丢失，重新启动polling服务..."
            start_polling
        fi
    done
}

# 设置信号处理
trap cleanup SIGTERM SIGINT SIGQUIT

case "${RUN_MODE:-main+polling}" in
"once")
    echo "🔄 单次执行模式"
    exec /usr/local/bin/python main.py
    ;;
"polling")
    echo "📱 仅Polling服务模式"
    start_polling
    
    # 等待polling进程
    if [ -f "$POLLING_PID_FILE" ]; then
        POLLING_PID=$(cat "$POLLING_PID_FILE")
        wait "$POLLING_PID"
    fi
    ;;
"cron")
    echo "📅 传统Cron模式（不启用polling）"
    # 生成 crontab
    echo "${CRON_SCHEDULE:-*/30 * * * *} cd /app && /usr/local/bin/python main.py" > /tmp/crontab
    
    echo "📅 生成的crontab内容:"
    cat /tmp/crontab

    if ! /usr/local/bin/supercronic -test /tmp/crontab; then
        echo "❌ crontab格式验证失败"
        exit 1
    fi

    # 立即执行一次（如果配置了）
    if [ "${IMMEDIATE_RUN:-false}" = "true" ]; then
        echo "▶️ 立即执行一次"
        /usr/local/bin/python main.py
    fi

    echo "⏰ 启动supercronic: ${CRON_SCHEDULE:-*/30 * * * *}"
    exec /usr/local/bin/supercronic -passthrough-logs /tmp/crontab
    ;;
"main+polling")
    echo "🚀 主程序+Polling并行模式（默认）"
    
    # 启动polling服务
    start_polling
    
    # 启动监控进程（后台）
    monitor_polling &
    MONITOR_PID=$!
    
    # 生成 crontab
    echo "${CRON_SCHEDULE:-*/30 * * * *} cd /app && /usr/local/bin/python main.py" > /tmp/crontab
    
    echo "📅 生成的crontab内容:"
    cat /tmp/crontab

    if ! /usr/local/bin/supercronic -test /tmp/crontab; then
        echo "❌ crontab格式验证失败"
        exit 1
    fi

    # 立即执行一次（如果配置了）
    if [ "${IMMEDIATE_RUN:-true}" = "true" ]; then
        echo "▶️ 立即执行一次"
        /usr/local/bin/python main.py
    fi

    echo "⏰ 启动supercronic: ${CRON_SCHEDULE:-*/30 * * * *}"
    echo "📱 Polling服务并行运行中"
    echo "🎯 supercronic 将作为主进程运行"
    
    # 启动主程序（supercronic作为前台进程）
    /usr/local/bin/supercronic -passthrough-logs /tmp/crontab &
    MAIN_PID=$!
    echo $MAIN_PID > "$MAIN_PID_FILE"
    
    # 等待主进程
    wait "$MAIN_PID"
    ;;
*)
    exec "$@"
    ;;
esac