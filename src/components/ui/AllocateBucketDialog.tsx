"use client";

import { useEffect, useState } from "react";
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

  const accentColor = selectedBucket
    ? (TYPE_COLOR[selectedBucket.display_type] ?? "var(--text2)")
    : "var(--border2)";

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
          maxWidth: 420,
          boxShadow: "0 0 0 1px var(--bg), 0 24px 48px rgba(0,0,0,0.8)",
          fontFamily: '"JetBrains Mono", monospace',
        }}
      >
        {/* Header */}
        <AlertDialogHeader
          style={{
            borderBottom: "1px solid var(--border)",
            padding: "16px 20px",
            borderLeft: `3px solid ${accentColor}`,
            background: "var(--bg)",
          }}
        >
          <div
            style={{
              display: "flex",
              alignItems: "center",
              justifyContent: "space-between",
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
              }}
            >
              {monthId}
            </span>
          </div>
          <p
            style={{
              fontSize: 10,
              letterSpacing: "0.04em",
              opacity: selectedBucket ? 1 : 0.4,
              transition: "opacity 0.15s",
            }}
          >
            {isBlue && selectedBucket
              ? "→ allocate_blue_bucket"
              : selectedBucket
                ? "→ allocate_bucket"
                : "→ select a bucket"}
          </p>
        </AlertDialogHeader>
        <AlertDialogDescription className="sr-only">
          Allocate funds to a budget bucket for {monthId}.
        </AlertDialogDescription>
        {/* Body */}
        <div
          style={{
            padding: "20px",
            display: "flex",
            flexDirection: "column",
            gap: 16,
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
          <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
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

            {/* Selected bucket info strip */}
            {selectedBucket && (
              <div
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: 8,
                  padding: "6px 10px",
                  background: "var(--bg2)",
                  border: "1px solid var(--border)",
                  borderLeft: `2px solid ${accentColor}`,
                  marginTop: 4,
                }}
              >
                <span
                  style={{
                    fontSize: 9,
                    letterSpacing: "0.12em",
                    textTransform: "uppercase",
                    color: accentColor,
                  }}
                >
                  {selectedBucket.display_type}
                </span>
                <span style={{ color: "var(--border2)" }}>·</span>
                <span style={{ fontSize: 11, color: "var(--text2)" }}>
                  {selectedBucket.bucket_name}
                </span>
              </div>
            )}
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
        <div style={{ display: "flex", gap: 8, padding: "0 20px 20px" }}>
          <button
            className="btn btn-ghost"
            onClick={handleClose}
            disabled={loading}
            style={{ flex: 1 }}
          >
            Cancel
          </button>
          <button
            className="btn btn-w"
            onClick={handleAllocate}
            disabled={loading || success || !selectedBucketId || !amount}
            style={{
              flex: 1,
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
