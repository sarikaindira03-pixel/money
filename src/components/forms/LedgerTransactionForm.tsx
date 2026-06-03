// src/components/forms/LedgerTransactionForm.tsx

interface LedgerTransactionFormProps {
  amount: string;
  note: string;
  formError?: string | null;
  isSubmitting?: boolean;

  onAmountChange: (value: string) => void;
  onNoteChange: (value: string) => void;
  onSubmit: () => void;
  onCancel: () => void;

  submitLabel?: string;
  submittingLabel?: string;
}

export default function LedgerTransactionForm({
  amount,
  note,
  formError,
  isSubmitting = false,
  onAmountChange,
  onNoteChange,
  onSubmit,
  onCancel,
  submitLabel = "Add",
  submittingLabel = "Adding...",
}: LedgerTransactionFormProps) {
  return (
    <div
      style={{
        background: "var(--bg1)",
        border: "1px solid var(--border2)",
        padding: 14,
        marginBottom: 20,
      }}
    >
      <div
        style={{
          display: "grid",
          gridTemplateColumns: "1fr 1fr",
          gap: 8,
          marginBottom: 10,
        }}
      >
        <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
          <label
            style={{
              fontSize: 9,
              letterSpacing: "0.12em",
              textTransform: "uppercase",
              color: "var(--text)",
            }}
          >
            Amount
          </label>

          <input
            type="number"
            placeholder="0"
            min={0}
            value={amount}
            onChange={(e) => onAmountChange(e.target.value)}
            autoFocus
            style={{
              background: "var(--bg)",
              border: "1px solid var(--border2)",
              color: "var(--text)",
              fontFamily: "var(--font-mono, monospace)",
              fontSize: 12,
              padding: "7px 10px",
              outline: "none",
            }}
          />
        </div>

        <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
          <label
            style={{
              fontSize: 9,
              letterSpacing: "0.12em",
              textTransform: "uppercase",
            }}
          >
            Note
          </label>

          <input
            type="text"
            placeholder="Important Note"
            value={note}
            onChange={(e) => onNoteChange(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && onSubmit()}
            style={{
              background: "var(--bg)",
              border: "1px solid var(--border2)",
              color: "var(--text)",
              fontFamily: "var(--font-mono, monospace)",
              fontSize: 12,
              padding: "7px 10px",
              outline: "none",
            }}
          />
        </div>
      </div>

      <div
        style={{
          display: "flex",
          gap: 8,
          justifyContent: "flex-end",
          alignItems: "center",
        }}
      >
        {formError && (
          <span
            style={{
              fontSize: 10,
              color: "var(--over)",
              flex: 1,
            }}
          >
            {formError}
          </span>
        )}

        <button
          onClick={onCancel}
          style={{
            fontFamily: "var(--font-mono, monospace)",
            fontSize: 10,
            letterSpacing: "0.08em",
            padding: "6px 14px",
            cursor: "pointer",
            border: "1px solid var(--border2)",
            background: "transparent",
            color: "var(--text)",
            textTransform: "uppercase",
          }}
        >
          Cancel
        </button>

        <button
          onClick={onSubmit}
          disabled={isSubmitting}
          style={{
            fontFamily: "var(--font-mono, monospace)",
            fontSize: 10,
            letterSpacing: "0.08em",
            padding: "6px 14px",
            cursor: isSubmitting ? "not-allowed" : "pointer",
            border: "1px solid var(--text)",
            background: "var(--bg)",
            color: "var(--text)",
            textTransform: "uppercase",
            opacity: isSubmitting ? 0.5 : 1,
          }}
        >
          {isSubmitting ? submittingLabel : submitLabel}
        </button>
      </div>
    </div>
  );
}
