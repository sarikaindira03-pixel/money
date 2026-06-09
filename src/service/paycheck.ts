import axios from "axios";
import { Paycheck } from "../types/data";
import { API_ENDPOINTS, BASE_URL } from "../utils/constants";
import { anonAuthHeaders } from "../lib/config";

export const paycheckApi = {
  list: async (): Promise<Paycheck[]> => {
    const { data } = await axios.get(
      `http://localhost:3002/api/${API_ENDPOINTS.paychecks}`,
      {
        headers: {
          ...anonAuthHeaders(), // Adds { apikey: "...", Authorization: "Bearer ..." } if pointing to Supabase
        },
      },
    );
    return data.data || data;
  },
  create: async (payload: { month: string; total_income: number }) => {
    const { data } = await axios.post(
      `${BASE_URL}/paychecks`,
      payload, // Request body
      {
        headers: {
          "Content-Type": "application/json",
          ...anonAuthHeaders(),
        },
      },
    );
    return data;
  },
};
