import axios from "axios";
import { income_entry_Request } from "../types/data";
import { API_ENDPOINTS, BASE_URL } from "../utils/constants";
import { anonAuthHeaders } from "../lib/config";

const BASE = `${BASE_URL}/${API_ENDPOINTS.income_entries}`;

export const incomeEntriesApi = {
  getIncomeEntries: async (month: string) => {
    const { data } = await axios.get(BASE, {
      params: { month },
      headers: anonAuthHeaders(),
    });
    return data.data ?? [];
  },

  add_or_removeEIncome: async (payload: income_entry_Request) => {
    const { data } = await axios.post(BASE, payload, {
      headers: {
        "Content-Type": "application/json",
        ...anonAuthHeaders(),
      },
    });
    return data;
  },
};
