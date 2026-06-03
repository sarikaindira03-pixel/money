import type {
  BucketConfig,
  NavState,
  ThreadStep,
  VaultBalanceData,
} from "../types/data";
import { mid1label } from "./formats";

// ─── COMPUTED HELPERS ─────────────────────────────────────────────────────────
export const vaultBalance = (
  data: VaultBalanceData,
): {
  dripped: number;
  withdrawn: number;
  available: number;
} => {
  const dripped = data.vaultEntries?.reduce((s, v) => s + v.total_drip, 0);
  const withdrawn = data.vaultWithdrawals?.withdrawals.reduce(
    (s, w) => s + w.total_amount,
    0,
  );
  return { dripped, withdrawn, available: dripped - withdrawn };
};

export const blueBoxBalance = (
  data: any,
  bucketId: string,
): { totalContrib: number; withdrawn: number; balance: number } => {
  const allMonths = Object.keys(data.paychecks).sort();
  let totalContrib = 0;
  allMonths.forEach((mid) => {
    const entry = data.monthlyEntries[mid]?.[bucketId];
    if (entry) totalContrib += entry.allocated;
  });
  const withdrawn = data.blueBoxWithdrawals
    .filter((w) => w.bucketId === bucketId)
    .reduce((s, w) => s + w.totalAmount, 0);
  return { totalContrib, withdrawn, balance: totalContrib - withdrawn };
};

// export const monthSummary = (
//   data: AppData,
//   monthId: string,
// ): MonthSummary | null => {
//   const pc = data.paychecks[monthId];
//   if (!pc) return null;
//   const entries = data.monthlyEntries[monthId] || {};
//   const configs = data.bucketConfigs.filter((b) => b.active);
//   let totalAlloc = 0,
//     totalSpent = 0;
//   configs.forEach((bc) => {
//     const e = entries[bc.bucket_id];
//     if (!e) return;
//     const meta = BUCKET_META[bc.type];
//     if (meta.hasAllocated) totalAlloc += e.allocated;
//     if (meta.hasSpent) totalSpent += e.spent;
//   });
//   return {
//     salary: pc.salary,
//     totalAlloc,
//     totalSpent,
//     unallocated: pc.salary - totalAlloc,
//   };
// };

const EXCLUDED_TYPES = new Set(["RESERVE", "ORANGE"]);

export const buildGrouped = (
  buckets: BucketConfig[],
): Record<string, BucketConfig[]> => {
  return buckets
    .filter((b) => !EXCLUDED_TYPES.has(b.display_type))
    .reduce(
      (acc, bucket) => {
        if (!acc[bucket.display_type]) acc[bucket.display_type] = [];
        acc[bucket.display_type].push(bucket);
        return acc;
      },
      {} as Record<string, BucketConfig[]>,
    );
};

export const deriveSelected = (
  buckets: BucketConfig[],
  selectedBucketId: string,
): { selectedBucket: BucketConfig | undefined; isBlue: boolean } => {
  const selectedBucket = buckets.find(
    (b) => String(b.bucket_id) === selectedBucketId,
  );
  return {
    selectedBucket,
    isBlue: selectedBucket?.display_type === "BLUE",
  };
};

export const buildThreadSteps = (
  navigation: NavState,
  bc: BucketConfig | undefined,
): ThreadStep[] => {
  const steps: ThreadStep[] = [{ label: "YEARS", go: "year" }];

  if (navigation.year)
    steps.push({ label: navigation.year.toString(), go: "month" });

  if (navigation.monthId)
    steps.push({ label: mid1label(navigation.monthId), go: "buckets" });

  if (bc) steps.push({ label: bc.bucket_name.toUpperCase(), go: null });

  if (navigation.screen === "vault") steps.push({ label: "VAULT", go: null });
  else if (navigation.screen === "blueboxes")
    steps.push({ label: "BLUE BOXES", go: null });
  else if (navigation.screen === "bluebox" && bc)
    steps.push({ label: `${bc.bucket_name.toUpperCase()} BOX`, go: null });

  return steps;
};
