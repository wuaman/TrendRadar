# TrendRadar 生产环境部署指南

## 🚀 快速开始

TrendRadar现在支持主程序+Telegram Polling并行运行，提供多种生产环境部署方案。

### 方案一：Docker部署（推荐）

Docker方案是最简单、最稳定的部署方式。

#### 1.1 使用预构建镜像

```bash
# 下载项目
git clone https://github.com/your-repo/TrendRadar.git
cd TrendRadar

# 配置环境变量
cp docker/env.example .env
# 编辑 .env 文件，设置你的配置

# 启动服务
cd docker
docker-compose up -d
```

#### 1.2 构建自定义镜像

```bash
# 使用构建版本的compose文件
cd docker
docker-compose -f docker-compose-build.yml up -d --build
```

#### 1.3 环境变量配置

在 `.env` 文件中配置关键参数：

```bash
# 运行模式（推荐使用 main+polling）
RUN_MODE=main+polling

# Telegram配置
TELEGRAM_BOT_TOKEN=123456789:your-bot-token
TELEGRAM_CHAT_ID=your-chat-id

# 启用Polling
ENABLE_POLLING=true

# 定时任务配置
CRON_SCHEDULE=*/30 * * * *
```

#### 1.4 运行模式说明

| 模式 | 说明 | 适用场景 |
|------|------|----------|
| `main+polling` | 主程序+Polling并行（默认） | 生产环境推荐 |
| `cron` | 仅定时任务，不启用Polling | 不需要分页功能 |
| `polling` | 仅Polling服务 | 分离部署 |
| `once` | 单次执行 | 测试用途 |

### 方案二：直接部署

适合VPS或物理服务器部署。

#### 2.1 使用生产启动脚本

```bash
# 克隆项目
git clone https://github.com/your-repo/TrendRadar.git
cd TrendRadar

# 安装依赖
pip install -r requirements.txt

# 配置文件
cp config/config.yaml.example config/config.yaml
# 编辑配置文件

# 启动服务
./start_production.sh start
```

#### 2.2 脚本使用方法

```bash
# 基本操作
./start_production.sh start      # 启动所有服务
./start_production.sh stop       # 停止所有服务
./start_production.sh restart    # 重启所有服务
./start_production.sh status     # 查看状态

# 单独操作
./start_production.sh start --main-only     # 仅启动主程序
./start_production.sh start --polling-only  # 仅启动Polling
./start_production.sh restart polling       # 重启Polling服务

# 查看日志
./start_production.sh logs                  # 查看所有日志
./start_production.sh logs main             # 查看主程序日志
./start_production.sh logs polling --lines 100  # 查看Polling日志最后100行

# 环境变量控制
ENABLE_MAIN=false ./start_production.sh start    # 仅启动Polling
DEBUG=true ./start_production.sh start           # 启用调试模式
```

## 📋 生产环境配置

### 基本配置

在 `config/config.yaml` 中配置：

```yaml
notification:
  webhooks:
    telegram_bot_token: "YOUR_BOT_TOKEN"
    telegram_chat_id: "YOUR_CHAT_ID"
    
    telegram_pagination:
      enabled: true
      use_polling: true
      polling_interval: 2
      long_polling_timeout: 10
      session_ttl_hours: 1
```

### 高级配置

#### 性能优化配置

```yaml
# 快速响应（消耗更多API调用）
telegram_pagination:
  polling_interval: 1
  long_polling_timeout: 5

# 节省资源（响应稍慢）
telegram_pagination:
  polling_interval: 3
  long_polling_timeout: 20
```

#### 代理配置

```yaml
crawler:
  use_proxy: true
  default_proxy: "http://127.0.0.1:10086"
```

## 🔧 监控和维护

### 服务监控

#### Docker环境

```bash
# 查看容器状态
docker ps
docker logs trend-radar

# 进入容器
docker exec -it trend-radar bash

# 容器内状态检查
python manage.py status

# 健康检查
docker inspect trend-radar | grep Health
```

#### 直接部署环境

```bash
# 查看服务状态
./start_production.sh status

# 查看进程
ps aux | grep -E "(main.py|telegram_polling_daemon.py)"

# 查看日志文件大小
ls -lh logs/
```

### 日志管理

#### 日志文件位置

**Docker环境：**
- 主程序日志: Docker logs
- Polling日志: `/app/output/polling.log`

**直接部署：**
- 主程序日志: `logs/main.log`
- Polling日志: `logs/polling.log`

#### 日志轮转

生产脚本自动处理日志轮转：
- 单个日志文件超过100MB自动轮转
- 保留最近5个历史日志文件
- 可通过环境变量调整：`LOG_MAX_SIZE=200M LOG_MAX_FILES=10`

### 故障排除

#### 常见问题

