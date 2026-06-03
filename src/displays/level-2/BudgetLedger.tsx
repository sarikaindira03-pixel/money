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
      style={{ fontFamily: "var(--font-mono, monospace)", padding: "1rem 0" }}
    >
      {/* Column headers */}
      <div
        style={{
          display: "grid",
          gridTemplateColumns: "1fr 110px 110px 110px 72px",
          padding: "4px 12px 4px 19px",
          marginBottom: 4,
        }}
      >
        {["Bucket", "Allocated", "Spent", "% Used"].map((h, i) => (
          <span
            key={h}
            style={{
              fontFamily: "var(--font-sans, sans-serif)",
              fontSize: 11,
              color: "var(--color-text-tertiary)",
              textAlign: i === 0 ? "left" : "right",
              textTransform: "uppercase",
              letterSpacing: "0.06em",
            }}
          >
            {h}
          </span>
        ))}
      </div>
      {Object.entries(groupedBuckets).map(([type, bucketList]) => {
        const metaKey = type.toUpperCase() as keyof typeof BUCKET_META;
        const meta = BUCKET_META[metaKey] ?? {
          color: "#f0f0f0",
          label: type,
        };

        return (
          <div key={type} style={{ marginBottom: "2rem" }}>
            {/* Group header */}
            <div
              style={{
                display: "flex",
                alignItems: "center",
                borderLeft: `3px solid ${meta.color}`,
                paddingLeft: 12,
                paddingBottom: 6,
                marginBottom: 2,
                borderBottom: "0.5px solid var(--color-border-tertiary)",
              }}
            >
              <span
                style={{
                  fontFamily: "var(--font-sans, sans-serif)",
                  fontSize: 11,
                  fontWeight: 500,
                  letterSpacing: "0.12em",
                  textTransform: "uppercase",
                  color: meta.color,
                }}
              >
                {meta.label}
              </span>
            </div>

            {/* Rows */}
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
                  style={{
                    display: "grid",
                    gridTemplateColumns: "1fr 110px 110px 110px 72px",
                    padding: "9px 12px 9px 16px",
                    borderLeft: `3px solid ${meta.color}`,
                    borderTop:
                      idx === 0
                        ? "none"
                        : "0.5px solid var(--color-border-tertiary)",
                    transition: "background 0.1s",
                    cursor: "pointer",
                  }}
                  onClick={() =>
                    handleBucketClick(b.month, b.bucket_id, b.allocated)
                  }
                  onMouseEnter={(e) =>
                    ((e.currentTarget as HTMLDivElement).style.background =
                      "var(--color-background-secondary)")
                  }
                  onMouseLeave={(e) =>
                    ((e.currentTarget as HTMLDivElement).style.background =
                      "transparent")
                  }
                >
                  {/* Name */}
                  <span
                    style={{
                      fontFamily: "var(--font-sans, sans-serif)",
                      fontSize: 13,
                      color: "var(--color-text-primary)",
                      textAlign: "left",
                    }}
                  >
                    {b.bucket_name}
                  </span>
                  {/* Allocated */}
                  <span
                    style={{
                      fontSize: 13,
                      textAlign: "right",
                      color: "var(--color-text-primary)",
                    }}
                  >
                    {fmt(b.allocated)}
                  </span>
                  {/* Spent */}
                  <span
                    style={{
                      fontSize: 13,
                      textAlign: "right",
                      color: isOverSpend
                        ? "#ef4444"
                        : "var(--color-text-primary)",
                    }}
                  >
                    {fmt(b.spent)}
                  </span>
                  {/* % Used */}
                  <span
                    style={{
                      fontSize: 13,
                      textAlign: "right",
                      color: pctColor,
                    }}
                  >
                    {pct}%
                  </span>
                </div>
              );
            })}
          </div>
        );
      })}
    </div>
  );
};

export default BudgetLedger;
