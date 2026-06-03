import { useQuery, useMutation } from "@tanstack/react-query";
import { ledgerApi } from "../../service/ledger";
import { LedgerEntry } from "../../types/data";
import { usePoke } from "@/src/lib/cache/poke";
import { qk } from "@/src/lib/cache/keys";
import { useRouter } from "next/navigation";
import useNavigationStore from "@/src/store/zustand";

export const useLedger = (bucketId: number, month: string) => {
  const poke = usePoke();

  const router = useRouter();
  const navigation = useNavigationStore((state) => state.navigation);
  const query = useQuery({
    queryKey: [...qk("ledger", month), bucketId], // scoped to month + bucket
    queryFn: () => ledgerApi.list(bucketId, month),
    enabled: !!bucketId && !!month,
  });

  const createMutation = useMutation({
    mutationFn: ledgerApi.create,
    onSuccess: () => {
      poke("ledger", month);
      // cascades → entries → locker, cashFlow

      router.push(`/month/${navigation.monthId}`);
    },
    onError: (error: any) => {
      console.error("Mutation Error:", error.message);
    },
  });

  const deleteMutation = useMutation({
    mutationFn: ledgerApi.delete,
    onSuccess: () => {
      poke("ledger", month);
      // same cascade — reversal also touches entries + locker
      router.push(`/month/${navigation.monthId}`);
    },
    onError: (error: any) => {
      console.error("Mutation Error:", error.message);
    },
  });

  // === Normalize entries safely ===
  const entries: LedgerEntry[] = Array.isArray(query.data) ? query.data : [];

  const is_month_open: boolean = entries[0]?.is_month_open ?? true;
  const total_spend = entries.reduce((sum, entry) => {
    return sum + Number(entry.amount_spent || 0);
  }, 0);

  return {
    ...query,
    entries,
    is_month_open,
    total_spend,
    addEntry: createMutation.mutateAsync,
    isAdding: createMutation.isPending,
    deleteEntry: deleteMutation.mutateAsync,
    isDeleting: deleteMutation.isPending,
  };
};
