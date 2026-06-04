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
        padding: "16px", // Slightly increased padding for mobile touch safety
        marginBottom: "20px",
        width: "100%",
        boxSizing: "border-box",
      }}
    >
      {/* Responsive Input Grid: Mobile-First Single Column -> Auto Desktop Breakout */}
      <div
        style={{
          display: "grid",
          /* If viewport width falls below ~360px (inputs + gap), it smoothly drops to 1 column. 
            Otherwise, it automatically fills out to a balanced 2-column structure.
          */
          gridTemplateColumns: "repeat(auto-fit, minmax(160px, 1fr))",
          gap: "12px",
          marginBottom: "16px",
        }}
      >
        {/* Amount Input Block */}
        <div style={{ display: "flex", flexDirection: "column", gap: "4px" }}>
          <label
            style={{
              fontSize: "9px",
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
              fontSize: "14px", // 14px+ prevents iOS Safari from automatically zooming into the layout on focus
              padding: "10px 12px", // Larger mobile tap areas
              outline: "none",
              width: "100%",
              boxSizing: "border-box",
            }}
          />
        </div>

        {/* Note Input Block */}
        <div style={{ display: "flex", flexDirection: "column", gap: "4px" }}>
          <label
            style={{
              fontSize: "9px",
              letterSpacing: "0.12em",
              textTransform: "uppercase",
              color: "var(--text)",
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
              fontSize: "14px", // Uniform size mapping to prevent input layout shifting
              padding: "10px 12px",
              outline: "none",
              width: "100%",
              boxSizing: "border-box",
            }}
          />
        </div>
      </div>

      {/* Responsive Footer Action Controls */}
      <div
        style={{
          display: "flex",
          /* Mobile-First: Column arrangement stacking buttons vertically. */
          flexDirection: "column",
          gap: "10px",
          alignItems: "stretch",
          width: "100%",
          /* Desktop Adjustments: Uses container queries or fluid layouts via smart media properties */
          marginTop: "12px",
        }}
        // Using a tiny dynamic runtime class or utility wrapper is ideal,
        // but let's achieve full inline layout fluid behavior through generic flex mechanics
        className="form-actions-wrapper"
      >
        {formError && (
          <span
            style={{
              fontSize: "11px",
              color: "var(--over)",
              textAlign: "left",
              marginBottom: "4px",
            }}
          >
            {formError}
          </span>
        )}

        {/* Sub-container handling button formatting natively across device modes */}
        <div
          style={{
            display: "flex",
            /* Wrap buttons automatically if the device viewport width constraint is extremely tight */
            flexWrap: "wrap-reverse",
            gap: "8px",
            justifyContent: "flex-end",
            width: "100%",
          }}
        >
          <button
            onClick={onCancel}
            style={{
              fontFamily: "var(--font-mono, monospace)",
              fontSize: "11px",
              letterSpacing: "0.08em",
              padding: "10px 16px",
              cursor: "pointer",
              border: "1px solid var(--border2)",
              background: "transparent",
              color: "var(--text)",
              textTransform: "uppercase",
              /* Flexible layout mapping: Expand full-width on tiny displays, naturally size on desktop */
              flexGrow: 1,
              flexBasis: "calc(50% - 4px)",
              maxWidth: "100%",
            }}
          >
            Cancel
          </button>

          <button
            onClick={onSubmit}
            disabled={isSubmitting}
            style={{
              fontFamily: "var(--font-mono, monospace)",
              fontSize: "11px",
              letterSpacing: "0.08em",
              padding: "10px 16px",
              cursor: isSubmitting ? "not-allowed" : "pointer",
              border: "1px solid var(--text)",
              background: "var(--bg)",
              color: "var(--text)",
              textTransform: "uppercase",
              opacity: isSubmitting ? 0.5 : 1,
              /* Match sibling button tracking properties precisely */
              flexGrow: 1,
              flexBasis: "calc(50% - 4px)",
              maxWidth: "100%",
            }}
          >
            {isSubmitting ? submittingLabel : submitLabel}
          </button>
        </div>
      </div>

      {/* Optional Global Overrides via Scoped Style block if Tailwind/CSS modules aren't handy */}
      <style>{`
        @media (min-width: 480px) {
          .form-actions-wrapper {
            flex-direction: row !important;
            justify-content: space-between !important;
            align-items: center !important;
          }
          .form-actions-wrapper button {
            flex-grow: 0 !important;
            flex-basis: auto !important;
            width: auto !important;
          }
        }
      `}</style>
    </div>
  );
}
