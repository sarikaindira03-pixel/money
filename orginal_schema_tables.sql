CREATE TABLE
    bucket_types (
        type_name VARCHAR(20) PRIMARY KEY,
        color VARCHAR(20) NOT NULL,
        vault_role VARCHAR(20) NOT NULL CHECK (vault_role IN ('DRIP_IN', 'DRIP_OUT', 'NONE'))
    );

INSERT INTO
    bucket_types
VALUES
    ('RED', 'red', 'NONE'),
    ('YELLOW', 'yellow', 'DRIP_IN'),
    ('ORANGE', 'orange', 'DRIP_OUT'),
    ('GREEN', 'green', 'NONE'),
    ('BLUE', 'blue', 'NONE'),
    ('RESERVE', 'grey', 'DRIP_IN');

CREATE TABLE
    public.bucket_configs (
        bucket_id SERIAL PRIMARY KEY,
        user_id uuid REFERENCES auth.users (id) ON DELETE CASCADE,
        bucket_name VARCHAR(50) NOT NULL,
        display_type VARCHAR(20) REFERENCES bucket_types (type_name),
        is_active BOOLEAN DEFAULT TRUE,
        UNIQUE (user_id, bucket_name)
    );

INSERT INTO
    bucket_configs (user_id, bucket_name, display_type)
VALUES
    (1, 'Rent', 'RED'),
    (1, 'Electricity', 'YELLOW'),
    (1, 'Savings Box', 'BLUE'),
    (1, 'Investments', 'GREEN'),
    (1, 'Emergency Fund', 'ORANGE'),
    (1, 'Salary Reserve', 'RESERVE');

CREATE TABLE
    paychecks (
        month_id SERIAL PRIMARY KEY,
        user_id uuid REFERENCES auth.users (id) ON DELETE CASCADE,
        month_label VARCHAR(20) NOT NULL, -- e.g. '2026-01'
        salary NUMERIC(12, 2) DEFAULT 0,
        UNIQUE (user_id, month_label)
    );

CREATE TABLE
    monthly_entries (
        id SERIAL PRIMARY KEY,
        user_id uuid REFERENCES auth.users (id) ON DELETE CASCADE,
        month_id INTEGER REFERENCES paychecks (month_id) ON DELETE CASCADE,
        bucket_id INTEGER REFERENCES bucket_configs (bucket_id),
        allocated NUMERIC(12, 2) DEFAULT 0,
        spent NUMERIC(12, 2) DEFAULT 0,
        UNIQUE (user_id, month_id, bucket_id)
    );

CREATE TABLE
    ledger_entries (
        id SERIAL PRIMARY KEY,
        user_id uuid REFERENCES auth.users (id) ON DELETE CASCADE,
        monthly_entry_id INTEGER REFERENCES monthly_entries (id) ON DELETE CASCADE,
        bucket_id INTEGER REFERENCES bucket_configs (bucket_id),
        vault_wd_id INTEGER REFERENCES vault_withdrawals (id),
        vault_credit_id INTEGER REFERENCES vault_entries (id),
        amount NUMERIC(12, 2) NOT NULL,
        txn_type VARCHAR(20) NOT NULL -- SPEND, CONTRIBUTION, VAULT_CREDIT, VAULT_WITHDRAWAL
    );

CREATE TABLE
    vault_entries (
        id SERIAL PRIMARY KEY,
        user_id uuid REFERENCES auth.users (id) ON DELETE CASCADE,
        month_id INTEGER REFERENCES paychecks (month_id),
        bucket_id INTEGER REFERENCES bucket_configs (bucket_id),
        total_drip NUMERIC(12, 2) DEFAULT 0
    );

CREATE TABLE
    vault_withdrawals (
        id SERIAL PRIMARY KEY,
        user_id uuid REFERENCES auth.users (id) ON DELETE CASCADE,
        month_id INTEGER REFERENCES paychecks (month_id),
        bucket_id INTEGER REFERENCES bucket_configs (bucket_id), -- System-filled
        target_bucket_id INTEGER REFERENCES bucket_configs (bucket_id),
        total_amount NUMERIC(12, 2) NOT NULL,
        withdrawal_date TIMESTAMP DEFAULT NOW ()
    );

CREATE TABLE
    vault_withdrawal_sources (
        id SERIAL PRIMARY KEY,
        withdrawal_id INTEGER REFERENCES vault_withdrawals (id) ON DELETE CASCADE,
        vault_entry_id INTEGER REFERENCES vault_entries (id),
        amount_taken NUMERIC(12, 2) NOT NULL
    );

CREATE TABLE
    treasure (
        id SERIAL PRIMARY KEY,
        user_id uuid REFERENCES auth.users (id) ON DELETE CASCADE,
        month_id INTEGER REFERENCES paychecks (month_id),
        amount NUMERIC(12, 2) NOT NULL,
        status VARCHAR(20) DEFAULT 'AVAILABLE' CHECK (status IN ('AVAILABLE', 'USED')),
        absorbed_by_month_id INTEGER REFERENCES paychecks (month_id) -- FIX: Memory Trace
    );

-- VIEWS
CREATE VIEW
    public.user_budget_summary AS
SELECT
    u.name,
    p.month_label,
    bc.bucket_name,
    me.allocated,
    me.spent,
    (me.allocated - me.spent) as remaining
FROM
    public.monthly_entries me
    JOIN auth.users u ON u.id = me.user_id
    JOIN public.paychecks p ON p.month_id = me.month_id
    JOIN public.bucket_configs bc ON bc.bucket_id = me.bucket_id;