import { useQuery } from "@tanstack/react-query";
import { budgetApi } from "../../service/budget";
import { qk } from "@/src/lib/cache/keys";

export const useMonthlyBudget = (monthId: string) => {
  return useQuery({
    queryKey: qk("entries", monthId),

    enabled: !!monthId,
    queryFn: () => budgetApi.list(monthId),
  });
};
