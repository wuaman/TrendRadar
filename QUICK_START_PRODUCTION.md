# 🚀 TrendRadar 生产环境快速启动

## 一分钟快速部署

### Docker 部署（推荐）

```bash
# 1. 克隆项目
git clone https://github.com/your-repo/TrendRadar.git
cd TrendRadar

# 2. 配置环境变量
cd docker
cp env.example .env

# 编辑 .env 文件，设置你的 Telegram Bot Token 和 Chat ID
# TELEGRAM_BOT_TOKEN=123456789:your-bot-token
# TELEGRAM_CHAT_ID=your-chat-id

# 3. 启动服务（默认主程序+Polling并行）
docker-compose up -d

# 4. 查看运行状态
docker logs trend-radar
```

### 直接部署

```bash
# 1. 克隆项目
git clone https://github.com/your-repo/TrendRadar.git
cd TrendRadar

# 2. 安装依赖
pip install -r requirements.txt

# 3. 配置 Telegram
# 编辑 config/config.yaml，设置你的 Bot Token 和 Chat ID

# 4. 启动服务（默认主程序+Polling并行）
./start_production.sh start

# 5. 查看状态
./start_production.sh status
```

## ✨ 新功能体验

### 1. 分页消息

现在你的 Telegram 会收到这样的消息：

```
📄 第 1/3 页

🔥 TrendRadar 热点分析报告 - 当日汇总
📅 2024-01-20 09:30:15

📊 综合热度榜 TOP 10：
1. 新闻标题1 (热度: 95.2)
2. 新闻标题2 (热度: 89.7)
...

[◀️ 上一页] [1/3] [下一页 ▶️]
```

点击按钮即可翻页！

### 2. 自动运行

服务启动后会：
- ⏰ 定时抓取新闻（默认每30分钟）
- 📱 自动处理分页按钮点击
- 🔄 异常自动重启
- 📝 日志自动管理

### 3. 运行模式

| 模式 | 说明 | 使用场景 |
|------|------|----------|
| `main+polling` | 主程序+分页并行（默认） | 🌟 生产推荐 |
| `cron` | 仅定时任务 | 不需要分页 |
| `polling` | 仅分页服务 | 分离部署 |
| `once` | 单次执行 | 测试调试 |

## 🔧 常用操作

### Docker 环境

```bash
# 查看日志
docker logs trend-radar

# 进入容器
docker exec -it trend-radar bash

# 重启服务
docker restart trend-radar

# 停止服务
docker-compose down
```

### 直接部署

```bash
# 查看状态
./start_production.sh status

# 查看日志
./start_production.sh logs

# 重启服务
./start_production.sh restart

# 停止服务
./start_production.sh stop
```

## 🛠️ 配置优化

### 快速响应配置

```yaml
# config/config.yaml
notification:
  webhooks:
    telegram_pagination:
      polling_interval: 1        # 1秒轮询
      long_polling_timeout: 5    # 5秒长轮询
```

### 节省资源配置

```yaml
# config/config.yaml
notification:
  webhooks:
    telegram_pagination:
      polling_interval: 5        # 5秒轮询
      long_polling_timeout: 20   # 20秒长轮询
```

## 📊 监控运行状态

### Docker 环境

```bash
# 健康检查
docker inspect trend-radar | grep -A 10 Health

# 资源使用
docker stats trend-radar
```

### 直接部署

```bash
# 进程状态
./start_production.sh status

# 系统资源
ps aux | grep -E "(main.py|telegram_polling_daemon.py)"
```

## 🔍 故障排除

### 1. 分页按钮无响应

```bash
# 检查 Polling 服务状态
./start_production.sh logs polling

# 重启 Polling 服务
./start_production.sh restart polling
```

### 2. 消息发送失败

```bash
# 检查配置
grep -E "(TELEGRAM_BOT_TOKEN|TELEGRAM_CHAT_ID)" .env

# 检查网络连接
curl -s "https://api.telegram.org/bot<YOUR_TOKEN>/getMe"
```

### 3. 服务异常停止

```bash
# 查看错误日志
./start_production.sh logs

# 检查磁盘空间
df -h

# 重启所有服务
./start_production.sh restart
```

## 🎯 性能优化建议

### 资源配置

**最小配置：**
- CPU: 1核心
- 内存: 512MB
- 存储: 2GB

**推荐配置：**
- CPU: 2核心
- 内存: 1GB
- 存储: 5GB

### 定时任务优化

```bash
# 高频更新（每10分钟）
CRON_SCHEDULE="*/10 * * * *"

# 标准更新（每30分钟）
CRON_SCHEDULE="*/30 * * * *"

# 低频更新（每小时）
CRON_SCHEDULE="0 * * * *"
```

## 🎉 享受新功能！

现在你可以：
- ✅ 在 Telegram 中流畅翻页浏览热点新闻
- ✅ 无需多条消息刷屏
- ✅ 服务自动运行，无需手动干预
- ✅ 完整的错误恢复和监控

有问题？查看详细文档：
- 📖 [生产部署指南](PRODUCTION_DEPLOYMENT.md)
- 🔧 [Polling 模式说明](TELEGRAM_POLLING.md)
- 📱 [分页功能指南](TELEGRAM_PAGINATION.md)
