#!/usr/bin/env uv run
"""
Pixiv 标签翻译查询脚本

使用方法:
    python query_translation.py

脚本启动后会提示输入一个词，然后调用 Pixiv 自动补全接口
获取对应的标签和官方翻译。
"""

import logging
import os
import sys

from src.api.auth import AuthAPI
from src.api.client import NetworkClient
from src.api.search import SearchAPI
from src.models import PixivTag

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)

logger = logging.getLogger(__name__)


def main():
    """主函数"""
    print("=== Pixiv 标签翻译查询 ===")
    print("输入一个词来查询对应的 Pixiv 标签和官方翻译")
    print("支持日文、英文、数字等")
    print("输入 'quit' 或 'exit' 退出")
    print("-" * 40)

    # 初始化 API 客户端
    try:
        print("正在初始化 Pixiv API...")
        client = NetworkClient()
        auth_api = AuthAPI(client)
        search_api = SearchAPI(client)

        # 设置自动 token 刷新并认证
        auth_api.setup_token_refresh()
        auth_api.login_with_refresh_token()
        print("✅ API 初始化成功")
        print("-" * 40)
    except Exception as e:
        logger.error(f"API 初始化失败: {e}")
        return 1

    # 主循环
    while True:
        try:
            # 获取用户输入
            word = input("请输入查询词: ").strip()

            if not word:
                print("❌ 输入不能为空，请重新输入")
                continue

            # 退出检查
            if word.lower() in ["quit", "exit", "退出", "q"]:
                print("👋 再见！")
                break

            print(f"\n🔍 正在查询 '{word}' 的标签和翻译...")

            # 调用自动补全接口
            tags_data = search_api.search_autocomplete(word)

            if not tags_data:
                print(f"❌ 没有找到 '{word}' 相关的标签")
                print("-" * 40)
                continue

            # 过滤掉特殊的 tag（如 100users入り）
            tags_data = [
                tag
                for tag in tags_data
                if not PixivTag.should_skip(tag.get("name", ""))
            ]

            if not tags_data:
                print(f"❌ 过滤后没有找到 '{word}' 相关的有效标签")
                print("-" * 40)
                continue

            # 统计和显示结果
            total_tags = len(tags_data)
            translated_tags = [tag for tag in tags_data if tag.get("translated_name")]
            translated_count = len(translated_tags)

            print(f"\n📊 查询结果:")
            print(f"  总标签数: {total_tags}")
            print(f"  有翻译的标签: {translated_count}")
            if total_tags > 0:
                print(f"  翻译成功率: {translated_count / total_tags * 100:.1f}%")

            # 显示有翻译的标签
            if translated_tags:
                print(f"\n🌐 有官方翻译的标签 ({len(translated_tags)} 个):")
                for i, tag in enumerate(translated_tags, 1):
                    name = tag.get("name", "")
                    translation = tag.get("translated_name", "")
                    print(f"  {i:2d}. {name} -> {translation}")
            else:
                print("\n❌ 没有找到带官方翻译的标签")

            # 显示所有标签（可选）
            show_all = input("\n是否显示所有标签？(y/n): ").strip().lower()
            if show_all in ["y", "yes", "是", "Y"]:
                print(f"\n📋 所有标签 ({total_tags} 个):")
                for i, tag in enumerate(tags_data, 1):
                    name = tag.get("name", "")
                    translation = tag.get("translated_name", "")
                    if translation:
                        print(f"  {i:3d}. {name} -> {translation}")
                    else:
                        print(f"  {i:3d}. {name}")

            print("-" * 40)

        except KeyboardInterrupt:
            print("\n\n👋 用户中断，程序退出")
            break
        except Exception as e:
            logger.error(f"查询过程中出错: {e}")
            print(f"❌ 查询失败: {e}")
            print("-" * 40)

    # 清理资源
    try:
        client.close()
    except:
        pass

    return 0


if __name__ == "__main__":
    sys.exit(main())
