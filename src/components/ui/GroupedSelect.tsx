// src/components/ui/GroupedSelect.tsx

"use client";

import * as Select from "@radix-ui/react-select";
import { ChevronDown, Check } from "lucide-react";

type GroupItem = {
  label: string;
  value: string;
};

type Group = {
  label: string;
  items: GroupItem[];
};

type GroupedSelectProps = {
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
  groups: Group[];
  className?: string;
};

const GroupedSelect = ({
  value,
  onChange,
  placeholder = "Select option",
  groups,
  className = "",
}: GroupedSelectProps) => {
  return (
    <Select.Root value={value} onValueChange={onChange}>
      <Select.Trigger
        className={`border px-3 py-2 rounded flex items-center justify-between w-62.5 ${className}`}
      >
        <Select.Value placeholder={placeholder} />

        <Select.Icon>
          <ChevronDown size={16} />
        </Select.Icon>
      </Select.Trigger>

      <Select.Portal>
        <Select.Content className="bg-black border rounded shadow-md overflow-hidden z-50">
          <Select.Viewport className="p-1">
            {groups.map((group) => (
              <div key={group.label}>
                <div className="px-2 py-1 text-xs opacity-60">
                  {group.label}
                </div>

                {group.items.map((item) => (
                  <Select.Item
                    key={item.value}
                    value={item.value}
                    className="px-2 py-2 rounded cursor-pointer outline-none hover:bg-neutral-800 flex items-center justify-between"
                  >
                    <Select.ItemText>{item.label}</Select.ItemText>

                    <Select.ItemIndicator>
                      <Check size={14} />
                    </Select.ItemIndicator>
                  </Select.Item>
                ))}
              </div>
            ))}
          </Select.Viewport>
        </Select.Content>
      </Select.Portal>
    </Select.Root>
  );
};

export default GroupedSelect;
