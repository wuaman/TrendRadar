# Docker Polling部署指南

## 概述

TrendRadar现在支持在Docker容器中自动运行Telegram polling服务，实现主程序和分页按钮处理的并行运行。

## 运行模式

### 1. main+polling（默认，推荐）
主程序定时任务 + Telegram polling服务并行运行
```bash
docker-compose up -d
```

### 2. cron（传统模式）
仅运行定时任务，不启用polling
```bash
RUN_MODE=cron docker-compose up -d
```

### 3. polling（仅polling）
仅运行Telegram polling服务
```bash
RUN_MODE=polling docker-compose up -d
```

### 4. once（单次执行）
执行一次分析后退出
```bash
RUN_MODE=once docker-compose up
```

## 环境变量配置

### 核心配置
```bash
# 运行模式（默认：main+polling）
RUN_MODE=main+polling

# 是否启用polling（默认：true）
ENABLE_POLLING=true

# Polling进程重启延迟（秒，默认：5）
POLLING_RESTART_DELAY=5

# Cron调度表达式（默认：每30分钟）
CRON_SCHEDULE="*/30 * * * *"

# 是否立即执行一次（默认：true）
IMMEDIATE_RUN=true
```

### Telegram配置
```bash
# 必需配置
TELEGRAM_BOT_TOKEN=your_bot_token
TELEGRAM_CHAT_ID=your_chat_id
```

## 快速开始

### 1. 准备配置文件
```bash
# 确保配置文件存在
ls config/config.yaml
ls config/frequency_words.txt
```

### 2. 设置环境变量
```bash
# 方式一：使用.env文件
cp docker/.env.example docker/.env
# 编辑 docker/.env 文件

# 方式二：直接设置环境变量
export TELEGRAM_BOT_TOKEN="your_bot_token"
export TELEGRAM_CHAT_ID="your_chat_id"
```

### 3. 启动服务
```bash
# 使用预构建镜像
docker-compose up -d

# 或使用本地构建
docker-compose -f docker/docker-compose-build.yml up -d
```

### 4. 查看日志
```bash
# 查看所有日志
docker logs trend-radar

# 实时跟踪日志
docker logs -f trend-radar

# 查看polling专用日志
docker exec trend-radar tail -f /app/output/polling.log
```

## 日志管理

### 日志文件位置
- 主程序日志：通过Docker logs查看
- Polling日志：`/app/output/polling.log`
- 分页状态：`/app/output/.pagination_states/`

### 日志查看命令
```bash
# 查看最近100行日志
docker logs --tail 100 trend-radar

# 查看polling服务日志
docker exec trend-radar tail -100 /app/output/polling.log

# 查看分页状态文件
docker exec trend-radar ls -la /app/output/.pagination_states/
```

## 健康检查

### 检查服务状态
```bash
# 检查容器状态
docker ps | grep trend-radar

# 检查进程状态
docker exec trend-radar ps aux

# 检查polling进程
docker exec trend-radar ps aux | grep polling
```

### 检查分页功能
```bash
# 检查配置
docker exec trend-radar cat /app/config/config.yaml | grep -A 10 telegram_pagination

# 检查分页状态目录
docker exec trend-radar ls -la /app/output/.pagination_states/

# 测试polling连接
docker exec trend-radar python -c "
from main import create_polling_service
service = create_polling_service()
if service:
    print('✅ Polling服务创建成功')
    updates = service.get_updates(timeout=1)
    print(f'📱 API连接测试: {len(updates)} 条更新')
else:
    print('❌ Polling服务创建失败')
"
```

## 故障排除

### 常见问题

1. **Polling服务无法启动**
   ```bash
   # 检查Bot Token配置
   docker exec trend-radar env | grep TELEGRAM_BOT_TOKEN
   
   # 检查网络连接
   docker exec trend-radar curl -s https://api.telegram.org/bot<TOKEN>/getMe
   ```

2. **分页按钮无响应**
   ```bash
   # 检查polling进程
   docker exec trend-radar ps aux | grep polling
   
   # 检查polling日志
   docker exec trend-radar tail -50 /app/output/polling.log
   ```

3. **容器重启后polling不工作**
   ```bash
   # 检查分页状态是否持久化
   docker exec trend-radar ls -la /app/output/.pagination_states/
   
   # 重启容器
   docker restart trend-radar
   ```

### 调试模式

启用详细日志输出：
```bash
# 临时启用调试模式
docker exec -it trend-radar python telegram_polling_daemon.py --verbose

# 或修改环境变量后重启
POLLING_LOG_LEVEL=debug docker-compose up -d
```

## 生产环境建议

### 1. 资源配置
```yaml
# docker-compose.yml 中添加资源限制
services:
  trend-radar:
    # ... 其他配置
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: '0.5'
        reservations:
          memory: 256M
          cpus: '0.25'
```

### 2. 日志管理
```yaml
# 配置日志轮转
services:
  trend-radar:
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
```

### 3. 健康检查
```yaml
# 添加健康检查
services:
  trend-radar:
    healthcheck:
      test: ["CMD", "python", "-c", "import requests; requests.get('https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe', timeout=5)"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
```

### 4. 备份策略
```bash
# 定期备份输出目录
docker run --rm -v trend-radar_output:/data -v $(pwd)/backup:/backup alpine tar czf /backup/trend-radar-$(date +%Y%m%d).tar.gz /data
```

## 升级指南

### 升级到新版本
```bash
# 1. 停止服务
docker-compose down

# 2. 拉取新镜像
docker-compose pull

# 3. 启动服务
docker-compose up -d

# 4. 检查状态
docker logs trend-radar
```

### 回滚操作
```bash
# 回滚到之前版本
docker-compose down
docker tag wantcat/trendradar:previous wantcat/trendradar:latest
docker-compose up -d
```

## 监控和告警

### Prometheus监控（可选）
```yaml
# 添加监控端点
services:
  trend-radar:
    ports:
      - "8080:8080"  # 监控端点
```

### 简单监控脚本
```bash
#!/bin/bash
# monitor.sh - 简单的监控脚本

CONTAINER_NAME="trend-radar"

# 检查容器状态
if ! docker ps | grep -q $CONTAINER_NAME; then
    echo "❌ 容器未运行"
    # 发送告警通知
    exit 1
fi

# 检查polling进程
if ! docker exec $CONTAINER_NAME ps aux | grep -q "polling_daemon"; then
    echo "⚠️ Polling进程未运行"
    # 尝试重启容器
    docker restart $CONTAINER_NAME
fi

echo "✅ 服务运行正常"
```

这样，用户就可以通过简单的Docker命令启动包含polling功能的完整服务了！
