#!/bin/bash
# TrendRadar 生产环境启动脚本
# 支持主程序和Telegram polling服务的后台运行

set -e

# 脚本配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="TrendRadar"
MAIN_PID_FILE="/tmp/trendradar_main.pid"
POLLING_PID_FILE="/tmp/trendradar_polling.pid"
LOG_DIR="$SCRIPT_DIR/logs"
MAIN_LOG_FILE="$LOG_DIR/main.log"
POLLING_LOG_FILE="$LOG_DIR/polling.log"

# 默认配置
ENABLE_MAIN=${ENABLE_MAIN:-true}
ENABLE_POLLING=${ENABLE_POLLING:-true}
POLLING_RESTART_DELAY=${POLLING_RESTART_DELAY:-5}
LOG_MAX_SIZE=${LOG_MAX_SIZE:-100M}
LOG_MAX_FILES=${LOG_MAX_FILES:-5}

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_debug() {
    if [ "$DEBUG" = "true" ]; then
        echo -e "${BLUE}[DEBUG]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"
    fi
}

# 创建必要目录
create_directories() {
    log_info "创建必要目录..."
    mkdir -p "$LOG_DIR"
    mkdir -p "output/.pagination_states"
    mkdir -p "output/.push_records"
}

# 检查依赖
check_dependencies() {
    log_info "检查运行环境..."
    
    # 检查Python
    if ! command -v python3 &> /dev/null && ! command -v python &> /dev/null; then
        log_error "Python未找到，请安装Python 3"
        exit 1
    fi
    
    # 检查配置文件
    if [ ! -f "config/config.yaml" ]; then
        log_error "配置文件不存在: config/config.yaml"
        exit 1
    fi
    
    if [ ! -f "config/frequency_words.txt" ]; then
        log_error "配置文件不存在: config/frequency_words.txt"
        exit 1
    fi
    
    # 检查主程序文件
    if [ ! -f "main.py" ]; then
        log_error "主程序文件不存在: main.py"
        exit 1
    fi
    
    if [ ! -f "telegram_polling_daemon.py" ]; then
        log_error "Polling程序文件不存在: telegram_polling_daemon.py"
        exit 1
    fi
    
    log_info "环境检查通过"
}

# 检查进程是否运行
is_process_running() {
    local pid_file="$1"
    
    if [ ! -f "$pid_file" ]; then
        return 1
    fi
    
    local pid
    pid=$(cat "$pid_file" 2>/dev/null)
    
    if [ -z "$pid" ]; then
        return 1
    fi
    
    if kill -0 "$pid" 2>/dev/null; then
        return 0
    else
        # PID文件存在但进程不存在，清理PID文件
        rm -f "$pid_file"
        return 1
    fi
}

# 日志轮转
rotate_log() {
    local log_file="$1"
    
    if [ ! -f "$log_file" ]; then
        return
    fi
    
    # 检查日志文件大小
    local size
    size=$(stat -f%z "$log_file" 2>/dev/null || stat -c%s "$log_file" 2>/dev/null || echo 0)
    local max_size_bytes=$((100 * 1024 * 1024))  # 100MB
    
    if [ "$size" -gt "$max_size_bytes" ]; then
        log_info "轮转日志文件: $log_file"
        
        # 保留最近几个日志文件
        for i in $(seq $((LOG_MAX_FILES - 1)) -1 1); do
            if [ -f "${log_file}.$i" ]; then
                mv "${log_file}.$i" "${log_file}.$((i + 1))"
            fi
        done
        
        mv "$log_file" "${log_file}.1"
        touch "$log_file"
    fi
}

# 启动主程序
start_main() {
    if [ "$ENABLE_MAIN" != "true" ]; then
        log_info "主程序已禁用"
        return
    fi
    
    if is_process_running "$MAIN_PID_FILE"; then
        log_warn "主程序已在运行中"
        return
    fi
    
    log_info "启动主程序..."
    rotate_log "$MAIN_LOG_FILE"
    
    # 使用nohup启动主程序
    nohup python main.py > "$MAIN_LOG_FILE" 2>&1 &
    local main_pid=$!
    echo $main_pid > "$MAIN_PID_FILE"
    
    # 等待一小段时间检查进程是否成功启动
    sleep 2
    if is_process_running "$MAIN_PID_FILE"; then
        log_info "主程序启动成功 (PID: $main_pid)"
        log_info "日志文件: $MAIN_LOG_FILE"
    else
        log_error "主程序启动失败"
        rm -f "$MAIN_PID_FILE"
        return 1
    fi
}

