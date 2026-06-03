interface FlowNoticeProps {
  type?: "info" | "warn" | "over" | "good";
  children: React.ReactNode;
}

const FlowNotice = ({ type = "info", children }: FlowNoticeProps) => {
  return <div className={`flow-notice ${type}`}>{children}</div>;
};
export default FlowNotice;
