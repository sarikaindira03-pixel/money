// "use client";

// import { useCallback, useState } from "react";
// import { useMonthlyBudget } from "@/src/hooks/budgets/useMonthlyBudget";
// import AllocateBucketDialog from "@/src/components/ui/AllocateBucketDialog";
// import CreateBucketDialog from "@/src/components/ui/CreateBucketDialog";
// import { dead_user_id } from "@/src/utils/constants";
// import BudgetLedger from "../level-2/BudgetLedger";
// import { usePaycheckByMonth } from "@/src/hooks/paychecks/usePaycheckByMonth";

// const BudgetView = ({ monthId }: { monthId: string }) => {
//   const [allocateOpen, setAllocateOpen] = useState(false);
//   const [createOpen, setCreateOpen] = useState(false);

//   const { salary, isLoading: salaryLoading } = usePaycheckByMonth(monthId);
//   const { data, isLoading } = useMonthlyBudget(monthId);

//   const fmt = useCallback(
//     (amount: number) =>
//       new Intl.NumberFormat("en-IN", {
//         style: "currency",
//         currency: "INR",
//         maximumFractionDigits: 0,
//       }).format(amount),
//     [],
//   );

//   if (isLoading || salaryLoading || !data) return <div>Loading...</div>;

//   const { total_allocated, total_spent, grouped_by_type } = data;
//   const pct = salary > 0 ? Math.round((total_allocated / salary) * 100) : 0;

//   return (
//     <div className="animate-in">
//       <div className="lv-h1">Records.</div>

//       <div className="stat-grid">
//         <div className="stat">
//           <div className="stat-l">Paycheck</div>
//           <div className="stat-v ok">{fmt(salary)}</div>
//         </div>
//         <div className="stat">
//           <div className="stat-l">Allocated</div>
//           <div className={`stat-v ${total_allocated > salary ? "over" : "ok"}`}>
//             {fmt(total_allocated)}
//           </div>
//         </div>
//         <div className="stat">
//           <div className="stat-l">Spent</div>
//           <div className="stat-v dim">{fmt(total_spent)}</div>
//         </div>
//       </div>

//       <div className="prog">
//         <div
//           className="prog-fill"
//           style={{
//             width: `${Math.min(pct, 100)}%`,
//             background: pct > 100 ? "var(--over)" : "var(--text2)",
//           }}
//         />
//       </div>

//       {pct > 100 && (
//         <div className="text-over text-sm mt-1">
//           Over allocated by {fmt(total_allocated - salary)}
//         </div>
//       )}

//       <div className="brow">
//         <button className="btn" onClick={() => setAllocateOpen(true)}>
//           Add New Record
//         </button>
//         <button className="btn btn-ghost" onClick={() => setCreateOpen(true)}>
//           + New Bucket
//         </button>
//       </div>

//       {/* Bucket configs fetched once inside the store, shared across both dialogs */}
//       <AllocateBucketDialog
//         open={allocateOpen}
//         onOpenChange={setAllocateOpen}
//         monthId={monthId}
//         userId={dead_user_id}
//         // onSuccess={() => refetch()}
//       />

//       <CreateBucketDialog
//         open={createOpen}
//         onOpenChange={setCreateOpen}
//         userId={dead_user_id}
//       />

//       <BudgetLedger groupedBuckets={grouped_by_type} fmt={fmt} />
//     </div>
//   );
// };

// export default BudgetView;
