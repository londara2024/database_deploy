-- Runs only once, when the data volume is empty (first start).
-- Add extensions, schemas, or extra users here.
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
