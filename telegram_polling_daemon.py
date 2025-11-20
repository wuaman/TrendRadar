#!/usr/bin/env python3
# coding=utf-8
"""
Telegram Polling 守护进程

独立运行的Telegram轮询服务，用于处理分页按钮点击事件。
无需webhook，适合个人部署和本地开发。

使用方式:
    python telegram_polling_daemon.py                    # 使用配置文件中的设置
    python telegram_polling_daemon.py --token YOUR_TOKEN # 指定Bot Token
    python telegram_polling_daemon.py --help            # 查看帮助

特性:
- 支持长轮询，减少API调用次数
- 自动重连和错误恢复
- 优雅的停止机制（Ctrl+C）
- 详细的日志输出
- 配置文件支持
"""

import argparse
import signal
import sys
import time
import threading
from pathlib import Path

# 添加主目录到Python路径
sys.path.insert(0, str(Path(__file__).parent))

from main import create_polling_service, CONFIG

class PollingDaemon:
    """Polling守护进程管理器"""
    
    def __init__(self, bot_token: str = None, proxy_url: str = None):
        self.bot_token = bot_token
        self.proxy_url = proxy_url
        self.polling_service = None
        self.is_running = False
        self.stats = {
            "start_time": None,
            "total_updates": 0,
            "total_callbacks": 0,
            "errors": 0
        }
    
    def setup_signal_handlers(self):
        """设置信号处理器"""
        def signal_handler(signum, frame):
            print(f"\n收到信号 {signum}，正在优雅停止...")
            self.stop()
        
        signal.signal(signal.SIGINT, signal_handler)
        signal.signal(signal.SIGTERM, signal_handler)
    
    def start(self):
        """启动守护进程"""
        self.setup_signal_handlers()
        
        # 创建轮询服务
        self.polling_service = create_polling_service(self.bot_token, self.proxy_url)
        if not self.polling_service:
            print("❌ 无法创建轮询服务，请检查配置")
            return False
        
        # 从配置中读取轮询设置
        polling_config = CONFIG.get("webhooks", {}).get("telegram_polling", {})
        interval = polling_config.get("polling_interval", 2)
        timeout = polling_config.get("long_polling_timeout", 10)
        
        self.polling_service.set_polling_config(interval, timeout)
        
        self.is_running = True
        self.stats["start_time"] = time.time()
        
        print("🚀 Telegram Polling 守护进程启动")
        print(f"📋 配置信息:")
        print(f"   Bot Token: {self.bot_token[:10] if self.bot_token else 'from config'}...")
        print(f"   代理设置: {self.proxy_url or '无'}")
        print(f"   轮询间隔: {interval}秒")
        print(f"   长轮询超时: {timeout}秒")
        print(f"📝 日志:")
        
        try:
            # 启动轮询
            self.polling_service.start_polling()
            return True
        except Exception as e:
            print(f"❌ 守护进程启动失败: {e}")
            return False
    
    def stop(self):
        """停止守护进程"""
        if self.polling_service and self.is_running:
            self.polling_service.stop_polling()
            self.is_running = False
            self.print_stats()
    
    def print_stats(self):
        """打印运行统计"""
        if self.stats["start_time"]:
            runtime = time.time() - self.stats["start_time"]
            print(f"\n📊 运行统计:")
            print(f"   运行时长: {runtime:.1f}秒")
            print(f"   处理更新: {self.stats['total_updates']}个")
            print(f"   处理回调: {self.stats['total_callbacks']}个")
            print(f"   错误次数: {self.stats['errors']}次")


def parse_arguments():
    """解析命令行参数"""
    parser = argparse.ArgumentParser(
        description="Telegram Polling 守护进程",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
使用示例:
  python telegram_polling_daemon.py
  python telegram_polling_daemon.py --token 123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11
  python telegram_polling_daemon.py --proxy http://127.0.0.1:10086
  python telegram_polling_daemon.py --token YOUR_TOKEN --proxy YOUR_PROXY

注意:
- 如果不指定token，将从config.yaml中读取
- 分页状态文件存储在 output/.pagination_states/ 目录
- 按 Ctrl+C 可以优雅停止服务
        """
    )
    
    parser.add_argument(
        "--token", "-t",
        help="Telegram Bot Token（可选，默认从配置文件读取）"
    )
    
    parser.add_argument(
        "--proxy", "-p",
        help="代理服务器地址（可选，格式: http://host:port）"
    )
    
    parser.add_argument(
        "--config", "-c",
        help="配置文件路径（可选，默认: config/config.yaml）"
    )
    
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="详细日志输出"
    )
    
    return parser.parse_args()


def check_dependencies():
    """检查依赖"""
    try:
        import requests
        import yaml
        return True
    except ImportError as e:
        print(f"❌ 缺少依赖: {e}")
        print("请安装依赖: pip install requests pyyaml")
        return False


def check_config():
    """检查配置"""
    try:
        # 检查是否启用了分页功能
        pagination_config = CONFIG.get("webhooks", {}).get("telegram_pagination", {})
        if not pagination_config.get("enabled", True):
            print("⚠️  警告: 分页功能未启用，polling服务可能无法正常工作")
            print("   请在config.yaml中设置 telegram_pagination.enabled: true")
        
        # 检查Bot Token
        bot_token = CONFIG.get("TELEGRAM_BOT_TOKEN", "")
        if not bot_token:
            print("⚠️  警告: 配置中未找到Telegram Bot Token")
            print("   请在config.yaml中设置 TELEGRAM_BOT_TOKEN 或使用 --token 参数")
        
        return True
    except Exception as e:
        print(f"❌ 配置检查失败: {e}")
        return False


def main():
    """主函数"""
    print("Telegram Polling Daemon v1.0")
    print("=" * 40)
    
    # 解析参数
    args = parse_arguments()
    
    # 检查依赖
    if not check_dependencies():
        sys.exit(1)
    
    # 检查配置
    if not check_config():
        sys.exit(1)
    
    # 创建并启动守护进程
    daemon = PollingDaemon(
        bot_token=args.token,
        proxy_url=args.proxy
    )
    
    try:
        success = daemon.start()
        if not success:
            sys.exit(1)
    except KeyboardInterrupt:
        print("\n收到中断信号")
    except Exception as e:
        print(f"❌ 运行出错: {e}")
        sys.exit(1)
    finally:
        daemon.stop()
        print("\n👋 Telegram Polling 守护进程已退出")


if __name__ == "__main__":
    main()
