-- Beginner API Interface — memory system schema (reference)
--
-- The memory system (self-state, core memories, native entities) reads from and
-- writes to the three tables below. Per the implementation instructions these
-- tables already exist in the live Supabase project; this file documents the
-- exact shape the frontend (public/app.js) depends on so the assumptions are
-- explicit and the project stays self-contained.
--
-- Safe to re-run: uses IF NOT EXISTS / OR REPLACE and DROP POLICY IF EXISTS.
-- If a table already exists with a different shape, IF NOT EXISTS leaves it
-- untouched — adjust columns by hand if they drift from what's documented here.

-- =========================================================================
-- Tables
-- =========================================================================

-- Claude's identity document. One current row per user (enforced below), with
-- a version number bumped on each save.
CREATE TABLE IF NOT EXISTS self_state (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  content     TEXT        NOT NULL DEFAULT '',
  version     INTEGER     NOT NULL DEFAULT 1,
  is_current  BOOLEAN     NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- At most one current self-state per user.
CREATE UNIQUE INDEX IF NOT EXISTS self_state_one_current_per_user
  ON self_state(user_id) WHERE is_current;

-- Durable memories surfaced into context, highest resonance first. Archived
-- (is_active = false) rather than deleted, so history is preserved.
CREATE TABLE IF NOT EXISTS core_memories (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  content          TEXT        NOT NULL,
  memory_type      TEXT        NOT NULL CHECK (memory_type IN
                     ('fact', 'preference', 'pattern', 'insight', 'milestone', 'connection')),
  resonance        INTEGER     NOT NULL DEFAULT 5 CHECK (resonance BETWEEN 1 AND 10),
  is_active        BOOLEAN     NOT NULL DEFAULT TRUE,
  surface_count    INTEGER     NOT NULL DEFAULT 0,
  last_surfaced_at TIMESTAMPTZ,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Cross-platform "native" memory entities, ranked by access_count.
CREATE TABLE IF NOT EXISTS claude_memory_entities (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name          TEXT        NOT NULL,
  entity_type   TEXT        NOT NULL DEFAULT '',
  observations  JSONB       NOT NULL DEFAULT '[]'::jsonb,
  access_count  INTEGER     NOT NULL DEFAULT 0,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =========================================================================
-- Indexes
-- =========================================================================

CREATE INDEX IF NOT EXISTS self_state_user_idx        ON self_state(user_id);
CREATE INDEX IF NOT EXISTS core_memories_user_idx      ON core_memories(user_id);
CREATE INDEX IF NOT EXISTS core_memories_resonance_idx ON core_memories(resonance DESC);
CREATE INDEX IF NOT EXISTS memory_entities_user_idx    ON claude_memory_entities(user_id);
CREATE INDEX IF NOT EXISTS memory_entities_access_idx  ON claude_memory_entities(access_count DESC);

-- =========================================================================
-- Row-Level Security — each user only sees their own memories
-- =========================================================================

ALTER TABLE self_state             ENABLE ROW LEVEL SECURITY;
ALTER TABLE core_memories          ENABLE ROW LEVEL SECURITY;
ALTER TABLE claude_memory_entities ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "own self_state"       ON self_state;
DROP POLICY IF EXISTS "own core_memories"    ON core_memories;
DROP POLICY IF EXISTS "own memory_entities"  ON claude_memory_entities;

CREATE POLICY "own self_state" ON self_state
  FOR ALL TO authenticated
  USING      (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "own core_memories" ON core_memories
  FOR ALL TO authenticated
  USING      (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "own memory_entities" ON claude_memory_entities
  FOR ALL TO authenticated
  USING      (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- =========================================================================
-- updated_at trigger for self_state (reuses set_updated_at from the main schema)
-- =========================================================================

DROP TRIGGER IF EXISTS self_state_updated_at ON self_state;

CREATE TRIGGER self_state_updated_at
  BEFORE UPDATE ON self_state
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
