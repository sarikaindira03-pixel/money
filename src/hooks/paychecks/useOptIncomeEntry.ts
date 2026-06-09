// useAddExtraIncome

import { usePoke } from "@/src/lib/cache/poke";
import { useMutation } from "@tanstack/react-query";
import { incomeEntriesApi } from "@/src/service/extraIncome";

export const useOptIncomeEntry = () => {
  const poke = usePoke();

  const useOptIncomeEntryMutation = useMutation({
    mutationFn: incomeEntriesApi.add_or_removeEIncome,
    onSuccess: (_, variables) => {
      poke("entries", variables.month);
      // cascades to → entries → locker
    },
    onError: (error: any) => {
      const message =
        error.response?.data?.error || "An unexpected error occurred";
      console.error("Mutation Error:", message);
    },
  });

  return {
    mutateAsync: useOptIncomeEntryMutation.mutateAsync,
    isMutating: useOptIncomeEntryMutation.isPending,
  };
};
