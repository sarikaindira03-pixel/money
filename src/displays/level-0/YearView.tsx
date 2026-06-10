"use client";
import { useRouter } from "next/navigation";
import { usePaychecksQuery } from "../../hooks/paychecks/usePaychecksQuery";
import useNavigationStore from "../../store/zustand";
import { YearItem } from "../../components/features/YearSelector/YearItem";
import { YearForm } from "../../components/features/YearSelector/YearForm";
import { ROUTES } from "@/src/utils/constants";

const YearView = () => {
  const router = useRouter();
  const navigation = useNavigationStore((state) => state.navigation);
  const setNavigation = useNavigationStore((state) => state.setNavigation);
  const { years, paycheckRecord, isLoading, isError } = usePaychecksQuery();
  const hasTrackedYears = years.length > 0;

  const getYearStats = (year: string) => {
    const months = Object.keys(paycheckRecord).filter((k) =>
      k.startsWith(`${year}-`),
    );
    const total = months.reduce(
      (s, m) => s + (paycheckRecord[m]?.total_income || 0),
      0,
    );
    return { count: months.length, total };
  };
  if (isLoading) return <div className="lv-sub">Loading records...</div>;
  if (isError)
    return (
      <div className="lv-sub text-red-500">Error connecting to server</div>
    );
  if (navigation.screen !== "year") return null;

  const handleYearClick = (year: string) => {
    setNavigation({ screen: "month", year });
    router.push(`${ROUTES.month}/${year}`);
  };

  return (
    <div>
      <header>
        {hasTrackedYears ? (
          <>
            <div className="lv-tag">Pick a Year</div>
          </>
        ) : (
          <h1 className="lv-h1">No Records Yet, Please Enter a paycheck</h1>
        )}
      </header>

      <div className="rlist">
        {years.map((y) => {
          const { count, total } = getYearStats(y);
          return (
            <YearItem
              key={y}
              year={y}
              count={count}
              total={total}
              onClick={handleYearClick}
            />
          );
        })}
      </div>

      <YearForm />
    </div>
  );
};

export default YearView;
