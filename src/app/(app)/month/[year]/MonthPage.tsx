"use client";
import { isMonthFormat, isYearFormat } from "@/src/lib/formats";
import MonthView from "../../../../displays/level-1/MonthView";
import BudgetView from "../../../../displays/level-2/BudgetView";

interface MonthPageProps {
  year: string;
}

const MonthPage = ({ year }: MonthPageProps) => {
  const param = String(year);
  // pick a month
  if (isYearFormat(param)) return <MonthView year={Number(year)} />;
  // month specific allocation details
  if (isMonthFormat(param)) return <BudgetView monthId={param} />;

  return <div>Invalid month format</div>;
};

export default MonthPage;
