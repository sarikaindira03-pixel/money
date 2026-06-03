--
-- PostgreSQL database dump
--

-- Dumped from database version 17.5
-- Dumped by pg_dump version 17.5

-- Started on 2026-05-22 07:45:30

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
-- TOC entry 7 (class 2615 OID 45967)
-- Name: auth; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA auth;


ALTER SCHEMA auth OWNER TO postgres;

--
-- TOC entry 2 (class 3079 OID 45930)
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- TOC entry 5158 (class 0 OID 0)
-- Dependencies: 2
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- TOC entry 283 (class 1255 OID 45983)
-- Name: uid(); Type: FUNCTION; Schema: auth; Owner: postgres
--

CREATE FUNCTION auth.uid() RETURNS uuid
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    AS $$
DECLARE
    uid_from_jwt uuid;
    uid_from_setting uuid;
BEGIN
    -- Priority 1: From JWT (real PostgREST usage)
    BEGIN
        uid_from_jwt := (current_setting('request.jwt.claims', true)::jsonb ->> 'sub')::uuid;
        IF uid_from_jwt IS NOT NULL THEN
            RETURN uid_from_jwt;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;

    -- Priority 2: From session variable (for manual testing)
    BEGIN
        uid_from_setting := current_setting('app.current_user_id', true)::uuid;
        IF uid_from_setting IS NOT NULL THEN
            RETURN uid_from_setting;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;

    RETURN NULL;
END;
$$;


ALTER FUNCTION auth.uid() OWNER TO postgres;

--
-- TOC entry 301 (class 1255 OID 47106)
-- Name: allocate_blue_bucket(uuid, character varying, integer, numeric); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.allocate_blue_bucket(IN p_user_id uuid, IN p_month character varying, IN p_bucket_id integer, IN p_allocated numeric)
    LANGUAGE plpgsql
    AS $$DECLARE
    v_salary            NUMERIC(12,2);
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

    IF (v_non_reserve_sum + p_allocated) > v_salary THEN
        RAISE EXCEPTION 'Allocation exceeds salary. Available: %, Requested: %', 
            v_salary - v_non_reserve_sum, p_allocated 
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
        VALUES (p_user_id, p_month, v_blue_opening, 0);
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
    SET allocated = v_salary - v_non_reserve_sum
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
END;$$;


ALTER PROCEDURE public.allocate_blue_bucket(IN p_user_id uuid, IN p_month character varying, IN p_bucket_id integer, IN p_allocated numeric) OWNER TO postgres;

--
-- TOC entry 300 (class 1255 OID 47105)
-- Name: allocate_bucket(uuid, character varying, integer, numeric); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.allocate_bucket(IN p_user_id uuid, IN p_month character varying, IN p_bucket_id integer, IN p_allocated numeric)
    LANGUAGE plpgsql
    AS $$
DECLARE
 v_salary               NUMERIC(12,2);
    -- v_current_allocated    NUMERIC(12,2) := 0;   -- existing value if updating
    v_non_reserve_sum      NUMERIC(12,2);
    v_bucket_type          VARCHAR(20);
    v_reserve_bucket_id    INTEGER;
    v_exists               BOOLEAN;
BEGIN
    SET LOCAL app.proc_active = 'true';

    IF p_allocated < 0 THEN
        RAISE EXCEPTION 'Allocated amount must be positive. Got: %', p_allocated USING ERRCODE = 'P0001';
    END IF;

    SELECT salary INTO v_salary FROM paychecks WHERE user_id = p_user_id AND month = p_month;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'No paycheck for user % month %. Call record_paycheck first.', p_user_id, p_month USING ERRCODE = 'P0002';
    END IF;

    IF EXISTS (SELECT 1 FROM vault WHERE user_id = p_user_id AND month = p_month AND closing_amt IS NOT NULL) THEN
        RAISE EXCEPTION 'Month % is already closed. Cannot change allocations.', p_month USING ERRCODE = 'P0003';
    END IF;

    SELECT bc.display_type INTO v_bucket_type
    FROM bucket_configs bc
    WHERE bc.bucket_id = p_bucket_id AND bc.user_id = p_user_id AND bc.is_active = TRUE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Bucket % not found or inactive for user %.', p_bucket_id, p_user_id USING ERRCODE = 'P0003';
    END IF;

    IF v_bucket_type = 'RESERVE' THEN
        RAISE EXCEPTION 'RESERVE allocated is computed automatically.' USING ERRCODE = 'P0004';
    END IF;

    IF v_bucket_type = 'BLUE' THEN
        RAISE EXCEPTION 'BLUE buckets use allocate_blue_bucket procedure.' USING ERRCODE = 'P0004';
    END IF;

	-- Get Reserve bucket_id
  SELECT bc.bucket_id INTO v_reserve_bucket_id
    FROM bucket_configs bc
    WHERE bc.user_id = p_user_id AND bc.display_type = 'RESERVE' AND bc.is_active = TRUE LIMIT 1;

	IF v_reserve_bucket_id IS NULL THEN
        RAISE EXCEPTION 'Reserve bucket not found for user %.', p_user_id 
            USING ERRCODE = 'P0005';
    END IF;
-- Check if record exists.
SELECT EXISTS(
    SELECT 1 FROM monthly_entries 
    WHERE user_id = p_user_id 
      AND month = p_month 
      AND bucket_id = p_bucket_id
) INTO v_exists;
    -- === Pre-check: Is there enough room? ===
    SELECT COALESCE(SUM(me.allocated), 0) INTO v_non_reserve_sum
    FROM monthly_entries me
    JOIN bucket_configs bc ON bc.bucket_id = me.bucket_id
    WHERE me.user_id = p_user_id 
      AND me.month = p_month 
      AND bc.display_type <> 'RESERVE'
      AND me.bucket_id <> p_bucket_id;   -- exclude current bucket

    IF (v_non_reserve_sum + p_allocated) > v_salary THEN
        RAISE EXCEPTION 'Allocation exceeds salary. Available: %, Requested: %', 
            v_salary - v_non_reserve_sum, p_allocated 
            USING ERRCODE = 'P0005';
    END IF;

    -- === Apply INSERT or UPDATE ===
    IF v_exists THEN
        UPDATE monthly_entries
        SET allocated = p_allocated
        WHERE user_id = p_user_id 
          AND month = p_month 
          AND bucket_id = p_bucket_id;
    ELSE
        INSERT INTO monthly_entries (user_id, month, bucket_id, allocated, spent)
        VALUES (p_user_id, p_month, p_bucket_id, p_allocated, 0);
    END IF;

    -- === Final Reserve Update ===
    SELECT COALESCE(SUM(me.allocated), 0) INTO v_non_reserve_sum
    FROM monthly_entries me
    JOIN bucket_configs bc ON bc.bucket_id = me.bucket_id
    WHERE me.user_id = p_user_id 
      AND me.month = p_month 
      AND bc.display_type <> 'RESERVE';

    UPDATE monthly_entries
    SET allocated = v_salary - v_non_reserve_sum
    WHERE user_id = p_user_id 
      AND month = p_month 
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
    WHEN OTHERS THEN  RAISE;
END;
$$;


ALTER PROCEDURE public.allocate_bucket(IN p_user_id uuid, IN p_month character varying, IN p_bucket_id integer, IN p_allocated numeric) OWNER TO postgres;

--
-- TOC entry 298 (class 1255 OID 47112)
-- Name: close_month(uuid, character varying); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.close_month(IN p_user_id uuid, IN p_month character varying)
    LANGUAGE plpgsql
    AS $$DECLARE
    v_vault_closing      NUMERIC(12,2);
    v_blue_vault_closing NUMERIC(12,2);
BEGIN
    SET LOCAL app.proc_active = 'true';

    IF NOT EXISTS (SELECT 1 FROM paychecks WHERE user_id = p_user_id AND month = p_month) THEN
        RAISE EXCEPTION 'No paycheck for user % month %.', p_user_id, p_month USING ERRCODE = 'P0001';
    END IF;

    IF EXISTS (SELECT 1 FROM vault WHERE user_id = p_user_id AND month = p_month AND closing_amt IS NOT NULL) THEN
        RAISE EXCEPTION 'Month % is already closed for user %.', p_month, p_user_id USING ERRCODE = 'P0002';
    END IF;

    -- Close main vault
    UPDATE vault
    SET closing_amt = current_amt
    WHERE user_id = p_user_id AND month = p_month;

    -- Close blue vault if exists
    UPDATE blue_vault
    SET closing_amt = current_amt
    WHERE user_id = p_user_id AND month = p_month
      AND closing_amt IS NULL;

