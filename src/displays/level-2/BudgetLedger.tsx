"use client";

import { useEffect, useRef, useState } from "react";
import { BUCKET_META, LONG_PRESS_MS } from "../../utils/constants";
import { useRouter } from "next/navigation";
import useNavigationStore from "../../store/zustand";
import { MonthlyBudgetBucket } from "../../types/data";
import { year_num } from "../../lib/formats";
import { useRemoveAllocateBudget } from "@/src/hooks/budgets/useRemoveAllocateBudget";

const BudgetLedger = ({
  groupedBuckets,
  fmt,
}: {
  groupedBuckets: Record<string, MonthlyBudgetBucket[]>;
  fmt: (n: number) => string;
}) => {
  const router = useRouter();
  const setNavigation = useNavigationStore((state) => state.setNavigation);

  const [deletingId, setDeletingId] = useState<number | null>(null);
  const [removingId, setRemovingId] = useState<number | null>(null); // in-flight
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const pressTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const rowRefs = useRef<Map<number, HTMLDivElement>>(new Map());
  const removeAllocateMutation = useRemoveAllocateBudget();
  useEffect(() => {
    if (deletingId === null) return;

    const handleClickOutside = (e: MouseEvent | TouchEvent) => {
      const activeRow = rowRefs.current.get(deletingId);
      if (activeRow && !activeRow.contains(e.target as Node)) {
        resetDelete();
      }
    };

    document.addEventListener("mousedown", handleClickOutside);
    document.addEventListener("touchstart", handleClickOutside);

    return () => {
      document.removeEventListener("mousedown", handleClickOutside);
      document.removeEventListener("touchstart", handleClickOutside);
    };
  }, [deletingId]);
  const startPress = (bucketId: number) => {
    pressTimer.current = setTimeout(() => {
      setDeletingId(bucketId);
      setErrorMsg(null);
    }, LONG_PRESS_MS);
  };

  const cancelPress = () => {
    if (pressTimer.current) clearTimeout(pressTimer.current);
  };

  const resetDelete = () => {
    setDeletingId(null);
    setErrorMsg(null);
  };

  const handleBucketClick = (
    monthLabel: string,
    bucket_id: number,
    allocated: number,
  ) => {
    // if in delete mode, clicking row just cancels delete mode
    if (deletingId !== null) {
      resetDelete();
      return;
    }
    const yearLabel = year_num(monthLabel);
    setNavigation({
      screen: "buckets",
      year: String(yearLabel),
      monthId: monthLabel,
      bucketId: String(bucket_id),
    });
    router.push(`/month/${monthLabel}/${bucket_id}?allocated=${allocated}`);
  };

  const handleRemove = async (b: MonthlyBudgetBucket, e: React.MouseEvent) => {
    e.stopPropagation();
    setRemovingId(b.bucket_id);
    setErrorMsg(null);

    try {
      await removeAllocateMutation.mutateAsync({
        bucket_id: b.bucket_id,
        month: b.month,
      });

      resetDelete();
    } catch (e: unknown) {
      const err = e as {
        response?: { data?: { error?: string } };
        message?: string;
      };
      const msg =
        err.response?.data?.error || err.message || "Something went wrong";
      setErrorMsg(msg);
    } finally {
      setRemovingId(null);
    }
  };

  return (
    <div
      style={{
        fontFamily: "var(--font-mono, monospace)",
        padding: "1rem 0",
        width: "100%",
      }}
    >
      {/* error toast */}
      {errorMsg && (
        <div
          style={{
            marginBottom: "1rem",
            padding: "10px 14px",
            borderRadius: "var(--border-radius-md)",
            border: "0.5px solid var(--red)",
            color: "var(--red)",
            fontSize: 13,
            display: "flex",
            justifyContent: "space-between",
            alignItems: "center",
          }}
        >
          <span>{errorMsg}</span>
          <button
            onClick={resetDelete}
            style={{
              background: "none",
              border: "none",
              cursor: "pointer",
              color: "var(--text)",
              fontSize: 16,
            }}
          >
            ✕
          </button>
        </div>
      )}

      <div style={{ display: "flex", flexDirection: "column", gap: "1.5rem" }}>
        {Object.entries(groupedBuckets).map(([type, bucketList]) => {
          const metaKey = type.toUpperCase();
          const meta = BUCKET_META[metaKey] ?? {
            color: "#f0f0f0",
            label: type,
          };

          return (
            <div key={type} style={{ width: "100%" }}>
              {/* Group header */}
              <div
                style={{
                  display: "flex",
                  alignItems: "center",
                  borderLeft: `3px solid ${meta.color}`,
                  paddingLeft: "12px",
                  paddingBottom: "6px",
                  marginBottom: "6px",
                  borderBottom: "0.5px solid var(--color-border-tertiary)",
                }}
              >
                <span
                  style={{
                    fontFamily: "var(--font-sans, sans-serif)",
                    fontSize: "10px",
                    fontWeight: 500,
                    letterSpacing: "0.12em",
                    textTransform: "uppercase",
                    color: meta.color,
                  }}
                >
                  {meta.label}
                </span>
              </div>

              {/* Column headers */}
              <div
                style={{
                  display: "grid",
                  gridTemplateColumns: "minmax(80px, 1fr) 65px 65px 50px",
                  gap: "8px",
                  padding: "4px 12px 4px 15px",
                  borderBottom: "1px dashed var(--color-border-tertiary)",
                  opacity: 0.7,
                }}
              >
                {["Bucket", "Alloc", "Spent", "%"].map((h, i) => (
                  <span
                    key={h}
                    style={{
                      fontFamily: "var(--font-sans, sans-serif)",
                      fontSize: "9px",
                      color: "var(--color-text-tertiary)",
                      textAlign: i === 0 ? "left" : "right",
                      textTransform: "uppercase",
                      letterSpacing: "0.04em",
                    }}
                  >
                    {h}
                  </span>
                ))}
              </div>

              {/* Rows */}
              <div style={{ display: "flex", flexDirection: "column" }}>
                {bucketList.map((b) => {
                  const isOverSpend = b.spent > b.original_allocated;
                  const pct = b.utilization_percent ?? 0;
                  const pctColor =
                    pct > 100
                      ? "#ef4444"
                      : pct > 85
                        ? "#eab308"
                        : "var(--color-text-primary)";
                  const isDeleting = deletingId === b.bucket_id;
                  const isRemoving = removingId === b.bucket_id;

                  return (
                    <div
                      key={b.bucket_id}
                      ref={(el) => {
                        if (el) rowRefs.current.set(b.bucket_id, el);
                        else rowRefs.current.delete(b.bucket_id);
                      }}
                      onClick={() =>
                        handleBucketClick(
                          b.month,
                          b.bucket_id,
                          b.original_allocated,
                        )
                      }
                      onMouseDown={() => startPress(b.bucket_id)}
                      onMouseUp={cancelPress}
                      onMouseLeave={cancelPress}
                      onTouchStart={() => startPress(b.bucket_id)}
                      onTouchEnd={cancelPress}
                      onMouseEnter={(e) => {
                        if (!isDeleting)
                          e.currentTarget.style.background =
                            "var(--color-background-secondary)";
                      }}
                      style={{
                        position: "relative", // ← required for absolute button
                        display: "grid",
                        gridTemplateColumns: "minmax(80px, 1fr) 65px 65px 50px",
                        gap: "8px",
                        alignItems: "center",
                        borderLeft: `3px solid ${isDeleting ? "#ef4444" : meta.color}`,
                        borderBottom:
                          "0.5px solid var(--color-border-tertiary)",
                        transition: "background 0.2s, border-left-color 0.2s",
                        cursor: isDeleting ? "default" : "pointer",
                        padding: "10px 12px",
                        background: isDeleting
                          ? "rgba(239,68,68,0.08)"
                          : "transparent",
                        userSelect: "none",
                        WebkitUserSelect: "none",
                      }}
                    >
                      <span
                        style={{
                          fontFamily: "var(--font-sans, sans-serif)",
                          fontSize: "12px",
                          color: isDeleting
                            ? "var(--red)"
                            : "var(--color-text-primary)",
                          overflow: "hidden",
                          textOverflow: "ellipsis",
                          whiteSpace: "nowrap",
                        }}
                      >
                        {b.bucket_name}
                      </span>

                      {/* Col 2: Allocated */}
                      <span
                        style={{
                          fontSize: "11px",
                          textAlign: "right",
                          color: "var(--color-text-secondary)",
                          opacity: isDeleting ? 0.3 : 1,
                        }}
                      >
                        {fmt(b.original_allocated)}
                      </span>

                      {/* Col 3: Spent */}
                      <span
                        style={{
                          fontSize: "11px",
                          textAlign: "right",
                          color: isOverSpend
                            ? "#ef4444"
                            : "var(--color-text-secondary)",
                          opacity: isDeleting ? 0.3 : 1,
                        }}
                      >
                        {fmt(b.spent)}
                      </span>

                      {/* Col 4: % fades out */}
                      <span
                        style={{
                          fontSize: "11px",
                          textAlign: "right",
                          color: pctColor,
                          opacity: isDeleting ? 0 : 1,
                          transition: "opacity 0.15s",
                        }}
                      >
                        {pct}%
                      </span>
                      {isDeleting && (
                        <button
                          onClick={(e) => handleRemove(b, e)}
                          disabled={isRemoving}
                          style={{
                            position: "absolute",
                            right: 12,
                            top: "50%",
                            transform: "translateY(-50%)",
                            fontSize: 11,
                            padding: "3px 10px",
                            borderRadius: "var(--border-radius-md)",
                            border: "0.5px solid var(--color-border-danger)",
                            background: "var(--color-background-primary)",
                            color: "var(--red)",
                            cursor: "pointer",
                            whiteSpace: "nowrap",
                          }}
                        >
                          {isRemoving ? "…" : "✕"}
                        </button>
                      )}
                    </div>
                  );
                })}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
};

export default BudgetLedger;
