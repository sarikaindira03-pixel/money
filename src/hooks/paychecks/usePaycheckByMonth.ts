// usePaycheckByMonth.ts — no changes needed
// it derives from usePaychecksQuery which is now on the registry
import { usePaychecksQuery } from "./usePaychecksQuery";

export const usePaycheckByMonth = (month: string) => {
  const { data, isLoading } = usePaychecksQuery();
  const record = data?.find((p) => p.month === month);
  return { salary: record?.total_income ?? 0, isLoading };
};
