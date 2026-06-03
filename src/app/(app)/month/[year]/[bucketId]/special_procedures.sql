record_blue_ledger_entry()
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

  -- ========================================
    -- Get current blue_vault balance and check blue_vault has enough amt
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
    v_new_spent := v_current_spent + p_amount;
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
END IF;
    IF  v_new_spent >= v_allocated THEN 
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

-- reverse_ledger_entry()
DECLARE
    v_bucket_id         INTEGER;
    v_amount            NUMERIC(12,2);
    v_month             VARCHAR(7);
    v_date              DATE;
    v_bucket_type       VARCHAR(20);
    v_affects_vault     VARCHAR(10);
    v_current_spent     NUMERIC(12,2);
    v_new_spent         NUMERIC(12,2);
    v_allocated         NUMERIC(12,2);
    v_salary            NUMERIC(12,2);
    v_reserve_bucket_id INTEGER;
    v_non_reserve_sum   NUMERIC(12,2);
    v_reversal_id       INTEGER;
    v_prev_spent        NUMERIC(12,2);
BEGIN
    SET LOCAL app.proc_active = 'true';

    -- ========================================
    -- Fetch original ledger entry
    -- ========================================
    SELECT bucket_id, amount_spent, month, date_of_entry
    INTO   v_bucket_id, v_amount, v_month, v_date
    FROM   ledger WHERE ledger_id = p_ledger_id AND user_id = p_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Ledger entry % not found for user %.', p_ledger_id, p_user_id 
        USING ERRCODE = 'P0001';
    END IF;

    IF (SELECT reversed FROM ledger WHERE ledger_id = p_ledger_id) THEN
        RAISE EXCEPTION 'Ledger entry % is already reversed.', p_ledger_id 
        USING ERRCODE = 'P0002';
    END IF;

    IF EXISTS (SELECT 1 FROM vault WHERE user_id = p_user_id AND month = v_month AND closing_amt IS NOT NULL) THEN
        RAISE EXCEPTION 'Month % is closed. Cannot reverse ledger entries.', v_month 
        USING ERRCODE = 'P0003';
    END IF;

 -- Block if any future month exists
    IF EXISTS (
        SELECT 1 FROM paychecks
        WHERE user_id = p_user_id
          AND month > v_month
    ) THEN
        RAISE EXCEPTION 'Cannot reverse entry for month %. A newer month (%) exists. Reversals only allowed on the latest open month.',
            v_month,
            (SELECT MAX(month) FROM paychecks WHERE user_id = p_user_id)
        USING ERRCODE = 'P0004';
    END IF;
    -- ========================================
    -- Fetch bucket info
    -- ========================================
    SELECT bc.display_type, bt.affects_vault 
    INTO   v_bucket_type, v_affects_vault
    FROM   bucket_configs bc 
    JOIN   bucket_types bt ON bt.type_name = bc.display_type
    WHERE  bc.bucket_id = v_bucket_id;

    -- ========================================
    -- Fetch current monthly_entries state
    -- ========================================
    SELECT spent, allocated INTO v_current_spent, v_allocated
    FROM   monthly_entries 
    WHERE  user_id = p_user_id AND month = v_month AND bucket_id = v_bucket_id;

    SELECT salary INTO v_salary 
    FROM   paychecks WHERE user_id = p_user_id AND month = v_month;

    SELECT bc.bucket_id INTO v_reserve_bucket_id
    FROM   bucket_configs bc 
    WHERE  bc.user_id = p_user_id AND bc.display_type = 'RESERVE' AND bc.is_active = TRUE 
    LIMIT  1;

    -- Previous spent before this entry
    v_prev_spent := v_current_spent - v_amount;
    v_new_spent  := v_prev_spent;

    -- ========================================
    -- Mark original ledger as reversed
    -- ========================================
    INSERT INTO ledger (user_id, bucket_id, amount_spent, month, date_of_entry, note, reversed)
    VALUES (p_user_id, v_bucket_id, v_amount, v_month, CURRENT_DATE,
            'REVERSAL OF #' || p_ledger_id || COALESCE(': ' || p_reason, ''), TRUE)
    RETURNING ledger_id INTO v_reversal_id;

    UPDATE ledger 
    SET    reversed = TRUE, reversed_by = v_reversal_id 
    WHERE  ledger_id = p_ledger_id;

    -- ========================================
    -- ORANGE Reversal
    -- ========================================
    IF v_bucket_type = 'ORANGE' THEN

        -- Restore both allocated and spent
        UPDATE monthly_entries 
        SET    spent = v_new_spent, allocated = v_new_spent
        WHERE  user_id = p_user_id AND month = v_month AND bucket_id = v_bucket_id;

        -- Always delete last cash_out_treasure (ORANGE always creates one)
        DELETE FROM cash_out_treasure
        WHERE id = (
            SELECT id FROM cash_out_treasure
            WHERE  user_id = p_user_id AND month = v_month AND bucket_id = v_bucket_id
            ORDER  BY id DESC LIMIT 1
        );

    -- ========================================
    -- YELLOW Reversal
    -- ========================================
    ELSIF v_bucket_type = 'YELLOW' THEN

        -- Restore spent, collapse allocated back to new_spent
        UPDATE monthly_entries 
        SET    spent = v_new_spent, allocated = v_new_spent
        WHERE  user_id = p_user_id AND month = v_month AND bucket_id = v_bucket_id;

        -- Delete last cash_out or cash_in depending on what original entry did
        IF v_current_spent > v_allocated THEN
            -- Original entry was overspend → delete last cash_out
            DELETE FROM cash_out_treasure
            WHERE id = (
                SELECT id FROM cash_out_treasure
                WHERE  user_id = p_user_id AND month = v_month AND bucket_id = v_bucket_id
                ORDER  BY id DESC LIMIT 1
            );
        ELSE
            -- Original entry was underspend → delete last cash_in
            DELETE FROM cash_in_treasure
            WHERE id = (
                SELECT id FROM cash_in_treasure
                WHERE  user_id = p_user_id AND month = v_month AND bucket_id = v_bucket_id
                ORDER  BY id DESC LIMIT 1
            );
        END IF;

    -- ========================================
    -- RED / GREEN Reversal
    -- ========================================
    ELSIF v_bucket_type IN ('RED', 'GREEN') THEN

        -- Restore spent only
        UPDATE monthly_entries 
        SET    spent = v_new_spent
        WHERE  user_id = p_user_id AND month = v_month AND bucket_id = v_bucket_id;

        -- Only delete cash_out if original entry caused one
        IF v_current_spent > v_allocated THEN
            -- Was already over or crossed boundary → cash_out existed
            DELETE FROM cash_out_treasure
            WHERE id = (
                SELECT id FROM cash_out_treasure
                WHERE  user_id = p_user_id AND month = v_month AND bucket_id = v_bucket_id
                ORDER  BY id DESC LIMIT 1
            );
        END IF;
        -- If never crossed allocated → no cash_out to delete

    -- ========================================
    -- BLUE Reversal
    -- ========================================
    ELSIF v_bucket_type = 'BLUE' THEN

  RAISE EXCEPTION 'Use reverse_blue_ledger_entry for BLUE buckets.' 
    USING ERRCODE = 'P0008';

    END IF;

    -- ========================================
    -- ALWAYS Recalculate RESERVE + Sync vault.current_amt
    -- ========================================
    IF v_affects_vault = 'MAIN' THEN
        SELECT COALESCE(SUM(me.allocated), 0) INTO v_non_reserve_sum
        FROM   monthly_entries me
        JOIN   bucket_configs bc ON bc.bucket_id = me.bucket_id
        WHERE  me.user_id = p_user_id AND me.month = v_month
          AND  bc.display_type <> 'RESERVE';

        UPDATE monthly_entries 
        SET    allocated = v_salary - v_non_reserve_sum
        WHERE  user_id = p_user_id AND month = v_month AND bucket_id = v_reserve_bucket_id;

        UPDATE vault
        SET    current_amt = (
            SELECT allocated FROM monthly_entries
            WHERE  user_id = p_user_id AND month = v_month AND bucket_id = v_reserve_bucket_id
        )
        WHERE  user_id = p_user_id AND month = v_month;
    END IF;

