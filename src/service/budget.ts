import axios from "axios";
import {
  AllocateBudgetRequest,
  MonthlyBudgetResponse,
  RemoveAllocateBudgetRequest,
} from "../types/data";
import { API_ENDPOINTS, BASE_URL } from "../utils/constants";

export const budgetApi = {
  list: async (monthId: string): Promise<MonthlyBudgetResponse> => {
    const response = await axios.get<MonthlyBudgetResponse>(
      `${BASE_URL}/paychecks/${monthId}/${API_ENDPOINTS.monthly_entries}`,
    );

    return response.data;
  },
  create: async (payload: AllocateBudgetRequest) => {
    const { data } = await axios.post(
      `${BASE_URL}/${API_ENDPOINTS.budget_allocate}`,
      payload,
    );

    return data;
  },

  // updateSalary: async (monthId: string, salary: number) => {
  //   const { data } = await axios.patch(`/months/${monthId}/salary`, {
  //     salary,
  //   });
  //   return data;
  // },
  remove: async (payload: RemoveAllocateBudgetRequest) => {
    const response = await axios.post(
      `${BASE_URL}/${API_ENDPOINTS.remove_budget_allocate}/remove-allocation`,
      payload,
    );
    return response.data;
  },
};
