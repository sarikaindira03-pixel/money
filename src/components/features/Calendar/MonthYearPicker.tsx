"use client";

import { useState, useRef, useEffect } from "react";
import { MONTHS_SHORT } from "../../../utils/constants";

const MonthYearPicker = ({
  value,
  onChange,
}: {
  value: string; // "YYYY-MM"
  onChange: (val: string) => void;
}) => {
  const currentYear = new Date().getFullYear();
  const [open, setOpen] = useState(false);
  const [viewYear, setViewYear] = useState(() => {
    return value ? parseInt(value.split("-")[0]) : currentYear;
  });
  const ref = useRef<HTMLDivElement>(null);

  const selectedYear = value ? parseInt(value.split("-")[0]) : null;
  const selectedMonth = value ? parseInt(value.split("-")[1]) - 1 : null;

  useEffect(() => {
    const handler = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) {
        setOpen(false);
      }
    };
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, []);

  const handleSelect = (monthIndex: number) => {
    const mm = String(monthIndex + 1).padStart(2, "0");
    onChange(`${viewYear}-${mm}`);
    setOpen(false);
  };

  const displayLabel =
    selectedYear !== null && selectedMonth !== null
      ? `${MONTHS_SHORT[selectedMonth]} ${selectedYear}`
      : "Select month";

  return (
    <div ref={ref} style={{ position: "relative", width: 180 }}>
      <button
        type="button"
        className="input-std"
        onClick={() => setOpen((o) => !o)}
        style={{
          width: "100%",
          textAlign: "left",
          cursor: "pointer",
          display: "flex",
          justifyContent: "space-between",
          alignItems: "center",
        }}
      >
        <span style={{ color: value ? "inherit" : "#888" }}>
          {displayLabel}
        </span>
        <span style={{ fontSize: 10, opacity: 0.5 }}>▼</span>
      </button>

      {open && (
        <div
          style={{
            position: "absolute",
            top: "calc(100% + 4px)",
            left: 0,
            zIndex: 100,
            backgroundColor: "#111111", // Added solid dark background
            color: "#ffffff", // Text color to white for contrast
            border: "1px solid #333333", // Adjusted border to match dark mode
            borderRadius: 10,
            padding: "12px",
            width: 220,
            boxShadow: "0 4px 20px rgba(0,0,0,0.50)", // Enhanced shadow for depth
          }}
        >
          {/* Year row */}
          <div
            style={{
              display: "flex",
              alignItems: "center",
              justifyContent: "space-between",
              marginBottom: 10,
            }}
          >
            <button
              type="button"
              onClick={() => setViewYear((y) => y - 1)}
              style={{
                background: "none",
                border: "none",
                cursor: "pointer",
                fontSize: 18,
                lineHeight: 1,
                padding: "2px 8px",
                borderRadius: 6,
                color: "#ffffff", // Arrow color white
              }}
            >
              ‹
            </button>
            <span style={{ fontWeight: 600, fontSize: 15 }}>{viewYear}</span>
            <button
              type="button"
              onClick={() => setViewYear((y) => y + 1)}
              style={{
                background: "none",
                border: "none",
                cursor: "pointer",
                fontSize: 18,
                lineHeight: 1,
                padding: "2px 8px",
                borderRadius: 6,
                color: "#ffffff", // Arrow color white
              }}
            >
              ›
            </button>
          </div>

          {/* Month grid */}
          <div
            style={{
              display: "grid",
              gridTemplateColumns: "repeat(3, 1fr)",
              gap: 6,
            }}
          >
            {MONTHS_SHORT.map((m, i) => {
              const isSelected =
                selectedMonth === i && selectedYear === viewYear;
              return (
                <button
                  key={m}
                  type="button"
                  onClick={() => handleSelect(i)}
                  style={{
                    padding: "7px 4px",
                    borderRadius: 7,
                    border: "none",
                    cursor: "pointer",
                    fontSize: 13,
                    fontWeight: isSelected ? 600 : 400,
                    // Highlighted month gets a distinct gray/white layout
                    background: isSelected ? "#ffffff" : "transparent",
                    color: isSelected ? "#111111" : "#ffffff",
                    transition: "background 0.12s",
                  }}
                  onMouseEnter={(e) => {
                    if (!isSelected) {
                      // Hover color updated to a nice dark-gray instead of light-gray
                      (e.target as HTMLElement).style.background = "#2a2a2a";
                    }
                  }}
                  onMouseLeave={(e) => {
                    if (!isSelected) {
                      (e.target as HTMLElement).style.background =
                        "transparent";
                    }
                  }}
                >
                  {m}
                </button>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
};

export default MonthYearPicker;