EXCEPTION
    WHEN OTHERS THEN RAISE;
END;
-- record_ledger_entry



DECLARE
    v_bucket_type       VARCHAR(20);
    v_affects_main      BOOLEAN;
    v_allocated         NUMERIC(12,2);
    v_current_spent     NUMERIC(12,2);
    v_new_spent         NUMERIC(12,2);
    v_salary            NUMERIC(12,2);
    v_reserve_bucket_id INTEGER;
    v_non_reserve_sum   NUMERIC(12,2);
    v_entry_exists      BOOLEAN;
    v_underspend        NUMERIC(12,2);
    v_overspend         NUMERIC(12,2);
	v_vault_current     NUMERIC(12,2);
BEGIN
    SET LOCAL app.proc_active = 'true';

    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'Amount must be positive.' USING ERRCODE = 'P0001';
    END IF;

    SELECT salary INTO v_salary 
    FROM paychecks WHERE user_id = p_user_id AND month = p_month;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No paycheck found.' USING ERRCODE = 'P0002';
    END IF;

    IF EXISTS (SELECT 1 FROM vault WHERE user_id = p_user_id AND month = p_month AND closing_amt IS NOT NULL) THEN
        RAISE EXCEPTION 'Month is closed.' USING ERRCODE = 'P0003';
    END IF;

	SELECT current_amt INTO v_vault_current
