import { fmt } from "../../../lib/formats";
interface YearItemProps {
  year: string;
  count: number;
  total: number;
  onClick: (year: string) => void;
}

export const YearItem = ({ year, count, total, onClick }: YearItemProps) => (
  <div
    className="rrow"
    onClick={() => onClick(year)}
    style={{ borderLeftColor: "#333" }}
  >
    <div className="rrow-l">
      <div
        className="rrow-name active"
        style={{ fontSize: 18, fontWeight: 700 }}
      >
        {year}
      </div>
      <div className="rrow-meta">
        {count} {count === 1 ? "month" : "months"} logged
      </div>
    </div>
    <div className="rrow-r">
      <div className="rrow-num">{fmt(total)}</div>
      <div className="rrow-sub">total earned</div>
    </div>
  </div>
);
