"use client";
import { useState } from "react";
import { useLedger } from "../../../../../hooks/ledgers/useLedger";
import { fmt } from "../../../../../lib/formats";
import { LedgerEntry } from "../../../../../types/data";
import { useSearchParams } from "next/navigation";
import { useBlueTreasure } from "../../../../../hooks/useBlueTreasure";
import LedgerTransactionForm from "@/src/components/forms/LedgerTransactionForm";
import { useBucketConfigs } from "@/src/hooks/buckets/useBucketConfigs";
interface BucketPageProps {
  bucketId: string;
  monthId: string;
}

const BucketPage = ({ bucketId, monthId }: BucketPageProps) => {
  const {
    entries,
    is_month_open,
    isLoading,
    error,
    total_spend,
    addEntry,
    isAdding,
    deleteEntry,
    isDeleting,
  } = useLedger(Number(bucketId), monthId);

  const searchParams = useSearchParams();
  const allocated = Number(searchParams?.get("allocated") ?? 0);
  const [deletingId, setDeletingId] = useState<string | null>(null);
  const { data: treasureData } = useBlueTreasure(bucketId, monthId);
  const totalBorrowed = (treasureData?.cashOut ?? []).reduce(
    (s, e) => s + Number(e.surplus_amt),
    0,
  );
  const remaining = allocated - total_spend;
  const isOver = total_spend > allocated;
  const pct =
    allocated > 0
      ? Math.min(Math.round((total_spend / allocated) * 100), 100)
      : 0;

  const [amount, setAmount] = useState("");
  const [note, setNote] = useState("");
  const [formError, setFormError] = useState<string | null>(null);
  const [showForm, setShowForm] = useState(false);

  const { data: buckets = [] } = useBucketConfigs();
  const isBlue =
    buckets.find((b) => String(b.bucket_id) === bucketId)?.display_type ===
    "BLUE";
  const handleAdd = async () => {
    const parsed = parseFloat(amount);
    if (!parsed || parsed <= 0) {
      setFormError("Enter a valid amount");
      return;
    }
    setFormError(null);
    try {
      const procedure = isBlue
        ? "record_blue_ledger_entry"
        : "record_ledger_entry";
      await addEntry({
        procedure,
        bucket_id: Number(bucketId),
        month: monthId,
        amount_spent: parsed,
        note: note.trim(),
      });
      setAmount("");
      setNote("");
      setShowForm(false);
    } catch (e: any) {
      const msg =
        e.response?.data?.error || // axios
        e.message ||
        "Something went wrong";
      setFormError(msg);
    }
  };

  const handleDelete = async (ledgerId: string) => {
    setDeletingId(ledgerId);
    const procedure = isBlue
      ? "reverse_blue_ledger_entry"
      : "reverse_ledger_entry";

    try {
      await deleteEntry({
        procedure: procedure,
        ledger_id: ledgerId,
        reason: "User deleted transaction",
      });
    } finally {
      setDeletingId(null);
    }
  };

  if (isLoading)
    return (
      <div style={{ padding: "1rem", fontSize: 12, color: "var(--text2)" }}>
        Loading...
      </div>
    );
  if (error)
    return (
      <div style={{ padding: "1rem", fontSize: 12, color: "var(--over)" }}>
        {(error as any).message}
      </div>
    );

  const entriesArray = entries ?? [];

  const noticeStyle: React.CSSProperties = {
    padding: "9px 14px",
    border: "1px solid var(--border2)",
    borderLeft: `3px solid ${isOver ? "var(--over)" : pct > 85 ? "var(--yellow)" : "var(--green)"}`,
    fontSize: 10,
    letterSpacing: "0.04em",
    marginBottom: 16,
    color: isOver ? "var(--over)" : pct > 85 ? "var(--yellow)" : "#5ab880",
  };

  const noticeText = isOver
    ? `Over budget by ${fmt(Math.abs(remaining))}`
    : pct > 85
      ? `Caution — only ${fmt(remaining)} remaining`
      : `On track — ${fmt(remaining)} remaining`;

  return (
    <div
      style={{ fontFamily: "var(--font-mono, monospace)", padding: "1rem 0" }}
    >
      {/* ── Stats ── */}
      <div style={{ display: "flex", gap: 1, marginBottom: 6 }}>
        {[
          { label: "Allocated", value: fmt(allocated), color: "var(--text)" },
          {
            label: "Spent",
            value: fmt(total_spend),
            color: isOver ? "var(--over)" : "var(--text)",
          },
          {
            label: isOver ? "Overspent" : "Remaining",
            value: fmt(Math.abs(remaining)),
            color: isOver ? "var(--over)" : "var(--text)",
          },
          {
            label: "Entries",
            value: String(entriesArray.length),
            color: "var(--text)",
            small: true,
          },
        ].map(({ label, value, color, small }) => (
          <div
            key={label}
            style={{
              flex: 1,
              padding: "12px 14px",
              background: "var(--bg1)",
              border: "1px solid var(--border)",
            }}
          >
            <div
              style={{
                fontSize: 9,
                letterSpacing: "0.12em",
                textTransform: "uppercase",
                color: "var(--text3)",
                marginBottom: 4,
              }}
            >
              {label}
            </div>
            <div
              style={{
                fontSize: small ? 13 : 16,
                fontWeight: small ? 400 : 700,
                letterSpacing: "-0.03em",
                color,
              }}
            >
              {value}
            </div>
          </div>
        ))}
      </div>

      {/* ── Progress bar ── */}
      <div style={{ height: 2, background: "var(--border2)", marginBottom: 4 }}>
        <div
          style={{
            height: "100%",
            width: `${pct}%`,
            background: isOver
              ? "var(--over)"
              : pct > 85
                ? "var(--yellow)"
                : "var(--text2)",
            transition: "width 0.4s",
          }}
        />
      </div>
      <div
        style={{
          display: "flex",
          justifyContent: "space-between",
          fontSize: 10,
          color: isOver ? "var(--over)" : "var(--text3)",
          letterSpacing: "0.04em",
          marginBottom: 16,
        }}
      >
        <span>{pct}% used</span>
        <span style={{ color: "var(--text4)" }}>{monthId}</span>
      </div>

      {/* ── Notice ── */}
      {allocated > 0 && <div style={noticeStyle}>{noticeText}</div>}
      {totalBorrowed > 0 && (
        <div
          style={{
            padding: "9px 14px",
            border: "1px solid #1a3a5c",
            borderLeft: "3px solid var(--blue)",
            background: "#050d18",
            fontSize: 10,
            letterSpacing: "0.04em",
            marginBottom: 16,
            display: "flex",
            justifyContent: "space-between",
            alignItems: "center",
            color: "#5a8fc8",
          }}
        >
          <span>Overspend covered by Blue Vault</span>
          <span
            style={{ fontWeight: 600, letterSpacing: "-0.02em", fontSize: 12 }}
          >
            {fmt(totalBorrowed)}
          </span>
        </div>
      )}
      {/* ── Add button / Form ── */}
      {!showForm ? (
        <button
          onClick={() => setShowForm(true)}
          disabled={!is_month_open}
          style={{
            width: "100%",
            padding: "9px 14px",
            marginBottom: 20,
            background: "transparent",
            border: "1px dashed var(--border2)",
            fontFamily: "var(--font-mono, monospace)",
            fontSize: 11,
            letterSpacing: "0.06em",
            cursor: !is_month_open ? "not-allowed" : "pointer",
            textAlign: "left",
            color: "var(--text3)",
            display: "flex",
            alignItems: "center",
            gap: 8,
            transition: "all 0.15s",
          }}
          onMouseEnter={(e) => {
            e.currentTarget.style.borderColor = "var(--text3)";
            e.currentTarget.style.color = "var(--text2)";
          }}
          onMouseLeave={(e) => {
            e.currentTarget.style.borderColor = "var(--border2)";
            e.currentTarget.style.color = "var(--text3)";
          }}
        >
          <span style={{ fontSize: 16, lineHeight: 1 }}>+</span>
          <span>Add transaction</span>
        </button>
      ) : (
        <LedgerTransactionForm
          amount={amount}
          note={note}
          formError={formError}
          isSubmitting={isAdding}
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

      {/* ── Table header ── */}
      <div
        style={{
          display: "grid",
          gridTemplateColumns: "52px 1fr 90px 32px",
          padding: "5px 14px",
          borderBottom: "1px solid var(--border)",
          marginBottom: 0,
        }}
      >
        {["Date", "Note", "Amount", ""].map((h, i) => (
          <span
            key={i}
            style={{
              fontSize: 9,
              letterSpacing: "0.12em",
              textTransform: "uppercase",
              color: "var(--text)",
              textAlign: i === 2 ? "right" : "left",
            }}
          >
            {h}
          </span>
        ))}
      </div>

      {/* ── Rows ── */}
      {entriesArray.length === 0 ? (
        <div
          style={{
            padding: "40px 0",
            textAlign: "center",
            fontSize: 11,
            color: "var(--text)",
            letterSpacing: "0.06em",
            border: "1px dashed var(--border)",
            borderTop: "none",
          }}
        >
          No transactions yet
        </div>
      ) : (
        <>
          {entriesArray.map((e: LedgerEntry) => (
            <TxRow
              key={e.ledger_id}
              entry={e}
              onDelete={handleDelete}
              is_month_open={is_month_open}
              isDeleting={isDeleting && deletingId === e.ledger_id}
            />
          ))}
          {/* ── Total strip ── */}
          <div
            style={{
              display: "flex",
              justifyContent: "flex-end",
              alignItems: "center",
              gap: 24,
              padding: "9px 14px",
              border: "1px solid var(--border)",
              borderTop: "none",
            }}
          >
            <span
              style={{
                fontSize: 9,
                letterSpacing: "0.1em",
                textTransform: "uppercase",
                color: "var(--text)",
              }}
            >
              Total
            </span>
            <span
              style={{
                fontSize: 13,
                fontWeight: 600,
                color: isOver ? "var(--over)" : "var(--text)",
              }}
            >
              {fmt(total_spend)}
            </span>
          </div>
        </>
      )}
    </div>
  );
};

// ── Extracted so hover state is clean ──
const TxRow = ({
  entry: e,
  onDelete,
  isDeleting,
  is_month_open,
}: {
  entry: LedgerEntry;
  onDelete: (id: string) => void;
  isDeleting: boolean;
  is_month_open: boolean;
}) => {
  const [hovered, setHovered] = useState(false);

  return (
    <div
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
      style={{
        display: "grid",
        gridTemplateColumns: "52px 1fr 90px 32px",
        padding: "10px 14px",
        border: "1px solid var(--border)",
        borderTop: "none",
        background: hovered ? "var(--bg2)" : "var(--bg1)",
        alignItems: "center",
        transition: "background 0.1s",
      }}
    >
      <span style={{ fontSize: 11, color: "var(--text)" }}>
        {String(e.date_of_entry).slice(5).replace("-", "/")}
      </span>
      <span
        style={{
          fontSize: 12,
          color: e.note ? "var(--text)" : "var(--text4)",
          fontStyle: e.note ? "normal" : "italic",
          overflow: "hidden",
          textOverflow: "ellipsis",
          whiteSpace: "nowrap",
        }}
      >
        {e.note || "—"}
      </span>
      <span
        style={{
          fontSize: 13,
          fontWeight: 600,
          letterSpacing: "-0.02em",
          textAlign: "right",
          color: "var(--text)",
        }}
      >
        {fmt(Number(e.amount_spent))}
      </span>
      {isDeleting ? (
        <svg
          width="12"
          height="12"
          viewBox="0 0 12 12"
          style={{ animation: "spin 0.7s linear infinite" }}
        >
          <circle
            cx="6"
            cy="6"
            r="4.5"
            fill="none"
            stroke="var(--text4)"
            strokeWidth="1.5"
            strokeDasharray="14 8"
          />
        </svg>
      ) : (
        <button
          onClick={() => onDelete(e.ledger_id)}
          disabled={!is_month_open}
          style={{
            background: "none",
            border: "none",
            fontSize: 14,
            cursor: !is_month_open ? "not-allowed" : "pointer",
            color: hovered ? "var(--over)" : "var(--text4)",
            padding: "0 0 0 8px",
            textAlign: "right",
            opacity: hovered ? 1 : 0,
            transition: "opacity 0.15s, color 0.1s",
          }}
        >
          ×
        </button>
      )}
    </div>
  );
};

export default BucketPage;
