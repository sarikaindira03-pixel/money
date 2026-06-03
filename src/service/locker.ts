import axios from "axios";
import { CurrentBalance } from "../types/data";
import { API_ENDPOINTS, BASE_URL } from "../utils/constants";

export const lockerApi = {
  list: async (): Promise<CurrentBalance> => {
    const { data } = await axios.get(`${BASE_URL}/${API_ENDPOINTS.locker}`);

    // Pick the open month first, otherwise fall back to the most recent
    const active =
      data.find((d: CurrentBalance) => d.is_month_open) ??
      data.sort((a: CurrentBalance, b: CurrentBalance) =>
        b.month.localeCompare(a.month),
      )[0];

    if (!active) throw new Error("No locker data found");
    return active;
  },
};
