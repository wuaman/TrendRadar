#!/bin/bash
# TrendRadar systemd服务安装脚本

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否以root权限运行
if [[ $EUID -ne 0 ]]; then
   log_error "此脚本需要root权限运行"
   echo "请使用: sudo $0"
   exit 1
fi

# 配置变量
INSTALL_DIR="/opt/trendradar"
SERVICE_USER="trendradar"
SERVICE_GROUP="trendradar"
SYSTEMD_DIR="/etc/systemd/system"

# 函数：创建用户和组
create_user() {
    log_info "创建系统用户和组..."
    
    if ! getent group "$SERVICE_GROUP" > /dev/null 2>&1; then
        groupadd --system "$SERVICE_GROUP"
        log_success "创建组: $SERVICE_GROUP"
    else
        log_warning "组已存在: $SERVICE_GROUP"
    fi
    
    if ! getent passwd "$SERVICE_USER" > /dev/null 2>&1; then
        useradd --system --gid "$SERVICE_GROUP" --home-dir "$INSTALL_DIR" \
                --shell /bin/false --comment "TrendRadar Service" "$SERVICE_USER"
        log_success "创建用户: $SERVICE_USER"
    else
        log_warning "用户已存在: $SERVICE_USER"
    fi
}

# 函数：安装应用
install_app() {
    log_info "安装应用到 $INSTALL_DIR..."
    
    # 创建安装目录
    mkdir -p "$INSTALL_DIR"
    
    # 复制应用文件
    cp -r . "$INSTALL_DIR/"
    
    # 创建Python虚拟环境
    if [ ! -d "$INSTALL_DIR/venv" ]; then
        log_info "创建Python虚拟环境..."
        python3 -m venv "$INSTALL_DIR/venv"
        source "$INSTALL_DIR/venv/bin/activate"
        pip install --upgrade pip
        pip install -r "$INSTALL_DIR/requirements.txt"
        deactivate
        log_success "Python虚拟环境创建完成"
    fi
    
    # 创建必要目录
    mkdir -p "$INSTALL_DIR/output"
    mkdir -p "$INSTALL_DIR/output/.pagination_states"
    mkdir -p "$INSTALL_DIR/logs"
    
    # 设置权限
    chown -R "$SERVICE_USER:$SERVICE_GROUP" "$INSTALL_DIR"
    chmod +x "$INSTALL_DIR/main.py"
    chmod +x "$INSTALL_DIR/telegram_polling_daemon.py"
    
    log_success "应用安装完成"
}

# 函数：安装systemd服务
install_services() {
    log_info "安装systemd服务..."
    
    # 复制服务文件
    cp systemd/trendradar-main.service "$SYSTEMD_DIR/"
    cp systemd/trendradar-polling.service "$SYSTEMD_DIR/"
    
    # 设置权限
    chmod 644 "$SYSTEMD_DIR/trendradar-main.service"
    chmod 644 "$SYSTEMD_DIR/trendradar-polling.service"
    
    # 重新加载systemd配置
    systemctl daemon-reload
    
    log_success "systemd服务安装完成"
}

# 函数：配置服务
configure_services() {
    log_info "配置服务..."
    
    # 启用服务
    systemctl enable trendradar-main.service
    systemctl enable trendradar-polling.service
    
    log_success "服务已启用"
}

# 函数：检查配置
check_config() {
    log_info "检查配置文件..."
    
    if [ ! -f "$INSTALL_DIR/config/config.yaml" ]; then
        log_warning "配置文件不存在: $INSTALL_DIR/config/config.yaml"
        log_info "请复制并编辑配置文件:"
        echo "  cp $INSTALL_DIR/config/config.yaml.example $INSTALL_DIR/config/config.yaml"
        return 1
    fi
    
    if [ ! -f "$INSTALL_DIR/config/frequency_words.txt" ]; then
        log_warning "词频文件不存在: $INSTALL_DIR/config/frequency_words.txt"
        return 1
    fi
    
    log_success "配置文件检查通过"
    return 0
}

# 函数：显示状态
show_status() {
    echo
    log_info "服务状态:"
    systemctl status trendradar-main.service --no-pager -l || true
    echo
    systemctl status trendradar-polling.service --no-pager -l || true
}

# 函数：显示帮助信息
show_help() {
    echo "TrendRadar systemd服务管理"
    echo
    echo "用法: $0 [选项]"
    echo
    echo "选项:"
    echo "  install    安装服务"
    echo "  uninstall  卸载服务"
    echo "  start      启动服务"
    echo "  stop       停止服务"
    echo "  restart    重启服务"
    echo "  status     查看服务状态"
    echo "  logs       查看日志"
    echo "  help       显示此帮助信息"
}

# 主函数
main() {
    case "${1:-install}" in
        "install")
            log_info "开始安装TrendRadar systemd服务..."
            create_user
            install_app
            install_services
            configure_services
            
            if check_config; then
                log_success "安装完成！"
                echo
                log_info "下一步操作:"
                echo "  1. 编辑配置文件: $INSTALL_DIR/config/config.yaml"
                echo "  2. 启动服务: sudo systemctl start trendradar-main"
                echo "  3. 查看状态: sudo systemctl status trendradar-main"
                echo "  4. 查看日志: sudo journalctl -u trendradar-main -f"
            else
                log_warning "安装完成，但需要配置文件"
            fi
            ;;
        "uninstall")
            log_info "卸载TrendRadar systemd服务..."
            systemctl stop trendradar-main.service trendradar-polling.service 2>/dev/null || true
            systemctl disable trendradar-main.service trendradar-polling.service 2>/dev/null || true
            rm -f "$SYSTEMD_DIR/trendradar-main.service"
            rm -f "$SYSTEMD_DIR/trendradar-polling.service"
            systemctl daemon-reload
            log_success "服务已卸载"
            log_warning "用户数据保留在: $INSTALL_DIR"
            ;;
        "start")
            log_info "启动服务..."
            systemctl start trendradar-main.service
            log_success "服务已启动"
            show_status
            ;;
        "stop")
            log_info "停止服务..."
            systemctl stop trendradar-main.service trendradar-polling.service
            log_success "服务已停止"
            ;;
        "restart")
            log_info "重启服务..."
            systemctl restart trendradar-main.service
            log_success "服务已重启"
            show_status
            ;;
        "status")
            show_status
            ;;
        "logs")
            log_info "查看服务日志 (按Ctrl+C退出):"
            journalctl -u trendradar-main.service -u trendradar-polling.service -f
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            log_error "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"
