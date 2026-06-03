import { useQuery } from "@tanstack/react-query";
import { bucketsApi } from "../../service/bucket";
import { qk } from "@/src/lib/cache/keys";

export const useBucketConfigs = (enabled = true) => {
  return useQuery({
    queryKey: qk("buckets"),
    enabled,
    queryFn: bucketsApi.list,
  });
};
