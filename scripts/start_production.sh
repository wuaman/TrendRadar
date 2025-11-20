#!/bin/bash
# TrendRadar 生产环境启动脚本
# 支持nohup后台运行，进程管理和监控

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 配置变量
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PID_DIR="$PROJECT_DIR/pids"
LOG_DIR="$PROJECT_DIR/logs"
MAIN_PID_FILE="$PID_DIR/main.pid"
POLLING_PID_FILE="$PID_DIR/polling.pid"
MAIN_LOG_FILE="$LOG_DIR/main.log"
POLLING_LOG_FILE="$LOG_DIR/polling.log"

# 日志函数
log_info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS:${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

# 创建必要目录
create_dirs() {
    mkdir -p "$PID_DIR" "$LOG_DIR"
    mkdir -p "$PROJECT_DIR/output/.pagination_states"
}

# 检查配置文件
check_config() {
    log_info "检查配置文件..."
    
    if [ ! -f "$PROJECT_DIR/config/config.yaml" ]; then
        log_error "配置文件不存在: $PROJECT_DIR/config/config.yaml"
        return 1
    fi
    
    if [ ! -f "$PROJECT_DIR/config/frequency_words.txt" ]; then
        log_error "词频文件不存在: $PROJECT_DIR/config/frequency_words.txt"
        return 1
    fi
    
    log_success "配置文件检查通过"
    return 0
}

# 检查进程是否运行
is_running() {
    local pid_file="$1"
    
    if [ ! -f "$pid_file" ]; then
        return 1
    fi
    
    local pid=$(cat "$pid_file")
    if [ -z "$pid" ]; then
        return 1
    fi
    
    if kill -0 "$pid" 2>/dev/null; then
        return 0
    else
        rm -f "$pid_file"
        return 1
    fi
}

# 启动主程序
start_main() {
    log_info "启动主程序..."
    
    if is_running "$MAIN_PID_FILE"; then
        log_warning "主程序已在运行 (PID: $(cat "$MAIN_PID_FILE"))"
        return 0
    fi
    
    cd "$PROJECT_DIR"
    nohup python main.py > "$MAIN_LOG_FILE" 2>&1 &
    local pid=$!
    echo $pid > "$MAIN_PID_FILE"
    
    # 等待一下确认进程启动成功
    sleep 2
    if is_running "$MAIN_PID_FILE"; then
        log_success "主程序启动成功 (PID: $pid)"
        log_info "日志文件: $MAIN_LOG_FILE"
        return 0
    else
        log_error "主程序启动失败"
        return 1
    fi
}

# 启动polling服务
start_polling() {
    log_info "启动Telegram polling服务..."
    
    if is_running "$POLLING_PID_FILE"; then
        log_warning "Polling服务已在运行 (PID: $(cat "$POLLING_PID_FILE"))"
        return 0
    fi
    
    cd "$PROJECT_DIR"
    nohup python telegram_polling_daemon.py > "$POLLING_LOG_FILE" 2>&1 &
    local pid=$!
    echo $pid > "$POLLING_PID_FILE"
    
    # 等待一下确认进程启动成功
    sleep 2
    if is_running "$POLLING_PID_FILE"; then
        log_success "Polling服务启动成功 (PID: $pid)"
        log_info "日志文件: $POLLING_LOG_FILE"
        return 0
    else
        log_error "Polling服务启动失败"
        return 1
    fi
}

# 停止进程
stop_process() {
    local name="$1"
    local pid_file="$2"
    local timeout="${3:-30}"
    
    if ! is_running "$pid_file"; then
        log_warning "$name 未在运行"
        return 0
    fi
    
    local pid=$(cat "$pid_file")
    log_info "停止 $name (PID: $pid)..."
    
    # 发送TERM信号
    kill -TERM "$pid" 2>/dev/null || true
    
    # 等待优雅退出
    local count=0
    while [ $count -lt $timeout ]; do
        if ! kill -0 "$pid" 2>/dev/null; then
            rm -f "$pid_file"
            log_success "$name 已停止"
            return 0
        fi
        sleep 1
        count=$((count + 1))
    done
    
    # 强制杀死
    log_warning "$name 未能优雅退出，强制停止..."
    kill -KILL "$pid" 2>/dev/null || true
    rm -f "$pid_file"
    log_success "$name 已强制停止"
}

# 启动所有服务
start_all() {
    log_info "启动TrendRadar生产环境服务..."
    
    create_dirs
    
    if ! check_config; then
        exit 1
    fi
    
    # 启动主程序
    if ! start_main; then
        log_error "主程序启动失败"
        exit 1
    fi
    
    # 启动polling服务
    if ! start_polling; then
        log_error "Polling服务启动失败"
        log_info "主程序将继续运行，但分页功能不可用"
    fi
    
    log_success "所有服务启动完成"
    show_status
}

# 停止所有服务
stop_all() {
    log_info "停止TrendRadar服务..."
    
    stop_process "Polling服务" "$POLLING_PID_FILE"
    stop_process "主程序" "$MAIN_PID_FILE"
    
    log_success "所有服务已停止"
}

# 重启所有服务
restart_all() {
    log_info "重启TrendRadar服务..."
    stop_all
    sleep 2
    start_all
}

# 显示服务状态
show_status() {
    echo
    log_info "服务状态:"
    echo "----------------------------------------"
    
    # 主程序状态
    if is_running "$MAIN_PID_FILE"; then
        local main_pid=$(cat "$MAIN_PID_FILE")
        echo -e "主程序:     ${GREEN}运行中${NC} (PID: $main_pid)"
    else
        echo -e "主程序:     ${RED}未运行${NC}"
    fi
    
    # Polling服务状态
    if is_running "$POLLING_PID_FILE"; then
        local polling_pid=$(cat "$POLLING_PID_FILE")
        echo -e "Polling服务: ${GREEN}运行中${NC} (PID: $polling_pid)"
    else
        echo -e "Polling服务: ${RED}未运行${NC}"
    fi
    
    echo "----------------------------------------"
    
    # 显示分页状态文件
    local pagination_dir="$PROJECT_DIR/output/.pagination_states"
    if [ -d "$pagination_dir" ]; then
        local state_count=$(find "$pagination_dir" -name "*.json" | wc -l)
        echo "分页状态文件: $state_count 个"
    fi
    
    # 显示日志文件大小
    if [ -f "$MAIN_LOG_FILE" ]; then
        local main_size=$(du -h "$MAIN_LOG_FILE" | cut -f1)
        echo "主程序日志: $main_size ($MAIN_LOG_FILE)"
    fi
    
    if [ -f "$POLLING_LOG_FILE" ]; then
        local polling_size=$(du -h "$POLLING_LOG_FILE" | cut -f1)
        echo "Polling日志: $polling_size ($POLLING_LOG_FILE)"
    fi
    
    echo
}

# 查看日志
show_logs() {
    local service="$1"
    local lines="${2:-50}"
    
    case "$service" in
        "main")
            if [ -f "$MAIN_LOG_FILE" ]; then
                log_info "主程序日志 (最近 $lines 行):"
                tail -n "$lines" "$MAIN_LOG_FILE"
            else
                log_warning "主程序日志文件不存在"
            fi
            ;;
        "polling")
            if [ -f "$POLLING_LOG_FILE" ]; then
                log_info "Polling服务日志 (最近 $lines 行):"
                tail -n "$lines" "$POLLING_LOG_FILE"
            else
                log_warning "Polling日志文件不存在"
            fi
            ;;
        "all"|"")
            show_logs "main" "$lines"
            echo
            show_logs "polling" "$lines"
            ;;
        *)
            log_error "未知服务: $service"
            echo "可用服务: main, polling, all"
            exit 1
            ;;
    esac
}

