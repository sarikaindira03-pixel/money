import { useMutation } from "@tanstack/react-query"; // ← removed useQueryClient
import { budgetApi } from "../../service/budget";
import { usePoke } from "@/src/lib/cache/poke";

export const useRemoveAllocateBudget = () => {
  const poke = usePoke();

  return useMutation({
    mutationFn: budgetApi.remove,
    onSuccess: (_, variables) => {
      poke("entries", variables.month);
      // cascades → locker
    },
  });
};
