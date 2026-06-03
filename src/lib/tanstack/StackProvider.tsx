"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
const StackProvider = ({ children }: { children: React.ReactNode }) => {
  const queryClient = new QueryClient({
    defaultOptions: {
      queries: {
        staleTime: Infinity,
        gcTime: 1000 * 60 * 60 * 24, // 24 hours — how long to keep in storage
        refetchOnWindowFocus: false,
      },
    },
  });
  return (
    <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
  );
};

export default StackProvider;
