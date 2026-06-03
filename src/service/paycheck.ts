// import axios from "axios";
// import { Paycheck } from "../types/data";
// import { BASE_URL, dead_user_id } from "../utils/constants";

// export const paycheckApi = {
//   list: async (): Promise<Paycheck[]> => {
//     const { data } = await axios.get(`http://localhost:8081/rest/v1/paychecks`);
//     return data.data || data;
//   },

//   create: async (payload: {
//     user_id?: string;
//     month: string;
//     salary: number;
//   }) => {
//     const { data } = await axios.post(`${BASE_URL}/paychecks`, {
//       ...payload,
//       user_id: dead_user_id,
//     });
//     return data;
//   },
// };
import axios from "axios";
import { Paycheck } from "../types/data";
import { BASE_URL } from "../utils/constants";
import { anonAuthHeaders } from "../lib/config";

export const paycheckApi = {
  list: async (): Promise<Paycheck[]> => {
    const { data } = await axios.get(`${BASE_URL}/paychecks`, {
      headers: {
        ...anonAuthHeaders(), // Adds { apikey: "...", Authorization: "Bearer ..." } if pointing to Supabase
      },
    });
    return data.data || data;
  },
  create: async (payload: { month: string; salary: number }) => {
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
