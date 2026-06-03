-- 8 (bucket_name,display_type)= Misc Surprises ORANGE
should we have orange bucket in monthly_entries via allocate_blue_bucket () ? ? ?

technically Orange means suprise which cannot be planned in monthly_entries(budget_planning table),
So we don't provide user to create Orange directly via monthly_entries,
But once ledger entry recorded then automatically Orange bucket will be created in monthly_entries



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

-- CALL allocate_blue_bucket('a240aa31-9303-41d1-9caf-a3389dedfd99', '2026-02', 9, 5000)
 -- === PAYCHECK ENTRY ===
 
 CALL record_paycheck('a240aa31-9303-41d1-9caf-a3389dedfd99','2026-01',90000)
 -- === BUDGET ALLOCATION ===
 CALL allocate_blue_bucket('a240aa31-9303-41d1-9caf-a3389dedfd99','2026-01',7,5000);
 CALL allocate_blue_bucket('a240aa31-9303-41d1-9caf-a3389dedfd99','2026-01',9,12000);
 
 CALL allocate_bucket('a240aa31-9303-41d1-9caf-a3389dedfd99','2026-01',2,10000); 
 CALL allocate_bucket('a240aa31-9303-41d1-9caf-a3389dedfd99','2026-01',3,15000); 
 CALL allocate_bucket('a240aa31-9303-41d1-9caf-a3389dedfd99','2026-01',4,14000); 
 CALL allocate_bucket('a240aa31-9303-41d1-9caf-a3389dedfd99','2026-01',5,1000); 
 CALL allocate_bucket('a240aa31-9303-41d1-9caf-a3389dedfd99','2026-01',6,10000); 
 -- CALL allocate_bucket('a240aa31-9303-41d1-9caf-a3389dedfd99','2026-01',9,12000); 

 -- === LEDGER ENTRY ===


CALL record_blue_ledger_entry('a240aa31-9303-41d1-9caf-a3389dedfd99',9,120,'2026-01','2026-01-16','RJY  Bus  Trip');

-- CALL close_month('a240aa31-9303-41d1-9caf-a3389dedfd99','2026-01');

SELECT * FROM vault


SELECT * FROM paychecks
SELECT allocated FROM monthly_entries WHERE bucket_id = 1


CALL record_ledger_entry('a240aa31-9303-41d1-9caf-a3389dedfd99',3,16000,'2026-01','2026-01-02','EMI CODE refractored');
 CALL reverse_ledger_entry('a240aa31-9303-41d1-9caf-a3389dedfd99',55,'over_spent amt not reflecting on vault')


SELECT * FROM vault
SELECT * FROM monthly_entries 
SELECT * FROM ledger


SELECT * FROM blue_vault
SELECT * FROM monthly_entries WHERE bucket_id <> 1
SELECT * FROM monthly_entries WHERE bucket_id = 3

SELECT * FROM blue_vault 

SELECT * FROM ledger 

-- WHERE user_id = 'a240aa31-9303-41d1-9caf-a3389dedfd99' AND month = '2026-01';

-- CALL record_blue_ledger_entry('a240aa31-9303-41d1-9caf-a3389dedfd99', 9, 2000, '2026-02', '2026-02-01', 'Feb Blue Test');


SELECT * FROM blue_vault WHERE user_id = 'a240aa31-9303-41d1-9caf-a3389dedfd99';


SELECT * FROM vault

SELECT * FROM blue_vault

SELECT * FROM cash_out_blue_treasure
SELECT * FROM cash_in_blue_treasure

SELECT * FROM cash_out_treasure
SELECT * FROM cash_in_treasure


-- TRUNCATE TABLE 
--     cash_out_treasure,
--     cash_in_treasure,
--     cash_out_blue_treasure,
--     cash_in_blue_treasure,
--     ledger,
--     monthly_entries,
--     vault,
--     blue_vault,
--     paychecks
-- CASCADE;

SELECT 
    bc.bucket_id,
    bc.display_type,
    bt.affects_vault as affects_main_flag   -- this decides whether final block runs
FROM bucket_configs bc
JOIN bucket_types bt ON bt.type_name = bc.display_type
WHERE bc.user_id = 'a240aa31-9303-41d1-9caf-a3389dedfd99' 

