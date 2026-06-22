# Vault — Color-Coded Personal Finance Engine

> Most budget apps treat every category the same. Vault doesn't. Each envelope color defines a distinct financial behavior — how it handles savings, overspending, and month-end rollover.

[![Live App](https://img.shields.io/badge/Live%20App-money--puce--ten.vercel.app-orange?style=flat-square)](https://money-puce-ten.vercel.app/)
[![Docs](https://img.shields.io/badge/Docs-funny--florentine--523c81.netlify.app-black?style=flat-square)](https://funny-florentine-523c81.netlify.app/)

&nbsp;

[![Vault preview](public/guide.png)](https://funny-florentine-523c81.netlify.app/)

&nbsp;

## The idea

Standard budgeting tools give you categories and a limit. Vault gives each category a **color** that defines its entire financial personality:

| Color     | Type          | Behavior                                                                                                              |
| --------- | ------------- | --------------------------------------------------------------------------------------------------------------------- |
| 🟠 Orange | Unexpected    | No budget set. Reacts to spending by pulling from Main Vault.                                                         |
| 🟡 Yellow | Fluid         | Overspend → Main Vault covers it. Underspend → sweeps back automatically.                                             |
| 🔴 Red    | Pocket Money  | Underspend stays yours forever. Overspend pulls from Main Vault.                                                      |
| 🟢 Green  | Pocket Money  | Same as Red — a second color for tracking separate discretionary intents.                                             |
| 🔵 Blue   | Isolated Goal | Fully self-contained. Surplus builds a private Blue Vault. Hard-blocked if it runs dry — Main Vault is never touched. |

Two vaults run in parallel: the **Main Vault** (your safety net, always visible) and the **Blue Vault** (a private accumulation pool fed only by Blue envelope surpluses). They never interact.

&nbsp;

## Tech stack

|               |                                      |
| ------------- | ------------------------------------ |
| Framework     | Next.js 16 (App Router)              |
| Language      | TypeScript                           |
| Styling       | Tailwind CSS v4                      |
| Components    | Radix UI, Lucide React, Tabler Icons |
| State         | Zustand                              |
| Server state  | TanStack Query                       |
| Backend / DB  | Supabase (PostgreSQL)                |
| Auth          | Supabase Auth                        |
| Notifications | Sonner                               |
| Runtime       | Bun                                  |
| Deployment    | Vercel                               |

&nbsp;

## Live

**App → [https://money-puce-ten.vercel.app/](https://money-puce-ten.vercel.app/)**  
**Docs → [https://funny-florentine-523c81.netlify.app/](https://funny-florentine-523c81.netlify.app/)**

---

# Vault — Database ERD

```mermaid
erDiagram
    USERS {
        uuid id PK
    }

    BUCKET_TYPES {
        varchar type_name PK
        varchar color
        varchar vault_role "DRIP_IN | DRIP_OUT | NONE"
        varchar affects_vault "MAIN | BLUE | NONE"
        bool overspend_ok
        bool underspend_returns
        text description
    }

    BUCKET_CONFIGS {
        int bucket_id PK
        uuid user_id FK
        varchar bucket_name
        varchar display_type FK
        bool is_active
    }

    PAYCHECKS {
        uuid user_id PK
        varchar month PK "YYYY-MM"
        numeric salary "> 0"
    }

    VAULT {
        uuid user_id PK
        varchar month PK
        numeric opening_amt "≥ 0"
        numeric closing_amt "≥ 0, null = month open"
        numeric current_amt "≥ 0"
    }

    BLUE_VAULT {
        uuid user_id PK
        varchar month PK
        numeric opening_amt "≥ 0"
        numeric closing_amt "≥ 0, null = month open"
        numeric current_amt "≥ 0"
    }

    MONTHLY_ENTRIES {
        int id PK
        uuid user_id FK
        varchar month FK
        int bucket_id FK
        numeric allocated "≥ 0"
        numeric spent "≥ 0"
    }

    LEDGER {
        int ledger_id PK
        uuid user_id FK
        int bucket_id FK
        numeric amount_spent "> 0"
        varchar month FK
        date date_of_entry
        text note
        bool reversed
        int reversed_by FK "self-ref"
    }

    CASH_IN_TREASURE {
        int id PK
        uuid user_id FK
        varchar month
        int bucket_id FK
        numeric underspend_amt "> 0"
        date entry_date
    }

    CASH_IN_BLUE_TREASURE {
        int id PK
        uuid user_id FK
        varchar month
        int bucket_id FK
        numeric underspend_amt "> 0"
        date entry_date
    }

    CASH_OUT_TREASURE {
        int id PK
        uuid user_id FK
        varchar month
        int bucket_id FK
        numeric surplus_amt "> 0"
        date entry_date
    }

    CASH_OUT_BLUE_TREASURE {
        int id PK
        uuid user_id FK
        varchar month
        int bucket_id FK
        numeric surplus_amt "> 0"
        date entry_date
    }

    USERS ||--o{ BUCKET_CONFIGS : "user_id"
    USERS ||--o{ PAYCHECKS : "user_id"
    USERS ||--o{ VAULT : "user_id"
    USERS ||--o{ BLUE_VAULT : "user_id"
    USERS ||--o{ MONTHLY_ENTRIES : "user_id (also direct FK)"
    USERS ||--o{ LEDGER : "user_id (also direct FK)"
    USERS ||--o{ CASH_IN_TREASURE : "user_id (also direct FK)"
    USERS ||--o{ CASH_IN_BLUE_TREASURE : "user_id (also direct FK)"
    USERS ||--o{ CASH_OUT_TREASURE : "user_id (also direct FK)"
    USERS ||--o{ CASH_OUT_BLUE_TREASURE : "user_id (also direct FK)"

    BUCKET_TYPES ||--o{ BUCKET_CONFIGS : "display_type"

    BUCKET_CONFIGS ||--o{ MONTHLY_ENTRIES : "bucket_id"
    BUCKET_CONFIGS ||--o{ LEDGER : "bucket_id"
    BUCKET_CONFIGS ||--o{ CASH_IN_TREASURE : "bucket_id"
    BUCKET_CONFIGS ||--o{ CASH_IN_BLUE_TREASURE : "bucket_id"
    BUCKET_CONFIGS ||--o{ CASH_OUT_TREASURE : "bucket_id"
    BUCKET_CONFIGS ||--o{ CASH_OUT_BLUE_TREASURE : "bucket_id"

    PAYCHECKS ||--o{ MONTHLY_ENTRIES : "(user_id, month)"
    PAYCHECKS ||--o{ LEDGER : "(user_id, month)"

    LEDGER ||--o| LEDGER : "reversed_by"
```

## Critical constraints & triggers

1. **Write-guard trigger** — `trg_fn_require_procedure_context` fires `BEFORE INSERT OR UPDATE`
   on `vault`, `blue_vault`, `ledger`, `monthly_entries`, `paychecks`, and all four
   `cash_*_treasure` tables. Any write that doesn't originate from an approved stored
   procedure is rejected, so application code can never mutate balances directly.

2. **Money can never go negative** — every financial table carries a `CHECK` constraint:
   `opening_amt / closing_amt / current_amt / allocated / spent >= 0`, and
   `amount_spent / surplus_amt / underspend_amt > 0`.

3. **Ledger reversals are append-only** — `ledger.reversed_by` self-references
   `ledger.ledger_id`. A mistaken entry is corrected by inserting a new reversing row and
   flipping `reversed = true` on the original — never by `UPDATE`/`DELETE`.

4. **Composite FKs tie spend to an existing paycheck month** — `ledger` and
   `monthly_entries` both carry a `(user_id, month) → paychecks` foreign key, so you can't
   log a budget or expense for a month that has no income record.
