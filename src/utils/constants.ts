import type { BucketMeta, BucketType } from "../types/data";

// ─── CONSTANTS ────────────────────────────────────────────────────────────────
export const BUCKET_META: Record<BucketType, BucketMeta> = {
  RED: {
    color: "#ef4444",
    label: "Need",
    rule: "Fixed committed expenses (rent, EMI). Overspend allowed; underspend is consumed, not returned.",
  },
  YELLOW: {
    color: "#eab308",
    label: "Want",
    rule: "Savings-style bucket. Underspend returns to main vault at month close via cash_in_treasure.",
  },
  BLUE: {
    color: "#3b82f6",
    label: "Saving",

    rule: "Isolated blue vault bucket. Never touches main vault. Underspend returns via cash_in_blue_treasure.",
  },
  GREEN: {
    color: "#22c55e",
    label: "Invest",

    rule: "Planned discretionary spend. Mechanically identical to RED; separated for reporting intent.",
  },
  ORANGE: {
    color: "#f97316",
    label: "Surprise",

    rule: "Surprise/emergency. allocated auto-syncs to total spend after each entry. No fixed plan.",
  },
  RESERVE: {
    color: "#8b5cf6",
    label: "Reserve",

    rule: "Virtual summary row only. allocated = unallocated salary. No ledger entries ever.",
  },
};

export const MONTHS_SHORT = [
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec",
];

// sairam
export const dead_user_id = "a240aa31-9303-41d1-9caf-a3389dedfd99";
// indira
// export const dead_user_id = "daf84b18-b04f-4541-8326-d09ba41e7cf0";
export const BASE_URL = "/api";

export const ROUTES = {
  month: "/month",
};
export const API_ENDPOINTS = {
  income_entries: "income_entries",
  paychecks: "paychecks",
  bucket_configs: "bucket_configs",
  monthly_entries: "monthly_entries",
  locker: "locker",
  ledger: "ledger",
  remove_budget_allocate: "budget",
  budget_allocate: "budget/allocate",
};

export const DEFAULT_SALARY = "90000";

export const LONG_PRESS_MS = 600;
export const TYPES = ["RED", "YELLOW", "GREEN", "BLUE"] as const;
export type DisplayType = (typeof TYPES)[number];

export const TYPE_COLOR: Record<DisplayType, string> = {
  RED: "var(--red)",
  YELLOW: "var(--yellow)",
  GREEN: "var(--green)",
  BLUE: "var(--blue)",
};