SELECT COUNT(*) FROM bucket_configs 
WHERE user_id = 'a240aa31-9303-41d1-9caf-a3389dedfd99' 
  AND display_type = 'RESERVE';
  AND bc.display_type = 'RESERVE';

SELECT * FROM bucket_configs
SELECT * FROM bucket_types

SELECT SUM(
    CASE WHEN bc.display_type IN ('RED','GREEN') THEN me.spent ELSE me.allocated END
) as total_non_reserve
FROM monthly_entries me
JOIN bucket_configs bc ON bc.bucket_id = me.bucket_id
WHERE me.user_id = 'a240aa31-9303-41d1-9caf-a3389dedfd99' 
  AND me.month = '2026-01'
  AND bc.display_type <> 'RESERVE';

***

SELECT * FROM auth.users
SELECT * FROM paychecks
SELECT * FROM vault

SELECT * FROM blue_vault
SELECT * FROM monthly_entries

CALL record_blue_ledger_entry('a240aa31-9303-41d1-9caf-a3389dedfd99',9,120,'2026-01','2026-01-16','RJY  Bus  Trip');


 CALL allocate_blue_bucket('a240aa31-9303-41d1-9caf-a3389dedfd99','2026-02',7,2000);



SELECT * FROM v_reserve
SELECT current_role


SELECT has_function_privilege('authenticated', 'public.record_paycheck(uuid, varchar, numeric)', 'execute');

-- Check who owns the procedures
SELECT proname, proowner::regrole 
FROM pg_proc 
WHERE proname = 'record_paycheck';
-- SET ROLE authenticated
-- SET ROLE postgres



GRANT SELECT, INSERT, UPDATE, DELETE ON public.blue_vault TO authenticated;

-- Also grant sequence access (for auto-incrementing IDs)
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO authenticated;
-- 1. Table-level privileges (most useful)
-- Check what authenticated role can do on bucket_configs
SELECT 
    grantee,
    privilege_type
FROM information_schema.table_privileges
WHERE table_name = 'bucket_configs'
  AND table_schema = 'public'
  AND grantee = 'authenticated';


  ***



-- v_vault_balances


CREATE VIEW v_vault_balances AS
SELECT
    v.user_id,
    v.month,
    v.current_amt               AS main_vault_balance,
    COALESCE(bv.current_amt, 0) AS blue_vault_balance,
    v.closing_amt IS NULL       AS is_month_open
FROM vault v
LEFT JOIN blue_vault bv
    ON bv.user_id = v.user_id
    AND bv.month  = v.month
WHERE v.user_id = auth.uid();



GRANT SELECT ON v_vault_balances TO authenticated;

***

CREATE VIEW monthly_budget_view AS
SELECT 
    bc.bucket_id,
    bc.user_id,
    bc.bucket_name,
    bc.display_type,
    bc.is_active,
    me.month,
    COALESCE(me.allocated, 0) AS allocated,
    COALESCE(SUM(l.amount_spent), 0) AS spent,
    COALESCE(me.allocated, 0) - COALESCE(SUM(l.amount_spent), 0) AS remaining,
    CASE
        WHEN COALESCE(me.allocated, 0) > 0 
        THEN ROUND(COALESCE(SUM(l.amount_spent), 0) * 100.0 / me.allocated, 2)
        ELSE 0
    END AS utilization_percent
FROM bucket_configs bc
LEFT JOIN monthly_entries me 
    ON bc.bucket_id = me.bucket_id 
    AND bc.user_id = me.user_id
LEFT JOIN ledger l 
    ON l.bucket_id = bc.bucket_id 
    AND l.user_id = bc.user_id
    AND l.month = me.month
    AND l.reversed = false
WHERE bc.is_active = true
  AND bc.bucket_id != 1
GROUP BY 
    bc.bucket_id,
    bc.user_id,
    bc.bucket_name,
    bc.display_type,
    bc.is_active,
    me.month,
    me.allocated
ORDER BY bc.display_type, bc.bucket_name;

GRANT SELECT ON monthly_budget_view TO authenticated;
_____________________________________________________________

allocate_blue_bucket

