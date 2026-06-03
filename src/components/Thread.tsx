import type { Screen, ThreadStep } from "../types/data";

interface ThreadProps {
  steps: ThreadStep[];
  onJump: (screen: Screen) => void;
}

const Thread = ({ steps, onJump }: ThreadProps) => {
  return (
    <div className="thread">
      {steps.map((s, i) => (
        <div
          key={i}
          className={`flex items-center gap-0 ${i === steps.length - 1 ? "flex-1" : "flex-none"}`}
        >
          <div className="t-node">
            <div
              className={`t-dot ${i === steps.length - 1 ? "active" : ""}`}
            />
            <span
              className={`t-label ${i === steps.length - 1 ? "current" : ""}`}
              onClick={() => s.go && onJump(s.go)}
            >
              {s.label}
            </span>
          </div>
          {i < steps.length - 1 && <div className="t-line" />}
        </div>
      ))}
    </div>
  );
};
export default Thread;