1. **Polling服务无响应**
   ```bash
   # Docker环境
   docker exec -it trend-radar python manage.py status
   
   # 直接部署
   ./start_production.sh status
   ./start_production.sh restart polling
   ```

2. **分页按钮点击无效**
   ```bash
   # 检查Polling日志
   ./start_production.sh logs polling
   
   # 检查分页状态文件
   ls -la output/.pagination_states/
   ```

3. **内存使用过高**
   ```bash
   # 重启服务
   ./start_production.sh restart
   
   # 检查日志文件大小
   du -sh logs/
   ```

#### 调试模式

```bash
# 启用调试输出
DEBUG=true ./start_production.sh start

# 查看详细日志
./start_production.sh logs --lines 200
```

## 🛡️ 安全建议

### 配置安全

1. **保护敏感信息**
   ```bash
   # 设置配置文件权限
   chmod 600 config/config.yaml
   chmod 600 .env
   ```

2. **使用环境变量**
   ```bash
   # 避免在配置文件中硬编码Token
   export TELEGRAM_BOT_TOKEN="your-token"
   export TELEGRAM_CHAT_ID="your-chat-id"
   ```

### 网络安全

1. **防火墙配置**
   - 只开放必要端口
   - 使用代理时确保代理安全性

2. **API安全**
   - 定期轮换Bot Token
   - 监控API调用频率

## 📊 性能优化

### 资源使用

**推荐配置：**
- CPU: 1核心
- 内存: 512MB
- 存储: 5GB

**高负载配置：**
- CPU: 2核心
- 内存: 1GB
- 存储: 10GB

### 优化建议

1. **轮询间隔优化**
   ```yaml
   # 平衡性能和资源消耗
   telegram_pagination:
     polling_interval: 2
     long_polling_timeout: 10
   ```

2. **日志管理**
   ```bash
   # 定期清理旧日志
   find logs/ -name "*.log.*" -mtime +30 -delete
   ```

3. **分页状态清理**
   ```bash
   # 清理过期分页状态（自动处理）
   # 可调整过期时间
   telegram_pagination:
     session_ttl_hours: 2
   ```

## 🔄 升级和迁移

### 升级步骤

1. **备份数据**
   ```bash
   # 备份配置和输出文件
   tar -czf backup-$(date +%Y%m%d).tar.gz config/ output/
   ```

2. **更新代码**
   ```bash
   git pull origin main
   ```

3. **重启服务**
   ```bash
   # Docker环境
   docker-compose down && docker-compose up -d
   
   # 直接部署
   ./start_production.sh restart
   ```

### 数据迁移

分页状态文件会自动迁移，无需手动操作。

## 🆘 故障恢复

### 紧急恢复步骤

1. **服务完全停止**
   ```bash
   # 强制停止所有相关进程
   pkill -f "main.py"
   pkill -f "telegram_polling_daemon.py"
   
   # 清理PID文件
   rm -f /tmp/trendradar_*.pid
   
   # 重新启动
   ./start_production.sh start
   ```

2. **数据损坏恢复**
   ```bash
   # 清理损坏的分页状态
   rm -rf output/.pagination_states/*
   
   # 重新生成配置
   python main.py  # 会自动创建必要目录
   ```

### 备份策略

```bash
#!/bin/bash
# 每日备份脚本
BACKUP_DIR="/backup/trendradar"
DATE=$(date +%Y%m%d)

mkdir -p "$BACKUP_DIR"
tar -czf "$BACKUP_DIR/trendradar-$DATE.tar.gz" \
    config/ \
    output/ \
    logs/ \
    --exclude="output/.pagination_states" \
    --exclude="logs/*.log.*"

# 保留最近7天的备份
find "$BACKUP_DIR" -name "trendradar-*.tar.gz" -mtime +7 -delete
```

## 📞 技术支持

### 获取帮助

1. **查看文档**
   - `TELEGRAM_POLLING.md` - Polling模式详细说明
   - `TELEGRAM_PAGINATION_QUICKSTART.md` - 快速上手指南

2. **调试信息收集**
   ```bash
   # 收集系统信息
   ./start_production.sh status > debug_info.txt
   ./start_production.sh logs >> debug_info.txt
   
   # Docker环境
   docker logs trend-radar > docker_debug.txt
   docker exec -it trend-radar python manage.py status >> docker_debug.txt
   ```

3. **常用检查命令**
   ```bash
   # 检查配置文件
   python -c "import yaml; print(yaml.safe_load(open('config/config.yaml')))"
   
   # 测试API连接
   python telegram_polling_daemon.py --help
   
   # 检查依赖
   pip list | grep -E "(requests|pyyaml)"
   ```

---

🎉 现在你已经拥有了一个完整的、生产级的TrendRadar部署方案！无论是Docker还是直接部署，都能让你的Telegram分页功能稳定运行。
