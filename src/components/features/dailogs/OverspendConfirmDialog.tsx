// components/OverspendConfirmDialog.tsx
"use client";
// Optional: Create a new endpoint
// POST /api/ledger/preview-overspend
// // Returns:
// {
//   willOverspend: true,
//   overspendAmount: 1200,
//   vaultCurrent: 77300,
//   vaultAfter: 76100,
//   ...
// }
import { formatCurrency } from "@/src/lib/formats";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "../../ui/alert-dialog";

interface OverspendConfirmDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  bucketName: string;
  allocated: number;
  currentSpent: number;
  newAmount: number;
  vaultCurrent: number;
  onConfirm: () => void;
  onCancel?: () => void;
}

export default function OverspendConfirmDialog({
  open,
  onOpenChange,
  bucketName,
  allocated,
  currentSpent,
  newAmount,
  vaultCurrent,
  onConfirm,
  onCancel,
}: OverspendConfirmDialogProps) {
  const newTotalSpent = currentSpent + newAmount;
  const overspend = Math.max(0, newTotalSpent - allocated);
  const vaultAfter = vaultCurrent - overspend;

  return (
    <AlertDialog open={open} onOpenChange={onOpenChange}>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle className="text-destructive">
            Confirm Overspending
          </AlertDialogTitle>
          <AlertDialogDescription className="space-y-4">
            <p>
              You are spending more than allocated in{" "}
              <strong>{bucketName}</strong>.
            </p>

            <div className="bg-muted p-4 rounded-lg text-sm space-y-1.5">
              <div className="flex justify-between">
                <span>Allocated:</span>
                <span>{formatCurrency(allocated)}</span>
              </div>
              <div className="flex justify-between">
                <span>Already Spent:</span>
                <span>{formatCurrency(currentSpent)}</span>
              </div>
              <div className="flex justify-between border-t pt-2 font-medium">
                <span>New Total:</span>
                <span>{formatCurrency(newTotalSpent)}</span>
              </div>
              <div className="flex justify-between text-destructive font-medium">
                <span>Overspend:</span>
                <span>{formatCurrency(overspend)}</span>
              </div>
            </div>

            <div className="bg-amber-50 border border-amber-200 p-4 rounded-lg">
              <p className="font-medium text-amber-800 mb-2">
                Impact on Main Vault:
              </p>
              <div className="flex justify-between text-sm">
                <span>Current Vault Balance:</span>
                <span>{formatCurrency(vaultCurrent)}</span>
              </div>
              <div className="flex justify-between font-semibold text-amber-900">
                <span>Balance After:</span>
                <span>{formatCurrency(vaultAfter)}</span>
              </div>
            </div>
          </AlertDialogDescription>
        </AlertDialogHeader>

        <AlertDialogFooter>
          <AlertDialogCancel onClick={onCancel}>Cancel</AlertDialogCancel>
          <AlertDialogAction
            onClick={onConfirm}
            className="bg-destructive hover:bg-destructive/90"
          >
            Yes, Deduct ₹{overspend.toFixed(2)} from Vault
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}
