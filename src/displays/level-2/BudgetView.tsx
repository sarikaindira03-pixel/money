"use client";

import { useState } from "react";
import { useMonthlyBudget } from "@/src/hooks/budgets/useMonthlyBudget";
import BudgetLedger from "./BudgetLedger";
import AllocateBucketDialog from "@/src/components/ui/AllocateBucketDialog";
import CreateBucketDialog from "@/src/components/ui/CreateBucketDialog";
import { usePaycheckByMonth } from "@/src/hooks/paychecks/usePaycheckByMonth";
import LedgerTransactionForm from "@/src/components/forms/LedgerTransactionForm";
import { useLedger } from "@/src/hooks/ledgers/useLedger";
import { useRouter } from "next/navigation";
import useNavigationStore from "@/src/store/zustand";
import { fmt } from "@/src/lib/formats";

const BudgetView = ({ monthId }: { monthId: string }) => {
  const { data, isLoading, refetch } = useMonthlyBudget(monthId);
  const orangeBucketId = data?.orange_bucket_id;

  const {
    isLoading: LedgerLoading,
    addEntry,
    isAdding,
  } = useLedger(Number(orangeBucketId), monthId);
  const router = useRouter();
  const navigation = useNavigationStore((state) => state.navigation);
  const [allocateOpen, setAllocateOpen] = useState(false);
  const [createOpen, setCreateOpen] = useState(false);
  const [showForm, setShowForm] = useState<boolean>(false);
  const [amount, setAmount] = useState("");
  const [note, setNote] = useState("");
  const [formError, setFormError] = useState<string | null>(null);
  const { salary, isLoading: salaryLoading } = usePaycheckByMonth(monthId);

  const handleAdd = async () => {
    const parsed = parseFloat(amount);
    if (!parsed || parsed <= 0) {
      setFormError("Enter a valid amount");
      return;
    }
    setFormError(null);
    try {
      const procedure = "record_ledger_entry";
      await addEntry({
        procedure,
        bucket_id: Number(orangeBucketId),
        month: monthId,
        amount_spent: parsed,
        note: note.trim(),
      });
      setAmount("");
      setNote("");
      setShowForm(false);
      refetch();
      router.push(`/month/${navigation.monthId}`);
    } catch (e: unknown) {
      const err = e as {
        response?: { data?: { error?: string } };
        message?: string;
      };
      const msg =
        err.response?.data?.error || err.message || "Something went wrong";
      setFormError(msg);
    }
  };

  if (isLoading || salaryLoading || !data) return <div>Loading...</div>;

  const { total_allocated, total_spent, grouped_by_type } = data ?? {};
  const pct = salary > 0 ? Math.round((total_allocated / salary) * 100) : 0;

  return (
    <div className="animate-in">
      <div className="lv-h1">Records.</div>

      <div className="stat-grid">
        <div className="stat">
          <div className="stat-l">Paycheck</div>
          <div className="stat-v ok">{fmt(salary)}</div>
        </div>
        <div className="stat">
          <div className="stat-l">Allocated</div>
          <div className={`stat-v ${total_allocated > salary ? "over" : "ok"}`}>
            {fmt(total_allocated)}
          </div>
        </div>
        <div className="stat">
          <div className="stat-l">Spent</div>
          <div className="stat-v dim">{fmt(total_spent)}</div>
        </div>
      </div>
      <div>
        {!data.isRecord && (
          <h1 className="text-yellow-400">No Records, Please Add New Record</h1>
        )}
      </div>
      <div className="prog">
        <div
          className="prog-fill"
          style={{
            width: `${Math.min(pct, 100)}%`,
            background: pct > 100 ? "var(--over)" : "var(--text2)",
          }}
        />
      </div>

      {pct > 100 && (
        <div className="text-over text-sm mt-1">
          Over allocated by {fmt(total_allocated - salary)}
        </div>
      )}

      {/* Button row */}
      {!!data.is_month_open && (
        <>
          <div className="brow">
            <button className="btn" onClick={() => setAllocateOpen(true)}>
              Add New Record
            </button>
            <button className="btn " onClick={() => setCreateOpen(true)}>
              + New Bucket
            </button>
            {!data.hasOrangeBucket && (
              <button
                className="btn btn-orange "
                onClick={() => setShowForm(true)}
              >
                Add Surprise Expense
              </button>
            )}
          </div>

          {!data.hasOrangeBucket && !!showForm && (
            <LedgerTransactionForm
              amount={amount}
              note={note}
              formError={formError}
              isSubmitting={isAdding || LedgerLoading}
              onAmountChange={setAmount}
              onNoteChange={setNote}
              onSubmit={handleAdd}
              onCancel={() => {
                setShowForm(false);
                setFormError(null);
                setAmount("");
                setNote("");
              }}
            />
          )}
        </>
      )}

      <AllocateBucketDialog
        open={allocateOpen}
        onOpenChange={setAllocateOpen}
        monthId={monthId}
      />

      <CreateBucketDialog open={createOpen} onOpenChange={setCreateOpen} />

      <BudgetLedger groupedBuckets={grouped_by_type} fmt={fmt} />
    </div>
  );
};

export default BudgetView;
