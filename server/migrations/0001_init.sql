-- The menu as of the last sync, stored pre-serialized so serving it costs
-- almost no CPU. Keys: 'products', 'bottles' (JSON arrays), 'syncedAt'.
CREATE TABLE menu_parts (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

-- The owner's edits per product (CellarTracker iWine). Kept even when a
-- product leaves CellarTracker, in case it comes back.
CREATE TABLE overrides (
  wine_id TEXT PRIMARY KEY,
  data TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

-- One row per sync, newest last.
CREATE TABLE syncs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  synced_at TEXT NOT NULL,
  product_count INTEGER NOT NULL,
  bottle_count INTEGER NOT NULL,
  report TEXT NOT NULL
);

-- Changes on every sync or edit; used as the menu's ETag.
CREATE TABLE meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

-- Failed passcode attempts per client address, for rate limiting.
CREATE TABLE login_attempts (
  ip TEXT PRIMARY KEY,
  window_start INTEGER NOT NULL,
  failures INTEGER NOT NULL
);
