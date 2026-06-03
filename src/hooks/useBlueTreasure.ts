// src/hooks/useBlueTreasure.ts
import { useQuery } from "@tanstack/react-query";
import axios from "axios";
import { qk } from "../lib/cache/keys";

export type CashOutEntry = {
  id: number;
  month: string;
  bucket_id: number;
  surplus_amt: number;
  entry_date: string;
};

export type CashInEntry = {
  id: number;
  month: string;
  bucket_id: number;
  underspend_amt: number;
  entry_date: string;
};

export const useBlueTreasure = (bucketId: string, month: string) => {
  return useQuery({
    queryKey: [...qk("cashFlow", month), bucketId], // scoped to month + bucket
    queryFn: async () => {
      const { data } = await axios.get(
        `/api/vault/blue-treasure?bucket_id=${bucketId}&month=${encodeURIComponent(month)}`,
      );
      return data as { cashOut: CashOutEntry[]; cashIn: CashInEntry[] };
    },
    enabled: !!bucketId && !!month,
  });
};
