// usePaychecksQuery.ts
import { useQuery } from "@tanstack/react-query";
import { paycheckApi } from "../../service/paycheck";
import { qk } from "@/src/lib/cache/keys";

export const usePaychecksQuery = () => {
  const query = useQuery({
    queryKey: qk("paychecks"),
    queryFn: paycheckApi.list,
  });

  const years = query.data
    ? [...new Set(query.data.map((p) => p.month.split("-")[0]))]
        .sort()
        .reverse()
    : [];

  const paycheckRecord = query.data
    ? Object.fromEntries(query.data.map((p) => [p.month, p]))
    : {};

  return { ...query, years, paycheckRecord };
};