# 启动Polling服务
start_polling() {
    if [ "$ENABLE_POLLING" != "true" ]; then
        log_info "Polling服务已禁用"
        return
    fi
    
    if is_process_running "$POLLING_PID_FILE"; then
        log_warn "Polling服务已在运行中"
        return
    fi
    
    log_info "启动Telegram Polling服务..."
    rotate_log "$POLLING_LOG_FILE"
    
    # 使用nohup启动polling服务
    nohup python telegram_polling_daemon.py > "$POLLING_LOG_FILE" 2>&1 &
    local polling_pid=$!
    echo $polling_pid > "$POLLING_PID_FILE"
    
    # 等待一小段时间检查进程是否成功启动
    sleep 2
    if is_process_running "$POLLING_PID_FILE"; then
        log_info "Polling服务启动成功 (PID: $polling_pid)"
        log_info "日志文件: $POLLING_LOG_FILE"
    else
        log_error "Polling服务启动失败"
        rm -f "$POLLING_PID_FILE"
        return 1
    fi
}

# 停止进程
stop_process() {
    local pid_file="$1"
    local process_name="$2"
    
    if ! is_process_running "$pid_file"; then
        log_info "$process_name 未在运行"
        return
    fi
    
    local pid
    pid=$(cat "$pid_file")
    
    log_info "停止 $process_name (PID: $pid)..."
    
    # 发送TERM信号
    kill -TERM "$pid" 2>/dev/null || true
    
    # 等待进程优雅退出
    local count=0
    while [ $count -lt 10 ] && kill -0 "$pid" 2>/dev/null; do
        sleep 1
        count=$((count + 1))
    done
    
    # 如果进程还在运行，强制杀死
    if kill -0 "$pid" 2>/dev/null; then
        log_warn "强制停止 $process_name"
        kill -KILL "$pid" 2>/dev/null || true
        sleep 1
    fi
    
    rm -f "$pid_file"
    log_info "$process_name 已停止"
}

# 显示状态
show_status() {
    echo
    log_info "=== $PROJECT_NAME 运行状态 ==="
    
    # 主程序状态
    if is_process_running "$MAIN_PID_FILE"; then
        local main_pid
        main_pid=$(cat "$MAIN_PID_FILE")
        echo -e "  主程序: ${GREEN}运行中${NC} (PID: $main_pid)"
    else
        echo -e "  主程序: ${RED}未运行${NC}"
    fi
    
    # Polling服务状态
    if is_process_running "$POLLING_PID_FILE"; then
        local polling_pid
        polling_pid=$(cat "$POLLING_PID_FILE")
        echo -e "  Polling: ${GREEN}运行中${NC} (PID: $polling_pid)"
    else
        echo -e "  Polling: ${RED}未运行${NC}"
    fi
    
    # 日志文件状态
    echo
    echo "  日志文件:"
    if [ -f "$MAIN_LOG_FILE" ]; then
        local main_size
        main_size=$(stat -f%z "$MAIN_LOG_FILE" 2>/dev/null || stat -c%s "$MAIN_LOG_FILE" 2>/dev/null || echo 0)
        echo "    主程序: $MAIN_LOG_FILE ($(numfmt --to=iec $main_size 2>/dev/null || echo "${main_size} bytes"))"
    fi
    
    if [ -f "$POLLING_LOG_FILE" ]; then
        local polling_size
        polling_size=$(stat -f%z "$POLLING_LOG_FILE" 2>/dev/null || stat -c%s "$POLLING_LOG_FILE" 2>/dev/null || echo 0)
        echo "    Polling: $POLLING_LOG_FILE ($(numfmt --to=iec $polling_size 2>/dev/null || echo "${polling_size} bytes"))"
    fi
    
    echo
}

# 显示日志
show_logs() {
    local service="$1"
    local lines="${2:-50}"
    
    case "$service" in
        "main")
            if [ -f "$MAIN_LOG_FILE" ]; then
                echo "=== 主程序日志 (最后 $lines 行) ==="
                tail -n "$lines" "$MAIN_LOG_FILE"
            else
                log_warn "主程序日志文件不存在"
            fi
            ;;
        "polling")
            if [ -f "$POLLING_LOG_FILE" ]; then
                echo "=== Polling服务日志 (最后 $lines 行) ==="
                tail -n "$lines" "$POLLING_LOG_FILE"
            else
                log_warn "Polling日志文件不存在"
            fi
            ;;
        "all"|*)
            show_logs "main" "$lines"
            echo
            show_logs "polling" "$lines"
            ;;
    esac
}

