// lib/cache/poke.ts
"use client";

import { useQueryClient } from "@tanstack/react-query";
import { CacheRegistry, type EntityKey } from "./registry";

/**
 * usePoke
 *
 * Returns a poke() function that recursively invalidates a cache entity
 * and all entities in its pokeOn chain, propagating arguments where applicable.
 *
 * Deduplication prevents circular invalidation loops.
 */
export function usePoke() {
  const qc = useQueryClient();

  return function poke<K extends EntityKey>(
    entity: K,
    arg?: Parameters<(typeof CacheRegistry)[K]["keys"]>[0],
  ): void {
    const invalidated = new Set<string>();
    function pokeInternal(
      entityKey: EntityKey,
      entityArg?: string | number,
    ): void {
      const config = CacheRegistry[entityKey];
      if (invalidated.has(entityKey)) return;
      invalidated.add(entityKey);

      // Invalidate scoped key
      if (entityArg !== undefined) {
        qc.invalidateQueries({
          queryKey: config.keys(entityArg as never),
          exact: false,
          refetchType: "all",
        });
      }

      // Invalidate broad key
      qc.invalidateQueries({
        queryKey: config.keys(undefined as never),
        exact: false,
        refetchType: "all",
      });

      // Recursively cascade
      for (const dep of config.pokeOn) {
        const depConfig = CacheRegistry[dep];

        if (entityArg !== undefined && depConfig.keys.length > 0) {
          pokeInternal(dep, entityArg);
        } else {
          pokeInternal(dep);
        }
      }
    }
    pokeInternal(entity, arg);
  };
}
