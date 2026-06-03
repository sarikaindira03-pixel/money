import { useMutation } from "@tanstack/react-query"; // ← removed useQueryClient
import { bucketsApi } from "@/src/service/bucket";
import { usePoke } from "@/src/lib/cache/poke";
import { BucketConfig } from "@/src/types/data";

interface CreateBucketParams {
  user_id: string;
  bucket_name: string;
  display_type: string;
  is_active: boolean;
}

interface UseCreateBucketOptions {
  onSuccess?: (data: BucketConfig) => void;
  onError?: (errorMessage: string) => void;
}

export const useCreateBucket = (options?: UseCreateBucketOptions) => {
  const poke = usePoke();

  const createMutation = useMutation({
    mutationFn: bucketsApi.create,
    onSuccess: (data) => {
      poke("buckets"); // ← broad, no bucketId — cascades to entries
      options?.onSuccess?.(data);
    },
    onError: (error: any) => {
      const message =
        error.response?.data?.message ??
        error.response?.data?.error ??
        "Failed to create bucket.";
      console.error("Mutation Error:", message);
      options?.onError?.(message);
    },
  });

  return {
    createBucket: createMutation.mutateAsync,
    isCreating: createMutation.isPending,
    error: createMutation.error,
  };
};
