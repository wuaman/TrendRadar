# Telegram分页功能说明

## 功能概述

新的Telegram分页功能将原有的"分批发送多条消息"改进为"单条消息内分页显示"，用户可以通过点击按钮在同一条消息内翻页查看内容。

## 主要特性

### ✨ 用户体验优化
- **单条消息展示**：所有内容在一条消息内分页显示，避免消息刷屏
- **直观的分页按钮**：`◀️ 1/5 ▶️` 格式，清晰显示当前页码和总页数
- **即时翻页**：点击按钮即时更新内容，无需等待新消息

### 🔧 技术特性
- **状态持久化**：分页状态保存到本地文件，支持服务重启后继续使用
- **自动清理**：过期的分页状态自动清理，避免存储空间浪费
- **向下兼容**：可通过配置关闭分页功能，回退到原有模式
- **错误处理**：完善的异常处理和用户提示

## 配置说明

在 `config/config.yaml` 中添加以下配置：

```yaml
notification:
  # Telegram 分页功能配置
  telegram_pagination:
    enabled: true # 是否启用分页功能，false 时使用传统的分批发送
    session_ttl_hours: 1 # 分页会话过期时间（小时）
    max_pages: 20 # 最大分页数量限制
```

### 配置项说明

- `enabled`: 控制是否启用分页功能
  - `true`: 启用分页显示（推荐）
  - `false`: 使用原有的分批发送模式
  
- `session_ttl_hours`: 分页会话的有效期
  - 超过此时间后，按钮将失效并提示用户重新获取数据
  - 建议设置为 1-24 小时
  
- `max_pages`: 最大分页数量限制
  - 防止内容过多导致分页过多
  - 超过限制时会在最后一页显示剩余内容

## 使用方式

### 1. 基本使用
启用分页功能后，正常运行程序即可：

```bash
python main.py
```

当Telegram消息内容较多时，会自动分页显示：
- 第一页会立即发送到Telegram
- 用户点击"下一页 ▶️"查看后续内容
- 点击"◀️ 上一页"返回之前的内容

### 2. 按钮说明
- **◀️ 上一页**: 翻到前一页（第一页时不显示）
- **1/5**: 显示当前页码和总页数（点击显示详细信息）
- **下一页 ▶️**: 翻到下一页（最后一页时不显示）

### 3. 状态管理
分页状态自动保存在 `output/.pagination_states/` 目录：
- 每个消息对应一个状态文件
- 文件命名格式：`pagination_state_{chat_id}_{message_id}.json`
- 过期状态会自动清理

## 高级功能（可选）

### Webhook回调处理

如果需要处理分页按钮的点击事件，可以设置Telegram Webhook：

```python
from main import setup_telegram_webhook, handle_telegram_callback

# 设置webhook
bot_token = "your_bot_token"
webhook_url = "https://your-server.com/telegram_webhook"
setup_telegram_webhook(bot_token, webhook_url)

# 在webhook端点处理回调
def webhook_handler(callback_query):
    return handle_telegram_callback(bot_token, callback_query)
```

详细示例请参考 `telegram_pagination_example.py` 文件。

## 故障排除

### 常见问题

1. **按钮点击无响应**
   - 检查是否设置了Webhook（单向推送模式不需要）
   - 确认网络连接正常

2. **提示"分页会话已过期"**
   - 分页状态超过设置的TTL时间
   - 重新运行程序获取最新数据

3. **分页功能未生效**
   - 检查 `config.yaml` 中的 `enabled` 配置
   - 确认消息内容确实需要分页（内容较少时不会分页）

### 日志信息

程序运行时会输出相关日志：
```
Telegram消息分为 3 页显示 [当日汇总]
Telegram分页消息发送成功，消息ID: 123 [当日汇总]
分页状态已保存: 123456789_123, 3页
```

### 文件结构

```
output/
├── .pagination_states/          # 分页状态存储目录
│   ├── pagination_state_123_456.json
│   └── ...
└── .push_records/              # 推送记录目录（原有）
    ├── push_record_20231201.json
    └── ...
```

## 技术实现

### 核心组件

1. **TelegramPaginationManager**: 分页状态管理器
2. **InlineKeyboard**: Telegram内联键盘按钮
3. **Callback处理**: 按钮点击事件处理
4. **消息编辑**: editMessageText API调用

### 数据流程

```
发送消息 → 生成分页 → 保存状态 → 用户点击按钮 → 处理回调 → 更新消息 → 更新状态
```

### API调用

- `sendMessage`: 发送初始分页消息
- `editMessageText`: 更新消息内容和按钮
- `answerCallbackQuery`: 回应按钮点击事件

## 版本兼容性

- ✅ 完全向下兼容：可随时关闭分页功能
- ✅ 配置兼容：新增配置项，不影响现有配置
- ✅ 数据兼容：分页状态独立存储，不影响原有数据

## 性能优化

- 分页状态使用JSON文件存储，读写高效
- 自动清理过期状态，避免存储空间浪费
- 按需加载分页内容，减少内存占用
- 合理的TTL设置，平衡用户体验和系统资源
