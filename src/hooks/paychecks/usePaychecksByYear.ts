// usePaychecksByYear.ts — no changes needed, same reason
import { usePaychecksQuery } from "./usePaychecksQuery";

export const usePaychecksByYear = (year: string | number) => {
  const { data: query, isLoading, isError } = usePaychecksQuery();
  const filteredData =
    query?.filter((p) => p.month.startsWith(`${year}-`)) || [];
  const sortedData = [...filteredData].sort((a, b) =>
    b.month.localeCompare(a.month),
  );
  return { ...query, isLoading, isError, paychecks: sortedData };
};
