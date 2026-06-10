// "use client";

// import { useState } from "react";
// import { useRouter } from "next/navigation";
// import useNavigationStore from "../../store/zustand";
// import { mid1label } from "../../lib/formats";
// import { usePaychecksByYear } from "@/src/hooks/paychecks/usePaychecksByYear";
// import { useAddExtraIncome } from "@/src/hooks/paychecks/useOptIncomeEntry";

// interface MonthViewProps {
//   year: string | number;
// }

// interface IncomeFormState {
//   sourceName: string;
//   amount: string;
//   submitting: boolean;
//   error: string | null;
// }

// const defaultForm: IncomeFormState = {
//   sourceName: "",
//   amount: "",
//   submitting: false,
//   error: null,
// };

// const MonthView = ({ year }: MonthViewProps) => {
//   const router = useRouter();
//   const setNavigation = useNavigationStore((s) => s.setNavigation);
//   const { paychecks, isLoading, isError } = usePaychecksByYear(year);
//   const { addEIncome } = useAddExtraIncome(); // year passed here for invalidation
//   const [expandedMonth, setExpandedMonth] = useState<string | null>(null);
//   const [form, setForm] = useState<IncomeFormState>(defaultForm);

//   const toggleAccordion = (month: string, e: React.MouseEvent) => {
//     e.stopPropagation();
//     setExpandedMonth((prev) => (prev === month ? null : month));
//     setForm(defaultForm);
//   };

//   const handleMonthClick = (month: string) => {
//     setNavigation({ screen: "buckets", year: String(year), monthId: month });
//     router.push(`/month/${month}`);
//   };

//   const handleSubmit = async (month: string, e: React.MouseEvent) => {
//     e.stopPropagation();

//     if (!form.sourceName.trim())
//       return setForm((f) => ({ ...f, error: "Source name is required." }));
//     if (!form.amount || Number(form.amount) <= 0)
//       return setForm((f) => ({ ...f, error: "Enter a valid amount." }));

//     setForm((f) => ({ ...f, submitting: true, error: null }));

//     try {
//       await addEIncome({
//         month,
//         source_name: form.sourceName.trim(),
//         amount: Number(form.amount),
//       });
//       setExpandedMonth(null);
//       setForm(defaultForm);
//     } catch (error) {
//       const errMsg =
//         (error as any)?.response?.data?.message ??
//         (error as Error)?.message ??
//         "Something went wrong.";
//       setForm((f) => ({ ...f, error: errMsg }));
//     } finally {
//       setForm((f) => ({ ...f, submitting: false }));
//     }
//   };

//   if (isLoading) return <div className="lv-sub">Loading months...</div>;
//   if (isError)
//     return <div className="lv-sub text-red-500">Error loading data</div>;

//   return (
//     <div>
//       <header>
//         <h1 className="lv-h1">Pick a month</h1>
//         <div className="lv-sub">
//           {paychecks.length} {paychecks.length === 1 ? "month" : "months"}{" "}
//           logged
//         </div>
//       </header>

//       <div className="rlist">
//         {paychecks.length > 0 ? (
//           paychecks.map((p) => {
//             const isOpen = expandedMonth === p.month;
//             return (
//               <div key={p.month} className="rrow-wrapper">
//                 <div
//                   className="rrow"
//                   onClick={() => handleMonthClick(p.month)}
//                   style={{
//                     borderBottom: isOpen
//                       ? "0.5px solid var(--color-border-tertiary)"
//                       : "none",
//                   }}
//                 >
//                   <div className="rrow-l">
//                     <div className="rrow-name">{mid1label(p.month)}</div>
//                   </div>
//                   {p.is_month_open && (
//                     <button
//                       onClick={(e) => toggleAccordion(p.month, e)}
//                       style={{ fontSize: 12 }}
//                     >
//                       {isOpen ? "✕ Cancel" : "+ Extra income"}
//                     </button>
//                   )}
//                 </div>

