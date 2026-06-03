import { fmt } from "../../../lib/formats";

const StatCard = ({
  label,
  value,
  type,
}: {
  label: string;
  value: number;
  type: string;
}) => (
  <div className="stat">
    <div className="stat-l">{label}</div>
    <div className={`stat-v ${type}`}>{fmt(value)}</div>
  </div>
);

export default StatCard;
