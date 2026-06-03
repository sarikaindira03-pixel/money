
-- =============================================================================
-- SECTION 0: TABLES
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
month VARCHAR(7) NOT NULL PRIMARY KEY,
user_id uuid REFERENCES auth.users (id) ON DELETE CASCADE,
salary NUMERIC(12, 2) DEFAULT 0,
UNIQUE (user_id, month)
);

CREATE TABLE monthly_entries (
id SERIAL PRIMARY KEY,
user_id uuid REFERENCES auth.users (id) ON DELETE CASCADE,
month VARCHAR(7) NOT NULL REFERENCES paychecks (month) ON DELETE CASCADE,
bucket_id INTEGER REFERENCES bucket_configs (bucket_id),
allocated NUMERIC(12, 2) DEFAULT 0,
spent NUMERIC(12, 2) DEFAULT 0,
UNIQUE (user_id, month, bucket_id)
);

-- =============================================================================
--
-- Workflow:
--   a. INSERT into paychecks, capture month
--   b. Lookup RESERVE bucket for this user → grab bucket_id + bucket_name
--   c. If no RESERVE bucket config exists → RAISE EXCEPTION
--   d. INSERT into monthly_entries for RESERVE bucket
--      allocated = salary - SUM(non-RESERVE allocated for same user+month)
--      On first insert this equals salary (SUM = 0)
--
-- ACID guarantee:
--   • Explicit BEGIN (PostgreSQL procedures use BEGIN...EXCEPTION...END)
--   • EXCEPTION block catches any error → rolls back → re-raises
--   • COMMIT happens implicitly on clean exit from the procedure
-- =============================================================================
 
