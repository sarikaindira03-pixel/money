"use client";

import { useState } from "react";
import {
  AlertDialog,
  AlertDialogContent,
  AlertDialogHeader,
  AlertDialogDescription,
  AlertDialogTitle,
} from "../ui/alert-dialog";
import GroupedSelect from "@/src/components/ui/GroupedSelect";
import { useAllocateBudget } from "@/src/hooks/budgets/useAllocateBudget";
import { fmt } from "@/src/lib/formats";
import { useBucketConfigs } from "@/src/hooks/buckets/useBucketConfigs";
import { buildGrouped, deriveSelected } from "@/src/lib/helpers";
import { DisplayType } from "@/src/utils/constants";

interface AllocateBucketDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  monthId: string;
}

const TYPE_COLOR: Record<string, string> = {
  RED: "var(--red)",
  YELLOW: "var(--yellow)",
  GREEN: "var(--green)",
  BLUE: "var(--blue)",
};

export default function AllocateBucketDialog({
  open,
  onOpenChange,
  monthId,
}: AllocateBucketDialogProps) {
  const { data: buckets = [], isLoading } = useBucketConfigs();

  const [selectedBucketId, setSelectedBucketId] = useState("");
  const [amount, setAmount] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState(false);
  const allocateMutation = useAllocateBudget();

  const groupedConfigs = buildGrouped(buckets);
  const { selectedBucket, isBlue } = deriveSelected(buckets, selectedBucketId);

  // const accentColor = selectedBucket
  //   ? (TYPE_COLOR[selectedBucket.display_type] ?? "var(--text2)")
  //   ;

  const currentDisplayType = selectedBucket
    ? (selectedBucket?.display_type as DisplayType)
    : "var(--border2)";
  const accentColor = TYPE_COLOR[currentDisplayType];

  const reset = () => {
    setSelectedBucketId("");
    setAmount("");
    setError(null);
    setSuccess(false);
  };

  const handleClose = () => {
    reset();
    onOpenChange(false);
  };

  const handleAllocate = async () => {
    if (!selectedBucketId || !amount) {
      setError("Select a bucket and enter an amount.");
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const procedure = isBlue ? "allocate_blue_bucket" : "allocate_bucket";

      await allocateMutation.mutateAsync({
        procedure,
        bucket_id: parseInt(selectedBucketId),
        month: monthId,
        amount: parseFloat(amount),
      });

      setSuccess(true);
      setTimeout(() => {
        handleClose();
      }, 900);
    } catch (e: unknown) {
      const err = e as {
        response?: { data?: { error?: string } };
        message?: string;
      };
      const msg =
        err.response?.data?.error || err.message || "Something went wrong";
      setError(msg);
    } finally {
      setLoading(false);
    }
  };

  const formattedAmount =
    amount && !isNaN(parseFloat(amount)) ? fmt(parseFloat(amount)) : null;

  return (
    <AlertDialog open={open} onOpenChange={onOpenChange}>
      <AlertDialogContent
        style={{
          background: "var(--bg1)",
          border: `1px solid ${accentColor}`,
          borderRadius: 0,
          padding: 0,
          // Responsive width: full-width on mobile with side margins,
          // capped at 420px on larger screens
          width: "calc(100vw - 32px)",
          maxWidth: 420,
          boxShadow: "0 0 0 1px var(--bg), 0 24px 48px rgba(0,0,0,0.8)",
          fontFamily: '"JetBrains Mono", monospace',
          // Ensure it doesn't overflow the viewport vertically on small screens
          maxHeight: "calc(100dvh - 48px)",
          overflowY: "auto",
        }}
      >
        {/* Header */}
        <AlertDialogHeader
          style={{
            borderBottom: "1px solid var(--border)",
            padding: "14px 16px",
            borderLeft: `3px solid ${accentColor}`,
            background: "var(--bg)",
            // Stick to top when content scrolls
            position: "sticky",
            top: 0,
            zIndex: 1,
          }}
        >
          <div
            style={{
              display: "flex",
              alignItems: "center",
              justifyContent: "space-between",
              gap: 8,
            }}
          >
            <AlertDialogTitle
              style={{
                fontSize: 9,
                letterSpacing: "0.18em",
                textTransform: "uppercase",
                color: "var(--text)",
                fontWeight: 400,
                fontFamily: '"JetBrains Mono", monospace',
                whiteSpace: "nowrap",
              }}
            >
              Allocate Funds
            </AlertDialogTitle>

            <span
              style={{
                fontSize: 9,
                letterSpacing: "0.15em",
                textTransform: "uppercase",
                color: "var(--text3)",
                // Truncate long month IDs on very small screens
                overflow: "hidden",
                textOverflow: "ellipsis",
                whiteSpace: "nowrap",
                minWidth: 0,
              }}
            >
              {monthId}
            </span>
          </div>
        </AlertDialogHeader>

        <AlertDialogDescription className="sr-only">
          Allocate funds to a budget bucket for {monthId}.
        </AlertDialogDescription>

        {/* Body */}
        <div
          style={{
            padding: "16px",
            display: "flex",
            flexDirection: "column",
            gap: 14,
          }}
        >
          {isLoading && (
            <p
              style={{
                fontSize: 10,
                color: "var(--text3)",
                letterSpacing: "0.08em",
              }}
            >
              Loading buckets…
            </p>
          )}

          {/* Bucket selector */}

          <div
            style={{
              display: "flex",
              flexDirection: "column",
              gap: 4,
              width: "100%",
            }}
          >
            <label
              style={{
                fontSize: 9,
                letterSpacing: "0.12em",
                textTransform: "uppercase",
                color: "var(--text3)",
              }}
            >
              Bucket
            </label>

            {/* 💡 SCROLL SYSTEM BOUNDARY
      Caps growing lists to a maximum height. 
      If your GroupedSelect has an internal 'dropdownClassName' or style prop for its popover, 
      apply these scroll styles there instead to prevent internal page jumping.
    */}
            <div
              className="select-viewport-scroller"
              style={{
                maxHeight: "220px",
                overflowY: "auto",
                overflowX: "hidden",
                width: "100%",
              }}
            >
              <GroupedSelect
                value={selectedBucketId}
                onChange={setSelectedBucketId}
                placeholder="— pick a bucket —"
                groups={Object.entries(groupedConfigs).map(
                  ([category, buckets]) => ({
                    label: category,
                    items: buckets.map((bucket) => ({
                      label: bucket.bucket_name,
                      value: String(bucket.bucket_id),
                    })),
                  }),
                )}
              />
            </div>

            {/* Selected bucket info strip */}
            {selectedBucket && (
              <div
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: 8,
                  padding: "8px 12px", // Optimized for mobile touch tracking
                  background: "var(--bg2)",
                  border: "1px solid var(--border)",
                  borderLeft: `3px solid ${accentColor}`, // 3px for high visibility on high-res mobile displays
                  marginTop: 6,
                  minWidth: 0, // Enforces ellipsis truncation mechanics on small viewports
                  width: "100%",
                  boxSizing: "border-box",
                }}
              >
                <span
                  style={{
                    fontSize: 9,
                    letterSpacing: "0.12em",
                    textTransform: "uppercase",
                    color: accentColor,
                    fontWeight: 600,
                    flexShrink: 0,
                  }}
                >
                  {selectedBucket.display_type}
                </span>

                <span style={{ color: "var(--border2)", flexShrink: 0 }}>
                  ·
                </span>

                <span
                  style={{
                    fontSize: 12, // 12px matches clean monochrome interfaces perfectly
                    fontFamily: "var(--font-sans, sans-serif)",
                    color: "var(--text2)",
                    overflow: "hidden",
                    textOverflow: "ellipsis",
                    whiteSpace: "nowrap",
                    minWidth: 0,
                  }}
                >
                  {selectedBucket.bucket_name}
                </span>
              </div>
            )}

            {/* Elegant subtle scrollbars for modern webkit viewports */}
            <style>{`
      .select-viewport-scroller::-webkit-scrollbar {
        width: 4px;
      }
      .select-viewport-scroller::-webkit-scrollbar-track {
        background: transparent;
      }
      .select-viewport-scroller::-webkit-scrollbar-thumb {
        background: var(--border2, #333);
        border-radius: 4px;
      }
    `}</style>
          </div>

          {/* Amount */}
          <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
            <label
              style={{
                fontSize: 9,
                letterSpacing: "0.12em",
                textTransform: "uppercase",
                color: "var(--text3)",
              }}
            >
              Amount
            </label>
            <div style={{ position: "relative" }}>
              <span
                style={{
                  position: "absolute",
                  left: 10,
                  top: "50%",
                  transform: "translateY(-50%)",
                  fontSize: 12,
                  color: "var(--text3)",
                  pointerEvents: "none",
                  userSelect: "none",
                }}
              >
                ₹
              </span>
              <input
                type="number"
                inputMode="decimal" // shows numeric keyboard on mobile
                min={0}
                value={amount}
                onChange={(e) => {
                  setAmount(e.target.value);
                  setError(null);
                }}
                placeholder="0"
                style={{
                  width: "100%",
                  paddingLeft: 24,
                  // Larger touch target on mobile
                  minHeight: 44,
                  fontSize: 14,
                  borderColor: amount ? accentColor : undefined,
                }}
              />
            </div>
            {formattedAmount && (
              <span
                style={{
                  fontSize: 11,
                  color: "var(--text2)",
                  letterSpacing: "0.02em",
                }}
              >
                {formattedAmount}
              </span>
            )}
          </div>

          {error && (
            <div className="flow-notice over" style={{ marginBottom: 0 }}>
              ✕ {error}
            </div>
          )}
          {success && (
            <div className="flow-notice good" style={{ marginBottom: 0 }}>
              ✓ Allocated successfully
            </div>
          )}
        </div>

        {/* Footer */}
        <div
          style={{
            display: "flex",
            gap: 8,
            padding: "0 16px 16px",
            // Stick to bottom when content scrolls
            position: "sticky",
            bottom: 0,
            background: "var(--bg1)",
            paddingTop: 12,
            borderTop: "1px solid var(--border)",
          }}
        >
          <button
            className="btn btn-ghost"
            onClick={handleClose}
            disabled={loading}
            style={{
              flex: 1,
              minHeight: 44, // accessible touch target
            }}
          >
            Cancel
          </button>
          <button
            className="btn btn-w"
            onClick={handleAllocate}
            disabled={loading || success || !selectedBucketId || !amount}
            style={{
              flex: 1,
              minHeight: 44, // accessible touch target
              borderColor: accentColor,
              opacity:
                loading || success || !selectedBucketId || !amount ? 0.4 : 1,
              cursor:
                loading || success || !selectedBucketId || !amount
                  ? "not-allowed"
                  : "pointer",
            }}
          >
            {loading ? "…" : "Allocate →"}
          </button>
        </div>
      </AlertDialogContent>
    </AlertDialog>
  );
}
