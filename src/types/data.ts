// ─── TYPES ────────────────────────────────────────────────────────────────────
export type BucketType =
  | "RED"
  | "YELLOW"
  | "ORANGE"
  | "GREEN"
  | "BLUE"
  | "RESERVE";
export type VaultRole = "none" | "drip_in" | "draw_out";

export type CurrentBalance = {
  user_id: string;
  month: string;
  main_vault_balance: number;
  blue_vault_balance: number;
  is_month_open: boolean;
};

export interface BucketMeta {
  label: string;
  color: string;
  rule: string;
}
export interface MonthlyBudgetBucket {
  original_allocated: number;
  bucket_id: number;
  bucket_name: string;
  display_type: BucketType;
  is_month_open: boolean;
  month: string;
  remaining: number;
  spent: number;
  user_id?: string;
  utilization_percent: number;
}
export type GroupedBudgetBuckets = Partial<
  Record<BucketType, MonthlyBudgetBucket[]>
>;

export interface MonthlyBudgetResponse {
  isRecord: boolean;
  hasOrangeBucket: boolean;
  bucket_id: number | null;
  orange_bucket_id: number | null;
  is_month_open: boolean;
  month: string;
  total_allocated: number;
  total_spent: number;
  grouped_by_type: GroupedBudgetBuckets;
}

export interface BucketConfig {
  bucket_id: number;
  user_id: string;
  bucket_name: string;
  display_type: string;
  is_active: boolean;
}

export interface Paycheck {
  user_id: string;
  total_income: number;
  month: string;
  is_month_open: boolean;
}

export interface MonthlyEntry {
  allocated: number;
  spent: number;
}

export interface LedgerEntry {
  ledger_id: string;
  month: string;
  amount_spent: number;
  note: string;
  date_of_entry: string;
  reversed: boolean;
  is_month_open: boolean;
}

export interface VaultEntry {
  id: string;
  monthId: string;
  bucketId: string;
  total_drip: number;
  drip_date: string;
  created_at?: string;
}

export interface VaultWithdrawal {
  id: string;
  month_id: string;
  bucketId: string;
  tagId: string;
  item_name: string | null;
  total_amount: number;
  pull_type: string;
  withdrawal_date: string;
  reason: string | null;
  target_bucket_id: string;
}

export interface VaultWithdrawalSource {
  id: string;
  withdrawalId: string;
  sourceMonthId: string;
  amountTaken: number;
}

export interface BlueBoxWithdrawal {
  id: string;
  date: string;
  bucketId: string;
  totalAmount: number;
  description: string;
}

export interface BlueBoxWithdrawalSource {
  id: string;
  withdrawalId: string;
  sourceMonthId: string;
  sourceEntryId: string;
  amountTaken: number;
  isFullyUsed: boolean;
}

export interface BlueBoxState {
  isSealed: boolean;
  sealedDate: string | null;
  sealedReason: string;
}

export interface BoxEvent {
  id: string;
  bucketId: string;
  monthId: string;
  boxType: string;
  amount: number;
  description: string;
  date: string;
}

export interface WithdrawalTag {
  id: string;
  label: string;
}

export interface VaultBalanceData {
  vaultEntries: VaultEntry[];
  vaultWithdrawals: {
    withdrawals: VaultWithdrawal[];
    sources: VaultWithdrawalSource[];
    tags: WithdrawalTag[];
  };
}

export type Screen =
  | "year"
  | "month"
  | "buckets"
  | "bucket"
  | "vault"
  | "blueboxes"
  | "bluebox";

export interface NavState {
  screen: Screen;
  year?: string;
  monthId?: string;
  bucketId?: string;
}

export interface ThreadStep {
  label: string;
  go: Screen | null;
}

export interface MonthSummary {
  salary: number;
  totalAlloc: number;
  totalSpent: number;
  unallocated: number;
}

export type AllocateBudgetRequest = {
  procedure: string;
  bucket_id: number;
  amount: number;
  month: string;
  note?: string;
};
export type RemoveAllocateBudgetRequest = {
  bucket_id: number;
  month: string;
};

export type income_entry_Request = {
  procedure: string;
  month: string;
  source_name: string;
  amount?: number ;
};
