import { paycheckApi } from "@/src/service/paycheck";
import { usePoke } from "@/src/lib/cache/poke";
import { useMutation } from "@tanstack/react-query";

export const useCreatePaycheck = () => {
  const poke = usePoke();

  const createMutation = useMutation({
    mutationFn: paycheckApi.create,
    onSuccess: (_, variables) => {
      poke("paychecks", variables.month);
      // cascades to → entries → locker
    },
    onError: (error: any) => {
      const message =
        error.response?.data?.error || "An unexpected error occurred";
      console.error("Mutation Error:", message);
    },
  });

  return {
    createPaycheck: createMutation.mutateAsync,
    isCreating: createMutation.isPending,
  };
};
