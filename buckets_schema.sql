--
-- PostgreSQL database dump
--

-- Dumped from database version 17.5
-- Dumped by pg_dump version 17.5

-- Started on 2026-05-07 17:18:15

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 5 (class 2615 OID 45559)
-- Name: auth; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA auth;


ALTER SCHEMA auth OWNER TO postgres;

--
-- TOC entry 270 (class 1255 OID 45549)
-- Name: fn_box_events_ledger(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_box_events_ledger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM set_config('app.vault_operation_active', 'true', true);
    
    IF NEW.box_type = 'DEPOSIT' THEN
        INSERT INTO ledger_entries (
            monthly_entry_id, bucket_id, box_event_id, 
            description, amount, txn_date, txn_type
        ) VALUES (
            NEW.month_id, NEW.bucket_id, NEW.id,
            COALESCE(NEW.description, format('Blue box DEPOSIT - month #%s', NEW.month_id)),
            NEW.amount, NEW.event_date, 'CONTRIBUTION'
        );
        

        
    ELSIF NEW.box_type = 'WITHDRAW' THEN
        INSERT INTO ledger_entries (
            monthly_entry_id, bucket_id, box_event_id, 
            description, amount, txn_date, txn_type
        ) VALUES (
            NEW.month_id, NEW.bucket_id, NEW.id,
            COALESCE(NEW.description, format('Blue box WITHDRAW - month #%s', NEW.month_id)),
            NEW.amount, NEW.event_date, 'SPEND'
        );
        
    ELSIF NEW.box_type = 'SEALED' THEN
        INSERT INTO blue_box_state (bucket_id, is_sealed, sealed_date)
        VALUES (NEW.bucket_id, TRUE, NEW.event_date)
        ON CONFLICT (bucket_id)
        DO UPDATE SET
            is_sealed   = TRUE,
            sealed_date = NEW.event_date;
    END IF;
        RETURN NULL;

EXCEPTION WHEN OTHERS THEN
    RAISE;
END;
$$;


ALTER FUNCTION public.fn_box_events_ledger() OWNER TO postgres;

--
-- TOC entry 269 (class 1255 OID 45548)
-- Name: fn_box_events_validate(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_box_events_validate() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_total_deposits   NUMERIC;
    v_allocated_limit  NUMERIC;
    v_total_withdrawals NUMERIC;
    v_available_balance NUMERIC;
BEGIN
    -- ===========================================================
    -- VALIDATE DEPOSIT: Check allocated limit
    -- ===========================================================
    IF NEW.box_type = 'DEPOSIT' THEN
        -- Get allocated limit for this bucket + month
        SELECT allocated INTO v_allocated_limit
        FROM monthly_entries
        WHERE bucket_id = NEW.bucket_id 
          AND month_id = NEW.month_id;
        
        IF NOT FOUND THEN
            RAISE EXCEPTION 'No monthly_entry found for bucket_id=% month_id=%', 
                NEW.bucket_id, NEW.month_id;
        END IF;
        
        -- Get current total deposits for this bucket + month
        SELECT COALESCE(SUM(amount), 0) INTO v_total_deposits
        FROM box_events
        WHERE bucket_id = NEW.bucket_id 
          AND month_id = NEW.month_id
          AND box_type = 'DEPOSIT';
        
        -- Check if new deposit would exceed limit
        IF v_total_deposits + NEW.amount > v_allocated_limit THEN
            RAISE EXCEPTION 'Deposit of % would exceed allocated limit of % (current deposits: %)', 
                NEW.amount, v_allocated_limit, v_total_deposits;
        END IF;
    
    -- ===========================================================
    -- VALIDATE WITHDRAW: Check sufficient balance
    -- ===========================================================
    ELSIF NEW.box_type = 'WITHDRAW' THEN
    -- Allow if coming from the official withdrawal trigger
    IF current_setting('app.vault_operation_active', true) = 'true' THEN
        -- legitimate internal insert, let it pass
        NULL;
    ELSE
        RAISE EXCEPTION 'Cannot withdraw directly from box_events, use blue_box_withdrawals instead';
    END IF;
    -- ===========================================================
    -- VALIDATE SEALED: Check balance is zero
    -- ===========================================================
    ELSIF NEW.box_type = 'SEALED' THEN

	
        -- Get total deposits for this bucket + month
        SELECT COALESCE(SUM(amount), 0) INTO v_total_deposits
        FROM box_events
        WHERE bucket_id = NEW.bucket_id 
          AND month_id = NEW.month_id
          AND box_type = 'DEPOSIT';
        
        -- Get total withdrawals for this bucket + month
        SELECT COALESCE(SUM(amount), 0) INTO v_total_withdrawals
        FROM box_events
        WHERE bucket_id = NEW.bucket_id 
          AND month_id = NEW.month_id
          AND box_type = 'WITHDRAW';
        
        -- Calculate current balance
        v_available_balance := v_total_deposits - v_total_withdrawals;
        
        -- Can only seal when balance is zero
        IF v_available_balance != 0 THEN
            RAISE EXCEPTION 'Cannot seal bucket % month % with balance % (must be 0)', 
                NEW.bucket_id, NEW.month_id, v_available_balance;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_box_events_validate() OWNER TO postgres;

--
-- TOC entry 266 (class 1255 OID 45520)
-- Name: trg_block_direct_box_withdraw(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.trg_block_direct_box_withdraw() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.box_type = 'WITHDRAW' 
       AND current_setting('app.vault_operation_active', true) != 'true' THEN
        RAISE EXCEPTION 
            'Cannot directly insert WITHDRAW into box_events. Use blue_box_withdrawals instead.';
    END IF;

    IF NEW.box_type = 'SEALED'
       AND current_setting('app.vault_operation_active', true) != 'true' THEN
        RAISE EXCEPTION
            'Cannot manually seal a blue box. Sealing is automatic when balance reaches 0.';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.trg_block_direct_box_withdraw() OWNER TO postgres;

--
-- TOC entry 272 (class 1255 OID 45557)
-- Name: trg_blue_box_state_guard(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.trg_blue_box_state_guard() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_display_type VARCHAR(50);
BEGIN
    -- Only apply guard to BLUE buckets
    SELECT bc.display_type INTO v_display_type
    FROM bucket_configs bc
    WHERE bc.bucket_id = CASE TG_OP
        WHEN 'DELETE' THEN OLD.bucket_id
        ELSE NEW.bucket_id
    END;

    -- Not a BLUE bucket → allow everything
    IF v_display_type != 'BLUE' THEN
        RETURN CASE TG_OP WHEN 'DELETE' THEN OLD ELSE NEW END;
    END IF;

    -- BLUE bucket → only allow if vault_operation_active flag is set
      IF COALESCE(current_setting('app.vault_operation_active', true), 'false') != 'true' THEN
         IF TG_OP = 'INSERT' THEN
            RAISE EXCEPTION
                'Cannot manually insert into blue_box_state for BLUE bucket %. Managed automatically.',
                NEW.bucket_id;
        ELSIF TG_OP = 'UPDATE' THEN
            RAISE EXCEPTION
                'Cannot manually update blue_box_state for BLUE bucket %. Managed automatically.',
                NEW.bucket_id;
        END IF;
    END IF;

    RETURN CASE TG_OP WHEN 'DELETE' THEN OLD ELSE NEW END;
END;
$$;


ALTER FUNCTION public.trg_blue_box_state_guard() OWNER TO postgres;

--
-- TOC entry 271 (class 1255 OID 45554)
-- Name: trg_blue_box_withdrawal_before(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.trg_blue_box_withdrawal_before() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_is_sealed    BOOLEAN;
    v_entry_exists INTEGER;
BEGIN
    -- Check seal status
    SELECT is_sealed INTO v_is_sealed
    FROM blue_box_state
    WHERE bucket_id = NEW.bucket_id;
	-- AND month_id =NEW.month_id;

    IF NOT FOUND THEN
        INSERT INTO blue_box_state (bucket_id, is_sealed, sealed_date)
        VALUES (NEW.bucket_id, FALSE, NULL);
        v_is_sealed := FALSE;
    END IF;

    IF v_is_sealed = TRUE THEN
        RAISE EXCEPTION
            'Blue box bucket % is sealed. No withdrawals allowed.', NEW.bucket_id;
    END IF;

    -- Check monthly_entry exists
    SELECT id INTO v_entry_exists
    FROM monthly_entries
    WHERE month_id  = NEW.month_id
      AND bucket_id = NEW.bucket_id
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'No monthly_entry found for month_id=% bucket_id=%',
            NEW.month_id, NEW.bucket_id;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.trg_blue_box_withdrawal_before() OWNER TO postgres;

--
-- TOC entry 268 (class 1255 OID 45540)
-- Name: trg_blue_box_withdrawal_manage(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.trg_blue_box_withdrawal_manage() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_remaining     NUMERIC;
    r               RECORD;
    v_available     NUMERIC;
    v_total_balance NUMERIC;
    v_box_event_id  INTEGER;
BEGIN
    -- ===========================================================
    -- DELETE - remove sources + box_event + ledger
    -- ===========================================================
    IF TG_OP = 'DELETE' THEN
        BEGIN
            PERFORM set_config('app.vault_operation_active', 'true', true);

            -- Remove sources
            DELETE FROM blue_box_withdrawal_sources
	            WHERE withdrawal_id = OLD.id;

            -- Remove SPEND ledger via box_event
            DELETE FROM ledger_entries
            WHERE box_event_id IN (
                SELECT id FROM box_events
                WHERE bucket_id = OLD.bucket_id
				AND month_id = OLD.month_id
                  AND box_type  = 'WITHDRAW'
            )
            AND txn_type = 'SPEND';

            -- Remove WITHDRAW box_event
            DELETE FROM box_events
            WHERE bucket_id = OLD.bucket_id
			AND month_id = OLD.month_id
              AND box_type  = 'WITHDRAW'
              AND amount    = OLD.total_amount
              AND event_date = OLD.withdrawal_date;

            -- Remove SEALED box_event + unseal state if was sealed
            DELETE FROM box_events
            WHERE bucket_id = OLD.bucket_id
			AND month_id = OLD.month_id
              AND box_type  = 'SEALED';

            UPDATE blue_box_state
            SET is_sealed   = FALSE,
                sealed_date = NULL
            WHERE bucket_id = OLD.bucket_id;

            PERFORM set_config('app.vault_operation_active', 'false', true);
        EXCEPTION WHEN OTHERS THEN
            PERFORM set_config('app.vault_operation_active', 'false', true);
            RAISE;
        END;

        RETURN OLD;
    END IF;

    -- ===========================================================
    -- UPDATE - rebuild sources + update box_event + ledger
    -- ===========================================================
    IF TG_OP = 'UPDATE' THEN
        -- Find existing box_event for this withdrawal
        SELECT id INTO v_box_event_id
        FROM box_events
        WHERE bucket_id  = OLD.bucket_id
          AND box_type   = 'WITHDRAW'
          AND event_date = OLD.withdrawal_date -- timestamp can pinpoint exact record 
          AND month_id = OLD.month_id
		LIMIT 1;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'No WITHDRAW box_event found for withdrawal %', OLD.id;
        END IF;

        -- Rebuild sources from scratch
        DELETE FROM blue_box_withdrawal_sources
        WHERE withdrawal_id = NEW.id;

        -- Remove sealed state (will re-check after reallocation)
        DELETE FROM box_events
        WHERE bucket_id = OLD.bucket_id
          AND box_type  = 'SEALED';

        UPDATE blue_box_state
        SET is_sealed   = FALSE,
            sealed_date = NULL
        WHERE bucket_id = OLD.bucket_id;
    END IF;

    -- ===========================================================
    -- INSERT or UPDATE - allocate oldest monthly_entries first
    -- ===========================================================
    v_remaining := NEW.total_amount;

    FOR r IN
        SELECT
            me.id AS entry_id,
            me.allocated - COALESCE((
                SELECT SUM(bbws.amount_taken)
                FROM blue_box_withdrawal_sources bbws
                WHERE bbws.source_entry_id = me.id
            ), 0) AS remaining
        FROM monthly_entries me
        WHERE me.bucket_id = NEW.bucket_id
          AND me.allocated - COALESCE((
                SELECT SUM(bbws.amount_taken)
                FROM blue_box_withdrawal_sources bbws
                WHERE bbws.source_entry_id = me.id
            ), 0) > 0
        ORDER BY me.month_id ASC
    LOOP
        EXIT WHEN v_remaining <= 0;

        v_available := r.remaining;

        INSERT INTO blue_box_withdrawal_sources (
		-- 1. Creates a record showing which monthly entry funded this withdrawal
-- 2. Records HOW MUCH was taken from that monthly entry
            withdrawal_id,
            source_entry_id,
            amount_taken
        ) VALUES (
            NEW.id,
            r.entry_id,
            LEAST(v_remaining, v_available)
        );

        v_remaining := v_remaining - LEAST(v_remaining, v_available);
    END LOOP;

    -- Safety: reject if balance insufficient
    IF v_remaining > 0 THEN
        RAISE EXCEPTION
            'Blue box does not have enough balance. Shortfall: %', v_remaining;
    END IF;

    -- ===========================================================
    -- LEDGER + BOX_EVENTS: Record or update
    -- ===========================================================
    PERFORM set_config('app.vault_operation_active', 'true', true);

    IF TG_OP = 'INSERT' THEN
        -- box_events trigger will create SPEND ledger automatically
        INSERT INTO box_events (
            bucket_id, month_id, box_type,
            amount, description, event_date
        ) VALUES (
            NEW.bucket_id, NEW.month_id, 'WITHDRAW',
            NEW.total_amount,
            COALESCE(NEW.description, format('Blue box WITHDRAW #%s', NEW.id)),
            NEW.withdrawal_date
        );

    ELSIF TG_OP = 'UPDATE' THEN
        -- Update existing box_event
        UPDATE box_events
        SET amount      = NEW.total_amount,
            description = COALESCE(NEW.description, format('Blue box WITHDRAW #%s (updated)', NEW.id)),
            event_date  = NEW.withdrawal_date
        WHERE id = v_box_event_id;

        -- Update SPEND ledger tied to this box_event
        UPDATE ledger_entries
        SET amount   = NEW.total_amount,
            txn_date = NEW.withdrawal_date
        WHERE box_event_id = v_box_event_id
          AND txn_type     = 'SPEND';
    END IF;

    -- ===========================================================
    -- STEP 3: Check if total balance = 0 → auto seal
    -- ===========================================================
 SELECT
    (
        SELECT COALESCE(SUM(be.amount), 0)
        FROM box_events be
        WHERE be.bucket_id = NEW.bucket_id
          AND be.box_type  = 'DEPOSIT'
    )
    -
    (
        SELECT COALESCE(SUM(bbws.amount_taken), 0)
        FROM blue_box_withdrawal_sources bbws
        JOIN monthly_entries me ON me.id = bbws.source_entry_id
        WHERE me.bucket_id = NEW.bucket_id
    )
    INTO v_total_balance;

    IF v_total_balance = 0 THEN
        INSERT INTO box_events (
            bucket_id, month_id, box_type,
            amount, description, event_date
        ) VALUES (
            NEW.bucket_id, NEW.month_id, 'SEALED',
            NULL, 'Auto-sealed: balance reached 0',
            NEW.withdrawal_date
        );
    END IF;

    PERFORM set_config('app.vault_operation_active', 'false', true);

    RETURN NEW;

EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('app.vault_operation_active', 'false', true);
    RAISE;
END;
$$;


ALTER FUNCTION public.trg_blue_box_withdrawal_manage() OWNER TO postgres;

--
-- TOC entry 265 (class 1255 OID 45258)
-- Name: trg_ledger_block_vault_delete(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.trg_ledger_block_vault_delete() RETURNS trigger
    LANGUAGE plpgsql
    AS $$BEGIN
    IF OLD.vault_wd_id IS NOT NULL  
       AND current_setting('app.vault_operation_active', true) != 'true' THEN
        RAISE EXCEPTION 'Cannot directly delete ledger entry tied to vault_wd_id=%', OLD.vault_wd_id;
    END IF;

    RETURN OLD;
END;$$;


ALTER FUNCTION public.trg_ledger_block_vault_delete() OWNER TO postgres;

--
-- TOC entry 267 (class 1255 OID 45216)
-- Name: trg_ledger_sync(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.trg_ledger_sync() RETURNS trigger
    LANGUAGE plpgsql
    AS $$DECLARE
    v_entry_id          INTEGER;
    v_bucket_id         INTEGER;
    v_monthly_allocated DECIMAL(10,2);
    v_current_spent     DECIMAL(10,2);
    v_remaining         DECIMAL(10,2);
    v_delta             DECIMAL(10,2);
    v_bucket_role       VARCHAR(50);
    v_display_type      VARCHAR(50);
BEGIN
    -- ===========================================================
    -- INSERT: Block direct inserts when vault operation not active
    -- ===========================================================

	
    IF TG_OP = 'INSERT' THEN
        IF current_setting('app.vault_operation_active', true) != 'true' THEN

            SELECT bt.vault_role, bc.display_type
            INTO v_bucket_role, v_display_type
            FROM bucket_types bt
            JOIN bucket_configs bc ON bt.type_name = bc.display_type
            WHERE bc.bucket_id = NEW.bucket_id;

            -- Block direct inserts for YELLOW vault bucket
            IF v_bucket_role = 'DRIP_IN'
               AND v_display_type = 'YELLOW'
               AND NEW.txn_type = 'VAULT_CREDIT'
               AND NEW.vault_credit_id IS NULL
               AND NEW.vault_wd_id IS NULL THEN
                RAISE EXCEPTION
                    'Direct ledger inserts not allowed for vault bucket % (YELLOW / DRIP_IN).',
                    NEW.bucket_id;
            END IF;

            -- Block direct inserts for blue box bucket
        -- Any insert with no source tracking = direct manual insert = blocked
         -- Block direct inserts for BLUE box bucket only
        IF v_display_type = 'BLUE'
           AND NEW.box_event_id IS NULL THEN
            RAISE EXCEPTION
                'Direct ledger inserts not allowed for blue box bucket %. Use box_events instead.',
                NEW.bucket_id;
        END IF;

        END IF;
        -- NO RETURN HERE → always falls through to spent update ✅
    END IF;

    -- ===========================================================
    -- UPDATE: Block direct updates on vault/blue box ledger rows
    -- ===========================================================
    IF TG_OP = 'UPDATE'  THEN
        IF current_setting('app.vault_operation_active', true) != 'true' THEN
            IF OLD.vault_credit_id IS NOT NULL
               OR OLD.vault_wd_id IS NOT NULL
               OR OLD.box_event_id IS NOT NULL THEN
                RAISE EXCEPTION
                    'Cannot directly modify vault or blue box ledger entries. Update source tables instead.';
            END IF;
        END IF;
    END IF;

    -- ===========================================================
    -- Resolve entry_id and bucket_id for all operations
    -- ===========================================================
    v_entry_id  := CASE TG_OP WHEN 'DELETE' THEN OLD.monthly_entry_id ELSE NEW.monthly_entry_id END;
    v_bucket_id := CASE TG_OP WHEN 'DELETE' THEN OLD.bucket_id        ELSE NEW.bucket_id        END;

    -- ===========================================================
    -- STEP 1: Lock monthly_entries row
    -- ===========================================================
    SELECT me.allocated
    INTO   v_monthly_allocated
    FROM   monthly_entries me
    WHERE  me.month_id  = v_entry_id
      AND  me.bucket_id = v_bucket_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'No monthly_entry found for monthly_entry_id=% / bucket_id=%',
            v_entry_id, v_bucket_id;
    END IF;

    -- ===========================================================
    -- STEP 2: Compute live spent
    -- Exclude CONTRIBUTION (it funds, not spends)
    -- ===========================================================
    SELECT COALESCE(SUM(le.amount), 0)
    INTO   v_current_spent
    FROM   ledger_entries le
    WHERE  le.monthly_entry_id = v_entry_id
      AND  le.bucket_id        = v_bucket_id
      AND  le.txn_type        != 'CONTRIBUTION'
      AND (
           TG_OP = 'INSERT'
        OR (TG_OP = 'UPDATE' AND le.id != OLD.id)
        OR (TG_OP = 'DELETE' AND le.id != OLD.id)
      );

    -- ===========================================================
    -- STEP 3: Delta calculation
    -- ===========================================================
    v_delta := CASE TG_OP
                   WHEN 'INSERT' THEN  NEW.amount
                   WHEN 'UPDATE' THEN  NEW.amount - OLD.amount
                   WHEN 'DELETE' THEN -OLD.amount
               END;

    v_remaining := v_monthly_allocated - v_current_spent;

    -- ===========================================================
    -- STEP 4: Budget guard
    -- Skip for:
    --   DELETE          → no NEW to check
    --   CONTRIBUTION    → funds the bucket
    --   VAULT_WITHDRAWAL→ funds target bucket
    --   box_event_id    → blue box already validated in its own trigger
    --   vault_wd_id     → vault already validated in vault trigger
    --   vault_credit_id → vault drip already validated in vault trigger
    -- ===========================================================
    IF TG_OP != 'DELETE'
       AND NEW.txn_type NOT IN ('CONTRIBUTION', 'VAULT_WITHDRAWAL')
       AND NEW.box_event_id    IS NULL
       AND NEW.vault_wd_id     IS NULL
       AND NEW.vault_credit_id IS NULL
       AND v_delta > 0
       AND v_delta > v_remaining THEN
        RAISE EXCEPTION
            'Budget exceeded — bucket_id=%, allocated=%, spent=%, remaining=%, attempted=%, max_allowed=%',
            v_bucket_id,
            v_monthly_allocated,
            v_current_spent,
            v_remaining,
            v_delta,
            v_remaining;
    END IF;

    -- ===========================================================
    -- STEP 5: Update monthly_entries.spent (all txn_types)
    -- ===========================================================
    PERFORM set_config('app.ledger_recalc_active', 'true', true);

    UPDATE monthly_entries
    SET spent = (
        SELECT COALESCE(SUM(le.amount), 0)
        FROM   ledger_entries le
        WHERE  le.monthly_entry_id = v_entry_id
          AND  le.bucket_id        = v_bucket_id
         AND  le.txn_type        != 'CONTRIBUTION'  -- ← exclude CONTRIBUTION
    )
    WHERE  month_id  = v_entry_id
      AND  bucket_id = v_bucket_id;

    PERFORM set_config('app.ledger_recalc_active', 'false', true);

    RETURN CASE TG_OP WHEN 'DELETE' THEN OLD ELSE NEW END;
END;$$;


ALTER FUNCTION public.trg_ledger_sync() OWNER TO postgres;

--
-- TOC entry 261 (class 1255 OID 45218)
-- Name: trg_ledger_truncate_sync(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.trg_ledger_truncate_sync() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- When all ledger rows are wiped, reset ALL spent to 0
    PERFORM set_config('app.ledger_recalc_active', 'true', true);

    UPDATE monthly_entries
    SET    spent = 0;

    PERFORM set_config('app.ledger_recalc_active', 'false', true);

    RETURN NULL; -- TRUNCATE triggers must return NULL
END;
$$;


ALTER FUNCTION public.trg_ledger_truncate_sync() OWNER TO postgres;

--
-- TOC entry 262 (class 1255 OID 45220)
-- Name: trg_protect_spent(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.trg_protect_spent() RETURNS trigger
    LANGUAGE plpgsql
    AS $$BEGIN
    IF current_setting('app.ledger_recalc_active', true) = 'true' THEN
        RETURN NEW;  -- bypassing the trigger rule 
    END IF;

	-- this is just a variable to keep tack of flag status. connected with trg_ledger_truncate_sync()

--- below we are applying rule , which means  app.ledger_recalc_active = false (TRUNCATE trigger thing) 
    IF NEW.spent IS DISTINCT FROM OLD.spent THEN
        RAISE EXCEPTION
        'spent column is system controlled and cannot be manually updated';
    END IF;

    RETURN NEW;
END;$$;


ALTER FUNCTION public.trg_protect_spent() OWNER TO postgres;

--
-- TOC entry 264 (class 1255 OID 45254)
-- Name: trg_vault_entries_after_insert(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.trg_vault_entries_after_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Create ledger entry AFTER vault entry is inserted (so NEW.id exists)
    INSERT INTO ledger_entries (
        monthly_entry_id,
        bucket_id,
		vault_credit_id,
        description,
        amount,
        txn_date,
        txn_type
    ) VALUES (
        NEW.month_id,
        NEW.bucket_id,
		NEW.id,
    format('VAULT_CREDIT to vault #%s', NEW.id),
    NEW.total_drip,
    NEW.drip_date,
    'VAULT_CREDIT'  
    );
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.trg_vault_entries_after_insert() OWNER TO postgres;

--
-- TOC entry 263 (class 1255 OID 45252)
-- Name: trg_vault_entries_before_ops(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.trg_vault_entries_before_ops() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_allocated     DECIMAL(10,2);
    v_spent         DECIMAL(10,2);
    v_remaining     DECIMAL(10,2);
    v_bucket_role   VARCHAR(50);
    v_display_type  VARCHAR(50);
    v_ledger_id     INTEGER;
BEGIN
    -- ===========================================================
    -- CASE 1: INSERT - Create new drip
    -- ===========================================================
    IF TG_OP = 'INSERT' THEN
        -- Step 1: Validate bucket eligibility
        SELECT 
            bt.vault_role,
            bc.display_type
        INTO 
            v_bucket_role,
            v_display_type
        FROM bucket_types bt
        JOIN bucket_configs bc ON bt.type_name = bc.display_type
        WHERE bc.bucket_id = NEW.bucket_id;
        
        -- Validation: Is this bucket allowed to drip?
        IF v_bucket_role != 'DRIP_IN' THEN
            RAISE EXCEPTION 'Bucket % is not DRIP_IN type (role: %)', 
                NEW.bucket_id, v_bucket_role;
        END IF;
        
        IF v_display_type != 'YELLOW' THEN
            RAISE EXCEPTION 'Bucket % is not YELLOW display (type: %)', 
                NEW.bucket_id, v_display_type;
        END IF;
        
        -- Step 2: Get monthly allocated and spent
        SELECT 
            me.allocated,
            me.spent
        INTO 
            v_allocated,
            v_spent
        FROM monthly_entries me
        WHERE me.month_id = NEW.month_id 
          AND me.bucket_id = NEW.bucket_id;

        -- Safety check: Monthly entry must exist
        IF NOT FOUND THEN
            RAISE EXCEPTION 'No monthly entry found for month_id=% bucket_id=%', 
                NEW.month_id, NEW.bucket_id;
        END IF;
        
        -- Calculate how much is left
        v_remaining := v_allocated - v_spent;

        -- Step 3: Check if enough budget remains
        IF NEW.total_drip > v_remaining THEN
            RAISE EXCEPTION 'DRIP EXCEEDS BUDGET: Remaining=%, Attempted=%',
                v_remaining, NEW.total_drip;
        END IF;

        -- Step 4: Let Postgres auto-assign ID (no manual nextval)
        -- We'll create ledger entry in AFTER trigger
        RETURN NEW; -- after this insert is done by postgresql, then we will run after_insert trigger point (where orginal ledger_entry INSERT is done).

    -- ===========================================================
    -- CASE 2: UPDATE - Amount changed! Adjust ledger entry
    -- ===========================================================
    ELSIF TG_OP = 'UPDATE' THEN

	    -- 🚫 BLOCK bucket_id changes
    IF NEW.bucket_id != OLD.bucket_id THEN
        RAISE EXCEPTION 'Cannot change bucket_id of vault entry';
    END IF;

    -- 🚫 BLOCK month_id changes
    IF NEW.month_id != OLD.month_id THEN
        RAISE EXCEPTION 'Cannot change month_id of vault entry';
    END IF;
        -- Find the corresponding ledger entry (with LIMIT 1 for safety)
        SELECT id INTO v_ledger_id
        FROM ledger_entries
        WHERE vault_credit_id = OLD.id
          AND txn_type = 'CONTRIBUTION'
        LIMIT 1;  -- Safety: prevent multiple row error
        
        IF NOT FOUND THEN
            RAISE EXCEPTION 'No ledger entry found for vault entry %', OLD.id;
        END IF;
  -- 🔴 FIX: Set flag before updating ledger!
        PERFORM set_config('app.vault_operation_active', 'true', true);
		
        -- If amount changed, we need to check budget again
        IF NEW.total_drip != OLD.total_drip THEN
            -- Get current allocated and spent
            SELECT 
                me.allocated,
                me.spent
            INTO 
                v_allocated,
                v_spent
            FROM monthly_entries me
            WHERE me.month_id = NEW.month_id 
              AND me.bucket_id = NEW.bucket_id;

            -- Calculate remaining (considering OLD amount will be removed)
            v_remaining := (v_allocated - (v_spent - OLD.total_drip));

            -- Check if new amount fits
            IF NEW.total_drip > v_remaining THEN
                RAISE EXCEPTION 'Updated amount % exceeds remaining budget %',
                    NEW.total_drip, v_remaining;
            END IF;

            -- Update the ledger entry amount
            UPDATE ledger_entries
            SET amount = NEW.total_drip,
                description = format('DRIP to vault #%s (updated)', NEW.id),
                txn_date = NEW.drip_date
            WHERE id = v_ledger_id;

        END IF;
        
			 -- 🔴 FIX: Reset flag after update
        PERFORM set_config('app.vault_operation_active', 'false', true);
		
        RETURN NEW;

    -- ===========================================================
    -- CASE 3: DELETE - Remove drip and its ledger entry
    -- ===========================================================
    ELSIF TG_OP = 'DELETE' THEN
	   -- Tell the guard this delete is coming from vault, not a direct user delete
  BEGIN
        PERFORM set_config('app.vault_operation_active', 'true', true);

        DELETE FROM ledger_entries
         WHERE (vault_wd_id = OLD.id OR vault_credit_id = OLD.id)
          AND txn_type = 'CONTRIBUTION';

        PERFORM set_config('app.vault_operation_active', 'false', true);

    EXCEPTION WHEN OTHERS THEN
        PERFORM set_config('app.vault_operation_active', 'false', true);
        RAISE;
    END;

    RETURN OLD;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.trg_vault_entries_before_ops() OWNER TO postgres;

--
-- TOC entry 249 (class 1255 OID 45400)
-- Name: trg_vault_withdrawal_manage(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.trg_vault_withdrawal_manage() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_remaining  NUMERIC;
    r            RECORD;
    v_available  NUMERIC;
    v_ledger_id  INTEGER;
    v_vault_ledger_id INTEGER;
BEGIN
    -- ===========================================================
    -- DELETE - remove sources + remove ledger entries
    -- ===========================================================
    IF TG_OP = 'DELETE' THEN
        BEGIN
            PERFORM set_config('app.vault_operation_active', 'true', true);

            -- Remove sources first
            DELETE FROM vault_withdrawal_sources
            WHERE withdrawal_id = OLD.id;

            -- Remove SPEND ledger (source bucket)
            DELETE FROM ledger_entries
            WHERE vault_wd_id = OLD.id
              AND txn_type = 'SPEND';

            -- Remove VAULT_WITHDRAWAL ledger (target bucket)
            DELETE FROM ledger_entries
            WHERE vault_wd_id = OLD.id
              AND txn_type = 'VAULT_WITHDRAWAL';

            -- Reverse allocated on target bucket if it was funded
            IF OLD.target_bucket_id IS NOT NULL THEN
                UPDATE monthly_entries
                SET allocated = allocated - OLD.total_amount
                WHERE month_id  = OLD.month_id
                  AND bucket_id = OLD.target_bucket_id;
            END IF;

            PERFORM set_config('app.vault_operation_active', 'false', true);
        EXCEPTION WHEN OTHERS THEN
            PERFORM set_config('app.vault_operation_active', 'false', true);
            RAISE;
        END;

        RETURN OLD;
    END IF;

    -- ===========================================================
    -- UPDATE - rebuild sources + update ledger entries
    -- ===========================================================
    IF TG_OP = 'UPDATE' THEN
        -- Find existing SPEND ledger entry
        SELECT id INTO v_ledger_id
        FROM ledger_entries
        WHERE vault_wd_id = OLD.id
          AND txn_type = 'SPEND'
        LIMIT 1;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'No SPEND ledger entry found for withdrawal %', OLD.id;
        END IF;

        -- Find existing VAULT_WITHDRAWAL ledger entry if target bucket exists
        IF OLD.target_bucket_id IS NOT NULL THEN
            SELECT id INTO v_vault_ledger_id
            FROM ledger_entries
            WHERE vault_wd_id = OLD.id
              AND txn_type = 'VAULT_WITHDRAWAL'
            LIMIT 1;

            -- Reverse old allocated on target bucket
            UPDATE monthly_entries
            SET allocated = allocated - OLD.total_amount
            WHERE month_id  = OLD.month_id
              AND bucket_id = OLD.target_bucket_id;
        END IF;

        -- Rebuild sources from scratch
        DELETE FROM vault_withdrawal_sources
        WHERE withdrawal_id = NEW.id;
    END IF;

    -- ===========================================================
    -- INSERT or UPDATE - allocate oldest month first
    -- ===========================================================
    v_remaining := NEW.total_amount;

    FOR r IN
        SELECT
            ve.id                                                AS vault_entry_id,
            ve.total_drip - COALESCE(SUM(vws.amount_taken), 0)  AS remaining
        FROM vault_entries ve
        LEFT JOIN vault_withdrawal_sources vws
            ON ve.id = vws.source_month_id
        WHERE ve.bucket_id = NEW.bucket_id
        GROUP BY ve.id, ve.total_drip, ve.month_id, ve.drip_date
        HAVING (ve.total_drip - COALESCE(SUM(vws.amount_taken), 0)) > 0
        ORDER BY ve.month_id ASC, ve.drip_date ASC
    LOOP
        EXIT WHEN v_remaining <= 0;

        v_available := r.remaining;

        INSERT INTO vault_withdrawal_sources (
            withdrawal_id,
            source_month_id,
            amount_taken
        ) VALUES (
            NEW.id,
            r.vault_entry_id,
            LEAST(v_remaining, v_available)
        );

        v_remaining := v_remaining - LEAST(v_remaining, v_available);
    END LOOP;

    -- Safety: reject if vault balance insufficient
    IF v_remaining > 0 THEN
        RAISE EXCEPTION
            'Vault does not have enough balance. Shortfall: %', v_remaining;
    END IF;

    -- ===========================================================
    -- LEDGER + ALLOCATED: Record or update transactions
    -- ===========================================================
    PERFORM set_config('app.vault_operation_active', 'true', true);

    IF TG_OP = 'INSERT' THEN

        -- SPEND entry on source bucket (Yellow)
        INSERT INTO ledger_entries (
            monthly_entry_id,
            bucket_id,
            vault_wd_id,
            description,
            amount,
            txn_date,
            txn_type
        ) VALUES (
            NEW.month_id,
            NEW.bucket_id,
            NEW.id,
            format('VAULT SPEND from vault #%s - %s', NEW.id, NEW.item_name),
            NEW.total_amount,
            NEW.withdrawal_date,
            'SPEND'
        );

        -- VAULT_WITHDRAWAL entry on target bucket + fund allocated
        IF NEW.target_bucket_id IS NOT NULL THEN
            INSERT INTO ledger_entries (
                monthly_entry_id,
                bucket_id,
                vault_wd_id,
                description,
                amount,
                txn_date,
                txn_type
            ) VALUES (
                NEW.month_id,
                NEW.target_bucket_id,
                NEW.id,
                format('VAULT_WITHDRAWAL received from vault #%s - %s', NEW.id, NEW.item_name),
                NEW.total_amount,
                NEW.withdrawal_date,
                'VAULT_WITHDRAWAL'
            );

            -- Fund the target bucket
            UPDATE monthly_entries
            SET allocated = allocated + NEW.total_amount
            WHERE month_id  = NEW.month_id
              AND bucket_id = NEW.target_bucket_id;
        END IF;

    ELSIF TG_OP = 'UPDATE' THEN

        -- Update SPEND ledger
        UPDATE ledger_entries
        SET amount      = NEW.total_amount,
            description = format('VAULT SPEND from vault #%s - %s (updated)', NEW.id, NEW.item_name),
            txn_date    = NEW.withdrawal_date
        WHERE id = v_ledger_id;

        -- Update VAULT_WITHDRAWAL ledger + re-fund allocated
        IF NEW.target_bucket_id IS NOT NULL THEN
            IF v_vault_ledger_id IS NOT NULL THEN
                UPDATE ledger_entries
                SET amount      = NEW.total_amount,
                    description = format('VAULT_WITHDRAWAL received from vault #%s - %s (updated)', NEW.id, NEW.item_name),
                    txn_date    = NEW.withdrawal_date
                WHERE id = v_vault_ledger_id;
            ELSE
                -- target_bucket_id was added on update, create fresh
                INSERT INTO ledger_entries (
                    monthly_entry_id,
                    bucket_id,
                    vault_wd_id,
                    description,
                    amount,
                    txn_date,
                    txn_type
                ) VALUES (
                    NEW.month_id,
                    NEW.target_bucket_id,
                    NEW.id,
                    format('VAULT_WITHDRAWAL received from vault #%s - %s', NEW.id, NEW.item_name),
                    NEW.total_amount,
                    NEW.withdrawal_date,
                    'VAULT_WITHDRAWAL'
                );
            END IF;

            -- Re-fund target bucket with new amount
            UPDATE monthly_entries
            SET allocated = allocated + NEW.total_amount
            WHERE month_id  = NEW.month_id
              AND bucket_id = NEW.target_bucket_id;
        END IF;

    END IF;

    PERFORM set_config('app.vault_operation_active', 'false', true);

    RETURN NEW;

EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('app.vault_operation_active', 'false', true);
    RAISE;
END;
$$;


ALTER FUNCTION public.trg_vault_withdrawal_manage() OWNER TO postgres;

--
-- TOC entry 248 (class 1255 OID 45387)
-- Name: trg_vws_block_direct_delete(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.trg_vws_block_direct_delete() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF current_setting('app.vault_operation_active', true) != 'true' THEN
        RAISE EXCEPTION 'Cannot directly delete vault_withdrawal_sources. Delete from vault_withdrawals instead.';
    END IF;
    RETURN OLD;
END;
$$;


ALTER FUNCTION public.trg_vws_block_direct_delete() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 246 (class 1259 OID 45560)
-- Name: users; Type: TABLE; Schema: auth; Owner: postgres
--

CREATE TABLE auth.users (
    user_id uuid DEFAULT gen_random_uuid() NOT NULL,
    phone character varying(20) NOT NULL,
    phone_verified boolean DEFAULT false,
    name character varying(100) NOT NULL,
    password_hash character varying(255) NOT NULL,
    profile_image_url text,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT users_phone_check CHECK (((phone)::text ~ '^[+]?[0-9]{10,15}$'::text))
);


ALTER TABLE auth.users OWNER TO postgres;

--
-- TOC entry 245 (class 1259 OID 45506)
-- Name: blue_box_state; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.blue_box_state (
    id integer NOT NULL,
    bucket_id integer NOT NULL,
    is_sealed boolean DEFAULT false NOT NULL,
    sealed_date timestamp without time zone
);


ALTER TABLE public.blue_box_state OWNER TO postgres;

--
-- TOC entry 244 (class 1259 OID 45505)
-- Name: blue_box_state_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.blue_box_state_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.blue_box_state_id_seq OWNER TO postgres;

--
-- TOC entry 5131 (class 0 OID 0)
-- Dependencies: 244
-- Name: blue_box_state_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.blue_box_state_id_seq OWNED BY public.blue_box_state.id;


--
-- TOC entry 243 (class 1259 OID 45488)
-- Name: blue_box_withdrawal_sources; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.blue_box_withdrawal_sources (
    id integer NOT NULL,
    withdrawal_id integer NOT NULL,
    source_entry_id integer NOT NULL,
    amount_taken numeric(10,2) NOT NULL,
    CONSTRAINT check_amount_taken CHECK ((amount_taken > (0)::numeric))
);


ALTER TABLE public.blue_box_withdrawal_sources OWNER TO postgres;

--
-- TOC entry 242 (class 1259 OID 45487)
-- Name: blue_box_withdrawal_sources_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.blue_box_withdrawal_sources_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.blue_box_withdrawal_sources_id_seq OWNER TO postgres;

--
-- TOC entry 5134 (class 0 OID 0)
-- Dependencies: 242
-- Name: blue_box_withdrawal_sources_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.blue_box_withdrawal_sources_id_seq OWNED BY public.blue_box_withdrawal_sources.id;


--
-- TOC entry 241 (class 1259 OID 45469)
-- Name: blue_box_withdrawals; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.blue_box_withdrawals (
    id integer NOT NULL,
    bucket_id integer NOT NULL,
    month_id integer NOT NULL,
    total_amount numeric(10,2) NOT NULL,
    description character varying(100),
    withdrawal_date timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT check_withdrawal_amount CHECK ((total_amount > (0)::numeric))
);


ALTER TABLE public.blue_box_withdrawals OWNER TO postgres;

--
-- TOC entry 240 (class 1259 OID 45468)
-- Name: blue_box_withdrawals_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.blue_box_withdrawals_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.blue_box_withdrawals_id_seq OWNER TO postgres;

--
-- TOC entry 5137 (class 0 OID 0)
-- Dependencies: 240
-- Name: blue_box_withdrawals_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.blue_box_withdrawals_id_seq OWNED BY public.blue_box_withdrawals.id;


--
-- TOC entry 239 (class 1259 OID 45449)
-- Name: box_events; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.box_events (
    id integer NOT NULL,
    bucket_id integer NOT NULL,
    month_id integer NOT NULL,
    box_type character varying(20) NOT NULL,
    amount numeric(10,2),
    description character varying(100),
    event_date timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT check_amount_positive CHECK (((amount IS NULL) OR (amount >= (0)::numeric))),
    CONSTRAINT check_box_type CHECK (((box_type)::text = ANY ((ARRAY['DEPOSIT'::character varying, 'WITHDRAW'::character varying, 'SEALED'::character varying])::text[])))
);


ALTER TABLE public.box_events OWNER TO postgres;

--
-- TOC entry 238 (class 1259 OID 45448)
-- Name: box_events_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.box_events_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.box_events_id_seq OWNER TO postgres;

--
-- TOC entry 5140 (class 0 OID 0)
-- Dependencies: 238
-- Name: box_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.box_events_id_seq OWNED BY public.box_events.id;


--
-- TOC entry 227 (class 1259 OID 45141)
-- Name: ledger_entries; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.ledger_entries (
    id integer NOT NULL,
    monthly_entry_id integer NOT NULL,
    bucket_id integer NOT NULL,
    vault_wd_id integer,
    description character varying(150),
    amount numeric(10,2),
    txn_date timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    txn_type character varying(20) NOT NULL,
    vault_credit_id integer,
    box_event_id integer,
    CONSTRAINT check_amount_positive CHECK ((amount >= (0)::numeric)),
    CONSTRAINT check_txn_type CHECK (((txn_type)::text = ANY ((ARRAY['CONTRIBUTION'::character varying, 'VAULT_CREDIT'::character varying, 'VAULT_WITHDRAWAL'::character varying, 'SPEND'::character varying])::text[])))
);


ALTER TABLE public.ledger_entries OWNER TO postgres;

--
-- TOC entry 224 (class 1259 OID 45065)
-- Name: monthly_entries; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.monthly_entries (
    id integer NOT NULL,
    month_id integer NOT NULL,
    bucket_id integer NOT NULL,
    allocated numeric(10,2),
    spent numeric(10,2) DEFAULT 0 NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT check_allocated_positive CHECK ((allocated >= (0)::numeric)),
    CONSTRAINT check_spent_positive CHECK ((spent >= (0)::numeric))
);


ALTER TABLE public.monthly_entries OWNER TO postgres;

--
-- TOC entry 230 (class 1259 OID 45247)
-- Name: bucket_budget_status_v; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.bucket_budget_status_v AS
 WITH bucket_wise_spent_amount AS (
         SELECT le.monthly_entry_id,
            le.bucket_id,
            sum(le.amount) AS spent_amount
           FROM public.ledger_entries le
          GROUP BY le.bucket_id, le.monthly_entry_id
        )
 SELECT me.month_id,
    COALESCE(me.allocated, (0)::numeric) AS allocated_amount,
    bwsa.spent_amount AS actual_spent_amount,
    (COALESCE(me.allocated, (0)::numeric) - bwsa.spent_amount) AS remaining_amount
   FROM (public.monthly_entries me
     RIGHT JOIN bucket_wise_spent_amount bwsa ON (((me.bucket_id = bwsa.bucket_id) AND (me.month_id = bwsa.monthly_entry_id))));


ALTER VIEW public.bucket_budget_status_v OWNER TO postgres;

--
-- TOC entry 222 (class 1259 OID 45053)
-- Name: bucket_configs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.bucket_configs (
    bucket_id integer NOT NULL,
    bucket_name character varying(20),
    display_type character varying(20),
    display_order integer,
    is_active boolean,
    notes character varying(150)
);


ALTER TABLE public.bucket_configs OWNER TO postgres;

--
-- TOC entry 221 (class 1259 OID 45052)
-- Name: bucket_configs_bucket_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.bucket_configs_bucket_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.bucket_configs_bucket_id_seq OWNER TO postgres;

--
-- TOC entry 5146 (class 0 OID 0)
-- Dependencies: 221
-- Name: bucket_configs_bucket_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.bucket_configs_bucket_id_seq OWNED BY public.bucket_configs.bucket_id;


--
-- TOC entry 220 (class 1259 OID 45047)
-- Name: bucket_types; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.bucket_types (
    type_name character varying(20) NOT NULL,
    color character varying(20),
    description character varying(150),
    vault_role character varying(50)
);


ALTER TABLE public.bucket_types OWNER TO postgres;

--
-- TOC entry 247 (class 1259 OID 45575)
-- Name: customers; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.customers (
    id uuid NOT NULL,
    name text NOT NULL,
    age numeric,
    city text
);


ALTER TABLE public.customers OWNER TO postgres;

--
-- TOC entry 226 (class 1259 OID 45140)
-- Name: ledger_entries_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.ledger_entries_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.ledger_entries_id_seq OWNER TO postgres;

--
-- TOC entry 5149 (class 0 OID 0)
-- Dependencies: 226
-- Name: ledger_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.ledger_entries_id_seq OWNED BY public.ledger_entries.id;


--
-- TOC entry 219 (class 1259 OID 45041)
-- Name: paychecks; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.paychecks (
    month_id integer NOT NULL,
    month_label character varying(20),
    salary numeric(10,2),
    notes character varying(150)
);


ALTER TABLE public.paychecks OWNER TO postgres;

--
-- TOC entry 225 (class 1259 OID 45100)
-- Name: monthly_budget_summary; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.monthly_budget_summary AS
 SELECT p.month_label AS month,
    bc.bucket_name AS bucket,
    bc.display_type AS bucket_code,
    me.allocated AS budgeted_amount,
    me.spent AS actual_spent
   FROM ((public.monthly_entries me
     JOIN public.bucket_configs bc ON ((me.bucket_id = bc.bucket_id)))
     JOIN public.paychecks p ON ((p.month_id = me.month_id)))
  ORDER BY p.month_label, bc.bucket_name;


ALTER VIEW public.monthly_budget_summary OWNER TO postgres;

--
-- TOC entry 223 (class 1259 OID 45064)
-- Name: monthly_entries_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.monthly_entries_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.monthly_entries_id_seq OWNER TO postgres;

--
-- TOC entry 5153 (class 0 OID 0)
-- Dependencies: 223
-- Name: monthly_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.monthly_entries_id_seq OWNED BY public.monthly_entries.id;


--
-- TOC entry 218 (class 1259 OID 45040)
-- Name: paychecks_month_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.paychecks_month_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.paychecks_month_id_seq OWNER TO postgres;

--
-- TOC entry 5155 (class 0 OID 0)
-- Dependencies: 218
-- Name: paychecks_month_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.paychecks_month_id_seq OWNED BY public.paychecks.month_id;


--
-- TOC entry 229 (class 1259 OID 45166)
-- Name: vault_entries; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.vault_entries (
    id integer NOT NULL,
    month_id integer NOT NULL,
    bucket_id integer NOT NULL,
    total_drip numeric(10,2),
    drip_date timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT check_total_drip_positive CHECK ((total_drip >= (0)::numeric))
);


ALTER TABLE public.vault_entries OWNER TO postgres;

--
-- TOC entry 228 (class 1259 OID 45165)
-- Name: vault_entries_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.vault_entries_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.vault_entries_id_seq OWNER TO postgres;

--
-- TOC entry 5158 (class 0 OID 0)
-- Dependencies: 228
-- Name: vault_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.vault_entries_id_seq OWNED BY public.vault_entries.id;


--
-- TOC entry 236 (class 1259 OID 45345)
-- Name: vault_withdrawal_sources; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.vault_withdrawal_sources (
    id integer NOT NULL,
    withdrawal_id integer NOT NULL,
    source_month_id integer NOT NULL,
    amount_taken numeric(10,2) NOT NULL,
    CONSTRAINT check_amount_taken_positive CHECK ((amount_taken >= (0)::numeric))
);


ALTER TABLE public.vault_withdrawal_sources OWNER TO postgres;

--
-- TOC entry 237 (class 1259 OID 45368)
-- Name: vault_status; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vault_status AS
 SELECT ve.id AS vault_entry_id,
    ve.month_id,
    ve.bucket_id,
    ve.drip_date,
    ve.total_drip,
    COALESCE(sum(vws.amount_taken), (0)::numeric) AS used,
    (ve.total_drip - COALESCE(sum(vws.amount_taken), (0)::numeric)) AS remaining,
    ((ve.total_drip - COALESCE(sum(vws.amount_taken), (0)::numeric)) <= (0)::numeric) AS is_drained
   FROM (public.vault_entries ve
     LEFT JOIN public.vault_withdrawal_sources vws ON ((ve.id = vws.source_month_id)))
  GROUP BY ve.id, ve.month_id, ve.bucket_id, ve.drip_date, ve.total_drip;


ALTER VIEW public.vault_status OWNER TO postgres;

--
-- TOC entry 235 (class 1259 OID 45344)
-- Name: vault_withdrawal_sources_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.vault_withdrawal_sources_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.vault_withdrawal_sources_id_seq OWNER TO postgres;

--
-- TOC entry 5162 (class 0 OID 0)
-- Dependencies: 235
-- Name: vault_withdrawal_sources_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.vault_withdrawal_sources_id_seq OWNED BY public.vault_withdrawal_sources.id;


--
-- TOC entry 234 (class 1259 OID 45315)
-- Name: vault_withdrawals; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.vault_withdrawals (
    id integer NOT NULL,
    month_id integer NOT NULL,
    bucket_id integer NOT NULL,
    tag_id integer NOT NULL,
    item_name character varying(50),
    total_amount numeric(10,2) NOT NULL,
    pull_type character varying(20) DEFAULT 'OVERSPEND_COVER'::character varying NOT NULL,
    withdrawal_date timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    reason character varying(100),
    target_bucket_id integer,
    CONSTRAINT check_pull_type CHECK (((pull_type)::text = 'OVERSPEND_COVER'::text)),
    CONSTRAINT check_total_amount_positive CHECK ((total_amount >= (0)::numeric))
);


ALTER TABLE public.vault_withdrawals OWNER TO postgres;

--
-- TOC entry 233 (class 1259 OID 45314)
-- Name: vault_withdrawals_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.vault_withdrawals_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.vault_withdrawals_id_seq OWNER TO postgres;

--
-- TOC entry 5165 (class 0 OID 0)
-- Dependencies: 233
-- Name: vault_withdrawals_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.vault_withdrawals_id_seq OWNED BY public.vault_withdrawals.id;


--
-- TOC entry 232 (class 1259 OID 45266)
-- Name: withdrawal_tags; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.withdrawal_tags (
    id integer NOT NULL,
    label character varying(50)
);


ALTER TABLE public.withdrawal_tags OWNER TO postgres;

--
-- TOC entry 231 (class 1259 OID 45265)
-- Name: withdrawal_tags_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.withdrawal_tags_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.withdrawal_tags_id_seq OWNER TO postgres;

--
-- TOC entry 5168 (class 0 OID 0)
-- Dependencies: 231
-- Name: withdrawal_tags_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.withdrawal_tags_id_seq OWNED BY public.withdrawal_tags.id;


--
-- TOC entry 4857 (class 2604 OID 45509)
-- Name: blue_box_state id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.blue_box_state ALTER COLUMN id SET DEFAULT nextval('public.blue_box_state_id_seq'::regclass);


--
-- TOC entry 4856 (class 2604 OID 45491)
-- Name: blue_box_withdrawal_sources id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.blue_box_withdrawal_sources ALTER COLUMN id SET DEFAULT nextval('public.blue_box_withdrawal_sources_id_seq'::regclass);


--
-- TOC entry 4854 (class 2604 OID 45472)
-- Name: blue_box_withdrawals id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.blue_box_withdrawals ALTER COLUMN id SET DEFAULT nextval('public.blue_box_withdrawals_id_seq'::regclass);


--
-- TOC entry 4852 (class 2604 OID 45452)
-- Name: box_events id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.box_events ALTER COLUMN id SET DEFAULT nextval('public.box_events_id_seq'::regclass);


--
-- TOC entry 4837 (class 2604 OID 45056)
-- Name: bucket_configs bucket_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bucket_configs ALTER COLUMN bucket_id SET DEFAULT nextval('public.bucket_configs_bucket_id_seq'::regclass);


--
-- TOC entry 4842 (class 2604 OID 45144)
-- Name: ledger_entries id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ledger_entries ALTER COLUMN id SET DEFAULT nextval('public.ledger_entries_id_seq'::regclass);


--
-- TOC entry 4838 (class 2604 OID 45068)
-- Name: monthly_entries id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.monthly_entries ALTER COLUMN id SET DEFAULT nextval('public.monthly_entries_id_seq'::regclass);


--
-- TOC entry 4836 (class 2604 OID 45044)
-- Name: paychecks month_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.paychecks ALTER COLUMN month_id SET DEFAULT nextval('public.paychecks_month_id_seq'::regclass);


--
-- TOC entry 4844 (class 2604 OID 45169)
-- Name: vault_entries id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vault_entries ALTER COLUMN id SET DEFAULT nextval('public.vault_entries_id_seq'::regclass);


--
-- TOC entry 4851 (class 2604 OID 45348)
-- Name: vault_withdrawal_sources id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vault_withdrawal_sources ALTER COLUMN id SET DEFAULT nextval('public.vault_withdrawal_sources_id_seq'::regclass);


--
-- TOC entry 4848 (class 2604 OID 45318)
-- Name: vault_withdrawals id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vault_withdrawals ALTER COLUMN id SET DEFAULT nextval('public.vault_withdrawals_id_seq'::regclass);


--
-- TOC entry 4847 (class 2604 OID 45269)
-- Name: withdrawal_tags id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.withdrawal_tags ALTER COLUMN id SET DEFAULT nextval('public.withdrawal_tags_id_seq'::regclass);


--
-- TOC entry 5122 (class 0 OID 45560)
-- Dependencies: 246
-- Data for Name: users; Type: TABLE DATA; Schema: auth; Owner: postgres
--

COPY auth.users (user_id, phone, phone_verified, name, password_hash, profile_image_url, is_active, created_at, updated_at) FROM stdin;
\.


--
-- TOC entry 5121 (class 0 OID 45506)
-- Dependencies: 245
-- Data for Name: blue_box_state; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.blue_box_state (id, bucket_id, is_sealed, sealed_date) FROM stdin;
1	3	t	\N
\.


--
-- TOC entry 5119 (class 0 OID 45488)
-- Dependencies: 243
-- Data for Name: blue_box_withdrawal_sources; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.blue_box_withdrawal_sources (id, withdrawal_id, source_entry_id, amount_taken) FROM stdin;
18	23	3	900.00
20	25	3	1200.00
21	27	4	900.00
22	28	4	900.00
23	32	4	1200.00
\.


--
-- TOC entry 5117 (class 0 OID 45469)
-- Dependencies: 241
-- Data for Name: blue_box_withdrawals; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.blue_box_withdrawals (id, bucket_id, month_id, total_amount, description, withdrawal_date) FROM stdin;
23	3	1	900.00	Should Pass	2026-03-21 10:39:40.916054
25	3	1	1200.00	Final withdrawal - should auto seal	2026-03-21 10:49:04.50056
27	3	1	900.00	Should Pass	2026-03-21 10:54:32.523914
28	3	1	900.00	Should Pass	2026-03-21 10:54:48.570679
32	3	2	1200.00	Should Pass	2026-03-21 11:11:04.330237
\.


--
-- TOC entry 5115 (class 0 OID 45449)
-- Dependencies: 239
-- Data for Name: box_events; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.box_events (id, bucket_id, month_id, box_type, amount, description, event_date) FROM stdin;
27	3	1	DEPOSIT	100.00	January Tax 1 savings	2026-03-20 15:07:56.606973
28	3	1	DEPOSIT	900.00	January Tax 2 savings	2026-03-20 15:08:27.295129
29	3	1	DEPOSIT	100.00	January Tax 3 savings	2026-03-20 15:08:43.409393
30	3	1	DEPOSIT	300.00	January Tax 4 savings	2026-03-20 15:13:14.121521
32	3	1	DEPOSIT	700.00	January Tax 5 savings	2026-03-20 15:14:16.157609
38	3	1	WITHDRAW	900.00	Should Pass	2026-03-21 10:39:40.916054
41	3	1	WITHDRAW	1200.00	Final withdrawal - should auto seal	2026-03-21 10:49:04.50056
42	3	1	SEALED	\N	Auto-sealed: balance reached 0	2026-03-21 10:49:04.50056
43	3	1	WITHDRAW	900.00	Should Pass	2026-03-21 10:54:32.523914
44	3	1	WITHDRAW	900.00	Should Pass	2026-03-21 10:54:48.570679
47	3	2	DEPOSIT	1200.00	\N	2026-03-21 11:06:24.022358
48	3	2	WITHDRAW	1200.00	Should Pass	2026-03-21 11:11:04.330237
\.


--
-- TOC entry 5101 (class 0 OID 45053)
-- Dependencies: 222
-- Data for Name: bucket_configs; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.bucket_configs (bucket_id, bucket_name, display_type, display_order, is_active, notes) FROM stdin;
1	Investment	GREEN	1	t	Future Plans and Growth over time
3	Property Tax	BLUE	2	t	Tax and Predictable Expenses
4	Mother Pocket Money	RED	3	t	Monthly Allowances
5	My Pocket Money	RED	4	t	Monthly Allowances
6	Electricity Bill	YELLOW	5	t	Monthly Allowances
7	Emergency Funds	ORANGE	6	t	monthly emergency Suprises
\.


--
-- TOC entry 5099 (class 0 OID 45047)
-- Dependencies: 220
-- Data for Name: bucket_types; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.bucket_types (type_name, color, description, vault_role) FROM stdin;
RED	red	Essential expenses	NONE
YELLOW	yellow	Monthly Bills	DRIP_IN
ORANGE	orange	Suprise spend	DRIP_OUT
GREEN	green	Goes out completely to investments	NONE
BLUE	blue	Blue zone savings	NONE
\.


--
-- TOC entry 5123 (class 0 OID 45575)
-- Dependencies: 247
-- Data for Name: customers; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.customers (id, name, age, city) FROM stdin;
\.


--
-- TOC entry 5105 (class 0 OID 45141)
-- Dependencies: 227
-- Data for Name: ledger_entries; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.ledger_entries (id, monthly_entry_id, bucket_id, vault_wd_id, description, amount, txn_date, txn_type, vault_credit_id, box_event_id) FROM stdin;
1	1	6	\N	JAN Movie	500.00	2026-03-13 18:09:21.364647	SPEND	\N	\N
3	1	6	\N	VAULT_CREDIT to vault #1	499.00	2026-03-13 18:10:05.35956	VAULT_CREDIT	1	\N
12	1	6	5	VAULT SPEND from vault #5 - 	199.00	2026-03-13 18:18:06.006372	SPEND	\N	\N
13	1	7	5	VAULT_WITHDRAWAL received from vault #5 - 	199.00	2026-03-13 18:18:06.006372	VAULT_WITHDRAWAL	\N	\N
35	1	3	\N	January Tax 1 savings	100.00	2026-03-20 15:07:56.606973	CONTRIBUTION	\N	27
36	1	3	\N	January Tax 2 savings	900.00	2026-03-20 15:08:27.295129	CONTRIBUTION	\N	28
37	1	3	\N	January Tax 3 savings	100.00	2026-03-20 15:08:43.409393	CONTRIBUTION	\N	29
38	1	3	\N	January Tax 4 savings	300.00	2026-03-20 15:13:14.121521	CONTRIBUTION	\N	30
39	1	3	\N	January Tax 5 savings	700.00	2026-03-20 15:14:16.157609	CONTRIBUTION	\N	32
42	1	3	\N	Should Pass	900.00	2026-03-21 10:39:40.916054	SPEND	\N	38
44	1	3	\N	Final withdrawal - should auto seal	1200.00	2026-03-21 10:49:04.50056	SPEND	\N	41
45	1	3	\N	Should Pass	900.00	2026-03-21 10:54:32.523914	SPEND	\N	43
46	1	3	\N	Should Pass	900.00	2026-03-21 10:54:48.570679	SPEND	\N	44
47	2	3	\N	Blue box DEPOSIT - month #2	1200.00	2026-03-21 11:06:24.022358	CONTRIBUTION	\N	47
48	2	3	\N	Should Pass	1200.00	2026-03-21 11:11:04.330237	SPEND	\N	48
\.


--
-- TOC entry 5103 (class 0 OID 45065)
-- Dependencies: 224
-- Data for Name: monthly_entries; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.monthly_entries (id, month_id, bucket_id, allocated, spent, created_at, updated_at) FROM stdin;
3	1	3	2100.00	3900.00	2026-03-14 12:03:30.400851	2026-03-14 12:03:30.400851
1	1	6	1000.00	999.00	2026-03-13 17:57:19.958968	2026-03-13 17:57:19.958968
2	1	7	199.00	0.00	2026-03-13 18:13:21.383956	2026-03-13 18:13:21.383956
4	2	3	6000.00	1200.00	2026-03-21 10:53:36.434489	2026-03-21 10:53:36.434489
\.


--
-- TOC entry 5098 (class 0 OID 45041)
-- Dependencies: 219
-- Data for Name: paychecks; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.paychecks (month_id, month_label, salary, notes) FROM stdin;
1	2026-01	100000.00	Clean start to 2026, Minimal surprises.
2	2026-02	100000.00	feb salary
\.


--
-- TOC entry 5107 (class 0 OID 45166)
-- Dependencies: 229
-- Data for Name: vault_entries; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.vault_entries (id, month_id, bucket_id, total_drip, drip_date, created_at) FROM stdin;
1	1	6	499.00	2026-03-13 18:10:05.35956	2026-03-13 18:10:05.35956
\.


--
-- TOC entry 5113 (class 0 OID 45345)
-- Dependencies: 236
-- Data for Name: vault_withdrawal_sources; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.vault_withdrawal_sources (id, withdrawal_id, source_month_id, amount_taken) FROM stdin;
5	5	1	199.00
\.


--
-- TOC entry 5111 (class 0 OID 45315)
-- Dependencies: 234
-- Data for Name: vault_withdrawals; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.vault_withdrawals (id, month_id, bucket_id, tag_id, item_name, total_amount, pull_type, withdrawal_date, reason, target_bucket_id) FROM stdin;
5	1	6	1	\N	199.00	OVERSPEND_COVER	2026-03-13 18:18:06.006372	\N	7
\.


--
-- TOC entry 5109 (class 0 OID 45266)
-- Dependencies: 232
-- Data for Name: withdrawal_tags; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.withdrawal_tags (id, label) FROM stdin;
1	Medical
2	Other
\.


--
-- TOC entry 5170 (class 0 OID 0)
-- Dependencies: 244
-- Name: blue_box_state_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.blue_box_state_id_seq', 3, true);


--
-- TOC entry 5171 (class 0 OID 0)
-- Dependencies: 242
-- Name: blue_box_withdrawal_sources_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.blue_box_withdrawal_sources_id_seq', 23, true);


--
-- TOC entry 5172 (class 0 OID 0)
-- Dependencies: 240
-- Name: blue_box_withdrawals_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.blue_box_withdrawals_id_seq', 33, true);


--
-- TOC entry 5173 (class 0 OID 0)
-- Dependencies: 238
-- Name: box_events_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.box_events_id_seq', 48, true);


--
-- TOC entry 5174 (class 0 OID 0)
-- Dependencies: 221
-- Name: bucket_configs_bucket_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.bucket_configs_bucket_id_seq', 6, true);


--
-- TOC entry 5175 (class 0 OID 0)
-- Dependencies: 226
-- Name: ledger_entries_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.ledger_entries_id_seq', 48, true);


--
-- TOC entry 5176 (class 0 OID 0)
-- Dependencies: 223
-- Name: monthly_entries_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.monthly_entries_id_seq', 4, true);


--
-- TOC entry 5177 (class 0 OID 0)
-- Dependencies: 218
-- Name: paychecks_month_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.paychecks_month_id_seq', 1, true);


--
-- TOC entry 5178 (class 0 OID 0)
-- Dependencies: 228
-- Name: vault_entries_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.vault_entries_id_seq', 1, true);


--
-- TOC entry 5179 (class 0 OID 0)
-- Dependencies: 235
-- Name: vault_withdrawal_sources_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.vault_withdrawal_sources_id_seq', 7, true);


--
-- TOC entry 5180 (class 0 OID 0)
-- Dependencies: 233
-- Name: vault_withdrawals_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.vault_withdrawals_id_seq', 7, true);


--
-- TOC entry 5181 (class 0 OID 0)
-- Dependencies: 231
-- Name: withdrawal_tags_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.withdrawal_tags_id_seq', 2, true);


--
-- TOC entry 4907 (class 2606 OID 45574)
-- Name: users users_phone_key; Type: CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.users
    ADD CONSTRAINT users_phone_key UNIQUE (phone);


--
-- TOC entry 4909 (class 2606 OID 45572)
-- Name: users users_pkey; Type: CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (user_id);


--
-- TOC entry 4903 (class 2606 OID 45514)
-- Name: blue_box_state blue_box_state_bucket_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.blue_box_state
    ADD CONSTRAINT blue_box_state_bucket_id_key UNIQUE (bucket_id);


--
-- TOC entry 4905 (class 2606 OID 45512)
-- Name: blue_box_state blue_box_state_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.blue_box_state
    ADD CONSTRAINT blue_box_state_pkey PRIMARY KEY (id);


--
-- TOC entry 4901 (class 2606 OID 45494)
-- Name: blue_box_withdrawal_sources blue_box_withdrawal_sources_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.blue_box_withdrawal_sources
    ADD CONSTRAINT blue_box_withdrawal_sources_pkey PRIMARY KEY (id);


--
-- TOC entry 4899 (class 2606 OID 45476)
-- Name: blue_box_withdrawals blue_box_withdrawals_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.blue_box_withdrawals
    ADD CONSTRAINT blue_box_withdrawals_pkey PRIMARY KEY (id);


--
-- TOC entry 4897 (class 2606 OID 45457)
-- Name: box_events box_events_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.box_events
    ADD CONSTRAINT box_events_pkey PRIMARY KEY (id);


--
-- TOC entry 4882 (class 2606 OID 45058)
-- Name: bucket_configs bucket_configs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bucket_configs
    ADD CONSTRAINT bucket_configs_pkey PRIMARY KEY (bucket_id);


--
-- TOC entry 4880 (class 2606 OID 45051)
-- Name: bucket_types bucket_types_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bucket_types
    ADD CONSTRAINT bucket_types_pkey PRIMARY KEY (type_name);


--
-- TOC entry 4911 (class 2606 OID 45581)
-- Name: customers customers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_pkey PRIMARY KEY (id);


--
-- TOC entry 4886 (class 2606 OID 45149)
-- Name: ledger_entries ledger_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ledger_entries
    ADD CONSTRAINT ledger_entries_pkey PRIMARY KEY (id);


--
-- TOC entry 4884 (class 2606 OID 45075)
-- Name: monthly_entries monthly_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.monthly_entries
    ADD CONSTRAINT monthly_entries_pkey PRIMARY KEY (id);


--
-- TOC entry 4878 (class 2606 OID 45046)
-- Name: paychecks paychecks_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.paychecks
    ADD CONSTRAINT paychecks_pkey PRIMARY KEY (month_id);


--
-- TOC entry 4888 (class 2606 OID 45174)
-- Name: vault_entries vault_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vault_entries
    ADD CONSTRAINT vault_entries_pkey PRIMARY KEY (id);


--
-- TOC entry 4895 (class 2606 OID 45351)
-- Name: vault_withdrawal_sources vault_withdrawal_sources_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vault_withdrawal_sources
    ADD CONSTRAINT vault_withdrawal_sources_pkey PRIMARY KEY (id);


--
-- TOC entry 4892 (class 2606 OID 45323)
-- Name: vault_withdrawals vault_withdrawals_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vault_withdrawals
    ADD CONSTRAINT vault_withdrawals_pkey PRIMARY KEY (id);


--
-- TOC entry 4890 (class 2606 OID 45271)
-- Name: withdrawal_tags withdrawal_tags_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.withdrawal_tags
    ADD CONSTRAINT withdrawal_tags_pkey PRIMARY KEY (id);


--
-- TOC entry 4893 (class 1259 OID 45362)
-- Name: idx_vault_sources_month; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_vault_sources_month ON public.vault_withdrawal_sources USING btree (source_month_id);


--
-- TOC entry 4942 (class 2620 OID 45521)
-- Name: box_events trg_block_direct_box_withdraw; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_block_direct_box_withdraw BEFORE INSERT ON public.box_events FOR EACH ROW EXECUTE FUNCTION public.trg_block_direct_box_withdraw();


--
-- TOC entry 4948 (class 2620 OID 45558)
-- Name: blue_box_state trg_blue_box_state_guard; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_blue_box_state_guard BEFORE INSERT OR UPDATE ON public.blue_box_state FOR EACH ROW EXECUTE FUNCTION public.trg_blue_box_state_guard();


--
-- TOC entry 4945 (class 2620 OID 45555)
-- Name: blue_box_withdrawals trg_blue_box_withdrawal_before; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_blue_box_withdrawal_before BEFORE INSERT ON public.blue_box_withdrawals FOR EACH ROW EXECUTE FUNCTION public.trg_blue_box_withdrawal_before();


--
-- TOC entry 4946 (class 2620 OID 45541)
-- Name: blue_box_withdrawals trg_blue_box_withdrawal_manage_before; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_blue_box_withdrawal_manage_before BEFORE DELETE ON public.blue_box_withdrawals FOR EACH ROW EXECUTE FUNCTION public.trg_blue_box_withdrawal_manage();


--
-- TOC entry 4947 (class 2620 OID 45553)
-- Name: blue_box_withdrawals trg_blue_box_withdrawals; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_blue_box_withdrawals AFTER INSERT OR DELETE OR UPDATE ON public.blue_box_withdrawals FOR EACH ROW EXECUTE FUNCTION public.trg_blue_box_withdrawal_manage();


--
-- TOC entry 4943 (class 2620 OID 45551)
-- Name: box_events trg_box_events_after; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_box_events_after AFTER INSERT ON public.box_events FOR EACH ROW EXECUTE FUNCTION public.fn_box_events_ledger();


--
-- TOC entry 4944 (class 2620 OID 45550)
-- Name: box_events trg_box_events_before; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_box_events_before BEFORE INSERT OR UPDATE ON public.box_events FOR EACH ROW EXECUTE FUNCTION public.fn_box_events_validate();


--
-- TOC entry 4934 (class 2620 OID 45259)
-- Name: ledger_entries trg_ledger_block_vault_delete; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_ledger_block_vault_delete BEFORE DELETE ON public.ledger_entries FOR EACH ROW EXECUTE FUNCTION public.trg_ledger_block_vault_delete();

ALTER TABLE public.ledger_entries DISABLE TRIGGER trg_ledger_block_vault_delete;


--
-- TOC entry 4935 (class 2620 OID 45222)
-- Name: ledger_entries trg_ledger_sync; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_ledger_sync AFTER INSERT OR DELETE OR UPDATE ON public.ledger_entries FOR EACH ROW EXECUTE FUNCTION public.trg_ledger_sync();


--
-- TOC entry 4936 (class 2620 OID 45219)
-- Name: ledger_entries trg_ledger_truncate_sync; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_ledger_truncate_sync AFTER TRUNCATE ON public.ledger_entries FOR EACH STATEMENT EXECUTE FUNCTION public.trg_ledger_truncate_sync();


--
-- TOC entry 4933 (class 2620 OID 45221)
-- Name: monthly_entries trg_protect_spent; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_protect_spent BEFORE UPDATE OF spent ON public.monthly_entries FOR EACH ROW EXECUTE FUNCTION public.trg_protect_spent();


--
-- TOC entry 4937 (class 2620 OID 45255)
-- Name: vault_entries trg_vault_entries_after_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_vault_entries_after_insert AFTER INSERT ON public.vault_entries FOR EACH ROW EXECUTE FUNCTION public.trg_vault_entries_after_insert();


--
-- TOC entry 4938 (class 2620 OID 45253)
-- Name: vault_entries trg_vault_entries_before_ops; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_vault_entries_before_ops BEFORE INSERT OR DELETE OR UPDATE ON public.vault_entries FOR EACH ROW EXECUTE FUNCTION public.trg_vault_entries_before_ops();


--
-- TOC entry 4939 (class 2620 OID 45403)
-- Name: vault_withdrawals trg_vault_withdrawal_manage_after; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_vault_withdrawal_manage_after AFTER INSERT OR UPDATE ON public.vault_withdrawals FOR EACH ROW EXECUTE FUNCTION public.trg_vault_withdrawal_manage();


--
-- TOC entry 4940 (class 2620 OID 45402)
-- Name: vault_withdrawals trg_vault_withdrawal_manage_before; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_vault_withdrawal_manage_before BEFORE DELETE ON public.vault_withdrawals FOR EACH ROW EXECUTE FUNCTION public.trg_vault_withdrawal_manage();


--
-- TOC entry 4941 (class 2620 OID 45388)
-- Name: vault_withdrawal_sources trg_vws_block_direct_delete; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_vws_block_direct_delete BEFORE DELETE ON public.vault_withdrawal_sources FOR EACH ROW EXECUTE FUNCTION public.trg_vws_block_direct_delete();


--
-- TOC entry 4932 (class 2606 OID 45515)
-- Name: blue_box_state fk_bbs_bucket; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.blue_box_state
    ADD CONSTRAINT fk_bbs_bucket FOREIGN KEY (bucket_id) REFERENCES public.bucket_configs(bucket_id);


--
-- TOC entry 4928 (class 2606 OID 45477)
-- Name: blue_box_withdrawals fk_bbw_bucket; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.blue_box_withdrawals
    ADD CONSTRAINT fk_bbw_bucket FOREIGN KEY (bucket_id) REFERENCES public.bucket_configs(bucket_id);


--
-- TOC entry 4929 (class 2606 OID 45482)
-- Name: blue_box_withdrawals fk_bbw_month; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.blue_box_withdrawals
    ADD CONSTRAINT fk_bbw_month FOREIGN KEY (month_id) REFERENCES public.paychecks(month_id);


--
-- TOC entry 4930 (class 2606 OID 45500)
-- Name: blue_box_withdrawal_sources fk_bbws_source_entry; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.blue_box_withdrawal_sources
    ADD CONSTRAINT fk_bbws_source_entry FOREIGN KEY (source_entry_id) REFERENCES public.monthly_entries(id);


--
-- TOC entry 4931 (class 2606 OID 45495)
-- Name: blue_box_withdrawal_sources fk_bbws_withdrawal; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.blue_box_withdrawal_sources
    ADD CONSTRAINT fk_bbws_withdrawal FOREIGN KEY (withdrawal_id) REFERENCES public.blue_box_withdrawals(id);


--
-- TOC entry 4926 (class 2606 OID 45458)
-- Name: box_events fk_box_events_bucket; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.box_events
    ADD CONSTRAINT fk_box_events_bucket FOREIGN KEY (bucket_id) REFERENCES public.bucket_configs(bucket_id);


--
-- TOC entry 4927 (class 2606 OID 45463)
-- Name: box_events fk_box_events_month; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.box_events
    ADD CONSTRAINT fk_box_events_month FOREIGN KEY (month_id) REFERENCES public.paychecks(month_id);


--
-- TOC entry 4912 (class 2606 OID 45086)
-- Name: bucket_configs fk_bucket_configs_bucket_display_type; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bucket_configs
    ADD CONSTRAINT fk_bucket_configs_bucket_display_type FOREIGN KEY (display_type) REFERENCES public.bucket_types(type_name) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 4913 (class 2606 OID 45091)
-- Name: monthly_entries fk_bucket_configs_bucket_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.monthly_entries
    ADD CONSTRAINT fk_bucket_configs_bucket_id FOREIGN KEY (bucket_id) REFERENCES public.bucket_configs(bucket_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 4914 (class 2606 OID 45081)
-- Name: monthly_entries fk_bucket_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.monthly_entries
    ADD CONSTRAINT fk_bucket_id FOREIGN KEY (bucket_id) REFERENCES public.bucket_configs(bucket_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 4916 (class 2606 OID 45155)
-- Name: ledger_entries fk_bucket_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ledger_entries
    ADD CONSTRAINT fk_bucket_id FOREIGN KEY (bucket_id) REFERENCES public.bucket_configs(bucket_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 4919 (class 2606 OID 45180)
-- Name: vault_entries fk_bucket_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vault_entries
    ADD CONSTRAINT fk_bucket_id FOREIGN KEY (bucket_id) REFERENCES public.bucket_configs(bucket_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 4917 (class 2606 OID 45150)
-- Name: ledger_entries fk_ledger_monthly_entry; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ledger_entries
    ADD CONSTRAINT fk_ledger_monthly_entry FOREIGN KEY (monthly_entry_id) REFERENCES public.monthly_entries(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 4915 (class 2606 OID 45076)
-- Name: monthly_entries fk_monthly_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.monthly_entries
    ADD CONSTRAINT fk_monthly_id FOREIGN KEY (month_id) REFERENCES public.paychecks(month_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 4920 (class 2606 OID 45175)
-- Name: vault_entries fk_monthly_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vault_entries
    ADD CONSTRAINT fk_monthly_id FOREIGN KEY (month_id) REFERENCES public.paychecks(month_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 4921 (class 2606 OID 45329)
-- Name: vault_withdrawals fk_vault_withdrawals_bucket; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vault_withdrawals
    ADD CONSTRAINT fk_vault_withdrawals_bucket FOREIGN KEY (bucket_id) REFERENCES public.bucket_configs(bucket_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 4922 (class 2606 OID 45334)
-- Name: vault_withdrawals fk_vault_withdrawals_month; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vault_withdrawals
    ADD CONSTRAINT fk_vault_withdrawals_month FOREIGN KEY (month_id) REFERENCES public.paychecks(month_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 4923 (class 2606 OID 45324)
-- Name: vault_withdrawals fk_vault_withdrawals_tag; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vault_withdrawals
    ADD CONSTRAINT fk_vault_withdrawals_tag FOREIGN KEY (tag_id) REFERENCES public.withdrawal_tags(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 4925 (class 2606 OID 45374)
-- Name: vault_withdrawal_sources fk_vws_vault_entry; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vault_withdrawal_sources
    ADD CONSTRAINT fk_vws_vault_entry FOREIGN KEY (source_month_id) REFERENCES public.vault_entries(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 4918 (class 2606 OID 45529)
-- Name: ledger_entries ledger_entries_box_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ledger_entries
    ADD CONSTRAINT ledger_entries_box_event_id_fkey FOREIGN KEY (box_event_id) REFERENCES public.box_events(id);


--
-- TOC entry 4924 (class 2606 OID 45394)
-- Name: vault_withdrawals vault_withdrawals_target_bucket_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vault_withdrawals
    ADD CONSTRAINT vault_withdrawals_target_bucket_id_fkey FOREIGN KEY (target_bucket_id) REFERENCES public.bucket_configs(bucket_id);


--
-- TOC entry 5129 (class 0 OID 0)
-- Dependencies: 6
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: pg_database_owner
--

GRANT USAGE ON SCHEMA public TO optimus_prime;


--
-- TOC entry 5130 (class 0 OID 0)
-- Dependencies: 245
-- Name: TABLE blue_box_state; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.blue_box_state TO optimus_prime;


--
-- TOC entry 5132 (class 0 OID 0)
-- Dependencies: 244
-- Name: SEQUENCE blue_box_state_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.blue_box_state_id_seq TO optimus_prime;


--
-- TOC entry 5133 (class 0 OID 0)
-- Dependencies: 243
-- Name: TABLE blue_box_withdrawal_sources; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.blue_box_withdrawal_sources TO optimus_prime;


--
-- TOC entry 5135 (class 0 OID 0)
-- Dependencies: 242
-- Name: SEQUENCE blue_box_withdrawal_sources_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.blue_box_withdrawal_sources_id_seq TO optimus_prime;


--
-- TOC entry 5136 (class 0 OID 0)
-- Dependencies: 241
-- Name: TABLE blue_box_withdrawals; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.blue_box_withdrawals TO optimus_prime;


--
-- TOC entry 5138 (class 0 OID 0)
-- Dependencies: 240
-- Name: SEQUENCE blue_box_withdrawals_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.blue_box_withdrawals_id_seq TO optimus_prime;


--
-- TOC entry 5139 (class 0 OID 0)
-- Dependencies: 239
-- Name: TABLE box_events; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.box_events TO optimus_prime;


--
-- TOC entry 5141 (class 0 OID 0)
-- Dependencies: 238
-- Name: SEQUENCE box_events_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.box_events_id_seq TO optimus_prime;


--
-- TOC entry 5142 (class 0 OID 0)
-- Dependencies: 227
-- Name: TABLE ledger_entries; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.ledger_entries TO optimus_prime;


--
-- TOC entry 5143 (class 0 OID 0)
-- Dependencies: 224
-- Name: TABLE monthly_entries; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.monthly_entries TO optimus_prime;


--
-- TOC entry 5144 (class 0 OID 0)
-- Dependencies: 230
-- Name: TABLE bucket_budget_status_v; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.bucket_budget_status_v TO optimus_prime;


--
-- TOC entry 5145 (class 0 OID 0)
-- Dependencies: 222
-- Name: TABLE bucket_configs; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.bucket_configs TO optimus_prime;


--
-- TOC entry 5147 (class 0 OID 0)
-- Dependencies: 221
-- Name: SEQUENCE bucket_configs_bucket_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.bucket_configs_bucket_id_seq TO optimus_prime;


--
-- TOC entry 5148 (class 0 OID 0)
-- Dependencies: 220
-- Name: TABLE bucket_types; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.bucket_types TO optimus_prime;


--
-- TOC entry 5150 (class 0 OID 0)
-- Dependencies: 226
-- Name: SEQUENCE ledger_entries_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.ledger_entries_id_seq TO optimus_prime;


--
-- TOC entry 5151 (class 0 OID 0)
-- Dependencies: 219
-- Name: TABLE paychecks; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.paychecks TO optimus_prime;


--
-- TOC entry 5152 (class 0 OID 0)
-- Dependencies: 225
-- Name: TABLE monthly_budget_summary; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.monthly_budget_summary TO optimus_prime;


--
-- TOC entry 5154 (class 0 OID 0)
-- Dependencies: 223
-- Name: SEQUENCE monthly_entries_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.monthly_entries_id_seq TO optimus_prime;


--
-- TOC entry 5156 (class 0 OID 0)
-- Dependencies: 218
-- Name: SEQUENCE paychecks_month_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.paychecks_month_id_seq TO optimus_prime;


--
-- TOC entry 5157 (class 0 OID 0)
-- Dependencies: 229
-- Name: TABLE vault_entries; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.vault_entries TO optimus_prime;


--
-- TOC entry 5159 (class 0 OID 0)
-- Dependencies: 228
-- Name: SEQUENCE vault_entries_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.vault_entries_id_seq TO optimus_prime;


--
-- TOC entry 5160 (class 0 OID 0)
-- Dependencies: 236
-- Name: TABLE vault_withdrawal_sources; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.vault_withdrawal_sources TO optimus_prime;


--
-- TOC entry 5161 (class 0 OID 0)
-- Dependencies: 237
-- Name: TABLE vault_status; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.vault_status TO optimus_prime;


--
-- TOC entry 5163 (class 0 OID 0)
-- Dependencies: 235
-- Name: SEQUENCE vault_withdrawal_sources_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.vault_withdrawal_sources_id_seq TO optimus_prime;


--
-- TOC entry 5164 (class 0 OID 0)
-- Dependencies: 234
-- Name: TABLE vault_withdrawals; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.vault_withdrawals TO optimus_prime;


--
-- TOC entry 5166 (class 0 OID 0)
-- Dependencies: 233
-- Name: SEQUENCE vault_withdrawals_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.vault_withdrawals_id_seq TO optimus_prime;


--
-- TOC entry 5167 (class 0 OID 0)
-- Dependencies: 232
-- Name: TABLE withdrawal_tags; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.withdrawal_tags TO optimus_prime;


--
-- TOC entry 5169 (class 0 OID 0)
-- Dependencies: 231
-- Name: SEQUENCE withdrawal_tags_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.withdrawal_tags_id_seq TO optimus_prime;


-- Completed on 2026-05-07 17:18:15

--
-- PostgreSQL database dump complete
--

