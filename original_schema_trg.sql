
-- (TRIGGERS)

CREATE OR REPLACE FUNCTION public.fn_ledger_sync() RETURNS TRIGGER AS $$
DECLARE
    v_me_id     INTEGER;
    v_bucket_id INTEGER;
BEGIN
    -- 1. Identify which Monthly Entry needs updating
    IF TG_OP = 'DELETE' THEN
        v_me_id     := OLD.monthly_entry_id;
        v_bucket_id := OLD.bucket_id;
    ELSE
        v_me_id     := NEW.monthly_entry_id;
        v_bucket_id := NEW.bucket_id;
    END IF;

    -- 2. Guard against infinite loops if you have other triggers
    PERFORM set_config('app.ledger_recalc_active', 'true', true);

    -- 3. Update the 'spent' column in monthly_entries
    -- Logic: SUM everything where the user spent money (txn_type = 'SPEND')
    UPDATE public.monthly_entries 
    SET spent = (
        SELECT COALESCE(SUM(amount), 0) 
        FROM public.ledger_entries le
        WHERE le.monthly_entry_id = v_me_id 
          AND le.txn_type = 'SPEND' -- Be explicit: only 'SPEND' increases 'spent'
    )
    WHERE id = v_me_id;

    -- 4. Reset guard
    PERFORM set_config('app.ledger_recalc_active', 'false', true);

    -- Return appropriate record to keep trigger happy
    IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_ledger_sync AFTER INSERT OR UPDATE OR DELETE ON public.ledger_entries
FOR EACH ROW EXECUTE FUNCTION public.fn_ledger_sync();

-- reset case 
DROP TRIGGER IF EXISTS trg_ledger_sync ON public.ledger_entries;
CREATE TRIGGER trg_ledger_sync AFTER INSERT OR UPDATE OR DELETE ON public.ledger_entries
FOR EACH ROW EXECUTE FUNCTION public.fn_ledger_sync();

-- 2. FIX: Reserve Recalc (Corrected Treasure Memory)

CREATE OR REPLACE FUNCTION public.fn_reserve_recalc() RETURNS TRIGGER AS $$
DECLARE
    v_salary            NUMERIC;
    v_other_allocations NUMERIC;
    v_treasure_sum      NUMERIC;
BEGIN
    -- Only run if not the Reserve bucket (ID 8 is reserve in your PRD)
    IF NEW.bucket_id = 8 THEN RETURN NEW; END IF;

    SELECT salary INTO v_salary FROM public.paychecks WHERE month_id = NEW.month_id;
    
    SELECT COALESCE(SUM(allocated), 0) INTO v_other_allocations 
    FROM public.monthly_entries WHERE month_id = NEW.month_id AND bucket_id != 8;

    -- FIX: Explicit Treasure Look-up
    SELECT COALESCE(SUM(amount), 0) INTO v_treasure_sum 
    FROM public.treasure WHERE absorbed_by_month_id = NEW.month_id;

    UPDATE public.monthly_entries 
    SET allocated = (v_salary + v_treasure_sum - v_other_allocations)
    WHERE month_id = NEW.month_id AND bucket_id = 8;

    UPDATE public.vault_entries 
    SET total_drip = (v_salary + v_treasure_sum - v_other_allocations)
    WHERE month_id = NEW.month_id AND bucket_id = 8;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_reserve_recalc AFTER INSERT OR UPDATE OF allocated ON public.monthly_entries
FOR EACH ROW EXECUTE FUNCTION public.fn_reserve_recalc();


-- 3. FIX: Vault Withdrawal (Recursion & System Assignment)
CREATE OR REPLACE FUNCTION public.fn_vault_withdrawal_manage() RETURNS TRIGGER AS $$
DECLARE
    v_rem   NUMERIC := NEW.total_amount;
    v_cur   RECORD;
    v_taken NUMERIC;
BEGIN
    -- 1. Clear old sources if update
    IF TG_OP = 'UPDATE' THEN
        DELETE FROM public.vault_withdrawal_sources WHERE withdrawal_id = NEW.id;
        DELETE FROM public.ledger_entries WHERE vault_wd_id = NEW.id;
    END IF;

    -- 2. Drain Logic
    FOR v_cur IN 
        SELECT ve.*, (ve.total_drip - COALESCE((SELECT SUM(amount_taken) FROM vault_withdrawal_sources WHERE vault_entry_id = ve.id), 0)) as rem_bal
        FROM public.vault_entries ve WHERE user_id = NEW.user_id ORDER BY month_id ASC
    LOOP
        EXIT WHEN v_rem <= 0;
        v_taken := LEAST(v_rem, v_cur.rem_bal);
        IF v_taken > 0 THEN
            INSERT INTO public.vault_withdrawal_sources (withdrawal_id, vault_entry_id, amount_taken)
            VALUES (NEW.id, v_cur.id, v_taken);
            
            -- Record the SPEND on the source bucket
            INSERT INTO public.ledger_entries (user_id, monthly_entry_id, bucket_id, vault_wd_id, amount, txn_type)
            SELECT NEW.user_id, me.id, v_cur.bucket_id, NEW.id, v_taken, 'SPEND'
            FROM public.monthly_entries me WHERE me.month_id = v_cur.month_id AND me.bucket_id = v_cur.bucket_id;
            
            v_rem := v_rem - v_taken;
            -- FIX: System-filled bucket_id (Recursive Prevention)
            NEW.bucket_id := v_cur.bucket_id; 
        END IF;
    END LOOP;

    IF v_rem > 0 THEN RAISE EXCEPTION 'Insufficient Vault Funds'; END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- FIX: Changed to BEFORE to allow NEW.assignment and prevent recursion
