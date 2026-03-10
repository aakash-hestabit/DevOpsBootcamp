CREATE TABLE IF NOT EXISTS users (
  id         SERIAL PRIMARY KEY,
  name       VARCHAR(100) NOT NULL,
  email      VARCHAR(150) NOT NULL UNIQUE,
  role       VARCHAR(20)  NOT NULL DEFAULT 'user' CHECK (role IN ('admin', 'user', 'moderator')),
  created_at TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_users_email ON users (email);
CREATE INDEX IF NOT EXISTS idx_users_role  ON users (role);

INSERT INTO users (name, email, role) VALUES
  ('Alice Admin',   'alice@example.com',   'admin'),
  ('Bob User',      'bob@example.com',     'user'),
  ('Carol Mod',     'carol@example.com',   'moderator'),
  ('Dave Dev',      'dave@example.com',    'user'),
  ('Eve Engineer',  'eve@example.com',     'user')
ON CONFLICT (email) DO NOTHING;
