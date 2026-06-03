"use client";

import { useState, useEffect } from "react";

interface SalaryEditorProps {
  currentSalary: number;
  isUpdating: boolean;
  onSave: (newSalary: number) => Promise<void>;
}

export const SalaryEditor = ({
  currentSalary,
  isUpdating,
  onSave,
}: SalaryEditorProps) => {
  const [isEditing, setIsEditing] = useState(false);
  const [value, setValue] = useState(currentSalary);

  // Keep local state in sync if external data changes
  useEffect(() => {
    setValue(currentSalary);
  }, [currentSalary]);

  const handleSave = async () => {
    if (value === currentSalary) {
      setIsEditing(false);
      return;
    }
    await onSave(value);
    setIsEditing(false);
  };

  if (isEditing) {
    return (
      <div className="form-box bg-white/5 p-6 rounded-lg animate-in fade-in duration-300">
        <label className="text-xs uppercase opacity-50 mb-2 block tracking-widest">
          Update Monthly Salary
        </label>
        <input
          type="number"
          min="0"
          value={value}
          onChange={(e) => {
            const val = parseFloat(e.target.value);
            if (val >= 0 || e.target.value === "") setValue(val);
          }}
          className="bg-transparent border-b border-white/20 text-2xl outline-none w-full py-2 mb-6"
          autoFocus
        />
        <div className="flex gap-4">
          <button
            className="btn btn-w btn-sm"
            onClick={handleSave}
            disabled={isUpdating}
          >
            {isUpdating ? "Saving..." : "Save Changes"}
          </button>
          <button
            className="btn btn-ghost btn-sm"
            onClick={() => setIsEditing(false)}
          >
            Cancel
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="flex justify-between items-center bg-white/5 p-4 rounded-lg border border-white/5 hover:border-white/10 transition-colors">
      <div>
        <div className="text-xs opacity-50 uppercase tracking-widest">
          Base Salary
        </div>
        <div className="text-xl font-medium">
          ₹ {currentSalary.toLocaleString()}
        </div>
      </div>
      <button
        className="btn btn-ghost btn-sm"
        onClick={() => setIsEditing(true)}
      >
        Edit Salary
      </button>
    </div>
  );
};
