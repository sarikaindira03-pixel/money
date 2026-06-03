// lib/pgPool.ts
import { Pool } from "pg";
// dev env only
const pool = new Pool({
  connectionString:
    "postgres://authenticated:authenticated@localhost:5432/money",
  max: 10,
});

export default pool;