EXCEPTION
    WHEN OTHERS THEN RAISE;
END;$$;


ALTER PROCEDURE public.close_month(IN p_user_id uuid, IN p_month character varying) OWNER TO postgres;

--
-- TOC entry 296 (class 1255 OID 47111)
-- Name: deactivate_bucket(uuid, integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.deactivate_bucket(IN p_user_id uuid, IN p_bucket_id integer)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_bucket_type      VARCHAR(20);
    v_open_entry_count INTEGER;
BEGIN
    SET LOCAL app.proc_active = 'true';

    SELECT bc.display_type INTO v_bucket_type
    FROM bucket_configs bc
    WHERE bc.bucket_id = p_bucket_id AND bc.user_id = p_user_id AND bc.is_active = TRUE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Bucket % not found or already inactive for user %.', p_bucket_id, p_user_id USING ERRCODE = 'P0001';
    END IF;

    IF v_bucket_type = 'RESERVE' THEN
        RAISE EXCEPTION 'RESERVE bucket cannot be deactivated.' USING ERRCODE = 'P0002';
    END IF;

    SELECT COUNT(*) INTO v_open_entry_count
    FROM monthly_entries me
    JOIN vault v ON v.user_id = me.user_id AND v.month = me.month
    WHERE me.bucket_id = p_bucket_id AND me.user_id = p_user_id AND v.closing_amt IS NULL;

    IF v_open_entry_count > 0 THEN
        RAISE EXCEPTION 'Bucket % has % open monthly entries. Close all open months first.', p_bucket_id, v_open_entry_count USING ERRCODE = 'P0003';
    END IF;

    UPDATE bucket_configs SET is_active = FALSE WHERE bucket_id = p_bucket_id AND user_id = p_user_id;

EXCEPTION
    WHEN OTHERS THEN  RAISE;
END;
$$;


ALTER PROCEDURE public.deactivate_bucket(IN p_user_id uuid, IN p_bucket_id integer) OWNER TO postgres;

--
-- TOC entry 304 (class 1255 OID 47318)
-- Name: record_blue_ledger_entry(uuid, integer, numeric, character varying, date, text); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.record_blue_ledger_entry(IN p_user_id uuid, IN p_bucket_id integer, IN p_amount numeric, IN p_month character varying, IN p_date date, IN p_note text DEFAULT NULL::text)
    LANGUAGE plpgsql
    AS $$DECLARE
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

        -- Collapse allocated down to match spent
        UPDATE monthly_entries
        SET allocated = v_new_spent
        WHERE user_id   = p_user_id
          AND month     = p_month
          AND bucket_id = p_bucket_id;

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

        -- Collapse allocated up to match new spent
        UPDATE monthly_entries
        SET allocated = v_new_spent
        WHERE user_id   = p_user_id
          AND month     = p_month
          AND bucket_id = p_bucket_id;

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
END;$$;


ALTER PROCEDURE public.record_blue_ledger_entry(IN p_user_id uuid, IN p_bucket_id integer, IN p_amount numeric, IN p_month character varying, IN p_date date, IN p_note text) OWNER TO postgres;

--
-- TOC entry 305 (class 1255 OID 47108)
-- Name: record_ledger_entry(uuid, integer, numeric, character varying, date, text); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.record_ledger_entry(IN p_user_id uuid, IN p_bucket_id integer, IN p_amount numeric, IN p_month character varying, IN p_date date, IN p_note text DEFAULT NULL::text)
    LANGUAGE plpgsql
    AS $$

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
            UPDATE monthly_entries 
            SET allocated = v_new_spent, 
                spent = v_new_spent
            WHERE user_id = p_user_id AND month = p_month AND bucket_id = p_bucket_id;
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

            -- Collapse allocated up to match new spent
            UPDATE monthly_entries 
            SET allocated = v_new_spent
            WHERE user_id = p_user_id AND month = p_month AND bucket_id = p_bucket_id;

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
      AND bc.display_type NOT IN ('RESERVE', 'BLUE');

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
END;$$;


ALTER PROCEDURE public.record_ledger_entry(IN p_user_id uuid, IN p_bucket_id integer, IN p_amount numeric, IN p_month character varying, IN p_date date, IN p_note text) OWNER TO postgres;

--
-- TOC entry 299 (class 1255 OID 47104)
-- Name: record_paycheck(uuid, character varying, numeric); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.record_paycheck(IN p_user_id uuid, IN p_month character varying, IN p_salary numeric)
    LANGUAGE plpgsql
    AS $_$
DECLARE
    v_reserve_bucket_id  INTEGER;
    v_opening_amt        NUMERIC(12, 2) := 0;
    v_prior_closing      NUMERIC(12, 2);
	 v_prev_month         VARCHAR(7);	
BEGIN
    SET LOCAL app.proc_active = 'true';

    IF p_salary <= 0 THEN
        RAISE EXCEPTION 'Salary must be positive. Got: %', p_salary USING ERRCODE = 'P0001';
    END IF;

    IF p_month !~ '^\d{4}-(0[1-9]|1[0-2])$' THEN
        RAISE EXCEPTION 'Invalid month format "%". Expected YYYY-MM.', p_month USING ERRCODE = 'P0001';
    END IF;

    IF EXISTS (SELECT 1 FROM paychecks WHERE user_id = p_user_id AND month = p_month) THEN
        RAISE EXCEPTION 'Paycheck already exists for user % month %.', p_user_id, p_month USING ERRCODE = 'P0001';
    END IF;

    SELECT bc.bucket_id INTO v_reserve_bucket_id
    FROM   bucket_configs bc
    WHERE  bc.user_id = p_user_id AND bc.display_type = 'RESERVE' AND bc.is_active = true
    LIMIT 1;

    IF v_reserve_bucket_id IS NULL THEN
        RAISE EXCEPTION 'No active RESERVE bucket for user %. Add one to bucket_configs first.', p_user_id USING ERRCODE = 'P0002';
    END IF;

	  -- Calculate prev month
    v_prev_month := TO_CHAR(TO_DATE(p_month, 'YYYY-MM') - INTERVAL '1 month', 'YYYY-MM');

  -- Auto close previous month if exists and not already closed
    IF EXISTS (
        SELECT 1 FROM vault
        WHERE user_id = p_user_id
          AND month   = v_prev_month
          AND closing_amt IS NULL
    ) THEN
        CALL close_month(p_user_id, v_prev_month);
    END IF;

	
    -- Get prev closing (will be set now if close_month was just called)

    SELECT closing_amt INTO v_prior_closing
    FROM   vault
    WHERE  user_id = p_user_id
      AND  month   = v_prev_month;

	v_opening_amt := p_salary + COALESCE(v_prior_closing, 0);

    INSERT INTO paychecks (user_id, month, salary) VALUES (p_user_id, p_month, p_salary);
	
	INSERT INTO vault (user_id, month, opening_amt, current_amt) 
	VALUES (p_user_id, p_month, v_opening_amt, v_opening_amt);

    INSERT INTO monthly_entries (user_id, month, bucket_id, allocated, spent)
    VALUES (p_user_id, p_month, v_reserve_bucket_id, v_opening_amt, 0);

EXCEPTION
    WHEN OTHERS THEN  RAISE;
END;
$_$;


ALTER PROCEDURE public.record_paycheck(IN p_user_id uuid, IN p_month character varying, IN p_salary numeric) OWNER TO postgres;

--
-- TOC entry 303 (class 1255 OID 47572)
-- Name: reverse_blue_ledger_entry(uuid, integer, text); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.reverse_blue_ledger_entry(IN p_user_id uuid, IN p_ledger_id integer, IN p_reason text DEFAULT NULL::text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_bucket_id         INTEGER;
    v_amount            NUMERIC(12,2);
    v_month             VARCHAR(7);
    v_date              DATE;
    v_bucket_type       VARCHAR(20);
    v_current_spent     NUMERIC(12,2);
    v_allocated         NUMERIC(12,2);
    v_reversal_id       INTEGER;
    v_prev_spent        NUMERIC(12,2);
    v_new_spent         NUMERIC(12,2);

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

    -- ========================================
    -- Validate blue month is not closed
    -- ========================================
    IF EXISTS (SELECT 1 FROM blue_vault WHERE user_id = p_user_id AND month = v_month AND closing_amt IS NOT NULL) THEN
        RAISE EXCEPTION 'Blue month % is closed. Cannot reverse ledger entries.', v_month
        USING ERRCODE = 'P0003';
    END IF;

    -- ========================================
    -- Block if any future month exists
    -- ========================================
    IF EXISTS (
        SELECT 1 FROM paychecks
        WHERE user_id = p_user_id
          AND month > v_month
    ) THEN
        RAISE EXCEPTION 'Cannot reverse entry for month %. A newer month (%) exists.',
            v_month,
            (SELECT MAX(month) FROM paychecks WHERE user_id = p_user_id)
        USING ERRCODE = 'P0004';
    END IF;

    -- ========================================
    -- Validate bucket is BLUE
    -- ========================================
    SELECT bc.display_type INTO v_bucket_type
    FROM   bucket_configs bc
    WHERE  bc.bucket_id = v_bucket_id AND bc.user_id = p_user_id;

    IF v_bucket_type <> 'BLUE' THEN
        RAISE EXCEPTION 'Ledger entry % is not a BLUE bucket entry. Use reverse_ledger_entry instead.', p_ledger_id
        USING ERRCODE = 'P0005';
    END IF;

    -- ========================================
    -- Fetch current monthly_entries state
    -- ========================================
    SELECT spent, allocated INTO v_current_spent, v_allocated
    FROM   monthly_entries
    WHERE  user_id = p_user_id AND month = v_month AND bucket_id = v_bucket_id;

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
    -- Restore monthly_entries
    -- ========================================
    UPDATE monthly_entries
    SET    spent     = v_new_spent,
           allocated = v_new_spent
    WHERE  user_id = p_user_id AND month = v_month AND bucket_id = v_bucket_id;

    -- ========================================
    -- Audit: delete last treasury record
    -- ========================================
    IF v_current_spent > v_allocated THEN
        -- Original entry was overspend → delete last cash_out_blue_treasure
        DELETE FROM cash_out_blue_treasure
        WHERE id = (
            SELECT id FROM cash_out_blue_treasure
            WHERE  user_id = p_user_id AND month = v_month AND bucket_id = v_bucket_id
            ORDER  BY id DESC LIMIT 1
        );
    ELSE
        -- Original entry was underspend → delete last cash_in_blue_treasure
        DELETE FROM cash_in_blue_treasure
        WHERE id = (
            SELECT id FROM cash_in_blue_treasure
            WHERE  user_id = p_user_id AND month = v_month AND bucket_id = v_bucket_id
            ORDER  BY id DESC LIMIT 1
        );
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
          AND me.month        = v_month
          AND bc.display_type = 'BLUE'
    )
    WHERE user_id = p_user_id AND month = v_month;

EXCEPTION
    WHEN OTHERS THEN RAISE;
END;
$$;


ALTER PROCEDURE public.reverse_blue_ledger_entry(IN p_user_id uuid, IN p_ledger_id integer, IN p_reason text) OWNER TO postgres;

--
-- TOC entry 302 (class 1255 OID 47109)
-- Name: reverse_ledger_entry(uuid, integer, text); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.reverse_ledger_entry(IN p_user_id uuid, IN p_ledger_id integer, IN p_reason text DEFAULT NULL::text)
    LANGUAGE plpgsql
    AS $$DECLARE
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
END;$$;


ALTER PROCEDURE public.reverse_ledger_entry(IN p_user_id uuid, IN p_ledger_id integer, IN p_reason text) OWNER TO postgres;

--
-- TOC entry 284 (class 1255 OID 47093)
-- Name: trg_fn_require_procedure_context(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.trg_fn_require_procedure_context() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF current_setting('app.proc_active', TRUE) IS DISTINCT FROM 'true' THEN
        RAISE EXCEPTION
            'Direct writes to % are not allowed. Use the designated stored procedure.',
            TG_TABLE_NAME
            USING ERRCODE = 'P0099';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.trg_fn_require_procedure_context() OWNER TO postgres;

--
-- TOC entry 297 (class 1255 OID 47110)
-- Name: update_salary(uuid, character varying, numeric); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.update_salary(IN p_user_id uuid, IN p_month character varying, IN p_salary numeric)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_non_reserve_count INTEGER;
    v_reserve_bucket_id INTEGER;
BEGIN
    SET LOCAL app.proc_active = 'true';

    IF p_salary <= 0 THEN
        RAISE EXCEPTION 'Salary must be positive. Got: %', p_salary USING ERRCODE = 'P0001';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM paychecks WHERE user_id = p_user_id AND month = p_month) THEN
        RAISE EXCEPTION 'No paycheck for user % month %.', p_user_id, p_month USING ERRCODE = 'P0002';
    END IF;

    IF EXISTS (SELECT 1 FROM vault WHERE user_id = p_user_id AND month = p_month AND closing_amt IS NOT NULL) THEN
        RAISE EXCEPTION 'Month % is already closed. Cannot update salary.', p_month USING ERRCODE = 'P0003';
    END IF;

    SELECT COUNT(*) INTO v_non_reserve_count
    FROM monthly_entries me
    JOIN bucket_configs  bc ON bc.bucket_id = me.bucket_id
    JOIN bucket_types    bt ON bt.type_name  = bc.display_type
    WHERE me.user_id = p_user_id AND me.month = p_month AND bt.type_name <> 'RESERVE';

    IF v_non_reserve_count > 0 THEN
        RAISE EXCEPTION 'Cannot update salary for month %. Allocations already exist. Remove all non-RESERVE entries first.', p_month USING ERRCODE = 'P0004';
    END IF;

    SELECT bc.bucket_id INTO v_reserve_bucket_id
    FROM bucket_configs bc WHERE bc.user_id = p_user_id AND bc.display_type = 'RESERVE' AND bc.is_active = TRUE LIMIT 1;

    UPDATE paychecks SET salary = p_salary WHERE user_id = p_user_id AND month = p_month;
    UPDATE monthly_entries SET allocated = p_salary WHERE user_id = p_user_id AND month = p_month AND bucket_id = v_reserve_bucket_id;

EXCEPTION
    WHEN OTHERS THEN  RAISE;
END;
$$;


ALTER PROCEDURE public.update_salary(IN p_user_id uuid, IN p_month character varying, IN p_salary numeric) OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 221 (class 1259 OID 45968)
-- Name: users; Type: TABLE; Schema: auth; Owner: postgres
--

CREATE TABLE auth.users (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    phone character varying(20) NOT NULL,
    phone_verified boolean DEFAULT false,
    name character varying(100) NOT NULL,
    password_hash character varying(255) NOT NULL,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    email text,
    email_confirmed_at timestamp with time zone,
    last_sign_in_at timestamp with time zone,
    raw_app_meta_data jsonb DEFAULT '{}'::jsonb,
    raw_user_meta_data jsonb DEFAULT '{}'::jsonb,
    CONSTRAINT users_phone_check CHECK (((phone)::text ~ '^[+]?[0-9]{10,15}$'::text))
);


ALTER TABLE auth.users OWNER TO postgres;

--
-- TOC entry 231 (class 1259 OID 46967)
-- Name: blue_vault; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.blue_vault (
    user_id uuid NOT NULL,
    month character varying(7) NOT NULL,
    opening_amt numeric(12,2) DEFAULT 0 NOT NULL,
    closing_amt numeric(12,2),
    current_amt numeric(12,2),
    CONSTRAINT blue_vault_closing_amt_check CHECK ((closing_amt >= (0)::numeric)),
    CONSTRAINT blue_vault_opening_amt_check CHECK ((opening_amt >= (0)::numeric))
);


ALTER TABLE public.blue_vault OWNER TO postgres;

--
-- TOC entry 224 (class 1259 OID 46846)
-- Name: bucket_configs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.bucket_configs (
    bucket_id integer NOT NULL,
    user_id uuid NOT NULL,
    bucket_name character varying(50) NOT NULL,
    display_type character varying(20) NOT NULL,
    is_active boolean DEFAULT true NOT NULL
);


ALTER TABLE public.bucket_configs OWNER TO postgres;

--
-- TOC entry 223 (class 1259 OID 46845)
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
-- TOC entry 5159 (class 0 OID 0)
-- Dependencies: 223
-- Name: bucket_configs_bucket_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.bucket_configs_bucket_id_seq OWNED BY public.bucket_configs.bucket_id;


--
-- TOC entry 222 (class 1259 OID 46834)
-- Name: bucket_types; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.bucket_types (
    type_name character varying(20) NOT NULL,
    color character varying(20) NOT NULL,
    vault_role character varying(20) NOT NULL,
    affects_vault character varying(10) NOT NULL,
    overspend_ok boolean DEFAULT true NOT NULL,
    underspend_returns boolean DEFAULT false NOT NULL,
    description text,
    CONSTRAINT bucket_types_affects_vault_check CHECK (((affects_vault)::text = ANY ((ARRAY['MAIN'::character varying, 'BLUE'::character varying, 'NONE'::character varying])::text[]))),
    CONSTRAINT bucket_types_vault_role_check CHECK (((vault_role)::text = ANY ((ARRAY['DRIP_IN'::character varying, 'DRIP_OUT'::character varying, 'NONE'::character varying])::text[])))
);


ALTER TABLE public.bucket_types OWNER TO postgres;

--
-- TOC entry 239 (class 1259 OID 47039)
-- Name: cash_in_blue_treasure; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.cash_in_blue_treasure (
    id integer NOT NULL,
    user_id uuid NOT NULL,
    month character varying(7) NOT NULL,
    bucket_id integer NOT NULL,
    underspend_amt numeric(12,2) NOT NULL,
    entry_date date DEFAULT CURRENT_DATE NOT NULL,
    CONSTRAINT cash_in_blue_treasure_underspend_amt_check CHECK ((underspend_amt > (0)::numeric))
);


ALTER TABLE public.cash_in_blue_treasure OWNER TO postgres;

--
-- TOC entry 238 (class 1259 OID 47038)
-- Name: cash_in_blue_treasure_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.cash_in_blue_treasure_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.cash_in_blue_treasure_id_seq OWNER TO postgres;

--
-- TOC entry 5160 (class 0 OID 0)
-- Dependencies: 238
-- Name: cash_in_blue_treasure_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.cash_in_blue_treasure_id_seq OWNED BY public.cash_in_blue_treasure.id;


--
-- TOC entry 235 (class 1259 OID 47000)
-- Name: cash_in_treasure; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.cash_in_treasure (
    id integer NOT NULL,
    user_id uuid NOT NULL,
    month character varying(7) NOT NULL,
    bucket_id integer NOT NULL,
    underspend_amt numeric(12,2) NOT NULL,
    entry_date date DEFAULT CURRENT_DATE NOT NULL,
    CONSTRAINT cash_in_treasure_underspend_amt_check CHECK ((underspend_amt > (0)::numeric))
);


ALTER TABLE public.cash_in_treasure OWNER TO postgres;

--
-- TOC entry 234 (class 1259 OID 46999)
-- Name: cash_in_treasure_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.cash_in_treasure_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.cash_in_treasure_id_seq OWNER TO postgres;

--
-- TOC entry 5161 (class 0 OID 0)
-- Dependencies: 234
-- Name: cash_in_treasure_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.cash_in_treasure_id_seq OWNED BY public.cash_in_treasure.id;


--
-- TOC entry 237 (class 1259 OID 47020)
-- Name: cash_out_blue_treasure; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.cash_out_blue_treasure (
    id integer NOT NULL,
    user_id uuid NOT NULL,
    month character varying(7) NOT NULL,
    bucket_id integer NOT NULL,
    surplus_amt numeric(12,2) NOT NULL,
    entry_date date DEFAULT CURRENT_DATE NOT NULL,
    CONSTRAINT cash_out_blue_treasure_surplus_amt_check CHECK ((surplus_amt > (0)::numeric))
);


ALTER TABLE public.cash_out_blue_treasure OWNER TO postgres;

--
-- TOC entry 236 (class 1259 OID 47019)
-- Name: cash_out_blue_treasure_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.cash_out_blue_treasure_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.cash_out_blue_treasure_id_seq OWNER TO postgres;

--
-- TOC entry 5162 (class 0 OID 0)
-- Dependencies: 236
-- Name: cash_out_blue_treasure_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.cash_out_blue_treasure_id_seq OWNED BY public.cash_out_blue_treasure.id;


--
-- TOC entry 233 (class 1259 OID 46981)
-- Name: cash_out_treasure; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.cash_out_treasure (
    id integer NOT NULL,
    user_id uuid NOT NULL,
    month character varying(7) NOT NULL,
    bucket_id integer NOT NULL,
    surplus_amt numeric(12,2) NOT NULL,
    entry_date date DEFAULT CURRENT_DATE NOT NULL,
    CONSTRAINT cash_out_treasure_surplus_amt_check CHECK ((surplus_amt > (0)::numeric))
);


ALTER TABLE public.cash_out_treasure OWNER TO postgres;

--
-- TOC entry 232 (class 1259 OID 46980)
-- Name: cash_out_treasure_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.cash_out_treasure_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.cash_out_treasure_id_seq OWNER TO postgres;

--
-- TOC entry 5163 (class 0 OID 0)
-- Dependencies: 232
-- Name: cash_out_treasure_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.cash_out_treasure_id_seq OWNED BY public.cash_out_treasure.id;


--
-- TOC entry 229 (class 1259 OID 46906)
-- Name: ledger; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.ledger (
    ledger_id integer NOT NULL,
    user_id uuid NOT NULL,
    bucket_id integer NOT NULL,
    amount_spent numeric(12,2) NOT NULL,
    month character varying(7) NOT NULL,
    date_of_entry date DEFAULT CURRENT_DATE NOT NULL,
    note text,
    reversed boolean DEFAULT false NOT NULL,
    reversed_by integer,
    CONSTRAINT ledger_amount_spent_check CHECK ((amount_spent > (0)::numeric))
);


ALTER TABLE public.ledger OWNER TO postgres;

--
-- TOC entry 228 (class 1259 OID 46905)
-- Name: ledger_ledger_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.ledger_ledger_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.ledger_ledger_id_seq OWNER TO postgres;

--
-- TOC entry 5164 (class 0 OID 0)
-- Dependencies: 228
-- Name: ledger_ledger_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.ledger_ledger_id_seq OWNED BY public.ledger.ledger_id;


--
-- TOC entry 227 (class 1259 OID 46878)
-- Name: monthly_entries; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.monthly_entries (
    id integer NOT NULL,
    user_id uuid NOT NULL,
    month character varying(7) NOT NULL,
    bucket_id integer NOT NULL,
    allocated numeric(12,2) DEFAULT 0 NOT NULL,
    spent numeric(12,2) DEFAULT 0 NOT NULL,
    CONSTRAINT monthly_entries_allocated_check CHECK ((allocated >= (0)::numeric)),
    CONSTRAINT monthly_entries_spent_check CHECK ((spent >= (0)::numeric))
);


ALTER TABLE public.monthly_entries OWNER TO postgres;

--
-- TOC entry 226 (class 1259 OID 46877)
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
-- TOC entry 5165 (class 0 OID 0)
-- Dependencies: 226
-- Name: monthly_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.monthly_entries_id_seq OWNED BY public.monthly_entries.id;


--
-- TOC entry 225 (class 1259 OID 46865)
-- Name: paychecks; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.paychecks (
    user_id uuid NOT NULL,
    month character varying(7) NOT NULL,
    salary numeric(12,2) NOT NULL,
    CONSTRAINT paychecks_month_check CHECK (((month)::text ~ '^\d{4}-(0[1-9]|1[0-2])$'::text)),
    CONSTRAINT paychecks_salary_check CHECK ((salary > (0)::numeric))
);


ALTER TABLE public.paychecks OWNER TO postgres;

--
-- TOC entry 240 (class 1259 OID 47068)
-- Name: v_bucket_spend; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_bucket_spend AS
 SELECT l.user_id,
    l.month,
    l.bucket_id,
    bc.bucket_name,
    bt.type_name AS bucket_type,
    bt.color AS bucket_color,
    bt.affects_vault,
    bt.vault_role,
    bt.underspend_returns,
    sum(l.amount_spent) AS total_spend
   FROM ((public.ledger l
     JOIN public.bucket_configs bc ON ((bc.bucket_id = l.bucket_id)))
     JOIN public.bucket_types bt ON (((bt.type_name)::text = (bc.display_type)::text)))
  WHERE (l.reversed = false)
  GROUP BY l.user_id, l.month, l.bucket_id, bc.bucket_name, bt.type_name, bt.color, bt.affects_vault, bt.vault_role, bt.underspend_returns;


ALTER VIEW public.v_bucket_spend OWNER TO postgres;

--
-- TOC entry 241 (class 1259 OID 47073)
-- Name: v_monthly_entries; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_monthly_entries AS
 SELECT me.id,
    me.user_id,
    me.month,
    me.bucket_id,
    bc.bucket_name,
    bt.type_name AS bucket_type,
    bt.color AS bucket_color,
    me.allocated,
    me.spent,
    (me.allocated - me.spent) AS remaining
   FROM ((public.monthly_entries me
     JOIN public.bucket_configs bc ON ((bc.bucket_id = me.bucket_id)))
     JOIN public.bucket_types bt ON (((bt.type_name)::text = (bc.display_type)::text)));


ALTER VIEW public.v_monthly_entries OWNER TO postgres;

--
-- TOC entry 230 (class 1259 OID 46937)
-- Name: vault; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.vault (
    user_id uuid NOT NULL,
    month character varying(7) NOT NULL,
    opening_amt numeric(12,2) DEFAULT 0 NOT NULL,
    closing_amt numeric(12,2),
    current_amt numeric(12,2),
    CONSTRAINT vault_closing_amt_check CHECK ((closing_amt >= (0)::numeric)),
    CONSTRAINT vault_opening_amt_check CHECK ((opening_amt >= (0)::numeric))
);


ALTER TABLE public.vault OWNER TO postgres;

--
-- TOC entry 245 (class 1259 OID 47199)
-- Name: v_orange_bucket_money_flow; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_orange_bucket_money_flow AS
 SELECT me.user_id,
    me.month,
    me.bucket_id,
    bc.bucket_name,
    me.spent AS total_spent,
    COALESCE(co.total_cash_out, (0)::numeric) AS total_pulled_from_vault,
    COALESCE(co.pull_count, (0)::bigint) AS pull_count,
    (- COALESCE(co.total_cash_out, (0)::numeric)) AS net_vault_impact,
    v.opening_amt AS vault_opening,
    v.current_amt AS vault_current,
    v.closing_amt AS vault_closing
   FROM ((((public.monthly_entries me
     JOIN public.bucket_configs bc ON ((bc.bucket_id = me.bucket_id)))
     JOIN public.paychecks p ON (((p.user_id = me.user_id) AND ((p.month)::text = (me.month)::text))))
     JOIN public.vault v ON (((v.user_id = me.user_id) AND ((v.month)::text = (me.month)::text))))
     LEFT JOIN ( SELECT cash_out_treasure.user_id,
            cash_out_treasure.month,
            cash_out_treasure.bucket_id,
            sum(cash_out_treasure.surplus_amt) AS total_cash_out,
            count(*) AS pull_count
           FROM public.cash_out_treasure
          GROUP BY cash_out_treasure.user_id, cash_out_treasure.month, cash_out_treasure.bucket_id) co ON (((co.user_id = me.user_id) AND ((co.month)::text = (me.month)::text) AND (co.bucket_id = me.bucket_id))))
  WHERE ((bc.display_type)::text = 'ORANGE'::text)
  ORDER BY me.month, me.bucket_id;


ALTER VIEW public.v_orange_bucket_money_flow OWNER TO postgres;

--
-- TOC entry 244 (class 1259 OID 47118)
-- Name: v_reserve; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.v_reserve (
    allocated numeric(12,2)
);


ALTER TABLE public.v_reserve OWNER TO postgres;

--
-- TOC entry 242 (class 1259 OID 47078)
-- Name: v_vault_current; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_vault_current AS
 WITH spend_summary AS (
         SELECT me.user_id,
            me.month,
            sum(
                CASE
                    WHEN ((bt.type_name)::text = ANY ((ARRAY['RED'::character varying, 'GREEN'::character varying])::text[])) THEN GREATEST(me.allocated, me.spent)
                    WHEN ((bt.type_name)::text = ANY ((ARRAY['YELLOW'::character varying, 'ORANGE'::character varying])::text[])) THEN me.spent
                    ELSE (0)::numeric
                END) AS total_deducted
           FROM ((public.monthly_entries me
             JOIN public.bucket_configs bc ON ((bc.bucket_id = me.bucket_id)))
             JOIN public.bucket_types bt ON (((bt.type_name)::text = (bc.display_type)::text)))
          WHERE ((bt.affects_vault)::text = 'MAIN'::text)
          GROUP BY me.user_id, me.month
        )
 SELECT v.user_id,
    v.month,
    v.opening_amt,
    COALESCE(p.salary, (0)::numeric) AS salary,
    COALESCE(ss.total_deducted, (0)::numeric) AS total_deducted,
    ((v.opening_amt + COALESCE(p.salary, (0)::numeric)) - COALESCE(ss.total_deducted, (0)::numeric)) AS current_amt,
    v.closing_amt
   FROM ((public.vault v
     LEFT JOIN public.paychecks p ON (((p.user_id = v.user_id) AND ((p.month)::text = (v.month)::text))))
     LEFT JOIN spend_summary ss ON (((ss.user_id = v.user_id) AND ((ss.month)::text = (v.month)::text))));


ALTER VIEW public.v_vault_current OWNER TO postgres;

--
-- TOC entry 243 (class 1259 OID 47088)
-- Name: v_reserve_summary; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_reserve_summary AS
 SELECT vc.user_id,
    vc.month,
    vc.current_amt AS allocated,
    COALESCE(sum(cot.surplus_amt), (0)::numeric) AS spent
   FROM (public.v_vault_current vc
     LEFT JOIN public.cash_out_treasure cot ON (((cot.user_id = vc.user_id) AND ((cot.month)::text = (vc.month)::text))))
  GROUP BY vc.user_id, vc.month, vc.current_amt;


ALTER VIEW public.v_reserve_summary OWNER TO postgres;

--
-- TOC entry 246 (class 1259 OID 47204)
-- Name: v_yellow_bucket_money_flow; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_yellow_bucket_money_flow AS
 SELECT me.user_id,
    me.month,
    me.bucket_id,
    bc.bucket_name,
    ((me.allocated + COALESCE(ci.total_cash_in, (0)::numeric)) - COALESCE(co.total_cash_out, (0)::numeric)) AS initial_allocated,
    me.allocated AS current_allocated,
    me.spent AS total_spent,
    COALESCE(ci.total_cash_in, (0)::numeric) AS total_saved_to_vault,
    COALESCE(ci.save_count, (0)::bigint) AS save_count,
    COALESCE(co.total_cash_out, (0)::numeric) AS total_pulled_from_vault,
    COALESCE(co.pull_count, (0)::bigint) AS pull_count,
    (COALESCE(ci.total_cash_in, (0)::numeric) - COALESCE(co.total_cash_out, (0)::numeric)) AS net_vault_impact,
    v.opening_amt AS vault_opening,
    v.current_amt AS vault_current,
    v.closing_amt AS vault_closing
   FROM (((((public.monthly_entries me
     JOIN public.bucket_configs bc ON ((bc.bucket_id = me.bucket_id)))
     JOIN public.paychecks p ON (((p.user_id = me.user_id) AND ((p.month)::text = (me.month)::text))))
     JOIN public.vault v ON (((v.user_id = me.user_id) AND ((v.month)::text = (me.month)::text))))
     LEFT JOIN ( SELECT cash_in_treasure.user_id,
            cash_in_treasure.month,
            cash_in_treasure.bucket_id,
            sum(cash_in_treasure.underspend_amt) AS total_cash_in,
            count(*) AS save_count
           FROM public.cash_in_treasure
          GROUP BY cash_in_treasure.user_id, cash_in_treasure.month, cash_in_treasure.bucket_id) ci ON (((ci.user_id = me.user_id) AND ((ci.month)::text = (me.month)::text) AND (ci.bucket_id = me.bucket_id))))
     LEFT JOIN ( SELECT cash_out_treasure.user_id,
            cash_out_treasure.month,
            cash_out_treasure.bucket_id,
            sum(cash_out_treasure.surplus_amt) AS total_cash_out,
            count(*) AS pull_count
           FROM public.cash_out_treasure
          GROUP BY cash_out_treasure.user_id, cash_out_treasure.month, cash_out_treasure.bucket_id) co ON (((co.user_id = me.user_id) AND ((co.month)::text = (me.month)::text) AND (co.bucket_id = me.bucket_id))))
  WHERE ((bc.display_type)::text = 'YELLOW'::text)
  ORDER BY me.month, me.bucket_id;


ALTER VIEW public.v_yellow_bucket_money_flow OWNER TO postgres;

--
-- TOC entry 4881 (class 2604 OID 46849)
-- Name: bucket_configs bucket_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bucket_configs ALTER COLUMN bucket_id SET DEFAULT nextval('public.bucket_configs_bucket_id_seq'::regclass);


--
-- TOC entry 4897 (class 2604 OID 47042)
-- Name: cash_in_blue_treasure id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cash_in_blue_treasure ALTER COLUMN id SET DEFAULT nextval('public.cash_in_blue_treasure_id_seq'::regclass);


--
-- TOC entry 4893 (class 2604 OID 47003)
-- Name: cash_in_treasure id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cash_in_treasure ALTER COLUMN id SET DEFAULT nextval('public.cash_in_treasure_id_seq'::regclass);


--
-- TOC entry 4895 (class 2604 OID 47023)
-- Name: cash_out_blue_treasure id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cash_out_blue_treasure ALTER COLUMN id SET DEFAULT nextval('public.cash_out_blue_treasure_id_seq'::regclass);


--
-- TOC entry 4891 (class 2604 OID 46984)
-- Name: cash_out_treasure id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cash_out_treasure ALTER COLUMN id SET DEFAULT nextval('public.cash_out_treasure_id_seq'::regclass);


--
-- TOC entry 4886 (class 2604 OID 46909)
-- Name: ledger ledger_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ledger ALTER COLUMN ledger_id SET DEFAULT nextval('public.ledger_ledger_id_seq'::regclass);


--
-- TOC entry 4883 (class 2604 OID 46881)
-- Name: monthly_entries id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.monthly_entries ALTER COLUMN id SET DEFAULT nextval('public.monthly_entries_id_seq'::regclass);


--
-- TOC entry 5133 (class 0 OID 45968)
-- Dependencies: 221
-- Data for Name: users; Type: TABLE DATA; Schema: auth; Owner: postgres
--

COPY auth.users (id, phone, phone_verified, name, password_hash, is_active, created_at, updated_at, email, email_confirmed_at, last_sign_in_at, raw_app_meta_data, raw_user_meta_data) FROM stdin;
a240aa31-9303-41d1-9caf-a3389dedfd99	+917013328957	f	Sairam	$2a$06$AZNjh0FD.YFyKcRRrfPFCu2N9kFTQPgn7FHuLB.2VAP/6DUlbK6ri	t	2026-05-15 11:20:59.707778+05:30	2026-05-15 11:20:59.707778+05:30	sairamsarika24@gmail.com	\N	\N	{}	{"name": "Sairam"}
\.


--
-- TOC entry 5143 (class 0 OID 46967)
-- Dependencies: 231
-- Data for Name: blue_vault; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.blue_vault (user_id, month, opening_amt, closing_amt, current_amt) FROM stdin;
a240aa31-9303-41d1-9caf-a3389dedfd99	2026-01	21000.00	\N	16000.00
\.


--
-- TOC entry 5136 (class 0 OID 46846)
-- Dependencies: 224
-- Data for Name: bucket_configs; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.bucket_configs (bucket_id, user_id, bucket_name, display_type, is_active) FROM stdin;
1	a240aa31-9303-41d1-9caf-a3389dedfd99	Reserve	RESERVE	t
2	a240aa31-9303-41d1-9caf-a3389dedfd99	Rent	RED	t
3	a240aa31-9303-41d1-9caf-a3389dedfd99	Loan EMI	RED	t
8	a240aa31-9303-41d1-9caf-a3389dedfd99	Misc Surprises	ORANGE	t
9	a240aa31-9303-41d1-9caf-a3389dedfd99	Vacation Fund	BLUE	t
4	a240aa31-9303-41d1-9caf-a3389dedfd99	Groceries	YELLOW	t
5	a240aa31-9303-41d1-9caf-a3389dedfd99	OTT Subs	YELLOW	t
6	a240aa31-9303-41d1-9caf-a3389dedfd99	Emergency SIP	GREEN	t
7	a240aa31-9303-41d1-9caf-a3389dedfd99	Gadget Fund	BLUE	t
\.


--
-- TOC entry 5134 (class 0 OID 46834)
-- Dependencies: 222
-- Data for Name: bucket_types; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.bucket_types (type_name, color, vault_role, affects_vault, overspend_ok, underspend_returns, description) FROM stdin;
RED	red	NONE	MAIN	t	f	Fixed committed expenses (rent, EMI). Overspend allowed; underspend is consumed, not returned.
GREEN	green	NONE	MAIN	t	f	Planned discretionary spend. Mechanically identical to RED; separated for reporting intent.
YELLOW	yellow	DRIP_IN	MAIN	t	t	Savings-style bucket. Underspend returns to main vault at month close via cash_in_treasure.
ORANGE	orange	DRIP_OUT	MAIN	t	f	Surprise/emergency. allocated auto-syncs to total spend after each entry. No fixed plan.
BLUE	blue	DRIP_IN	BLUE	t	t	Isolated blue vault bucket. Never touches main vault. Underspend returns via cash_in_blue_treasure.
RESERVE	grey	DRIP_IN	NONE	f	f	Virtual summary row only. allocated = unallocated salary. No ledger entries ever.
\.


--
-- TOC entry 5151 (class 0 OID 47039)
-- Dependencies: 239
-- Data for Name: cash_in_blue_treasure; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.cash_in_blue_treasure (id, user_id, month, bucket_id, underspend_amt, entry_date) FROM stdin;
\.


--
-- TOC entry 5147 (class 0 OID 47000)
-- Dependencies: 235
-- Data for Name: cash_in_treasure; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.cash_in_treasure (id, user_id, month, bucket_id, underspend_amt, entry_date) FROM stdin;
\.


--
-- TOC entry 5149 (class 0 OID 47020)
-- Dependencies: 237
-- Data for Name: cash_out_blue_treasure; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.cash_out_blue_treasure (id, user_id, month, bucket_id, surplus_amt, entry_date) FROM stdin;
3	a240aa31-9303-41d1-9caf-a3389dedfd99	2026-01	9	2500.00	2026-01-18
\.


--
-- TOC entry 5145 (class 0 OID 46981)
-- Dependencies: 233
-- Data for Name: cash_out_treasure; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.cash_out_treasure (id, user_id, month, bucket_id, surplus_amt, entry_date) FROM stdin;
24	a240aa31-9303-41d1-9caf-a3389dedfd99	2026-01	8	12000.00	2026-01-16
25	a240aa31-9303-41d1-9caf-a3389dedfd99	2026-01	8	700.00	2026-01-16
\.


--
-- TOC entry 5141 (class 0 OID 46906)
-- Dependencies: 229
-- Data for Name: ledger; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.ledger (ledger_id, user_id, bucket_id, amount_spent, month, date_of_entry, note, reversed, reversed_by) FROM stdin;
68	a240aa31-9303-41d1-9caf-a3389dedfd99	8	12000.00	2026-01	2026-01-16	AC Repair	f	\N
69	a240aa31-9303-41d1-9caf-a3389dedfd99	9	5000.00	2026-01	2026-01-16	RJY  Bus  Trip	f	\N
72	a240aa31-9303-41d1-9caf-a3389dedfd99	9	2500.00	2026-01	2026-05-22	REVERSAL OF #71:  RJY return ticket cancelled	t	\N
71	a240aa31-9303-41d1-9caf-a3389dedfd99	9	2500.00	2026-01	2026-01-18	Return from RJY  Bus  Trip	t	72
73	a240aa31-9303-41d1-9caf-a3389dedfd99	8	700.00	2026-01	2026-01-16	Fan Repair	f	\N
\.


--
-- TOC entry 5139 (class 0 OID 46878)
-- Dependencies: 227
-- Data for Name: monthly_entries; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.monthly_entries (id, user_id, month, bucket_id, allocated, spent) FROM stdin;
112	a240aa31-9303-41d1-9caf-a3389dedfd99	2026-01	7	6000.00	0.00
113	a240aa31-9303-41d1-9caf-a3389dedfd99	2026-01	9	5000.00	5000.00
111	a240aa31-9303-41d1-9caf-a3389dedfd99	2026-01	8	12700.00	12700.00
110	a240aa31-9303-41d1-9caf-a3389dedfd99	2026-01	1	77300.00	0.00
\.


--
-- TOC entry 5137 (class 0 OID 46865)
-- Dependencies: 225
-- Data for Name: paychecks; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.paychecks (user_id, month, salary) FROM stdin;
a240aa31-9303-41d1-9caf-a3389dedfd99	2026-01	90000.00
\.


--
-- TOC entry 5152 (class 0 OID 47118)
-- Dependencies: 244
-- Data for Name: v_reserve; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.v_reserve (allocated) FROM stdin;
58500.00
\.


--
-- TOC entry 5142 (class 0 OID 46937)
-- Dependencies: 230
-- Data for Name: vault; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.vault (user_id, month, opening_amt, closing_amt, current_amt) FROM stdin;
a240aa31-9303-41d1-9caf-a3389dedfd99	2026-01	90000.00	\N	77300.00
\.


--
-- TOC entry 5166 (class 0 OID 0)
-- Dependencies: 223
-- Name: bucket_configs_bucket_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.bucket_configs_bucket_id_seq', 9, true);


--
-- TOC entry 5167 (class 0 OID 0)
-- Dependencies: 238
-- Name: cash_in_blue_treasure_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.cash_in_blue_treasure_id_seq', 9, true);


--
-- TOC entry 5168 (class 0 OID 0)
-- Dependencies: 234
-- Name: cash_in_treasure_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.cash_in_treasure_id_seq', 4, true);


--
-- TOC entry 5169 (class 0 OID 0)
-- Dependencies: 236
-- Name: cash_out_blue_treasure_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.cash_out_blue_treasure_id_seq', 3, true);


--
-- TOC entry 5170 (class 0 OID 0)
-- Dependencies: 232
-- Name: cash_out_treasure_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.cash_out_treasure_id_seq', 25, true);


--
-- TOC entry 5171 (class 0 OID 0)
-- Dependencies: 228
-- Name: ledger_ledger_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.ledger_ledger_id_seq', 73, true);


--
-- TOC entry 5172 (class 0 OID 0)
-- Dependencies: 226
-- Name: monthly_entries_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.monthly_entries_id_seq', 113, true);


--
-- TOC entry 4916 (class 2606 OID 45982)
-- Name: users users_pkey; Type: CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- TOC entry 4939 (class 2606 OID 46974)
-- Name: blue_vault blue_vault_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.blue_vault
    ADD CONSTRAINT blue_vault_pkey PRIMARY KEY (user_id, month);


--
-- TOC entry 4920 (class 2606 OID 46852)
-- Name: bucket_configs bucket_configs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bucket_configs
    ADD CONSTRAINT bucket_configs_pkey PRIMARY KEY (bucket_id);


--
-- TOC entry 4922 (class 2606 OID 46854)
-- Name: bucket_configs bucket_configs_user_id_bucket_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bucket_configs
    ADD CONSTRAINT bucket_configs_user_id_bucket_name_key UNIQUE (user_id, bucket_name);


--
-- TOC entry 4918 (class 2606 OID 46844)
-- Name: bucket_types bucket_types_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bucket_types
    ADD CONSTRAINT bucket_types_pkey PRIMARY KEY (type_name);


--
-- TOC entry 4951 (class 2606 OID 47046)
-- Name: cash_in_blue_treasure cash_in_blue_treasure_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cash_in_blue_treasure
    ADD CONSTRAINT cash_in_blue_treasure_pkey PRIMARY KEY (id);


--
-- TOC entry 4945 (class 2606 OID 47007)
-- Name: cash_in_treasure cash_in_treasure_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cash_in_treasure
    ADD CONSTRAINT cash_in_treasure_pkey PRIMARY KEY (id);


--
-- TOC entry 4948 (class 2606 OID 47027)
-- Name: cash_out_blue_treasure cash_out_blue_treasure_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cash_out_blue_treasure
    ADD CONSTRAINT cash_out_blue_treasure_pkey PRIMARY KEY (id);


--
-- TOC entry 4942 (class 2606 OID 46988)
-- Name: cash_out_treasure cash_out_treasure_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cash_out_treasure
    ADD CONSTRAINT cash_out_treasure_pkey PRIMARY KEY (id);


--
-- TOC entry 4934 (class 2606 OID 46916)
-- Name: ledger ledger_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ledger
    ADD CONSTRAINT ledger_pkey PRIMARY KEY (ledger_id);


--
-- TOC entry 4927 (class 2606 OID 46887)
-- Name: monthly_entries monthly_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.monthly_entries
    ADD CONSTRAINT monthly_entries_pkey PRIMARY KEY (id);


--
-- TOC entry 4929 (class 2606 OID 46889)
-- Name: monthly_entries monthly_entries_user_id_month_bucket_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.monthly_entries
    ADD CONSTRAINT monthly_entries_user_id_month_bucket_id_key UNIQUE (user_id, month, bucket_id);


--
-- TOC entry 4924 (class 2606 OID 46871)
-- Name: paychecks paychecks_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.paychecks
    ADD CONSTRAINT paychecks_pkey PRIMARY KEY (user_id, month);


--
-- TOC entry 4937 (class 2606 OID 46944)
-- Name: vault vault_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vault
    ADD CONSTRAINT vault_pkey PRIMARY KEY (user_id, month);


--
-- TOC entry 4940 (class 1259 OID 47062)
-- Name: idx_blue_vault_user_month; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_blue_vault_user_month ON public.blue_vault USING btree (user_id, month);


--
-- TOC entry 4952 (class 1259 OID 47067)
-- Name: idx_cash_in_blue_user_month; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_cash_in_blue_user_month ON public.cash_in_blue_treasure USING btree (user_id, month);


--
-- TOC entry 4946 (class 1259 OID 47065)
-- Name: idx_cash_in_user_month; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_cash_in_user_month ON public.cash_in_treasure USING btree (user_id, month);


--
-- TOC entry 4949 (class 1259 OID 47066)
-- Name: idx_cash_out_blue_user_month; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_cash_out_blue_user_month ON public.cash_out_blue_treasure USING btree (user_id, month);


--
-- TOC entry 4943 (class 1259 OID 47064)
-- Name: idx_cash_out_user_month; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_cash_out_user_month ON public.cash_out_treasure USING btree (user_id, month);


--
-- TOC entry 4930 (class 1259 OID 47059)
-- Name: idx_ledger_bucket_month; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_ledger_bucket_month ON public.ledger USING btree (bucket_id, month);


--
-- TOC entry 4931 (class 1259 OID 47060)
-- Name: idx_ledger_reversed; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_ledger_reversed ON public.ledger USING btree (reversed) WHERE (reversed = false);


--
-- TOC entry 4932 (class 1259 OID 47058)
-- Name: idx_ledger_user_month; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_ledger_user_month ON public.ledger USING btree (user_id, month);


--
-- TOC entry 4925 (class 1259 OID 47057)
-- Name: idx_monthly_entries_user_month; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_monthly_entries_user_month ON public.monthly_entries USING btree (user_id, month);


--
-- TOC entry 4935 (class 1259 OID 47061)
-- Name: idx_vault_user_month; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_vault_user_month ON public.vault USING btree (user_id, month);


--
-- TOC entry 4977 (class 2620 OID 47102)
-- Name: blue_vault trg_protect_blue_vault; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_protect_blue_vault BEFORE INSERT OR UPDATE ON public.blue_vault FOR EACH ROW EXECUTE FUNCTION public.trg_fn_require_procedure_context();


--
-- TOC entry 4979 (class 2620 OID 47097)
-- Name: cash_in_treasure trg_protect_cash_in; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_protect_cash_in BEFORE INSERT ON public.cash_in_treasure FOR EACH ROW EXECUTE FUNCTION public.trg_fn_require_procedure_context();


--
-- TOC entry 4981 (class 2620 OID 47099)
-- Name: cash_in_blue_treasure trg_protect_cash_in_blue; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_protect_cash_in_blue BEFORE INSERT ON public.cash_in_blue_treasure FOR EACH ROW EXECUTE FUNCTION public.trg_fn_require_procedure_context();


--
-- TOC entry 4978 (class 2620 OID 47096)
-- Name: cash_out_treasure trg_protect_cash_out; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_protect_cash_out BEFORE INSERT ON public.cash_out_treasure FOR EACH ROW EXECUTE FUNCTION public.trg_fn_require_procedure_context();


--
-- TOC entry 4980 (class 2620 OID 47098)
-- Name: cash_out_blue_treasure trg_protect_cash_out_blue; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_protect_cash_out_blue BEFORE INSERT ON public.cash_out_blue_treasure FOR EACH ROW EXECUTE FUNCTION public.trg_fn_require_procedure_context();


--
-- TOC entry 4975 (class 2620 OID 47095)
-- Name: ledger trg_protect_ledger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_protect_ledger BEFORE INSERT OR UPDATE ON public.ledger FOR EACH ROW EXECUTE FUNCTION public.trg_fn_require_procedure_context();


--
-- TOC entry 4974 (class 2620 OID 47094)
-- Name: monthly_entries trg_protect_monthly_entries; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_protect_monthly_entries BEFORE INSERT OR UPDATE ON public.monthly_entries FOR EACH ROW EXECUTE FUNCTION public.trg_fn_require_procedure_context();


--
-- TOC entry 4973 (class 2620 OID 47100)
-- Name: paychecks trg_protect_paychecks; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_protect_paychecks BEFORE INSERT OR UPDATE ON public.paychecks FOR EACH ROW EXECUTE FUNCTION public.trg_fn_require_procedure_context();


--
-- TOC entry 4976 (class 2620 OID 47101)
-- Name: vault trg_protect_vault; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_protect_vault BEFORE INSERT OR UPDATE ON public.vault FOR EACH ROW EXECUTE FUNCTION public.trg_fn_require_procedure_context();


--
-- TOC entry 4964 (class 2606 OID 46975)
-- Name: blue_vault blue_vault_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.blue_vault
    ADD CONSTRAINT blue_vault_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- TOC entry 4953 (class 2606 OID 46860)
-- Name: bucket_configs bucket_configs_display_type_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bucket_configs
    ADD CONSTRAINT bucket_configs_display_type_fkey FOREIGN KEY (display_type) REFERENCES public.bucket_types(type_name);


--
-- TOC entry 4954 (class 2606 OID 46855)
-- Name: bucket_configs bucket_configs_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bucket_configs
    ADD CONSTRAINT bucket_configs_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- TOC entry 4971 (class 2606 OID 47052)
-- Name: cash_in_blue_treasure cash_in_blue_treasure_bucket_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cash_in_blue_treasure
    ADD CONSTRAINT cash_in_blue_treasure_bucket_id_fkey FOREIGN KEY (bucket_id) REFERENCES public.bucket_configs(bucket_id);


--
-- TOC entry 4972 (class 2606 OID 47047)
-- Name: cash_in_blue_treasure cash_in_blue_treasure_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cash_in_blue_treasure
    ADD CONSTRAINT cash_in_blue_treasure_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- TOC entry 4967 (class 2606 OID 47013)
-- Name: cash_in_treasure cash_in_treasure_bucket_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cash_in_treasure
    ADD CONSTRAINT cash_in_treasure_bucket_id_fkey FOREIGN KEY (bucket_id) REFERENCES public.bucket_configs(bucket_id);


--
-- TOC entry 4968 (class 2606 OID 47008)
-- Name: cash_in_treasure cash_in_treasure_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cash_in_treasure
    ADD CONSTRAINT cash_in_treasure_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- TOC entry 4969 (class 2606 OID 47033)
-- Name: cash_out_blue_treasure cash_out_blue_treasure_bucket_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cash_out_blue_treasure
    ADD CONSTRAINT cash_out_blue_treasure_bucket_id_fkey FOREIGN KEY (bucket_id) REFERENCES public.bucket_configs(bucket_id);


--
-- TOC entry 4970 (class 2606 OID 47028)
-- Name: cash_out_blue_treasure cash_out_blue_treasure_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cash_out_blue_treasure
    ADD CONSTRAINT cash_out_blue_treasure_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- TOC entry 4965 (class 2606 OID 46994)
-- Name: cash_out_treasure cash_out_treasure_bucket_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cash_out_treasure
    ADD CONSTRAINT cash_out_treasure_bucket_id_fkey FOREIGN KEY (bucket_id) REFERENCES public.bucket_configs(bucket_id);


--
-- TOC entry 4966 (class 2606 OID 46989)
-- Name: cash_out_treasure cash_out_treasure_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cash_out_treasure
    ADD CONSTRAINT cash_out_treasure_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- TOC entry 4959 (class 2606 OID 46922)
-- Name: ledger ledger_bucket_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ledger
    ADD CONSTRAINT ledger_bucket_id_fkey FOREIGN KEY (bucket_id) REFERENCES public.bucket_configs(bucket_id);


--
-- TOC entry 4960 (class 2606 OID 46927)
-- Name: ledger ledger_reversed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ledger
    ADD CONSTRAINT ledger_reversed_by_fkey FOREIGN KEY (reversed_by) REFERENCES public.ledger(ledger_id);


--
-- TOC entry 4961 (class 2606 OID 46917)
-- Name: ledger ledger_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ledger
    ADD CONSTRAINT ledger_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- TOC entry 4962 (class 2606 OID 46932)
-- Name: ledger ledger_user_id_month_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ledger
    ADD CONSTRAINT ledger_user_id_month_fkey FOREIGN KEY (user_id, month) REFERENCES public.paychecks(user_id, month);


--
-- TOC entry 4956 (class 2606 OID 46895)
-- Name: monthly_entries monthly_entries_bucket_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.monthly_entries
    ADD CONSTRAINT monthly_entries_bucket_id_fkey FOREIGN KEY (bucket_id) REFERENCES public.bucket_configs(bucket_id);


--
-- TOC entry 4957 (class 2606 OID 46890)
-- Name: monthly_entries monthly_entries_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.monthly_entries
    ADD CONSTRAINT monthly_entries_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- TOC entry 4958 (class 2606 OID 46900)
-- Name: monthly_entries monthly_entries_user_id_month_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.monthly_entries
    ADD CONSTRAINT monthly_entries_user_id_month_fkey FOREIGN KEY (user_id, month) REFERENCES public.paychecks(user_id, month) ON DELETE CASCADE;


--
-- TOC entry 4955 (class 2606 OID 46872)
-- Name: paychecks paychecks_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.paychecks
    ADD CONSTRAINT paychecks_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- TOC entry 4963 (class 2606 OID 46945)
-- Name: vault vault_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vault
    ADD CONSTRAINT vault_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


-- Completed on 2026-05-22 07:45:30

--
-- PostgreSQL database dump complete
--