DECLARE
    v_salary            NUMERIC(12,2);
	  v_opening_amt       NUMERIC(12,2);  
    v_non_reserve_sum   NUMERIC(12,2);
    v_bucket_type       VARCHAR(20);
    v_reserve_bucket_id INTEGER;
    v_exists            BOOLEAN;
    v_prev_closing      NUMERIC(12,2);
    v_blue_opening      NUMERIC(12,2);
	v_current_spent     NUMERIC(12,2) := 0; 
BEGIN
    SET LOCAL app.proc_active = 'true';

    IF p_allocated < 0 THEN
        RAISE EXCEPTION 'Allocated amount must be positive. Got: %', p_allocated USING ERRCODE = 'P0001';
    END IF;

    SELECT salary INTO v_salary 
    FROM paychecks WHERE user_id = p_user_id AND month = p_month;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'No paycheck for user % month %.', p_user_id, p_month USING ERRCODE = 'P0002';
    END IF;

	
SELECT opening_amt INTO v_opening_amt FROM vault WHERE user_id = p_user_id AND month = p_month;

    IF EXISTS (SELECT 1 FROM blue_vault 
               WHERE user_id = p_user_id AND month = p_month AND closing_amt IS NOT NULL) THEN
        RAISE EXCEPTION 'Month % is already closed. Cannot change allocations.', p_month 
        USING ERRCODE = 'P0003';
    END IF;

    SELECT bc.display_type INTO v_bucket_type
    FROM bucket_configs bc
    WHERE bc.bucket_id = p_bucket_id AND bc.user_id = p_user_id AND bc.is_active = TRUE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Bucket % not found or inactive.', p_bucket_id USING ERRCODE = 'P0003';
    END IF;

    IF v_bucket_type <> 'BLUE' THEN
        RAISE EXCEPTION 'This procedure is only for BLUE buckets. Use allocate_bucket instead.' 
        USING ERRCODE = 'P0004';
    END IF;

    SELECT bucket_id INTO v_reserve_bucket_id
    FROM bucket_configs 
    WHERE user_id = p_user_id AND display_type = 'RESERVE' AND is_active = true 
    LIMIT 1;

    IF v_reserve_bucket_id IS NULL THEN
        RAISE EXCEPTION 'Reserve bucket not found for user %.', p_user_id USING ERRCODE = 'P0005';
    END IF;

    -- Check if monthly_entries record exists
    SELECT EXISTS(
        SELECT 1 FROM monthly_entries 
        WHERE user_id = p_user_id AND month = p_month AND bucket_id = p_bucket_id
    ) INTO v_exists;

    -- Pre-check: enough room in salary?
    SELECT COALESCE(SUM(me.allocated), 0) INTO v_non_reserve_sum
    FROM monthly_entries me
    JOIN bucket_configs bc ON bc.bucket_id = me.bucket_id
    WHERE me.user_id     = p_user_id 
      AND me.month       = p_month 
      AND bc.display_type <> 'RESERVE'
      AND me.bucket_id   <> p_bucket_id;

   

	-- CORRECT
IF (v_non_reserve_sum + p_allocated) > v_opening_amt THEN
    RAISE EXCEPTION 'Allocation exceeds available balance. Available: %, Requested: %', 
        v_opening_amt - v_non_reserve_sum, p_allocated   -- ← correct
    USING ERRCODE = 'P0006';
END IF;

    -- INSERT or UPDATE monthly_entries
  IF v_exists THEN
        SELECT spent INTO v_current_spent
        FROM monthly_entries
        WHERE user_id  = p_user_id 
          AND month    = p_month 
          AND bucket_id = p_bucket_id;

        IF v_current_spent > 0 THEN
            RAISE EXCEPTION 'Cannot re-allocate blue bucket %. Already spent: %.', 
                p_bucket_id, v_current_spent
            USING ERRCODE = 'P0008';
        END IF;

        UPDATE monthly_entries
        SET allocated = p_allocated
        WHERE user_id  = p_user_id 
          AND month    = p_month 
          AND bucket_id = p_bucket_id;

    ELSE
        INSERT INTO monthly_entries (user_id, month, bucket_id, allocated, spent)
        VALUES (p_user_id, p_month, p_bucket_id, p_allocated, 0);
    END IF;

    -- ========================================
    -- Sync blue_vault (Option B — always init/update here)
    -- ========================================

    -- Get prev month closing if exists
    SELECT closing_amt INTO v_prev_closing
    FROM blue_vault
    WHERE user_id = p_user_id
      AND month   = TO_CHAR(TO_DATE(p_month, 'YYYY-MM') - INTERVAL '1 month', 'YYYY-MM');

