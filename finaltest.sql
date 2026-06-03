-- 
-- a240aa31-9303-41d1-9caf-a3389dedfd99
-- 2 (bucket_name,display_type)= Rent RED
-- 3 (bucket_name,display_type)= Loan EMI  RED
-- 4 (bucket_name,display_type)= Groceries YELLOW
-- 5 (bucket_name,display_type)= OTT Subs YELLOW
-- 6 (bucket_name,display_type)= Emergency SIP GREEN
-- 7 (bucket_name,display_type)= Gadget Fund BLUE
-- 8 (bucket_name,display_type)= Misc Surprises ORANGE
-- 9 (bucket_name,display_type)= Vacation Fund BLUE
CALL record_paycheck (
    'a240aa31-9303-41d1-9caf-a3389dedfd99',
    '2026-02',
    90000
)
-- === BUDGET ALLOCATION ===
CALL allocate_blue_bucket (
    'a240aa31-9303-41d1-9caf-a3389dedfd99',
    '2026-02',
    9,
    4000
);

CALL allocate_blue_bucket (
    'a240aa31-9303-41d1-9caf-a3389dedfd99',
    '2026-02',
    7,
    1000
);

CALL allocate_bucket (
    'a240aa31-9303-41d1-9caf-a3389dedfd99',
    '2026-01',
    2,
    10000
);

-- === LEDGER ENTRY ===
CALL record_blue_ledger_entry (
    'a240aa31-9303-41d1-9caf-a3389dedfd99',
    9,
    3000,
    '2026-02',
    '2026-02-16',
    'RJY  Bus  Trip'
);

CALL record_blue_ledger_entry (
    'a240aa31-9303-41d1-9caf-a3389dedfd99',
    7,
    2500,
    '2026-01',
    '2026-02-18',
    'Gadget'
);

-- CALL close_month('a240aa31-9303-41d1-9caf-a3389dedfd99','2026-01');
SELECT
    *
FROM
    paychecks
    -- CALL record_ledger_entry('a240aa31-9303-41d1-9caf-a3389dedfd99',2,12000,'2026-01','2026-01-02','Second payment');
    CALL record_ledger_entry (
        'a240aa31-9303-41d1-9caf-a3389dedfd99',
        2,
        6000,
        '2026-01',
        '2026-01-02',
        'initial payment'
    );

SELECT
    allocated
FROM
    monthly_entries
WHERE
    user_id = 'a240aa31-9303-41d1-9caf-a3389dedfd99'
    AND month = '2026-01'
    AND bucket_id = 1
SELECT
    *
FROM
    blue_vault me
WHERE
    me.user_id = 'a240aa31-9303-41d1-9caf-a3389dedfd99'
    AND me.month = '2026-01'
    AND bc.display_type = 'BLUE';

SELECT
    *
FROM
    monthly_entries
SELECT
    *
FROM
    bucket_configs
SELECT
    *
FROM
    blue_vault
    -- op:14000, ca:3500
    -- op:3500, ca:3500
    -- only recorder when ledger is created
SELECT
    *
FROM
    cash_out_blue_treasure
SELECT
    *
FROM
    cash_in_blue_treasure
SELECT
    *
FROM
    ledger
SELECT
    *
FROM
    vault
    -- op:90000, ca:66000
    -- op:66k+90k=156k, ca:156k  
TRUNCATE TABLE cash_out_treasure,
cash_in_treasure,
cash_out_blue_treasure,
cash_in_blue_treasure,
ledger,
monthly_entries,
vault,
blue_vault,
paychecks CASCADE;