# 重启服务
restart_service() {
    local service="$1"
    
    case "$service" in
        "main")
            stop_process "$MAIN_PID_FILE" "主程序"
            sleep 2
            start_main
            ;;
        "polling")
            stop_process "$POLLING_PID_FILE" "Polling服务"
            sleep 2
            start_polling
            ;;
        "all"|*)
            log_info "重启所有服务..."
            stop_process "$POLLING_PID_FILE" "Polling服务"
            stop_process "$MAIN_PID_FILE" "主程序"
            sleep 3
            start_main
            start_polling
            ;;
    esac
}

# 显示帮助
show_help() {
    cat << EOF
$PROJECT_NAME 生产环境管理脚本

用法: $0 [命令] [选项]

命令:
  start     - 启动服务（默认）
  stop      - 停止所有服务
  restart   - 重启服务
  status    - 显示运行状态
  logs      - 显示日志
  help      - 显示此帮助

选项:
  --main-only     - 仅操作主程序
  --polling-only  - 仅操作Polling服务
  --lines N       - 显示日志时的行数 (默认50)

环境变量:
  ENABLE_MAIN=true/false        - 是否启用主程序 (默认: true)
  ENABLE_POLLING=true/false     - 是否启用Polling (默认: true)
  POLLING_RESTART_DELAY=N       - Polling重启延迟秒数 (默认: 5)
  DEBUG=true/false              - 是否启用调试输出 (默认: false)

使用示例:
  $0 start                      - 启动所有服务
  $0 stop                       - 停止所有服务
  $0 restart --polling-only     - 仅重启Polling服务
  $0 logs main                  - 查看主程序日志
  $0 status                     - 查看运行状态
  
  # 使用环境变量
  ENABLE_MAIN=false $0 start    - 仅启动Polling服务
  DEBUG=true $0 start           - 启动时显示调试信息

日志文件位置:
  主程序: $MAIN_LOG_FILE
  Polling: $POLLING_LOG_FILE

EOF
}

# 信号处理
cleanup() {
    echo
    log_info "收到中断信号，正在停止服务..."
    stop_process "$POLLING_PID_FILE" "Polling服务"
    stop_process "$MAIN_PID_FILE" "主程序"
    exit 0
}

# 主函数
main() {
    # 切换到脚本目录
    cd "$SCRIPT_DIR"
    
    # 解析参数
    local command="start"
    local service="all"
    local lines=50
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            start|stop|restart|status|logs|help)
                command="$1"
                shift
                ;;
            --main-only)
                service="main"
                shift
                ;;
            --polling-only)
                service="polling"
                shift
                ;;
            --lines)
                lines="$2"
                shift 2
                ;;
            main|polling|all)
                if [ "$command" = "logs" ] || [ "$command" = "restart" ]; then
                    service="$1"
                fi
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 设置信号处理
    trap cleanup SIGTERM SIGINT SIGQUIT
    
    # 执行命令
    case "$command" in
        "start")
            log_info "启动 $PROJECT_NAME 生产环境服务..."
            create_directories
            check_dependencies
            
            case "$service" in
                "main")
                    start_main
                    ;;
                "polling")
                    start_polling
                    ;;
                "all")
                    start_main
                    start_polling
                    ;;
            esac
            
            show_status
            log_info "服务启动完成"
            ;;
            
        "stop")
            log_info "停止 $PROJECT_NAME 服务..."
            case "$service" in
                "main")
                    stop_process "$MAIN_PID_FILE" "主程序"
                    ;;
                "polling")
                    stop_process "$POLLING_PID_FILE" "Polling服务"
                    ;;
                "all")
                    stop_process "$POLLING_PID_FILE" "Polling服务"
                    stop_process "$MAIN_PID_FILE" "主程序"
                    ;;
            esac
            log_info "服务停止完成"
            ;;
            
        "restart")
            restart_service "$service"
            show_status
            ;;
            
        "status")
            show_status
            ;;
            
        "logs")
            show_logs "$service" "$lines"
            ;;
            
        "help")
            show_help
            ;;
            
        *)
            log_error "未知命令: $command"
            show_help
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"
