import axios from "axios";
import { BucketConfig } from "../types/data";
import { API_ENDPOINTS, BASE_URL } from "../utils/constants";

export const bucketsApi = {
  list: async (): Promise<BucketConfig[]> => {
    const { data: buckets } = await axios.get(
      `${BASE_URL}/${API_ENDPOINTS.bucket_configs}`,
    );
    return buckets;
  },

  create: async (payload: {
    bucket_name: string;
    display_type: string;
    is_active: boolean;
  }): Promise<BucketConfig> => {
    const { data } = await axios.post(
      `${BASE_URL}/${API_ENDPOINTS.bucket_configs}`,
      payload,
    );
    return data;
  },

  updateSalary: async (monthId: string, salary: number) => {
    const { data } = await axios.patch(`/months/${monthId}/salary`, {
      salary,
    });
    return data;
  },
};
