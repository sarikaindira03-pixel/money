🔸 Orange | Ad-Hoc Contingency
Concept: Purely unexpected, unbudgeted drains.

Data Constraints: Initial Allocated = 0. At runtime, Allocated dynamically updates to match Spend.

Balance Resolution: 100% of the funds are pulled directly from the Main Vault at the moment of the transaction. No variance (Spend - Allocated = 0) is ever generated.

🟡 Yellow | Absorptive Fluid Budget
Concept: Standard flexible budgeting where the Main Vault cushions errors and absorbs victories.

Surplus Handling (Spend < Allocated): The leftover amount is automatically "swept" and flushed back into the Main Vault at the end of the tracking cycle.

Deficit Handling (Spend > Allocated): The system treats this as a short-fall and dynamically pulls the difference from the Main Vault.

🔴🟢 Red & Green | Pocket Money (Discretionary Cash)
Concept: Hand-off cash. Once allocated, the system drops tracking responsibility for surpluses.

Schema & Frontend Separation: Both share the exact same database table design and backend logic. They are split strictly at the presentation layer (UI) via a color metadata tag for tracking distinct user intents.

Surplus Handling (Spend < Allocated): The leftover money does not move in the database. It is treated as "liquid cash in the user's physical pocket." The system zeroes out its accountability for this surplus—it stays out in the wild.

Deficit Handling (Spend > Allocated): If the user overspends this physical boundary, the system acts as an emergency backstop and draws the deficit from the Main Vault.

🔹 Blue | Isolated Sinking Ecosystem
Concept: Self-sustaining sub-ledgers (e.g., long-term savings pools, vehicle maintenance buckets).

The Blue Vault Mechanics: A single global pool or array of balances derived entirely from historical Blue-category surpluses (Sum(Allocated - Spend)).

Surplus Handling (Spend < Allocated): Leftover amounts are securely routed away from the Main Vault and appended directly to the Blue Vault balance.

Deficit & Insolvency Handling (Spend > Allocated): The system attempts to draw the deficit from the accumulating Blue Vault.

The Hard Stop Rule: If Deficit > Blue Vault Balance, the system rejects the transaction. The operation fails safely using ACID database properties (Atomicity ensures no partial state writes occur), throwing a structural error back to the application layer.

---

System Limitations & Hard Boundaries (Crucial for Frontend Safety)
When you design the frontend inputs and validation logic, you must strictly enforce these five boundaries so the UI doesn't crash against your database rules:

The Blue Vault Insolvency Rule:

The Boundary: A user cannot add a Blue transaction if the overspend amount exceeds the current total balance of the Blue Vault.

Frontend Handling: Before the user hits "Submit" on a Blue transaction, calculate Current Blue Vault + Current Bucket Balance. If the transaction exceeds this, disable the button and show an error: "Transaction Blocked: Your Blue Vault has insufficient funds to cover this overage ($X short)."

The Main Vault Drain Guard:

The Boundary: For Yellow, Red, Green, and Orange buckets, overspending pulls instantly from the Main Vault. If the Main Vault runs out of money, the database rejects the transaction.

Frontend Handling: Check the user's Main Vault balance. If a transaction's deficit is larger than the available vault cash, give a clear alert: "Insufficient funds in Main Vault to cover this expense."

The Orange Zero-Start:

The Boundary: Orange buckets cannot have an initial allocated budget.

Frontend Handling: In your "Create a Budget Setup" form, if a user selects the color Orange, gray out/disable the "Allocated Amount" text input field and lock it to $0.

Red vs. Green is Purely Visual:

The Boundary: Under the hood, Red and Green share identical programmatic logic.

Frontend Handling: Use Red for "guilt-free personal expenses" and Green for "discretionary investments or targeted short-term habits". They are grouped together in your ledger logic, so use them purely to help the user visually organize their "pocket money."

Historical Integrity (The Month Barrier):

The Boundary: Because your database relies heavily on the snapshot of a specific month linked to paychecks and monthly_entries, altering old data will mess up historical vault balances.

Frontend Handling: Lock past months from editing unless the user explicitly enters an "Advanced/Override Mode."

💡 Frontend UI Tips for Success:
Show the Vaults constantly: Put a prominent sticky header or widget showing the current Main Vault Balance and Blue Vault Balance. This makes the color feedback loops instantly rewarding to look at.

Visualizing Triggers: When a user types a number into a Yellow bucket that exceeds their budget, show a live micro-copy indicator: "⚠️ Will draw $20 from Main Vault." If they do it on a Blue bucket: "🔹 Will draw $20 from Blue Vault Accumulation."
