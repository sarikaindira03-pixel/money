// lib/cache/keys.ts

import { CacheRegistry, type EntityKey } from "./registry";

/**
 * qk — query key
 *
 * Returns the TanStack Query key for a given entity.
 * Pass an arg to get a scoped key, omit it for the broad key.
 *
 * @example
 * useQuery({ queryKey: qk("ledger", "2026-01"), queryFn: ... })
 * useQuery({ queryKey: qk("buckets"),           queryFn: ... })
 */
export function qk<K extends EntityKey>(
  entity: K,
  arg?: Parameters<(typeof CacheRegistry)[K]["keys"]>[0],
): readonly unknown[] {
  return CacheRegistry[entity].keys(arg as never);
}