# 跟踪日志
follow_logs() {
    local service="$1"
    
    case "$service" in
        "main")
            if [ -f "$MAIN_LOG_FILE" ]; then
                log_info "跟踪主程序日志 (按Ctrl+C退出):"
                tail -f "$MAIN_LOG_FILE"
            else
                log_warning "主程序日志文件不存在"
            fi
            ;;
        "polling")
            if [ -f "$POLLING_LOG_FILE" ]; then
                log_info "跟踪Polling服务日志 (按Ctrl+C退出):"
                tail -f "$POLLING_LOG_FILE"
            else
                log_warning "Polling日志文件不存在"
            fi
            ;;
        "all"|"")
            if [ -f "$MAIN_LOG_FILE" ] && [ -f "$POLLING_LOG_FILE" ]; then
                log_info "跟踪所有日志 (按Ctrl+C退出):"
                tail -f "$MAIN_LOG_FILE" "$POLLING_LOG_FILE"
            else
                log_warning "部分日志文件不存在"
            fi
            ;;
        *)
            log_error "未知服务: $service"
            echo "可用服务: main, polling, all"
            exit 1
            ;;
    esac
}

# 清理日志
clean_logs() {
    local days="${1:-7}"
    
    log_info "清理 $days 天前的日志文件..."
    
    # 轮转当前日志
    if [ -f "$MAIN_LOG_FILE" ]; then
        local backup_file="$MAIN_LOG_FILE.$(date +%Y%m%d_%H%M%S)"
        mv "$MAIN_LOG_FILE" "$backup_file"
        log_info "主程序日志已备份到: $backup_file"
    fi
    
    if [ -f "$POLLING_LOG_FILE" ]; then
        local backup_file="$POLLING_LOG_FILE.$(date +%Y%m%d_%H%M%S)"
        mv "$POLLING_LOG_FILE" "$backup_file"
        log_info "Polling日志已备份到: $backup_file"
    fi
    
    # 删除旧日志
    find "$LOG_DIR" -name "*.log.*" -mtime +$days -delete 2>/dev/null || true
    
    log_success "日志清理完成"
}

