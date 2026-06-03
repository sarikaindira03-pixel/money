// // lib/cache/registry.ts

// import { vaultCache } from "./domains/vault";

// type CacheEntity = {
//   tag: (id?: string) => string; // generates the tag
//   invalidates: string[]; // which other entities this busts
// };

// export const CacheRegistry = {
//   ...vaultCache,
//   buckets: {
//     tag: (bucketId?: string) => (bucketId ? `buckets:${bucketId}` : "buckets"),
//     invalidates: ["entries", "vault"], // bucket change affects entries view
//   },
// } as const satisfies Record<string, CacheEntity>;

// lib/cache/registry.ts

type Month = string; // "YYYY-MM"
type BucketId = number;

// ─── Entity Keys ──────────────────────────────────────────────────────────────
// One key per API endpoint group in src/app/api/
// Matches DB tables/views, not endpoint paths

export type EntityKey =
  | "locker" // → v_vault_balances          → src/app/api/locker
  | "entries" // → monthly_entries            → src/app/api/budget/allocate + paychecks
  | "ledger" // → ledger + ledger_by_bucket_month → src/app/api/ledger
  | "buckets" // → bucket_configs             → src/app/api/bucket_configs
  | "paychecks" // → paychecks                 → src/app/api/paychecks
  | "cashFlow" // → cash_in/out_treasure (both variants) → src/app/api/vault
  | "vault"; // → vault + blue_vault raw     → src/app/api/vault

type CacheEntity<TArg = undefined> = TArg extends undefined
  ? {
      keys: () => readonly unknown[];
      tag: () => string;
      pokeOn: readonly EntityKey[];
    }
  : {
      keys: (arg?: TArg) => readonly unknown[];
      tag: (arg?: TArg) => string;
      pokeOn: readonly EntityKey[];
    };

// ─── Registry ─────────────────────────────────────────────────────────────────
// pokeOn answers: "when I mutate X, what else is now stale?"
// Source: trace each stored procedure → which tables it writes → which GET reads those tables