FROM vault 
WHERE user_id = p_user_id AND month = p_month;

  -- Step 1: Get bucket info (no monthly_entries check yet)
    SELECT bc.display_type, 
           (bt.affects_vault = 'MAIN')
      INTO v_bucket_type, v_affects_main
    FROM bucket_configs bc 
    JOIN bucket_types bt ON bt.type_name = bc.display_type
    WHERE bc.bucket_id = p_bucket_id 
      AND bc.user_id = p_user_id 
      AND bc.is_active = true;
    --   AND EXISTS (
    --     SELECT 1 
    --     FROM monthly_entries me 
    --     WHERE me.bucket_id = bc.bucket_id
    --   );

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Bucket not found.' USING ERRCODE = 'P0004';
    END IF;

	 -- Step 2: For non-ORANGE buckets, monthly_entries must already exist
    IF v_bucket_type <> 'ORANGE' THEN
        IF NOT EXISTS (
            SELECT 1 FROM monthly_entries 
            WHERE bucket_id = p_bucket_id
        ) THEN
            RAISE EXCEPTION 'No monthly entry found for bucket %.', p_bucket_id USING ERRCODE = 'P0004';
        END IF;
    END IF;

    IF v_bucket_type = 'RESERVE' THEN
        RAISE EXCEPTION 'Cannot create ledger for RESERVE.' USING ERRCODE = 'P0005';
    END IF;

    -- Check if entry exists
    SELECT EXISTS(
        SELECT 1 FROM monthly_entries 
        WHERE user_id = p_user_id AND month = p_month AND bucket_id = p_bucket_id
    ) INTO v_entry_exists;

    IF v_entry_exists THEN
        SELECT allocated, spent INTO v_allocated, v_current_spent
        FROM monthly_entries 
        WHERE user_id = p_user_id AND month = p_month AND bucket_id = p_bucket_id;
    ELSE
        v_allocated := 0;
        v_current_spent := 0;
    END IF;

    v_new_spent := v_current_spent + p_amount;

    -- Create Ledger
    INSERT INTO ledger (user_id, bucket_id, amount_spent, month, date_of_entry, note)
    VALUES (p_user_id, p_bucket_id, p_amount, p_month, p_date, p_note);

    -- ========================================
    -- ORANGE Special Handling
    -- ========================================
    IF v_bucket_type = 'ORANGE' THEN
        IF NOT v_entry_exists THEN
            INSERT INTO monthly_entries (user_id, month, bucket_id, allocated, spent)
            VALUES (p_user_id, p_month, p_bucket_id, v_new_spent, v_new_spent);
        ELSE
            -- UPDATE monthly_entries 
            -- SET allocated = v_new_spent, 
            --     spent = v_new_spent
            -- WHERE user_id = p_user_id AND month = p_month AND bucket_id = p_bucket_id;
        END IF;

        -- Always record cash out for Orange
        INSERT INTO cash_out_treasure (user_id, month, bucket_id, surplus_amt, entry_date)
        VALUES (p_user_id, p_month, p_bucket_id, p_amount, p_date);

    -- ========================================
    -- YELLOW Handling
    -- ========================================
    ELSIF v_bucket_type = 'YELLOW' THEN

        UPDATE monthly_entries 
        SET spent = v_new_spent 
        WHERE user_id = p_user_id AND month = p_month AND bucket_id = p_bucket_id;

        IF v_new_spent <= v_allocated THEN
            -- Underspend: push remaining gap to vault
            v_underspend := v_allocated - v_new_spent;

            IF v_underspend > 0 THEN
                INSERT INTO cash_in_treasure (user_id, month, bucket_id, underspend_amt, entry_date)
                VALUES (p_user_id, p_month, p_bucket_id, v_underspend, p_date);
            END IF;

            -- Collapse allocated down to match spent
            UPDATE monthly_entries 
            SET allocated = v_new_spent
            WHERE user_id = p_user_id AND month = p_month AND bucket_id = p_bucket_id;

        ELSE
            -- Overspend: pull surplus from vault
            v_overspend := v_new_spent - v_allocated;
   -- Guard: make sure vault has enough before pulling
          IF v_vault_current < v_overspend THEN
    RAISE EXCEPTION 'Insufficient vault balance. Available: %, Requested: %',
        v_vault_current, v_overspend
    USING ERRCODE = 'P0007';
