// // lib/cache/invalidate.ts
// import { revalidateTag } from "next/cache";
// import { CacheRegistry } from "./registry";

// type EntityKey = keyof typeof CacheRegistry;

// export async function invalidate(entity: EntityKey, id?: string) {
//   const target = CacheRegistry[entity];

//   // Invalidate the entity itself
//   revalidateTag(target.tag(id), "default");

//   // Cascade — invalidate everything that depends on it
//   for (const dep of target.invalidates) {
//     const depEntity = CacheRegistry[dep as EntityKey];
//     revalidateTag(depEntity.tag(), "default");
//   }
// }