SELECT COALESCE(SUM(me.allocated), 0) INTO v_blue_opening
FROM monthly_entries me
JOIN bucket_configs bc ON bc.bucket_id = me.bucket_id
WHERE me.user_id      = p_user_id
  AND me.month        = p_month
  AND bc.display_type = 'BLUE';
  
    v_blue_opening := v_blue_opening + COALESCE(v_prev_closing, 0);

    IF EXISTS (SELECT 1 FROM blue_vault WHERE user_id = p_user_id AND month = p_month) THEN
        -- Already exists (re-allocation) — update opening only, preserve current_amt
        UPDATE blue_vault
        SET opening_amt = v_blue_opening
        WHERE user_id = p_user_id AND month = p_month;
    ELSE
        -- First time allocation this month — create fresh
        INSERT INTO blue_vault (user_id, month, opening_amt, current_amt)
        VALUES (p_user_id, p_month, v_blue_opening, v_blue_opening);
    END IF;

    -- ========================================
    -- Re-calculate RESERVE allocated
    -- ========================================
    SELECT COALESCE(SUM(me.allocated), 0) INTO v_non_reserve_sum
    FROM monthly_entries me
    JOIN bucket_configs bc ON bc.bucket_id = me.bucket_id
    WHERE me.user_id     = p_user_id 
      AND me.month       = p_month 
      AND bc.display_type <> 'RESERVE';

    UPDATE monthly_entries
    SET allocated = v_opening_amt - v_non_reserve_sum
    WHERE user_id  = p_user_id 
      AND month    = p_month 
      AND bucket_id = v_reserve_bucket_id;

    -- Sync vault.current_amt to RESERVE allocated
    UPDATE vault
    SET current_amt = (
        SELECT allocated FROM monthly_entries
        WHERE user_id  = p_user_id 
          AND month    = p_month 
          AND bucket_id = v_reserve_bucket_id
    )
    WHERE user_id = p_user_id AND month = p_month;

EXCEPTION
    WHEN OTHERS THEN RAISE;
END;
_____________________________________________________________

record_blue_ledger_entry
DECLARE
    v_bucket_type       VARCHAR(20);
    v_allocated         NUMERIC(12,2);
    v_current_spent     NUMERIC(12,2);
    v_new_spent         NUMERIC(12,2);
    v_entry_exists      BOOLEAN;
    v_underspend        NUMERIC(12,2);
    v_overspend         NUMERIC(12,2);
    v_blue_current      NUMERIC(12,2);
  
