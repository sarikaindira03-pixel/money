"use client";
import { useState } from "react";
import { AxiosError } from "axios";
import MonthYearPicker from "../Calendar/MonthYearPicker";
import { useCreatePaycheck } from "@/src/hooks/paychecks/useCreatePaycheck";
import { DEFAULT_SALARY } from "@/src/utils/constants";
import { useQueryClient } from "@tanstack/react-query";
import { qk } from "@/src/lib/cache/keys";
export const YearForm = () => {
  const { createPaycheck, isCreating } = useCreatePaycheck();

  const queryClient = useQueryClient();
  const [isAdding, setIsAdding] = useState<boolean>(false);
  const [selectedMonth, setSelectedMonth] = useState<string>("");
  const [salaryInput, setSalaryInput] = useState<string>(DEFAULT_SALARY);

  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const resetForm = () => {
    setIsAdding(false);
    setSelectedMonth("");
    setSalaryInput(DEFAULT_SALARY);
    setErrorMessage(null);
  };

  const handleSubmit = async () => {
    setErrorMessage(null);
    if (!selectedMonth || !salaryInput) return;
    // 1. Fetch the authenticated user dynamically

    try {
      await createPaycheck({
        month: selectedMonth,
        total_income: Number(salaryInput),
      });
      resetForm();
      queryClient.invalidateQueries({ queryKey: qk("paychecks") });
    } catch (error) {
      const axiosError = error as AxiosError<{
        message?: string;
        error?: string;
      }>;
      const errMsg =
        axiosError.response?.data?.message ||
        axiosError.response?.data?.error ||
        axiosError.message ||
        "";

      if (errMsg.includes("already exists") || errMsg.includes("P0001")) {
        setErrorMessage(`Paycheck for ${selectedMonth} already exists.`);
      } else {
        setErrorMessage(errMsg || "Failed to create paycheck.");
      }
    }
  };

  if (!isAdding) {
    return (
      <div className="brow" style={{ marginTop: 20 }}>
        <button className="btn btn-w" onClick={() => setIsAdding(true)}>
          New Entry
        </button>
      </div>
    );
  }

  return (
    <div
      className="brow"
      style={{
        marginTop: 20,
        display: "flex",
        gap: 12,
        flexWrap: "wrap",
        alignItems: "end",
      }}
    >
      <div>
        <label className="lv-label">Month</label>
        <MonthYearPicker value={selectedMonth} onChange={setSelectedMonth} />
      </div>

      <div>
        <label className="lv-label">Salary</label>
        <input
          className="input-std"
          type="number"
          min="0"
          value={salaryInput}
          onChange={(e) => setSalaryInput(e.target.value)}
          onKeyDown={(e) => e.key === "-" && e.preventDefault()}
          placeholder="Salary"
          style={{ width: 160 }}
        />
      </div>

      <div style={{ display: "flex", gap: 10 }}>
        <button
          className={`btn ${errorMessage ? "btn-ghost" : "btn-w"}`}
          onClick={handleSubmit}
          disabled={!selectedMonth || isCreating}
        >
          {isCreating ? "Creating..." : "Create"}
        </button>
        <button className="btn btn-ghost" onClick={resetForm}>
          Cancel
        </button>
      </div>

      {errorMessage && (
        <div
          style={{
            color: "#ff4d4d",
            fontSize: "13px",
            marginTop: "8px",
            fontWeight: "500",
          }}
        >
          {errorMessage}
        </div>
      )}
    </div>
  );
};