CREATE OR REPLACE PROCEDURE paycheck_record_entry(
    p_user_id  uuid,
    p_month    VARCHAR(7),
    p_salary   NUMERIC(12, 2)
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_month              VARCHAR(7);
    v_reserve_bucket_id  INTEGER;
    v_reserve_bucket_name VARCHAR(20);
    v_non_reserve_sum    NUMERIC(12, 2);
    v_reserve_allocated  NUMERIC(12, 2);
BEGIN
 
    -- -------------------------------------------------------------------------
    -- STEP A: Insert into paychecks and capture the month
    -- -------------------------------------------------------------------------
    INSERT INTO paychecks (user_id, month, salary)
    VALUES (p_user_id, p_month, p_salary)
    RETURNING month INTO v_month;
 
    -- -------------------------------------------------------------------------
    -- STEP B: Find the RESERVE bucket config for this user
    --         bucket_configs.display_type must equal 'RESERVE'
    -- -------------------------------------------------------------------------
    SELECT
        bc.bucket_id,
        bc.bucket_name
    INTO
        v_reserve_bucket_id,
        v_reserve_bucket_name
    FROM bucket_configs bc
    WHERE bc.user_id       = p_user_id
      AND bc.display_type  = 'RESERVE'
      AND bc.is_active     = TRUE
    LIMIT 1;
 
    -- -------------------------------------------------------------------------
    -- STEP C: Guard — RESERVE bucket must exist before proceeding
    -- -------------------------------------------------------------------------
    IF v_reserve_bucket_id IS NULL THEN
        RAISE EXCEPTION
            'Create bucket record first. No active RESERVE bucket found for user %.',
            p_user_id
        USING ERRCODE = 'P0001';
    END IF;
 
    -- -------------------------------------------------------------------------
    -- STEP D: Compute allocated for RESERVE
    --
    --   Formula: salary - SUM(allocated of non-RESERVE entries for same user+month)
    --
    --   On first insert (no other monthly_entries yet for this month):
    --     SUM = 0  →  allocated = salary  ✅
    --
    --   On subsequent calls (if somehow called again after allocations exist):
    --     allocated = salary - existing non-RESERVE allocations
    -- -------------------------------------------------------------------------
    SELECT COALESCE(SUM(me.allocated), 0)
    INTO v_non_reserve_sum
    FROM monthly_entries me
    JOIN bucket_configs bc ON bc.bucket_id = me.bucket_id
    JOIN bucket_types   bt ON bt.type_name = bc.display_type
    WHERE me.user_id = p_user_id
      AND me.month   = v_month
      AND bt.type_name <> 'RESERVE';
 
    v_reserve_allocated := p_salary - v_non_reserve_sum;
 
    -- -------------------------------------------------------------------------
    -- STEP D (insert): Create the RESERVE monthly_entry row
    --
    -- Note: The BEFORE INSERT trigger (Section 2) normally blocks non-RESERVE
    --       inserts when no RESERVE row exists yet. This insert IS the RESERVE
    --       row itself, so the trigger will pass it through directly.
    -- -------------------------------------------------------------------------
    INSERT INTO monthly_entries (
        user_id,
        month,
        bucket_id,
        allocated_name,
        allocated,
        spent
    )
    VALUES (
        p_user_id,
        v_month,
        v_reserve_bucket_id,
        v_reserve_bucket_name,
        v_reserve_allocated,
        0
    );
 
EXCEPTION
    WHEN OTHERS THEN
        -- Re-raise the original error to the caller
        -- PostgreSQL automatically rolls back the transaction on unhandled exception
        -- RAISE without arguments re-raises the current exception with full context
        RAISE;
END;
$$;
 
 
-- =============================================================================
-- SECTION 2: TRIGGER — Block non-RESERVE monthly_entry inserts
--            when no RESERVE row exists for that (user_id, month)
--
-- Fires: BEFORE INSERT on monthly_entries
-- Logic:
--   • If the row being inserted IS the RESERVE type → allow through
--   • If it is NOT RESERVE → check that a RESERVE row already exists
--     for the same (user_id, month). If not → block with exception.
-- =============================================================================
 
CREATE OR REPLACE FUNCTION trg_fn_require_reserve_before_entry()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_inserting_type  VARCHAR(20);
    v_reserve_exists  BOOLEAN;
BEGIN
 
    -- Determine the bucket_type of the row being inserted
    SELECT bc.display_type
    INTO v_inserting_type
    FROM bucket_configs bc
    WHERE bc.bucket_id = NEW.bucket_id;
 
    -- If this insert IS the RESERVE row → allow it through immediately
    IF v_inserting_type = 'RESERVE' THEN
        RETURN NEW;
    END IF;
 
    -- For non-RESERVE inserts: verify a RESERVE row exists for this user+month
    SELECT EXISTS (
        SELECT 1
        FROM monthly_entries  me
        JOIN bucket_configs   bc ON bc.bucket_id    = me.bucket_id
        WHERE me.user_id  = NEW.user_id
          AND me.month    = NEW.month
          AND bc.display_type = 'RESERVE'
    ) INTO v_reserve_exists;
 
    IF NOT v_reserve_exists THEN
        RAISE EXCEPTION
            'Cannot add monthly entry for month % until a RESERVE entry exists. '
            'Call paycheck_record_entry first.',
            NEW.month
        USING ERRCODE = 'P0002';
    END IF;
 
    RETURN NEW;
END;
$$;
 
CREATE TRIGGER trg_require_reserve_before_entry
BEFORE INSERT ON monthly_entries
FOR EACH ROW
EXECUTE FUNCTION trg_fn_require_reserve_before_entry();
 
 
-- =============================================================================
-- SECTION 3: TRIGGER — Block paychecks.salary UPDATE
--
-- Fires: BEFORE UPDATE OF salary ON paychecks
-- Block condition:
--   Any non-RESERVE monthly_entry exists for (user_id, month) of this paycheck
--   i.e. allocations have already been distributed → salary is locked
--
-- Allow condition:
--   The only monthly_entry for this (user_id, month) is the RESERVE row
--   AND its allocated value equals the current salary
--   (meaning no real allocation has happened yet)
-- =============================================================================
 
CREATE OR REPLACE FUNCTION trg_fn_block_salary_update()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_non_reserve_count  INTEGER;
BEGIN
 
    -- Count non-RESERVE entries for this user+month combo
    SELECT COUNT(*)
    INTO v_non_reserve_count
    FROM monthly_entries  me
    JOIN bucket_configs   bc ON bc.bucket_id    = me.bucket_id
    JOIN bucket_types     bt ON bt.type_name    = bc.display_type
    WHERE me.user_id  = OLD.user_id
      AND me.month    = OLD.month
      AND bt.type_name <> 'RESERVE';
 
    -- If any non-RESERVE allocation exists → salary is locked
    IF v_non_reserve_count > 0 THEN
        RAISE EXCEPTION
            'Cannot update salary for month %. Allocations already exist. '
            'Remove all non-RESERVE monthly entries first.',
            OLD.month
        USING ERRCODE = 'P0003';
    END IF;
 
    -- Allow the update; also sync the RESERVE allocated to match the new salary
    -- so the RESERVE row stays accurate (salary - 0 non-reserve = new salary)
    UPDATE monthly_entries me
    SET    allocated = NEW.salary
    FROM   bucket_configs bc
    JOIN   bucket_types   bt ON bt.type_name = bc.display_type
    WHERE  me.bucket_id  = bc.bucket_id
      AND  me.user_id    = OLD.user_id
      AND  me.month      = OLD.month
      AND  bt.type_name  = 'RESERVE';
 
    RETURN NEW;
END;
$$;
 
CREATE TRIGGER trg_block_salary_update
BEFORE UPDATE OF salary ON paychecks
FOR EACH ROW
EXECUTE FUNCTION trg_fn_block_salary_update();
 
 
-- =============================================================================
-- QUICK REFERENCE — Call the procedure
-- =============================================================================
--
--   CALL paycheck_record_entry(
--       '550e8400-e29b-41d4-a716-446655440000',   -- user_id (uuid)
--       '2025-06',                                 -- month   (YYYY-MM)
--       85000.00                                   -- salary
--   );
--
-- What happens on success:
--   1. paychecks row created for (user_id, month, salary)
--   2. monthly_entries row created for RESERVE bucket
--      with allocated = 85000.00 (salary - 0 non-reserve)
--
-- What happens on failure (any step):
--   Full rollback — neither paychecks nor monthly_entries row is created
--   Exception message returned to caller
--
-- =============================================================================
    