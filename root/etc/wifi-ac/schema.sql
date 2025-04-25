-- AP性能趋势数据表
CREATE TABLE IF NOT EXISTS trends (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    mac TEXT NOT NULL,
    timestamp INTEGER NOT NULL,
    load REAL,
    signal INTEGER,
    channel INTEGER
);

-- 可扩展：其他表（如事件、配置变更等）
-- CREATE TABLE IF NOT EXISTS events (...);
