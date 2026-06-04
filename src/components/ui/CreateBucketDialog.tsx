"use client";

import { useState } from "react";
import {
  AlertDialog,
  AlertDialogContent,
  AlertDialogHeader,
  AlertDialogDescription,
  AlertDialogTitle,
} from "../ui/alert-dialog";
import { useCreateBucket } from "@/src/hooks/buckets/useCreateBucket";
import { DisplayType, TYPE_COLOR, TYPES } from "@/src/utils/constants";

interface CreateBucketDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export default function CreateBucketDialog({
  open,
  onOpenChange,
}: CreateBucketDialogProps) {
  const [name, setName] = useState("");
  const [displayType, setDisplayType] = useState<DisplayType>("RED");

  // const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState(false);

  const { createBucket, isCreating } = useCreateBucket({
    onSuccess: () => {
      setSuccess(true);
      setTimeout(() => {
        handleClose();
      }, 900);
    },
    onError: (errorMessage) => {
      // Handle error - show toast notification or set error state
      console.error(errorMessage);
    },
  });
  const accentColor = TYPE_COLOR[displayType];

  const reset = () => {
    setName("");
    setDisplayType("RED");
    setError(null);
    setSuccess(false);
  };

  const handleClose = () => {
    reset();
    onOpenChange(false);
  };

  const handleCreate = async () => {
    if (!name.trim()) {
      setError("Enter a bucket name.");
      return;
    }

    // setLoading(true);
    setError(null);

    try {
      await createBucket({
        bucket_name: name.trim(),
        display_type: displayType,
        is_active: true,
      });

      setSuccess(true);
      setTimeout(() => handleClose(), 900);
    } catch (e: unknown) {
      const err = e as { message?: string };
      setError(err.message ?? "Something went wrong.");
    }
  };

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
              New Bucket
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
              {displayType}
            </span>
          </div>
        </AlertDialogHeader>
        <AlertDialogDescription className="sr-only">
          Create a new budget bucket with a name and type.
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
          {/* Name */}
          <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
            <label
              style={{
                fontSize: 9,
                letterSpacing: "0.12em",
                textTransform: "uppercase",
                color: "var(--text3)",
              }}
            >
              Bucket Name
            </label>
            <input
              type="text"
              value={name}
              onChange={(e) => {
                setName(e.target.value);
                setError(null);
              }}
              placeholder="e.g. Gym Fund"
              maxLength={40}
              autoFocus
              style={{
                borderColor: name ? accentColor : undefined,
              }}
            />
          </div>

          {/* Type selector — inline pill buttons */}
          <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
            <label
              style={{
                fontSize: 9,
                letterSpacing: "0.12em",
                textTransform: "uppercase",
                color: "var(--text3)",
              }}
            >
              Type
            </label>
            <div style={{ display: "flex", gap: 6 }}>
              {TYPES.map((t) => (
                <button
                  key={t}
                  onClick={() => setDisplayType(t)}
                  style={{
                    flex: 1,
                    padding: "6px 0",
                    fontSize: 9,
                    letterSpacing: "0.1em",
                    textTransform: "uppercase",
                    fontFamily: '"JetBrains Mono", monospace',
                    cursor: "pointer",
                    background: displayType === t ? TYPE_COLOR[t] : "var(--bg)",
                    color: displayType === t ? "#000" : TYPE_COLOR[t],
                    border: `1px solid ${TYPE_COLOR[t]}`,
                    transition: "all 0.1s",
                    borderRadius: 0,
                  }}
                >
                  {t}
                </button>
              ))}
            </div>
          </div>

          {/* Preview strip */}
          <div
            style={{
              display: "flex",
              alignItems: "center",
              justifyContent: "space-between",
              padding: "8px 12px",
              background: "var(--bg2)",
              border: "1px solid var(--border)",
              borderLeft: `3px solid ${accentColor}`,
            }}
          >
            <span style={{ fontSize: 12, color: "var(--text2)" }}>
              {name.trim() || "—"}
            </span>
            <span
              style={{
                fontSize: 9,
                letterSpacing: "0.12em",
                textTransform: "uppercase",
                color: accentColor,
              }}
            >
              {displayType}
            </span>
          </div>

          {/* Error */}
          {error && (
            <div className="flow-notice over" style={{ marginBottom: 0 }}>
              ✕ {error}
            </div>
          )}

          {/* Success */}
          {success && (
            <div className="flow-notice good" style={{ marginBottom: 0 }}>
              ✓ Bucket created
            </div>
          )}
        </div>

        {/* Footer */}
        <div style={{ display: "flex", gap: 8, padding: "0 20px 20px" }}>
          <button
            className="btn btn-ghost"
            onClick={handleClose}
            disabled={isCreating}
            style={{ flex: 1 }}
          >
            Cancel
          </button>
          <button
            className="btn btn-w"
            onClick={handleCreate}
            disabled={isCreating || success || !name.trim()}
            style={{
              flex: 1,
              borderColor: accentColor,
              opacity: isCreating || success || !name.trim() ? 0.4 : 1,
              cursor:
                isCreating || success || !name.trim()
                  ? "not-allowed"
                  : "pointer",
            }}
          >
            {isCreating ? "…" : "Create →"}
          </button>
        </div>
      </AlertDialogContent>
    </AlertDialog>
  );
}
