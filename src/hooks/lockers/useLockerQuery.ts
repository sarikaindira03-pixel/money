// hooks/useLockerQuery.ts
import { useQuery } from "@tanstack/react-query";
import { CurrentBalance } from "../../types/data";
import { lockerApi } from "../../service/locker";
import { qk } from "@/src/lib/cache/keys";

export function useLockerQuery() {
  return useQuery<CurrentBalance>({
    queryKey: qk("locker"),
    queryFn: lockerApi.list,
    retry: 1,
  });
}
