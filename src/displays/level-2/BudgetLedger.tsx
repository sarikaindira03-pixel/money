"use client";

import { BUCKET_META } from "../../utils/constants";
import { useRouter } from "next/navigation";
import useNavigationStore from "../../store/zustand";
import { MonthlyBudgetBucket } from "../../types/data";
import { year_num } from "../../lib/formats";

const BudgetLedger = ({
  groupedBuckets,
  fmt,
}: {
  groupedBuckets: Record<string, MonthlyBudgetBucket[]>;
  fmt: (n: number) => string;
}) => {
  const router = useRouter();
  const setNavigation = useNavigationStore((state) => state.setNavigation);

  const handleBucketClick = (
    monthLabel: string,

    bucket_id: number,
    allocated: number,
  ) => {
    const yearLabel = year_num(monthLabel);
    setNavigation({
      screen: "buckets",
      year: String(yearLabel),
      monthId: monthLabel,
      bucketId: String(bucket_id),
    });
    router.push(`/month/${monthLabel}/${bucket_id}?allocated=${allocated}`);
  };
  return (
    <div
      style={{
        fontFamily: "var(--font-mono, monospace)",
        padding: "1rem 0",
        width: "100%",
      }}
    >
      {/* Clean Unified Layout Wrapper */}
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

              {/* Column sub-headers (Scoped inside group for structural clarity) */}
              <div
                style={{
                  display: "grid",
                  /* Dynamic grid tracking: Flexible bucket name, fixed widths that contract perfectly on mobile */
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

              {/* Data Rows */}
              <div style={{ display: "flex", flexDirection: "column" }}>
                {bucketList.map((b, idx) => {
                  const isOverSpend = b.spent > b.allocated;
                  const pct = b.utilization_percent ?? 0;
                  const pctColor =
                    pct > 100
                      ? "#ef4444"
                      : pct > 85
                        ? "#eab308"
                        : "var(--color-text-primary)";

                  return (
                    <div
                      key={b.bucket_id}
                      onClick={() =>
                        handleBucketClick(b.month, b.bucket_id, b.allocated)
                      }
                      onMouseEnter={(e) => {
                        e.currentTarget.style.background =
                          "var(--color-background-secondary)";
                      }}
                      onMouseLeave={(e) => {
                        e.currentTarget.style.background = "transparent";
                      }}
                      style={{
                        display: "grid",
                        /* Identical grid definition ensuring absolute alignment tracking with headers */
                        gridTemplateColumns: "minmax(80px, 1fr) 65px 65px 50px",
                        gap: "8px",
                        alignItems: "center",
                        borderLeft: `3px solid ${meta.color}`,
                        borderBottom:
                          "0.5px solid var(--color-border-tertiary)",
                        transition: "background 0.1s",
                        cursor: "pointer",
                        padding: "10px 12px 10px 12px",
                      }}
                    >
                      {/* Col 1: Bucket Name */}
                      <span
                        style={{
                          fontFamily: "var(--font-sans, sans-serif)",
                          fontSize: "12px",
                          color: "var(--color-text-primary)",
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
                        }}
                      >
                        {fmt(b.allocated)}
                      </span>

                      {/* Col 3: Spent */}
                      <span
                        style={{
                          fontSize: "11px",
                          textAlign: "right",
                          color: isOverSpend
                            ? "#ef4444"
                            : "var(--color-text-secondary)",
                        }}
                      >
                        {fmt(b.spent)}
                      </span>

                      {/* Col 4: Percent Used */}
                      <span
                        style={{
                          fontSize: "11px",
                          textAlign: "right",
                          color: pctColor,
                          fontWeight: pct >= 100 ? "60px" : "normal",
                        }}
                      >
                        {pct}%
                      </span>
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
