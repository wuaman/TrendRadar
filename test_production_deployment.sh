#!/bin/bash
# TrendRadar 生产部署测试脚本

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 测试函数
test_docker_deployment() {
    log_info "=== 测试Docker部署 ==="
    
    # 检查Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker未安装"
        return 1
    fi
    
    # 检查docker-compose
    if ! command -v docker-compose &> /dev/null; then
        log_warn "docker-compose未安装，尝试使用docker compose"
        if ! docker compose version &> /dev/null; then
            log_error "docker-compose和docker compose都不可用"
            return 1
        fi
        COMPOSE_CMD="docker compose"
    else
        COMPOSE_CMD="docker-compose"
    fi
    
    # 检查配置文件
    if [ ! -f "docker/docker-compose.yml" ]; then
        log_error "Docker compose文件不存在"
        return 1
    fi
    
    # 检查环境变量示例
    if [ ! -f "docker/env.example" ]; then
        log_error "环境变量示例文件不存在"
        return 1
    fi
    
    log_info "Docker环境检查通过"
    
    # 测试compose文件语法
    cd docker
    if $COMPOSE_CMD config &> /dev/null; then
        log_info "Docker compose配置语法正确"
    else
        log_error "Docker compose配置语法错误"
        return 1
    fi
    cd ..
    
    return 0
}

test_direct_deployment() {
    log_info "=== 测试直接部署 ==="
    
    # 检查Python
    if command -v python3 &> /dev/null; then
        PYTHON_CMD="python3"
    elif command -v python &> /dev/null; then
        PYTHON_CMD="python"
    else
        log_error "Python未安装"
        return 1
    fi
    
    # 检查Python版本
    PYTHON_VERSION=$($PYTHON_CMD --version 2>&1 | cut -d' ' -f2 | cut -d'.' -f1-2)
    log_info "Python版本: $PYTHON_VERSION"
    
    # 检查必要文件
    required_files=(
        "main.py"
        "telegram_polling_daemon.py"
        "start_production.sh"
        "config/config.yaml"
        "requirements.txt"
    )
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            log_error "必要文件不存在: $file"
            return 1
        fi
    done
    
    # 检查启动脚本权限
    if [ ! -x "start_production.sh" ]; then
        log_warn "启动脚本没有执行权限，正在修复..."
        chmod +x start_production.sh
    fi
    
    # 测试启动脚本语法
    if bash -n start_production.sh; then
        log_info "启动脚本语法正确"
    else
        log_error "启动脚本语法错误"
        return 1
    fi
    
    # 测试Python导入
    if $PYTHON_CMD -c "import sys; sys.path.append('.'); import main" 2>/dev/null; then
        log_info "主程序导入测试通过"
    else
        log_warn "主程序导入测试失败（可能缺少依赖）"
    fi
    
    return 0
}

test_configuration() {
    log_info "=== 测试配置文件 ==="
    
    # 检查config.yaml
    if [ -f "config/config.yaml" ]; then
        # 简单的YAML语法检查（如果有yaml模块）
        if python3 -c "import yaml" 2>/dev/null; then
            if python3 -c "import yaml; yaml.safe_load(open('config/config.yaml'))" 2>/dev/null; then
                log_info "config.yaml语法正确"
            else
                log_error "config.yaml语法错误"
                return 1
            fi
        else
            log_warn "缺少yaml模块，跳过语法检查"
            log_info "config.yaml文件存在"
        fi
        
        # 检查关键配置项
        if grep -q "telegram_pagination" config/config.yaml; then
            log_info "包含Telegram分页配置"
        else
            log_warn "缺少Telegram分页配置"
        fi
        
        if grep -q "use_polling" config/config.yaml; then
            log_info "包含Polling配置"
        else
            log_warn "缺少Polling配置"
        fi
    else
        log_error "config/config.yaml不存在"
        return 1
    fi
    
    # 检查频率词文件
    if [ -f "config/frequency_words.txt" ]; then
        log_info "frequency_words.txt存在"
    else
        log_error "config/frequency_words.txt不存在"
        return 1
    fi
    
    return 0
}