CREATE TRIGGER trg_vault_withdrawal_manage BEFORE INSERT OR UPDATE ON public.vault_withdrawals
FOR EACH ROW EXECUTE FUNCTION public.fn_vault_withdrawal_manage();


-- 4 


CREATE OR REPLACE FUNCTION public.fn_close_month(
    p_user_id UUID, 
    p_month_id VARCHAR(7) -- Corrected from INTEGER
)
RETURNS VOID AS $$
DECLARE
    v_leftover NUMERIC;
    v_reserve_bucket_id INTEGER;
    v_already_closed BOOLEAN;
BEGIN
    -- 1. DYNAMICALLY find the Reserve Bucket ID
    SELECT bucket_id INTO v_reserve_bucket_id 
    FROM public.bucket_configs 
    WHERE user_id = p_user_id AND display_type = 'RESERVE'
    LIMIT 1;

    -- 2. Check if this month has already been closed 
    -- (Prevents generating duplicate Treasure)
    SELECT EXISTS (
        SELECT 1 FROM public.treasure 
        WHERE user_id = p_user_id AND month_id = p_month_id
    ) INTO v_already_closed;

    IF v_already_closed THEN
        RAISE EXCEPTION 'Month % is already closed for this user.', p_month_id;
    END IF;

    -- 3. Calculate leftover from the RESERVE bucket
    SELECT (allocated - spent) INTO v_leftover
    FROM public.monthly_entries
    WHERE user_id = p_user_id 
      AND month_id = p_month_id 
      AND bucket_id = v_reserve_bucket_id;

    -- 4. Only insert if there is actually money left to carry over
    IF v_leftover IS NOT NULL AND v_leftover > 0 THEN
        INSERT INTO public.treasure (user_id, month_id, amount, status)
        VALUES (p_user_id, p_month_id, v_leftover, 'AVAILABLE');
        
        -- Optional: You might want to log this in the ledger as a carry-over event
    END IF;

END;
$$ LANGUAGE plpgsql;

-- Attach the trigger to the paychecks table
CREATE TRIGGER trg_paycheck_insert_init 
AFTER INSERT ON public.paychecks
FOR EACH ROW EXECUTE FUNCTION public.fn_paycheck_insert_init();

-- check trg reset {if we want to reset the flow in DB}

DROP TRIGGER IF EXISTS trg_paycheck_insert_init ON public.paychecks;
CREATE TRIGGER trg_paycheck_insert_init 
AFTER INSERT ON public.paychecks
FOR EACH ROW EXECUTE FUNCTION public.fn_paycheck_insert_init();




CREATE OR REPLACE FUNCTION public.fn_paycheck_insert_init() RETURNS TRIGGER AS $$
DECLARE
    v_treasure_total    NUMERIC;
    v_reserve_bucket_id INTEGER;
BEGIN
    -- 1. DYNAMICALLY find the Reserve Bucket ID for this specific user
    -- We need this ID to link the entry to the 'RESERVE' bucket config
    SELECT bucket_id INTO v_reserve_bucket_id 
    FROM public.bucket_configs 
    WHERE user_id = NEW.user_id AND display_type = 'RESERVE'
    LIMIT 1;

    -- 2. Safety Check: If user hasn't set up a Reserve bucket, we can't proceed
    IF v_reserve_bucket_id IS NULL THEN
        RAISE EXCEPTION 'User % has no RESERVE bucket configured.', NEW.user_id;
    END IF;

    -- 3. Get total available treasure (windfalls) to be absorbed into this month
    SELECT COALESCE(SUM(amount), 0) INTO v_treasure_total
    FROM public.treasure 
    WHERE user_id = NEW.user_id AND status = 'AVAILABLE';

    -- 4. Auto-create the Monthly Entry
    -- We use NEW.month_id ('2026-05') so it links correctly to the parent record
    INSERT INTO public.monthly_entries (user_id, month_id, bucket_id, allocated, spent)
    VALUES (
        NEW.user_id, 
        NEW.month_id, -- Use the VARCHAR(7) ID
        v_reserve_bucket_id, 
        (NEW.salary + v_treasure_total), 
        0
    );

    -- 5. Auto-create the Vault Entry
    -- This keeps the "Savings/Drip" tracker in sync with the salary injection
    INSERT INTO public.vault_entries (user_id, month_id, bucket_id, total_drip)
    VALUES (
        NEW.user_id, 
        NEW.month_id, 
        v_reserve_bucket_id, 
        (NEW.salary + v_treasure_total)
    );

    -- 6. Mark absorbed Treasure as USED and tag it with THIS specific month
    UPDATE public.treasure 
    SET status = 'USED', 
        absorbed_by_month_id = NEW.month_id
    WHERE user_id = NEW.user_id AND status = 'AVAILABLE';

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

--  Function
CREATE OR REPLACE FUNCTION public.fn_close_month(p_user_id uuid, p_month_id INTEGER) RETURNS VOID AS $$
DECLARE
    v_leftover NUMERIC;
BEGIN
    -- Calculate what is left in the Reserve (Allocated - Spent)
    SELECT (allocated - spent) INTO v_leftover
    FROM public.monthly_entries
    WHERE user_id = p_user_id AND month_id = p_month_id AND bucket_id = 8;

    -- If there is money left, move it to the Treasure table
    IF v_leftover > 0 THEN
        INSERT INTO public.treasure (user_id, month_id, amount, status)
        VALUES (p_user_id, p_month_id, v_leftover, 'AVAILABLE');
    END IF;
END;
$$ LANGUAGE plpgsql;