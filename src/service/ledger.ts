import axios from "axios";
import { LedgerEntry } from "../types/data";
import { API_ENDPOINTS, BASE_URL } from "../utils/constants";

export const ledgerApi = {
  list: async (bucketId: number, month: string): Promise<LedgerEntry[]> => {
    const { data } = await axios.get(
      `${BASE_URL}/${API_ENDPOINTS.ledger}?bucket_id=${bucketId}&month=${encodeURIComponent(month)}`,
    );
    return data.entries;
  },

  create: async (payload: {
    procedure: string;
    bucket_id: number;
    month: string;
    amount_spent: number;
    note?: string;
  }) => {
    const { data } = await axios.post(`${BASE_URL}/${API_ENDPOINTS.ledger}`, {
      ...payload,
      note: payload.note || null,
      date_of_entry: new Date().toISOString().split("T")[0],
    });
    return data;
  },

  delete: async (payload: {
    procedure: string;
    ledger_id: string;
    reason: string;
  }) => {
    const { ledger_id, ...body } = payload;
    const { data } = await axios.delete(
      `${BASE_URL}/${API_ENDPOINTS.ledger}/${ledger_id}`,
      { data: body },
    );
    return data;
  },
};