test_polling_functionality() {
    log_info "=== 测试Polling功能 ==="
    
    # 测试polling daemon脚本语法
    if python3 -m py_compile telegram_polling_daemon.py 2>/dev/null; then
        log_info "Polling daemon脚本语法正确"
    else
        log_error "Polling daemon脚本语法错误"
        return 1
    fi
    
    # 测试polling daemon帮助信息
    if python3 telegram_polling_daemon.py --help > /dev/null 2>&1; then
        log_info "Polling daemon帮助功能正常"
    else
        log_warn "Polling daemon帮助功能异常"
    fi
    
    # 检查分页状态目录创建
    if mkdir -p output/.pagination_states 2>/dev/null; then
        log_info "分页状态目录创建成功"
        rmdir output/.pagination_states 2>/dev/null || true
    else
        log_error "无法创建分页状态目录"
        return 1
    fi
    
    return 0
}

test_docker_entrypoint() {
    log_info "=== 测试Docker Entrypoint ==="
    
    if [ ! -f "docker/entrypoint.sh" ]; then
        log_error "Docker entrypoint脚本不存在"
        return 1
    fi
    
    # 检查脚本语法
    if bash -n docker/entrypoint.sh; then
        log_info "Docker entrypoint脚本语法正确"
    else
        log_error "Docker entrypoint脚本语法错误"
        return 1
    fi
    
    # 检查是否包含polling相关代码
    if grep -q "start_polling" docker/entrypoint.sh; then
        log_info "Entrypoint包含Polling启动逻辑"
    else
        log_error "Entrypoint缺少Polling启动逻辑"
        return 1
    fi
    
    # 检查运行模式支持
    if grep -q "main+polling" docker/entrypoint.sh; then
        log_info "Entrypoint支持main+polling模式"
    else
        log_error "Entrypoint缺少main+polling模式支持"
        return 1
    fi
    
    return 0
}

run_comprehensive_test() {
    log_info "开始TrendRadar生产部署测试"
    echo "=================================================="
    
    local tests=(
        "test_configuration"
        "test_polling_functionality"
        "test_docker_entrypoint"
        "test_docker_deployment"
        "test_direct_deployment"
    )
    
    local passed=0
    local total=${#tests[@]}
    
    for test_func in "${tests[@]}"; do
        echo
        if $test_func; then
            ((passed++))
        fi
    done
    
    echo
    echo "=================================================="
    log_info "测试结果: $passed/$total 通过"
    
    if [ $passed -eq $total ]; then
        log_info "🎉 所有测试通过！生产部署准备就绪。"
        echo
        log_info "📋 部署选项:"
        echo "  1. Docker部署: cd docker && docker-compose up -d"
        echo "  2. 直接部署: ./start_production.sh start"
        echo
        log_info "📚 查看文档:"
        echo "  - PRODUCTION_DEPLOYMENT.md - 生产部署指南"
        echo "  - TELEGRAM_POLLING.md - Polling模式说明"
        echo "  - TELEGRAM_PAGINATION_QUICKSTART.md - 快速上手"
        return 0
    else
        log_error "⚠️  部分测试失败，请检查相关配置。"
        return 1
    fi
}

# 显示帮助
show_help() {
    cat << EOF
TrendRadar 生产部署测试脚本

用法: $0 [选项]

选项:
  --docker      仅测试Docker部署
  --direct      仅测试直接部署
  --config      仅测试配置文件
  --polling     仅测试Polling功能
  --entrypoint  仅测试Docker entrypoint
  --help        显示此帮助

不带参数运行将执行所有测试。

EOF
}

# 主函数
main() {
    case "${1:-all}" in
        "--docker")
            test_docker_deployment
            ;;
        "--direct")
            test_direct_deployment
            ;;
        "--config")
            test_configuration
            ;;
        "--polling")
            test_polling_functionality
            ;;
        "--entrypoint")
            test_docker_entrypoint
            ;;
        "--help")
            show_help
            ;;
        "all"|*)
            run_comprehensive_test
            ;;
    esac
}

# 运行主函数
main "$@"
