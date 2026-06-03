// app/month/[year]/page.tsx
import HomeApp from "../../HomeApp";
import MonthPage from "./MonthPage";

interface MonthPageProps {
  params: {
    year: string;
  };
}

export default async function page({ params }: MonthPageProps) {
  const { year } = await params;

  return (
    <div>
      <HomeApp />
      <MonthPage year={year} key={year} />
    </div>
  );
}