//                 {isOpen && (
//                   <div
//                     className="accordion-panel"
//                     onClick={(e) => e.stopPropagation()}
//                   >
//                     <input
//                       type="text"
//                       placeholder="Source name (e.g. Freelance, Bonus)"
//                       value={form.sourceName}
//                       onChange={(e) =>
//                         setForm((f) => ({ ...f, sourceName: e.target.value }))
//                       }
//                       autoFocus
//                     />
//                     <input
//                       type="number"
//                       placeholder="Amount"
//                       min={1}
//                       value={form.amount}
//                       onChange={(e) =>
//                         setForm((f) => ({ ...f, amount: e.target.value }))
//                       }
//                     />
//                     {form.error && (
//                       <p
//                         className="text-red-500"
//                         style={{ margin: 0, fontSize: 13 }}
//                       >
//                         {form.error}
//                       </p>
//                     )}
//                     <button
//                       onClick={(e) => handleSubmit(p.month, e)}
//                       disabled={form.submitting}
//                       style={{ alignSelf: "flex-end" }}
//                     >
//                       {form.submitting ? "Adding…" : "Add income"}
//                     </button>
//                   </div>
//                 )}
//               </div>
//             );
//           })
//         ) : (
//           <div className="empty">NO MONTHS LOGGED FOR {year}</div>
//         )}
//       </div>
//     </div>
//   );
// };

// export default MonthView;

"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import useNavigationStore from "../../store/zustand";
import { mid1label } from "../../lib/formats";
import { usePaychecksByYear } from "@/src/hooks/paychecks/usePaychecksByYear";
import { useOptIncomeEntry } from "@/src/hooks/paychecks/useOptIncomeEntry";
import { useIncomeEntries } from "@/src/hooks/IncomeEntries/useIncomeEntries";

interface MonthViewProps {
  year: string | number;
}

interface IncomeFormState {
  sourceName: string;
  amount: string;
  submitting: boolean;
  error: string | null;
}

const defaultForm: IncomeFormState = {
  sourceName: "",
  amount: "",
  submitting: false,
  error: null,
};