export const CacheRegistry = {
  /**
   * locker — v_vault_balances
   * Reads: vault.current_amt, blue_vault.current_amt, vault.closing_amt
   *
   * Stale when:
   *   - Any ledger entry changes vault.current_amt (via RESERVE recalculation)
   *   - Any allocation changes RESERVE → vault.current_amt
   *   - Paycheck recorded → vault.opening_amt changes
   *   - Month closed → vault.closing_amt set
   *
   * pokeOn: [] — nothing reads locker as a dependency, it's a leaf
   */
  locker: {
    keys: (month?: Month) => (month ? ["locker", month] : ["locker"]),
    tag: (month?: Month) => (month ? `locker:${month}` : "locker"),
    pokeOn: [],
  } satisfies CacheEntity<Month>,

  /**
   * entries — monthly_entries / monthly_budget_view / v_monthly_entries
   * Reads: monthly_entries.allocated, monthly_entries.spent per bucket per month
   *
   * Stale when:
   *   - allocate_bucket / allocate_blue_bucket → writes monthly_entries
   *   - record_ledger_entry / record_blue_ledger_entry → updates monthly_entries.spent
   *   - reverse_ledger_entry / reverse_blue_ledger_entry → restores monthly_entries.spent
   *   - record_paycheck → inserts monthly_entries (RESERVE row)
   *   - update_salary → updates monthly_entries.allocated (RESERVE row)
   *   - deactivate_bucket → bucket disappears from entries view
   *
   * pokeOn: locker — entries change always means RESERVE recalculated → vault.current_amt moved
   */
  entries: {
    keys: (month?: Month) => (month ? ["entries", month] : ["entries"]),
    tag: (month?: Month) => (month ? `entries:${month}` : "entries"),
    pokeOn: ["locker"] satisfies EntityKey[],
  } satisfies CacheEntity<Month>,

  /**
   * ledger — ledger table / ledger_by_bucket_month view
   * Reads: ledger rows (amount_spent, note, reversed, date_of_entry)
   *
   * Stale when:
   *   - record_ledger_entry / record_blue_ledger_entry → INSERT into ledger
   *   - reverse_ledger_entry / reverse_blue_ledger_entry → UPDATE ledger.reversed
   *
   * pokeOn: entries + locker — every ledger write updates monthly_entries.spent
   *         and recalculates RESERVE → vault.current_amt
   */
  ledger: {
    keys: (month?: Month) => (month ? ["ledger", month] : ["ledger"]),
    tag: (month?: Month) => (month ? `ledger:${month}` : "ledger"),
    pokeOn: ["entries", "locker", "cashFlow"] satisfies EntityKey[],
  } satisfies CacheEntity<Month>,

  /**
   * buckets — bucket_configs table
   * Reads: bucket_id, bucket_name, display_type, is_active
   *
   * Stale when:
   *   - New bucket inserted (bucket_configs INSERT — direct SQL, no procedure)
   *   - deactivate_bucket → sets is_active = false
   *
   * pokeOn: entries — entries view joins bucket_configs for display_type/name
   */
  buckets: {
    keys: (bucketId?: BucketId) =>
      bucketId ? ["buckets", bucketId] : ["buckets"],
    tag: (bucketId?: BucketId) =>
      bucketId ? `buckets:${bucketId}` : "buckets",
    pokeOn: ["entries"] satisfies EntityKey[],
  } satisfies CacheEntity<BucketId>,

  /**
   * paychecks — paychecks table
   * Reads: salary per month
   *
   * Stale when:
   *   - record_paycheck → INSERT into paychecks
   *   - update_salary → UPDATE paychecks.salary
   *
   * pokeOn: entries + locker — salary change recalculates vault.opening_amt
   *         and the RESERVE row in monthly_entries
   */
  paychecks: {
    keys: (month?: Month) => (month ? ["paychecks", month] : ["paychecks"]),
    tag: (month?: Month) => (month ? `paychecks:${month}` : "paychecks"),
    pokeOn: ["entries", "locker"] satisfies EntityKey[],
  } satisfies CacheEntity<Month>,

  /**
   * cashFlow — cash_in_treasure, cash_out_treasure,
   *            cash_in_blue_treasure, cash_out_blue_treasure
   * Reads: audit trail of money moving in/out of treasure
   *
   * Stale when:
   *   - record_ledger_entry → INSERT into cash_in/out_treasure (YELLOW/ORANGE overspend)
   *   - record_blue_ledger_entry → INSERT into cash_in/out_blue_treasure
   *   - reverse_ledger_entry → DELETE from cash_in/out_treasure
   *   - reverse_blue_ledger_entry → DELETE from cash_in/out_blue_treasure
   *
   * pokeOn: [] — cashFlow is a leaf, nothing depends on it
   */
  cashFlow: {
    keys: (month?: Month) => (month ? ["cash-flow", month] : ["cash-flow"]),
    tag: (month?: Month) => (month ? `cash-flow:${month}` : "cash-flow"),
    pokeOn: [],
  } satisfies CacheEntity<Month>,

  /**
   * vault — raw vault + blue_vault rows
   * Only needed if you have a dedicated vault detail screen.
   * Most screens use `locker` (v_vault_balances) instead.
   *
   * Stale when: same as locker — any write that touches vault or blue_vault
   * pokeOn: [] — leaf node
   */
  vault: {
    keys: (month?: Month) => (month ? ["vault", month] : ["vault"]),
    tag: (month?: Month) => (month ? `vault:${month}` : "vault"),
    pokeOn: [],
  } satisfies CacheEntity<Month>,
} as const satisfies Record<EntityKey, CacheEntity<any>>;

// ─── Cascade cheat sheet ──────────────────────────────────────────────────────
//
//  poke("ledger", month)    → entries → locker
//                           → locker  (direct)
//                           → cashFlow (direct)
//
//  poke("entries", month)   → locker
//
//  poke("paychecks", month) → entries → locker
//                           → locker  (direct)
//
//  poke("buckets")          → entries → locker
//
//  poke("locker")           → (nothing)
//  poke("cashFlow")         → (nothing)
//  poke("vault")            → (nothing)
