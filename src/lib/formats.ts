import { MONTHS_SHORT } from "../utils/constants";

export const fmt = new Intl.NumberFormat("en-IN", {
  style: "currency",
  currency: "INR",
  maximumFractionDigits: 0,
}).format;
// const fmtSgn = (n: number): string => (n < 0 ? "−" : "") + fmt(n);
export const mid2label = (mid: string): string => {
  const [y, m] = mid.split("-");
  return `${MONTHS_SHORT[+m - 1]} ${y}`;
};
export const mid1label = (mid: string): string => {
  const [y, m] = mid.split("-");
  return `${MONTHS_SHORT[+m - 1]} `;
};

export const year_num = (mid: string): number => {
  const [y, m] = mid.split("-");
  return Number(y);
  //2026-01 as 2026 , 2026-10 as 2026
};
export const today = (): string => new Date().toISOString().slice(0, 10);
export const uid = (): string =>
  Date.now() + Math.random().toString(36).slice(2);

export function formatCurrency(amount: number | string): string {
  const num = typeof amount === "string" ? parseFloat(amount) : amount;

  return new Intl.NumberFormat("en-IN", {
    style: "currency",
    currency: "INR",
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(num);
}

export const isYearFormat = (param: string) => /^\d{4}$/.test(param);
export const isMonthFormat = (param: string) => /^\d{4}-\d{2}$/.test(param);
