// // lib/cache/domains/vault.ts
// export const vaultCache = {
//   vault: {
//     tag: () => "vault",
//     invalidates: [],
//   },
//   entries: {
//     tag: (monthId?: string) => (monthId ? `entries:${monthId}` : "entries"),
//     invalidates: ["vault"],
//   },
//   withdrawals: {
//     tag: (monthId?: string) =>
//       monthId ? `withdrawals:${monthId}` : "withdrawals",
//     invalidates: ["vault"],
//   },
// };

// // // lib/cache/registry.ts
// // import { vaultCache } from "./domains/vault";
// // import { budgetCache } from "./domains/budget";

// // export const CacheRegistry = {
// //   ...vaultCache,
// //   ...budgetCache,
// // };
