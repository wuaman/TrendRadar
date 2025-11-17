#!/usr/bin/env python3
# coding=utf-8
"""
Telegram分页功能使用示例

本脚本演示如何使用新的Telegram分页功能。

使用方式：
1. 配置config.yaml中的telegram相关设置
2. 运行主程序，Telegram消息将自动使用分页显示
3. 如需处理按钮回调，可参考本文件中的webhook处理示例

注意：
- 分页功能默认启用，可通过config.yaml中的telegram_pagination.enabled控制
- 回调处理需要设置Telegram Webhook（可选）
- 分页状态会自动保存到output/.pagination_states/目录
"""

import json
from typing import Dict, Optional
from main import (
    handle_telegram_callback, 
    setup_telegram_webhook,
    TelegramPaginationManager
)

# 示例：处理Telegram Webhook回调的简单HTTP服务器
def create_simple_webhook_handler():
    """
    创建一个简单的webhook处理器示例
    
    在实际部署时，你需要：
    1. 设置一个公网可访问的HTTPS服务器
    2. 调用setup_telegram_webhook设置webhook URL
    3. 在webhook端点处理POST请求并调用handle_telegram_callback
    """
    
    # Flask示例（需要安装flask: pip install flask）
    try:
        from flask import Flask, request, jsonify
        
        app = Flask(__name__)
        
        @app.route('/telegram_webhook', methods=['POST'])
        def telegram_webhook():
            """处理Telegram webhook回调"""
            try:
                data = request.get_json()
                
                # 检查是否是callback_query
                if 'callback_query' in data:
                    callback_query = data['callback_query']
                    
                    # 从配置中获取bot_token和proxy_url
                    from main import CONFIG
                    bot_token = CONFIG.get("TELEGRAM_BOT_TOKEN", "")
                    proxy_url = CONFIG.get("PROXY_URL") if CONFIG.get("USE_PROXY") else None
                    
                    # 处理回调
                    success = handle_telegram_callback(bot_token, callback_query, proxy_url)
                    
                    if success:
                        return jsonify({"ok": True})
                    else:
                        return jsonify({"ok": False, "error": "处理回调失败"})
                
                return jsonify({"ok": True})
                
            except Exception as e:
                print(f"Webhook处理出错: {e}")
                return jsonify({"ok": False, "error": str(e)})
        
        return app
        
    except ImportError:
        print("Flask未安装，无法创建webhook服务器示例")
        return None


def test_pagination_manager():
    """测试分页管理器功能"""
    print("=== 测试分页管理器 ===")
    
    # 创建分页管理器
    manager = TelegramPaginationManager()
    
    # 模拟分页数据
    test_pages = [
        "第1页内容：这是测试数据...",
        "第2页内容：这是更多测试数据...", 
        "第3页内容：这是最后一页..."
    ]
    
    chat_id = "123456789"
    message_id = "987654321"
    
    # 保存分页状态
    manager.save_pagination_state(
        chat_id, message_id, test_pages, 0, "测试报告"
    )
    
    # 读取分页状态
    state = manager.get_pagination_state(chat_id, message_id)
    if state:
        print(f"分页状态读取成功: {state['total_pages']}页")
        
        # 更新页码
        success = manager.update_current_page(chat_id, message_id, 1)
        print(f"页码更新: {'成功' if success else '失败'}")
        
        # 再次读取验证
        updated_state = manager.get_pagination_state(chat_id, message_id)
        if updated_state:
            print(f"当前页码: {updated_state['current_page'] + 1}/{updated_state['total_pages']}")
    
    # 清理测试数据
    manager.delete_pagination_state(chat_id, message_id)
    print("测试完成，已清理测试数据")


def show_usage_guide():
    """显示使用指南"""
    print("""
=== Telegram分页功能使用指南 ===

1. 配置启用分页功能：
   在 config/config.yaml 中设置：
   ```yaml
   notification:
     telegram_pagination:
       enabled: true
       session_ttl_hours: 1
       max_pages: 20
   ```

2. 正常使用：
   - 运行主程序时，如果Telegram消息内容较多会自动分页
   - 用户在Telegram中点击"◀️ 上一页"/"下一页 ▶️"按钮翻页
   - 分页状态会自动保存，支持1小时内的翻页操作

3. 高级功能（可选）：
   - 设置Webhook服务器处理按钮回调
   - 自定义分页会话过期时间
   - 限制最大分页数量

4. 注意事项：
   - 分页功能需要用户主动点击按钮，无法自动翻页
   - 分页状态文件存储在 output/.pagination_states/ 目录
   - 如果禁用分页功能，将回退到原有的分批发送模式

5. 故障排除：
   - 如果按钮无响应，检查是否设置了正确的Webhook
   - 如果提示"会话已过期"，说明分页状态超时，需重新获取数据
   - 查看日志文件了解详细错误信息
""")


if __name__ == "__main__":
    print("Telegram分页功能示例")
    print("=====================")
    
    # 显示使用指南
    show_usage_guide()
    
    # 测试分页管理器
    test_pagination_manager()
    
    # 创建webhook处理器示例（仅作演示）
    webhook_app = create_simple_webhook_handler()
    if webhook_app:
        print("\n=== Webhook服务器示例 ===")
        print("Flask应用已创建，可通过以下方式启动：")
        print("python telegram_pagination_example.py")
        print("然后访问 http://localhost:5000/telegram_webhook")
        print("\n注意：实际部署需要HTTPS和公网访问")
