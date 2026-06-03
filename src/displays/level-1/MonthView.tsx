"use client";

import { useRouter } from "next/navigation";
import useNavigationStore from "../../store/zustand";
import { mid1label } from "../../lib/formats";
import { usePaychecksByYear } from "@/src/hooks/paychecks/usePaychecksByYear";

interface MonthViewProps {
  year: string | number;
}

const MonthView = ({ year }: MonthViewProps) => {
  const router = useRouter();
  const setNavigation = useNavigationStore((state) => state.setNavigation);
  const { paychecks, isLoading, isError } = usePaychecksByYear(year);

  const handleMonthClick = (monthLabel: string) => {
    setNavigation({
      screen: "buckets",
      year: String(year),
      monthId: monthLabel,
    });
    router.push(`/month/${monthLabel}`);
  };

  if (isLoading) return <div className="lv-sub">Loading months...</div>;
  if (isError)
    return <div className="lv-sub text-red-500">Error loading data</div>;

  return (
    <div>
      <header>
        <h1 className="lv-h1">Pick a month</h1>
        <div className="lv-sub">
          {paychecks.length} {paychecks.length === 1 ? "month" : "months"}{" "}
          logged
        </div>
      </header>

      <div className="rlist">
        {paychecks.length > 0 ? (
          paychecks.map((p) => (
            <div
              key={p.month}
              className="rrow"
              onClick={() => handleMonthClick(p.month)}
              style={{ borderLeftColor: "#2a2a2a", cursor: "pointer" }}
            >
              <div className="rrow-l">
                <div className="rrow-name">{mid1label(p.month)}</div>
              </div>
            </div>
          ))
        ) : (
          <div className="empty">NO MONTHS LOGGED FOR {year}</div>
        )}
      </div>
    </div>
  );
};

export default MonthView;