// ─── Accordion row (one per month) ───────────────────────────────────────────
const MonthRow = ({
  p,
  onMonthClick,
}: {
  p: any;
  onMonthClick: (month: string) => void;
}) => {
  const [isOpen, setIsOpen] = useState(false);
  const [form, setForm] = useState<IncomeFormState>(defaultForm);
  const [removingSource, setRemovingSource] = useState<string | null>(null);

  const { entries, isLoading: loadingEntries } = useIncomeEntries(
    p.month,
    isOpen,
  );
  const { mutateAsync, isMutating } = useOptIncomeEntry();
  // const { removeEIncome, isRemovingEIncome } = useRemoveExtraIncome();

  const handleToggle = (e: React.MouseEvent) => {
    e.stopPropagation();
    setIsOpen((prev) => !prev);
    setForm(defaultForm);
  };

  const handleSubmit = async (e: React.MouseEvent) => {
    e.stopPropagation();

    if (!form.sourceName.trim())
      return setForm((f) => ({ ...f, error: "Source name is required." }));
    if (!form.amount || Number(form.amount) <= 0)
      return setForm((f) => ({ ...f, error: "Enter a valid amount." }));

    setForm((f) => ({ ...f, submitting: true, error: null }));
    try {
      await mutateAsync({
        procedure: "add_income",
        month: p.month,
        source_name: form.sourceName.trim(),
        amount: Number(form.amount),
      });
      setForm(defaultForm);
    } catch (error) {
      const errMsg =
        (error as any)?.response?.data?.error ??
        (error as Error)?.message ??
        "Something went wrong.";
      setForm((f) => ({ ...f, error: errMsg }));
    } finally {
      setForm((f) => ({ ...f, submitting: false }));
    }
  };

  const handleRemove = async (e: React.MouseEvent, sourceName: string) => {
    e.stopPropagation();
    setRemovingSource(sourceName);
    try {
      await mutateAsync({
        procedure: "remove_income",
        month: p.month,
        source_name: sourceName,
      });
    } catch (error) {
      const errMsg =
        (error as any)?.response?.data?.error ??
        (error as Error)?.message ??
        "Remove failed.";
      // surface error inline on the entry row (optional: add per-row error state if needed)
      console.error(errMsg);
    } finally {
      setRemovingSource(null);
    }
  };

  return (
    <div className="rrow-wrapper">
      {/* Main row — click body → navigate, click chevron → toggle */}
      <div
        className="rrow"
        onClick={() => onMonthClick(p.month)}
        style={{
          borderBottom: isOpen
            ? "0.5px solid var(--color-border-tertiary)"
            : "none",
        }}
      >
        <div className="rrow-l">
          <div className="rrow-name">{mid1label(p.month)}</div>
        </div>
        <button
          onClick={handleToggle}
          style={{ fontSize: 12 }}
          aria-label={isOpen ? "Collapse" : "Expand"}
        >
          {isOpen ? "▲" : "▼"}
        </button>
      </div>

      {/* Accordion panel */}
      {isOpen && (
        <div className="accordion-panel" onClick={(e) => e.stopPropagation()}>
          {/* Income breakdown list */}
          {loadingEntries ? (
            <p
              style={{
                fontSize: 13,
                color: "var(--color-text-secondary)",
                margin: 0,
              }}
            >
              Loading...
            </p>
          ) : entries.length === 0 ? (
            <p
              style={{
                fontSize: 13,
                color: "var(--color-text-secondary)",
                margin: 0,
              }}
            >
              No income entries found.
            </p>
          ) : (
            <ul className="income-entry-list">
              {entries.map((entry: any) => {
                const isPrimary = entry.source_name === "Primary Income";
                const isRemoving = removingSource === entry.source_name;
                return (
                  <li key={entry.source_name} className="income-entry-row">
                    <div className="income-entry-info">
                      <span className="income-entry-source">
                        {entry.source_name} =
                      </span>
                      {/* {isPrimary && (
                        <span className="income-entry-badge">core</span>
                      )} */}
                    </div>
                    <div className="income-entry-right">
                      <span className="income-entry-amount">
                        ₹{Number(entry.amount).toLocaleString("en-IN")}
                      </span>
                      {/* Remove button — only for non-primary, only for open months */}
                      {p.is_month_open && !isPrimary && (
                        <button
                          className="income-entry-remove"
                          onClick={(e) => handleRemove(e, entry.source_name)}
                          disabled={isRemoving || isMutating}
                          aria-label={`Remove ${entry.source_name}`}
                        >
                          {isRemoving ? "…" : "✕"}
                        </button>
                      )}
                    </div>
                  </li>
                );
              })}
            </ul>
          )}

          {/* Add income form — only for open months */}
          {p.is_month_open && (
            <div className="add-income-form">
              <input
                type="text"
                placeholder="Source name"
                value={form.sourceName}
                onChange={(e) =>
                  setForm((f) => ({ ...f, sourceName: e.target.value }))
                }
              />
              <input
                type="number"
                placeholder="Amount"
                min={1}
                value={form.amount}
                onChange={(e) =>
                  setForm((f) => ({ ...f, amount: e.target.value }))
                }
              />
              {form.error && (
                <p className="text-red-500" style={{ margin: 0, fontSize: 13 }}>
                  {form.error}
                </p>
              )}
              <button
                onClick={handleSubmit}
                disabled={form.submitting}
                className="btn"
                style={{ cursor: "pointer", whiteSpace: "nowrap" }}
              >
                {form.submitting ? "Adding…" : "Add Income"}
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  );
};

// ─── Parent ───────────────────────────────────────────────────────────────────
const MonthView = ({ year }: MonthViewProps) => {
  const router = useRouter();
  const setNavigation = useNavigationStore((s) => s.setNavigation);
  const { paychecks, isLoading, isError } = usePaychecksByYear(year);

  const handleMonthClick = (month: string) => {
    setNavigation({ screen: "buckets", year: String(year), monthId: month });
    router.push(`/month/${month}`);
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
            <MonthRow key={p.month} p={p} onMonthClick={handleMonthClick} />
          ))
        ) : (
          <div className="empty">NO MONTHS LOGGED FOR {year}</div>
        )}
      </div>
    </div>
  );
};

export default MonthView;
