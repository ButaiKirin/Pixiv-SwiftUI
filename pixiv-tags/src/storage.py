import json
import logging
import os
from typing import List, Optional, Tuple

from .models import PixivTag
from .sqlite_storage import SQLiteStorage

logger = logging.getLogger(__name__)


class TagStorage:
    """标签数据存储管理（仅 SQLite 模式）"""

    def __init__(self, db_path: str = None):
        self.sqlite_path = db_path or os.getenv("SQLITE_DB_PATH", "data/pixiv_tags.db")
        self.sqlite = SQLiteStorage(self.sqlite_path)

        self.tags: List[PixivTag] = []  # 内存缓存
        self.tag_names: set = set()

        # 增量更新相关
        self.pending_new_tags: List[PixivTag] = []  # 待同步的新标签
        self.pending_freq_ops: List[
            Tuple[str, int, Optional[str]]
        ] = []  # 待同步的频率和翻译操作 [(name, delta, official_translation), ...]

        self.sync_interval: int = int(
            os.getenv("SAVE_INTERVAL", "20")
        )  # 每 N 个插画同步一次
        self.illusts_since_sync: int = 0  # 自上次同步后的插画数

        logger.info(
            f"使用 SQLite 模式，数据库路径: {self.sqlite_path}, 同步间隔: {self.sync_interval} 个插画"
        )

    def load_to_memory(self) -> int:
        """将数据从数据库加载到内存缓存"""
        try:
            self.tags = self.sqlite.get_all_tags()
            self.tag_names = {tag.name for tag in self.tags}
            logger.info(f"从 SQLite 加载了 {len(self.tags)} 个标签到内存")
            return len(self.tags)
        except Exception as e:
            logger.error(f"从 SQLite 加载标签失败: {e}")
            self.tags = []
            self.tag_names = set()
            return 0

    def add_tags_to_memory(self, new_tags: List[PixivTag]) -> int:
        """将新标签添加到内存，并同步到待处理更新列表"""
        added_count = 0
        for tag in new_tags:
            if tag.name not in self.tag_names:
                # 新标签，添加到内存
                self.tags.append(tag)
                self.tag_names.add(tag.name)
                added_count += 1
                # 累积到待处理新标签列表
                self.pending_new_tags.append(tag)
            else:
                # 已存在的标签，更新内存中的频率
                for existing_tag in self.tags:
                    if existing_tag.name == tag.name:
                        existing_tag.frequency += tag.frequency
                        # 更新内存中的官方翻译（如果有新翻译的话，或者目前为空）
                        if tag.official_translation:
                            existing_tag.official_translation = tag.official_translation

                        # 虽然内存更新了，但在 SQLite 中我们可以分两次操作：
                        # 1. 以后台增量方式更新频率 (delta=1) 和官方翻译
                        self.pending_freq_ops.append(
                            (tag.name, tag.frequency, tag.official_translation)
                        )
                        break
        return added_count

    def increment_tag_frequency(
        self,
        tag_name: str,
        increment: int = 1,
        official_translation: Optional[str] = None,
    ) -> bool:
        """增加标签频率（仅内存操作）并可更新官方翻译"""
        for tag in self.tags:
            if tag.name == tag_name:
                tag.frequency += increment
                if official_translation:
                    tag.official_translation = official_translation

                self.pending_freq_ops.append(
                    (tag_name, increment, official_translation)
                )
                return True
        return False

    def on_illust_processed(self):
        """当处理完一个插画后调用，用于检查自动同步（基于插画计数）"""
        self.illusts_since_sync += 1
        if self.illusts_since_sync >= self.sync_interval:
            self.sync_to_database()

    def sync_to_database(self) -> bool:
        """增量同步到数据库"""
        if not self.pending_new_tags and not self.pending_freq_ops:
            self.illusts_since_sync = 0
            return True

        try:
            # 同步新标签
            if self.pending_new_tags:
                inserted = self.sqlite.insert_new_tags_only(self.pending_new_tags)
                logger.debug(f"增量同步: 插入 {inserted} 个新标签")
                self.pending_new_tags.clear()

            # 同步频率和翻译更新
            if self.pending_freq_ops:
                updated = self.sqlite.apply_tag_updates(self.pending_freq_ops)
                logger.debug(f"增量同步: 更新 {updated} 个标签频率及翻译")
                self.pending_freq_ops.clear()

            self.illusts_since_sync = 0
            return True
        except Exception as e:
            logger.error(f"增量同步到 SQLite 失败: {e}")
            return False

    def save_from_memory(self) -> bool:
        """强制同步所有待处理内容到数据库"""
        try:
            result = self.sync_to_database()
            if result:
                logger.info(f"成功将内存所有更新同步到 SQLite (总数: {len(self.tags)})")
            return result
        except Exception as e:
            logger.error(f"强制保存到 SQLite 失败: {e}")
            return False

    def get_memory_count(self) -> int:
        return len(self.tags)

    def get_memory_tags(self) -> List[PixivTag]:
        return self.tags.copy()

    def is_tag_in_memory(self, tag_name: str) -> bool:
        return tag_name in self.tag_names

    def get_tag_frequency(self, tag_name: str) -> int:
        for tag in self.tags:
            if tag.name == tag_name:
                return tag.frequency
        return 0

    # 保持向后兼容的方法
    def load_tags(self) -> List[PixivTag]:
        """从内存加载标签（向后兼容）"""
        self.load_to_memory()
        return self.get_memory_tags()

    def save_tags(self, tags: List[PixivTag]):
        """保存标签（向后兼容）"""
        self.tags = tags
        self.tag_names = {tag.name for tag in tags}
        self.save_from_memory()

    def append_tags(self, new_tags: List[PixivTag]):
        """追加新标签到内存（向后兼容）"""
        self.add_tags_to_memory(new_tags)

    def force_sync(self) -> bool:
        """强制同步（向后兼容）"""
        return self.save_from_memory()
