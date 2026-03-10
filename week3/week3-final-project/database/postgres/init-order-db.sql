CREATE TABLE IF NOT EXISTS orders (
  id          SERIAL PRIMARY KEY,
  user_id     INTEGER      NOT NULL,
  product_id  VARCHAR(50)  NOT NULL,
  quantity    INTEGER      NOT NULL DEFAULT 1,
  total_price NUMERIC(10,2) NOT NULL,
  status      VARCHAR(20)  NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'cancelled')),
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_orders_user    ON orders (user_id);
CREATE INDEX IF NOT EXISTS idx_orders_status  ON orders (status);

INSERT INTO orders (user_id, product_id, quantity, total_price, status) VALUES
  (1, 'seed-product-1', 2, 1999.98, 'completed'),
  (2, 'seed-product-2', 1, 79.99,   'pending'),
  (3, 'seed-product-3', 3, 149.97,  'pending')
ON CONFLICT DO NOTHING;