BEGIN
    SET LOCAL app.proc_active = 'true';

    -- ========================================
    -- Basic Validations
    -- ========================================
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'Amount must be positive.' USING ERRCODE = 'P0001';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM paychecks WHERE user_id = p_user_id AND month = p_month) THEN
        RAISE EXCEPTION 'No paycheck found.' USING ERRCODE = 'P0002';
    END IF;

    IF EXISTS (SELECT 1 FROM blue_vault WHERE user_id = p_user_id AND month = p_month AND closing_amt IS NOT NULL) THEN
        RAISE EXCEPTION 'Blue month is closed.' USING ERRCODE = 'P0003';
    END IF;

    -- ========================================
    -- Validate bucket is BLUE and active
    -- ========================================
    SELECT bc.display_type INTO v_bucket_type
    FROM bucket_configs bc
    WHERE bc.bucket_id = p_bucket_id
      AND bc.user_id   = p_user_id
      AND bc.is_active = true;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Bucket not found.' USING ERRCODE = 'P0004';
    END IF;

    IF v_bucket_type <> 'BLUE' THEN
        RAISE EXCEPTION 'Bucket % is not a BLUE bucket. Use record_ledger_entry instead.', p_bucket_id 
        USING ERRCODE = 'P0004';
    END IF;

    -- ========================================
    -- monthly_entries must exist for BLUE
    -- ========================================
    IF NOT EXISTS (
        SELECT 1 FROM monthly_entries
        WHERE user_id  = p_user_id
          AND month    = p_month
          AND bucket_id = p_bucket_id
    ) THEN
        RAISE EXCEPTION 'No monthly entry found for blue bucket %.', p_bucket_id 
        USING ERRCODE = 'P0004';
    END IF;

    -- ========================================
    -- Get current monthly_entries state
    -- ========================================
    SELECT allocated, spent INTO v_allocated, v_current_spent
    FROM monthly_entries
    WHERE user_id   = p_user_id
      AND month     = p_month
      AND bucket_id = p_bucket_id;

    v_new_spent := v_current_spent + p_amount;

    -- ========================================
    -- Get current blue_vault balance
    -- ========================================
    SELECT current_amt INTO v_blue_current
    FROM blue_vault
    WHERE user_id = p_user_id AND month = p_month;

	     -- Guard: check blue_vault has enough
        IF v_blue_current < p_amount THEN
            RAISE EXCEPTION 'Insufficient blue vault balance. Available: %, Requested: %',
                v_blue_current, p_amount
            USING ERRCODE = 'P0007';
        END IF;

    -- ========================================
    -- Create Ledger Entry
    -- ========================================
    INSERT INTO ledger (user_id, bucket_id, amount_spent, month, date_of_entry, note)
    VALUES (p_user_id, p_bucket_id, p_amount, p_month, p_date, p_note);

    -- ========================================
    -- Update monthly_entries spent
    -- ========================================
    UPDATE monthly_entries
    SET spent = v_new_spent
    WHERE user_id   = p_user_id
      AND month     = p_month
      AND bucket_id = p_bucket_id;

    -- ========================================
    -- BLUE Spend Behaviour (same as YELLOW but against blue_vault)
    -- ========================================
    IF v_new_spent <= v_allocated THEN
        -- Underspend: audit only
        v_underspend := v_allocated - v_new_spent;

        IF v_underspend > 0 THEN
            INSERT INTO cash_in_blue_treasure (user_id, month, bucket_id, underspend_amt, entry_date)
            VALUES (p_user_id, p_month, p_bucket_id, v_underspend, p_date);
        END IF;
-- I manually commented this 
        -- -- Collapse allocated down to match spent
        -- UPDATE monthly_entries
        -- SET allocated = v_new_spent
        -- WHERE user_id   = p_user_id
        --   AND month     = p_month
        --   AND bucket_id = p_bucket_id;

    ELSE
        -- Overspend: pull surplus from blue_vault
        v_overspend := v_new_spent - v_allocated;

        -- Guard: check blue_vault has enough
        IF v_blue_current < v_overspend THEN
            RAISE EXCEPTION 'Insufficient blue vault balance. Available: %, Requested: %',
                v_blue_current, v_overspend
            USING ERRCODE = 'P0007';
        END IF;

        -- Audit only
        INSERT INTO cash_out_blue_treasure (user_id, month, bucket_id, surplus_amt, entry_date)
        VALUES (p_user_id, p_month, p_bucket_id, v_overspend, p_date);

        -- -- Collapse allocated up to match new spent
        -- UPDATE monthly_entries
        -- SET allocated = v_new_spent
        -- WHERE user_id   = p_user_id
        --   AND month     = p_month
        --   AND bucket_id = p_bucket_id;

    END IF;

    -- ========================================
    -- ALWAYS Sync blue_vault.current_amt
    -- (mirrors how main vault syncs via RESERVE at bottom)
    -- ========================================
    UPDATE blue_vault
    SET current_amt = opening_amt - (
        SELECT COALESCE(SUM(me.spent), 0)
        FROM monthly_entries me
        JOIN bucket_configs bc ON bc.bucket_id = me.bucket_id
        WHERE me.user_id      = p_user_id
          AND me.month        = p_month
          AND bc.display_type = 'BLUE'
    )
    WHERE user_id = p_user_id AND month = p_month;

EXCEPTION
    WHEN OTHERS THEN RAISE;
END;