END IF;
            INSERT INTO cash_out_treasure (user_id, month, bucket_id, surplus_amt, entry_date)
            VALUES (p_user_id, p_month, p_bucket_id, v_overspend, p_date);

            -- -- Collapse allocated up to match new spent
            -- UPDATE monthly_entries 
            -- SET allocated = v_new_spent
            -- WHERE user_id = p_user_id AND month = p_month AND bucket_id = p_bucket_id;

        END IF;


  -- ========================================
    -- RED / GREEN / BLUE Handling
    -- ========================================
    ELSIF v_bucket_type IN ('RED', 'GREEN') THEN

        UPDATE monthly_entries 
        SET spent = v_new_spent 
        WHERE user_id = p_user_id AND month = p_month AND bucket_id = p_bucket_id;

        -- No cash_in_treasure, no vault credit for underspend
        -- Only pull from vault if overspend
        IF v_new_spent > v_allocated THEN
            v_overspend := v_new_spent - GREATEST(v_allocated, v_current_spent);

            IF v_overspend > 0 THEN

			 -- Guard: make sure vault has enough before pulling
              IF v_vault_current < v_overspend THEN
    RAISE EXCEPTION 'Insufficient vault balance. Available: %, Required: %',
        v_vault_current, v_overspend
    USING ERRCODE = 'P0007';
END IF;
                INSERT INTO cash_out_treasure (user_id, month, bucket_id, surplus_amt, entry_date)
                VALUES (p_user_id, p_month, p_bucket_id, v_overspend, p_date);
				
            END IF;
        END IF;

    -- ========================================
    -- OTHER bucket types — to be handled later
    -- ========================================
    ELSE
        RAISE EXCEPTION 'Unhandled bucket type: %', v_bucket_type USING ERRCODE = 'P0006';

    END IF;
 -- ========================================
    -- ALWAYS Update Reserve + Sync vault.current_amt
    -- ========================================
    IF v_affects_main THEN

        -- REMOVE the spent recalculation block entirely
        -- REMOVE the mixed CASE calculation

          SELECT COALESCE(SUM(
            CASE
                WHEN bc.display_type IN ('RED', 'GREEN')
                    THEN GREATEST(me.allocated, me.spent)
                ELSE me.allocated
            END
        ), 0) INTO v_non_reserve_sum
        FROM monthly_entries me
        JOIN bucket_configs bc ON bc.bucket_id = me.bucket_id
        WHERE me.user_id = p_user_id
          AND me.month = p_month
      -- AND bc.display_type NOT IN ('RESERVE', 'BLUE');
      AND bc.display_type NOT IN ('RESERVE');

        -- Update RESERVE bucket allocated = salary - all other allocations
        UPDATE monthly_entries 
        SET allocated = v_salary - v_non_reserve_sum
        WHERE user_id = p_user_id 
          AND month = p_month 
          AND bucket_id = (
                SELECT bucket_id FROM bucket_configs 
                WHERE user_id = p_user_id AND display_type = 'RESERVE' LIMIT 1
              );

        -- Sync vault.current_amt to RESERVE bucket's allocated
        UPDATE vault
        SET current_amt = (
            SELECT me.allocated
            FROM monthly_entries me
            JOIN bucket_configs bc ON bc.bucket_id = me.bucket_id
            WHERE me.user_id = p_user_id
              AND me.month = p_month
              AND bc.display_type = 'RESERVE'
            LIMIT 1
        )
        WHERE user_id = p_user_id AND month = p_month;

    END IF;

EXCEPTION
    WHEN OTHERS THEN RAISE;
END;
-- allocate_blue_bucket
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
-- Redundant update, allocated shouldn't update at any spot.
        -- UPDATE monthly_entries
        -- SET allocated = p_allocated
        -- WHERE user_id  = p_user_id 
        --   AND month    = p_month 
        --   AND bucket_id = p_bucket_id;

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
        SET opening_amt = v_blue_opening, current_amt = v_blue_opening
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
-- update_salary
-- added last two table updates

-- monthly_budget_view