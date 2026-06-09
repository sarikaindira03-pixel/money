import { useQuery } from "@tanstack/react-query";
import { incomeEntriesApi } from "@/src/service/extraIncome";

export const useIncomeEntries = (month: string, enabled: boolean) => {
  const { data, isLoading, isError } = useQuery({
    queryKey: ["income-entries", month],
    queryFn: () => incomeEntriesApi.getIncomeEntries(month),
    enabled, // only fetch when accordion is open
  });

  return {
    entries: data ?? [],
    isLoading,
    isError,
  };
};
