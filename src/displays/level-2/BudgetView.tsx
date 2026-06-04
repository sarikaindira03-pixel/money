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
    <div className="animate-in" style={{ padding: "0 0 2rem" }}>
      <div className="lv-h1" style={{ marginBottom: "1rem" }}>
        Records.
      </div>
      <a href="https://funny-florentine-523c81.netlify.app/">Guide</a>

      {/* Stat grid — 3 equal columns, compact on mobile */}
      <div
        style={{
          display: "grid",
          gridTemplateColumns: "repeat(3, 1fr)",
          gap: 8,
          marginBottom: "1rem",
        }}
      >
        {[
          { label: "Paycheck", value: fmt(salary), cls: "ok" },
          {
            label: "Allocated",
            value: fmt(total_allocated),
            cls: total_allocated > salary ? "over" : "ok",
          },
          { label: "Spent", value: fmt(total_spent), cls: "ok" },
        ].map(({ label, value, cls }) => (
          <div key={label} className="stat" style={{ minWidth: 0 }}>
            <div
              className="stat-l"
              style={{ fontSize: 10, letterSpacing: "0.08em" }}
            >
              {label}
            </div>
            <div
              className={`stat-v ${cls}`}
              style={{
                fontSize: "clamp(13px, 3.5vw, 18px)",
                overflow: "hidden",
                textOverflow: "ellipsis",
                whiteSpace: "nowrap",
              }}
            >
              {value}
            </div>
          </div>
        ))}
      </div>

      {/* Progress bar */}
      <div className="prog" style={{ marginBottom: pct > 100 ? 4 : "1rem" }}>
        <div
          className="prog-fill"
          style={{
            width: `${Math.min(pct, 100)}%`,
            background: pct > 100 ? "var(--over)" : "var(--text2)",
          }}
        />
      </div>
      {pct > 100 && (
        <div
          className="text-over text-sm"
          style={{ marginBottom: "1rem", fontSize: 11 }}
        >
          Over allocated by {fmt(total_allocated - salary)}
        </div>
      )}

      {!data.isRecord && (
        <p
          style={{
            fontSize: 12,
            color: "#eab308",
            marginBottom: "1rem",
            letterSpacing: "0.04em",
          }}
        >
          No records yet — add your first entry below.
        </p>
      )}

      {/* Button row — wraps naturally on mobile */}
      {!!data.is_month_open && (
        <>
          <div
            className="brow"
            style={{
              display: "flex",
              flexWrap: "wrap",
              gap: 8,
              marginBottom: "1rem",
            }}
          >
            <button
              className="btn"
              onClick={() => setAllocateOpen(true)}
              style={{ flex: "1 1 auto", minWidth: 120, minHeight: 40 }}
            >
              Add New Record
            </button>
            <button
              className="btn"
              onClick={() => setCreateOpen(true)}
              style={{ flex: "1 1 auto", minWidth: 120, minHeight: 40 }}
            >
              + New Bucket
            </button>
            {!data.hasOrangeBucket && (
              <button
                className="btn btn-orange"
                onClick={() => setShowForm(true)}
                style={{ flex: "1 1 100%", minHeight: 40 }}
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