# 健康检查
health_check() {
    log_info "执行健康检查..."
    
    local issues=0
    
    # 检查主程序
    if ! is_running "$MAIN_PID_FILE"; then
        log_error "主程序未运行"
        issues=$((issues + 1))
    fi
    
    # 检查polling服务
    if ! is_running "$POLLING_PID_FILE"; then
        log_error "Polling服务未运行"
        issues=$((issues + 1))
    fi
    
    # 检查配置文件
    if ! check_config >/dev/null 2>&1; then
        log_error "配置文件检查失败"
        issues=$((issues + 1))
    fi
    
    # 检查分页状态目录
    if [ ! -d "$PROJECT_DIR/output/.pagination_states" ]; then
        log_error "分页状态目录不存在"
        issues=$((issues + 1))
    fi
    
    # 检查日志文件大小
    if [ -f "$MAIN_LOG_FILE" ]; then
        local size=$(stat -f%z "$MAIN_LOG_FILE" 2>/dev/null || stat -c%s "$MAIN_LOG_FILE" 2>/dev/null || echo 0)
        if [ "$size" -gt 104857600 ]; then  # 100MB
            log_warning "主程序日志文件过大 ($(du -h "$MAIN_LOG_FILE" | cut -f1))"
        fi
    fi
    
    if [ "$issues" -eq 0 ]; then
        log_success "健康检查通过"
        return 0
    else
        log_error "发现 $issues 个问题"
        return 1
    fi
}

# 显示帮助信息
show_help() {
    echo "TrendRadar 生产环境管理脚本"
    echo
    echo "用法: $0 <命令> [选项]"
    echo
    echo "命令:"
    echo "  start              启动所有服务"
    echo "  stop               停止所有服务"
    echo "  restart            重启所有服务"
    echo "  status             显示服务状态"
    echo "  logs [service]     显示日志 (service: main|polling|all)"
    echo "  follow [service]   跟踪日志 (service: main|polling|all)"
    echo "  clean [days]       清理日志 (默认7天)"
    echo "  health             健康检查"
    echo "  help               显示此帮助信息"
    echo
    echo "示例:"
    echo "  $0 start           # 启动所有服务"
    echo "  $0 logs main       # 查看主程序日志"
    echo "  $0 follow polling  # 跟踪polling日志"
    echo "  $0 clean 3         # 清理3天前的日志"
}

# 主函数
main() {
    case "${1:-start}" in
        "start")
            start_all
            ;;
        "stop")
            stop_all
            ;;
        "restart")
            restart_all
            ;;
        "status")
            show_status
            ;;
        "logs")
            show_logs "$2" "$3"
            ;;
        "follow")
            follow_logs "$2"
            ;;
        "clean")
            clean_logs "$2"
            ;;
        "health")
            health_check
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            log_error "未知命令: $1"
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"
