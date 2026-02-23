import logging
import os
import re
import sqlite3
from contextlib import contextmanager
from typing import List, Optional, Tuple

from .models import PixivTag

logger = logging.getLogger(__name__)


class SQLiteStorage:
    """SQLite 标签存储管理（同步实现）"""

    _SKIP_CONDITION = "name NOT GLOB '*[0-9]users入り'"

    def __init__(self, db_path: str = "data/pixiv_tags.db"):
        self.db_path = db_path
        self._init_done = False
        self._stats_cache: dict = {}

    @contextmanager
    def _get_connection(self):
        """获取数据库连接（自动关闭）"""
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        try:
            yield conn
        finally:
            conn.close()

    def init(self):
        """初始化数据库（只执行一次）"""
        if self._init_done:
            return

        os.makedirs(os.path.dirname(self.db_path), exist_ok=True)

        with self._get_connection() as conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS pixiv_tags (
                    name TEXT PRIMARY KEY,
                    official_translation TEXT,
                    chinese_translation TEXT DEFAULT '',
                    english_translation TEXT DEFAULT '',
                    frequency INTEGER DEFAULT 0,
                    chinese_reviewed INTEGER DEFAULT 0,
                    english_reviewed INTEGER DEFAULT 0,
                    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
                )
            """)
            conn.execute(
                "CREATE INDEX IF NOT EXISTS idx_frequency ON pixiv_tags(frequency DESC)"
            )
            conn.execute(
                "CREATE INDEX IF NOT EXISTS idx_translation ON pixiv_tags(official_translation)"
            )
            conn.execute("""
                CREATE INDEX IF NOT EXISTS idx_chinese_reviewed_freq_name 
                ON pixiv_tags(chinese_reviewed, frequency DESC, name ASC)
            """)
            conn.execute("""
                CREATE INDEX IF NOT EXISTS idx_english_reviewed_freq_name 
                ON pixiv_tags(english_reviewed, frequency DESC, name ASC)
            """)
            conn.commit()

        self._init_done = True
        logger.info(f"SQLite 数据库初始化完成: {self.db_path}")

    def upsert_tag(self, tag: PixivTag) -> bool:
        """插入或更新标签（频率累加）"""
        if PixivTag.should_skip(tag.name):
            return False

        self.init()
        with self._get_connection() as conn:
            conn.execute(
                """
                INSERT INTO pixiv_tags (name, official_translation, chinese_translation, english_translation, frequency)
                VALUES (?, ?, ?, ?, 1)
                ON CONFLICT(name) DO UPDATE SET
                    frequency = frequency + 1,
                    official_translation = COALESCE(?, official_translation),
                    updated_at = CURRENT_TIMESTAMP
            """,
                (
                    tag.name,
                    tag.official_translation,
                    tag.chinese_translation,
                    tag.english_translation,
                    tag.official_translation,
                ),
            )
            conn.commit()
        return True

    def upsert_tags_batch(self, tags: List[PixivTag]) -> int:
        """批量插入或更新（频率累加）"""
        # 过滤掉特殊的 tag
        tags = [tag for tag in tags if not PixivTag.should_skip(tag.name)]
        if not tags:
            return 0

        self.init()
        with self._get_connection() as conn:
            for tag in tags:
                conn.execute(
                    """
                    INSERT INTO pixiv_tags (name, official_translation, chinese_translation, english_translation, frequency)
                    VALUES (?, ?, ?, ?, 1)
                    ON CONFLICT(name) DO UPDATE SET
                        frequency = frequency + 1,
                        official_translation = COALESCE(?, official_translation),
                        updated_at = CURRENT_TIMESTAMP
                """,
                    (
                        tag.name,
                        tag.official_translation,
                        tag.chinese_translation,
                        tag.english_translation,
                        tag.official_translation,
                    ),
                )
            conn.commit()
        return len(tags)

    def insert_new_tags_only(self, tags: List[PixivTag]) -> int:
        """只插入不存在的标签（IGNORE），返回实际插入的数量"""
        # 过滤掉特殊的 tag
        tags = [tag for tag in tags if not PixivTag.should_skip(tag.name)]
        if not tags:
            return 0

        self.init()
        with self._get_connection() as conn:
            inserted_count = 0
            for tag in tags:
                cursor = conn.execute(
                    """
                    INSERT OR IGNORE INTO pixiv_tags 
                    (name, official_translation, chinese_translation, english_translation, frequency)
                    VALUES (?, ?, ?, ?, ?)
                """,
                    (
                        tag.name,
                        tag.official_translation,
                        tag.chinese_translation,
                        tag.english_translation,
                        tag.frequency,
                    ),
                )
                if cursor.rowcount > 0:
                    inserted_count += 1
            conn.commit()
        return inserted_count

    def apply_frequency_ops(self, ops: List[Tuple[str, int]]) -> int:
        """批量应用频率更新，返回实际更新的行数"""
        if not ops:
            return 0

        self.init()
        with self._get_connection() as conn:
            updated_count = 0
            for name, delta in ops:
                cursor = conn.execute(
                    "UPDATE pixiv_tags SET frequency = frequency + ?, updated_at = CURRENT_TIMESTAMP WHERE name = ?",
                    (delta, name),
                )
                if cursor.rowcount > 0:
                    updated_count += 1
            conn.commit()
        return updated_count

    def _row_to_tag(self, row) -> PixivTag:
        """将数据库行转换为 PixivTag 对象"""
        return PixivTag(
            name=row["name"],
            official_translation=row["official_translation"],
            chinese_translation=row["chinese_translation"],
            english_translation=row["english_translation"],
            frequency=row["frequency"],
            chinese_reviewed=bool(
                row["chinese_reviewed"] if "chinese_reviewed" in row.keys() else 0
            ),
            english_reviewed=bool(
                row["english_reviewed"] if "english_reviewed" in row.keys() else 0
            ),
        )

    def get_tag(self, name: str) -> Optional[PixivTag]:
        """查询单个标签"""
        self.init()
        with self._get_connection() as conn:
            cursor = conn.execute("SELECT * FROM pixiv_tags WHERE name = ?", (name,))
            row = cursor.fetchone()
            if row:
                return self._row_to_tag(row)
        return None

    def get_all_tags(self) -> List[PixivTag]:
        """获取全部标签"""
        self.init()
        with self._get_connection() as conn:
            cursor = conn.execute(
                f"SELECT * FROM pixiv_tags WHERE {self._SKIP_CONDITION} ORDER BY frequency DESC"
            )
            return [self._row_to_tag(row) for row in cursor.fetchall()]

    def count(self) -> int:
        """统计标签数量"""
        self.init()
        with self._get_connection() as conn:
            cursor = conn.execute(
                f"SELECT COUNT(*) FROM pixiv_tags WHERE {self._SKIP_CONDITION}"
            )
            result = cursor.fetchone()
            return result[0] if result else 0

    def increment_frequency(self, name: str, delta: int = 1) -> bool:
        """增加标签频率"""
        self.init()
        with self._get_connection() as conn:
            cursor = conn.execute(
                "UPDATE pixiv_tags SET frequency = frequency + ?, updated_at = CURRENT_TIMESTAMP WHERE name = ?",
                (delta, name),
            )
            conn.commit()
            return cursor.rowcount > 0

    def _escape_fts5_query(self, keyword: str) -> str:
        """转义 FTS5 特殊字符"""
        escaped = keyword.replace('"', '""')
        return f'"{escaped}"'

    def search_by_keyword(self, keyword: str, limit: int = 50) -> List[PixivTag]:
        """使用 FTS5 全文搜索标签（前缀匹配，结合 frequency 排序）"""
        if not keyword.strip():
            return []

        self.init()
        with self._get_connection() as conn:
            fts_query = self._escape_fts5_query(keyword) + "*"
            cursor = conn.execute(
                f"""
                SELECT t.* FROM pixiv_tags t
                JOIN pixiv_tags_fts fts ON t.rowid = fts.rowid
                WHERE pixiv_tags_fts MATCH ? AND t.{self._SKIP_CONDITION}
                ORDER BY t.frequency DESC, rank
                LIMIT ?
                """,
                (fts_query, limit),
            )
            return [self._row_to_tag(row) for row in cursor.fetchall()]

    def get_tag_index(self, name: str, language: str = "chinese") -> Optional[int]:
        """根据标签名获取其在排序列表中的索引位置（按频率降序，名称升序）"""
        self.init()
        with self._get_connection() as conn:
            cursor = conn.execute(
                f"""
                SELECT COUNT(*) FROM pixiv_tags
                WHERE (
                    (frequency > (SELECT frequency FROM pixiv_tags WHERE name = ?))
                   OR (frequency = (SELECT frequency FROM pixiv_tags WHERE name = ?)
                       AND name < ?)
                ) AND {self._SKIP_CONDITION}
                """,
                (name, name, name),
            )
            result = cursor.fetchone()
            return result[0] if result else None

    def get_top_tags(self, limit: int = 100) -> List[PixivTag]:
        """按频率排序获取热门标签（新增功能）"""
        self.init()
        with self._get_connection() as conn:
            cursor = conn.execute(
                f"SELECT * FROM pixiv_tags WHERE {self._SKIP_CONDITION} ORDER BY frequency DESC LIMIT ?",
                (limit,),
            )
            return [self._row_to_tag(row) for row in cursor.fetchall()]

    def get_tags_for_review(
        self, language: str = "chinese", limit: int = 100, offset: int = 0
    ) -> List[PixivTag]:
        """获取待审核的标签（按频率排序）"""
        self.init()
        reviewed_column = f"{language}_reviewed"
        with self._get_connection() as conn:
            cursor = conn.execute(
                f"""
                SELECT * FROM pixiv_tags
                WHERE {reviewed_column} = 0 AND {self._SKIP_CONDITION}
                ORDER BY frequency DESC
                LIMIT ? OFFSET ?
                """,
                (limit, offset),
            )
            return [self._row_to_tag(row) for row in cursor.fetchall()]

    def get_tag_by_index(
        self, index: int, language: str = "chinese"
    ) -> Optional[PixivTag]:
        """按索引获取标签（按频率降序，名称升序）"""
        self.init()
        with self._get_connection() as conn:
            cursor = conn.execute(
                f"""
                SELECT * FROM pixiv_tags
                WHERE {self._SKIP_CONDITION}
                ORDER BY frequency DESC, name ASC
                LIMIT 1 OFFSET ?
                """,
                (index,),
            )
            row = cursor.fetchone()
            if row:
                return self._row_to_tag(row)
        return None

    def get_tag_by_keyset(
        self, freq: int, name: str, direction: str = "next"
    ) -> Optional[PixivTag]:
        """使用键集分页获取下一个/上一个标签（避免 OFFSET）"""
        self.init()
        with self._get_connection() as conn:
            if direction == "next":
                cursor = conn.execute(
                    f"""
                    SELECT * FROM pixiv_tags
                    WHERE (frequency < ? OR (frequency = ? AND name > ?))
                      AND {self._SKIP_CONDITION}
                    ORDER BY frequency DESC, name ASC
                    LIMIT 1
                    """,
                    (freq, freq, name),
                )
            else:
                cursor = conn.execute(
                    f"""
                    SELECT * FROM pixiv_tags
                    WHERE (frequency > ? OR (frequency = ? AND name < ?))
                      AND {self._SKIP_CONDITION}
                    ORDER BY frequency ASC, name DESC
                    LIMIT 1
                    """,
                    (freq, freq, name),
                )
            row = cursor.fetchone()
            if row:
                return self._row_to_tag(row)
        return None

    def get_next_unreviewed(
        self, current_tag_name: str, language: str = "chinese"
    ) -> Optional[PixivTag]:
        """获取当前标签之后的下一个未审核标签（按频率降序，名称升序）"""
        self.init()
        reviewed_column = f"{language}_reviewed"
        with self._get_connection() as conn:
            cursor = conn.execute(
                f"""
                SELECT * FROM pixiv_tags
                WHERE (
                    (frequency = (SELECT frequency FROM pixiv_tags WHERE name = ?)
                     AND name > ?)
                    OR frequency < (SELECT frequency FROM pixiv_tags WHERE name = ?)
                )
                AND {reviewed_column} = 0 AND {self._SKIP_CONDITION}
                ORDER BY frequency DESC, name ASC
                LIMIT 1
                """,
                (current_tag_name, current_tag_name, current_tag_name),
            )
            row = cursor.fetchone()
            if row:
                return self._row_to_tag(row)
        return None

    def get_prev_unreviewed(
        self, current_tag_name: str, language: str = "chinese"
    ) -> Optional[PixivTag]:
        """获取当前标签之前的上一个未审核标签（按频率降序，名称升序）"""
        self.init()
        reviewed_column = f"{language}_reviewed"
        with self._get_connection() as conn:
            cursor = conn.execute(
                f"""
                SELECT * FROM pixiv_tags
                WHERE (
                    (frequency = (SELECT frequency FROM pixiv_tags WHERE name = ?)
                     AND name < ?
                     AND {reviewed_column} = 0)
                ) AND {self._SKIP_CONDITION}
                ORDER BY name DESC
                LIMIT 1
                """,
                (current_tag_name, current_tag_name),
            )
            row = cursor.fetchone()
            if row:
                return self._row_to_tag(row)
            cursor2 = conn.execute(
                f"""
                SELECT * FROM pixiv_tags
                WHERE frequency > (SELECT frequency FROM pixiv_tags WHERE name = ?)
                AND {reviewed_column} = 0 AND {self._SKIP_CONDITION}
                ORDER BY frequency ASC, name DESC
                LIMIT 1
                """,
                (current_tag_name,),
            )
            row2 = cursor2.fetchone()
            if row2:
                return self._row_to_tag(row2)
        return None

    def get_first_unreviewed_index(self, language: str = "chinese") -> Optional[int]:
        """获取第一个未审核标签的索引位置"""
        self.init()
        reviewed_column = f"{language}_reviewed"
        with self._get_connection() as conn:
            cursor = conn.execute(
                f"""
                SELECT * FROM pixiv_tags
                WHERE {reviewed_column} = 0 AND {self._SKIP_CONDITION}
                ORDER BY frequency DESC, name ASC
                LIMIT 1
                """
            )
            row = cursor.fetchone()
            if row:
                frequency = row["frequency"]
                name = row["name"]
                cursor2 = conn.execute(
                    f"""
                    SELECT COUNT(*) FROM pixiv_tags
                    WHERE ((frequency > ?) OR (frequency = ? AND name < ?))
                    AND {self._SKIP_CONDITION}
                    """,
                    (frequency, frequency, name),
                )
                result = cursor2.fetchone()
                return result[0] if result else None
        return None

    def _init_stats_cache(self):
        """初始化统计缓存（启动时计算一次）"""
        if self._stats_cache:
            return
        self.init()
        for lang in ["chinese", "english"]:
            self._stats_cache[lang] = self._compute_review_count(lang)

    def _compute_review_count(self, language: str) -> dict:
        """计算审核统计信息（从数据库查询）"""
        reviewed_column = f"{language}_reviewed"
        with self._get_connection() as conn:
            cursor = conn.execute(
                f"""
                SELECT
                    COUNT(*) as total,
                    SUM(CASE WHEN {reviewed_column} = 1 THEN 1 ELSE 0 END) as reviewed,
                    SUM(CASE WHEN {reviewed_column} = 0 THEN 1 ELSE 0 END) as pending
                FROM pixiv_tags
                WHERE {self._SKIP_CONDITION}
                """
            )
            row = cursor.fetchone()
            return {
                "total": row[0] or 0,
                "reviewed": row[1] or 0,
                "pending": row[2] or 0,
            }

    def get_review_count(self, language: str = "chinese") -> dict:
        """获取审核统计信息（从缓存读取）"""
        self._init_stats_cache()
        return self._stats_cache.get(
            language, {"total": 0, "reviewed": 0, "pending": 0}
        )

    def update_translation_and_review(
        self,
        name: str,
        chinese_translation: Optional[str] = None,
        english_translation: Optional[str] = None,
        chinese_reviewed: Optional[bool] = None,
        english_reviewed: Optional[bool] = None,
    ) -> bool:
        """更新翻译和审核状态"""
        self.init()
        self._init_stats_cache()

        with self._get_connection() as conn:
            current = conn.execute(
                "SELECT chinese_reviewed, english_reviewed FROM pixiv_tags WHERE name = ?",
                (name,),
            ).fetchone()

            if not current:
                return False

            old_chinese_reviewed = bool(current[0])
            old_english_reviewed = bool(current[1])

            updates = []
            params = []

            if chinese_translation is not None:
                updates.append("chinese_translation = ?")
                params.append(chinese_translation)

            if english_translation is not None:
                updates.append("english_translation = ?")
                params.append(english_translation)

            if chinese_reviewed is not None:
                updates.append("chinese_reviewed = ?")
                params.append(1 if chinese_reviewed else 0)

            if english_reviewed is not None:
                updates.append("english_reviewed = ?")
                params.append(1 if english_reviewed else 0)

            if not updates:
                return False

            updates.append("updated_at = CURRENT_TIMESTAMP")
            params.append(name)

            query = f"UPDATE pixiv_tags SET {', '.join(updates)} WHERE name = ?"
            cursor = conn.execute(query, params)
            conn.commit()

            if cursor.rowcount > 0:
                if (
                    chinese_reviewed is not None
                    and chinese_reviewed != old_chinese_reviewed
                ):
                    cache = self._stats_cache.get("chinese", {})
                    if chinese_reviewed:
                        cache["reviewed"] = cache.get("reviewed", 0) + 1
                        cache["pending"] = cache.get("pending", 0) - 1
                    else:
                        cache["reviewed"] = cache.get("reviewed", 0) - 1
                        cache["pending"] = cache.get("pending", 0) + 1

                if (
                    english_reviewed is not None
                    and english_reviewed != old_english_reviewed
                ):
                    cache = self._stats_cache.get("english", {})
                    if english_reviewed:
                        cache["reviewed"] = cache.get("reviewed", 0) + 1
                        cache["pending"] = cache.get("pending", 0) - 1
                    else:
                        cache["reviewed"] = cache.get("reviewed", 0) - 1
                        cache["pending"] = cache.get("pending", 0) + 1

                return True

            return False

    def _is_western_tag(self, name: str) -> bool:
        """判断是否为欧美 tag（完全由英文字母和数字组成）"""
        return bool(re.match(r"^[a-zA-Z0-9]+$", name))

    def get_next_unreviewed_skip_western(
        self, current_tag_name: str, language: str = "chinese"
    ) -> Optional[PixivTag]:
        """获取下一个未审核标签，跳过欧美 tag（优化版：使用 SQL 过滤）"""
        self.init()
        reviewed_column = f"{language}_reviewed"

        with self._get_connection() as conn:
            current = conn.execute(
                "SELECT frequency FROM pixiv_tags WHERE name = ?",
                (current_tag_name,),
            ).fetchone()

            if not current:
                return None

            current_freq = current[0]

            cursor = conn.execute(
                f"""
                SELECT * FROM pixiv_tags
                WHERE (frequency < ? OR (frequency = ? AND name > ?))
                  AND {reviewed_column} = 0
                  AND {self._SKIP_CONDITION}
                  AND name GLOB '*[^a-zA-Z0-9]*'
                ORDER BY frequency DESC, name ASC
                LIMIT 1
                """,
                (current_freq, current_freq, current_tag_name),
            )
            row = cursor.fetchone()
            if row:
                return self._row_to_tag(row)

            cursor = conn.execute(
                f"""
                SELECT * FROM pixiv_tags
                WHERE {reviewed_column} = 0
                  AND {self._SKIP_CONDITION}
                  AND name GLOB '*[^a-zA-Z0-9]*'
                ORDER BY frequency DESC, name ASC
                LIMIT 1
                """
            )
            row = cursor.fetchone()
            if row:
                return self._row_to_tag(row)

            return None
