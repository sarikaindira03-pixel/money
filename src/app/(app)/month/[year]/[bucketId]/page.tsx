// bucketId
// app/month/[year]/[bucketId]/page.tsx

import HomeApp from "../../../HomeApp";
import BucketPage from "./BucketPage";

interface MonthPageProps {
  params: {
    bucketId: number;
    year: number;
  };
}

export default async function page({ params }: MonthPageProps) {
  const { bucketId, year } = await params;

  return (
    <div>
      <HomeApp />
      <BucketPage bucketId={String(bucketId)} monthId={String(year)} />
    </div>
  );
}
