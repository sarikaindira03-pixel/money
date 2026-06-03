-- Local Auth Eco-System
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS auth.users (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
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
    
    CONSTRAINT users_phone_check CHECK (phone ~ '^[+]?[0-9]{10,15}$')
);

INSERT INTO auth.users (
    name, 
    phone, 
    password_hash,
    raw_user_meta_data,
	email
) VALUES (
    'Sairam',
    '+917013328957',
    crypt('Eleven@152', gen_salt('bf')),   -- This is the proper way
    jsonb_build_object('name', 'Sairam'),
	'sairamsarika24@gmail.com'
)
RETURNING *;


SELECT column_name
FROM information_schema.columns
WHERE table_schema = 'auth'
AND table_name = 'users';


CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid AS $$
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
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

SET app.user_id = '550e8400-e29b-41d4-a716-446655440000';


SELECT auth.uid();

-- NOTES



  CALL allocate_bucket('a240aa31-9303-41d1-9caf-a3389dedfd99', '2025-01',
        (SELECT bucket_id FROM bucket_configs WHERE user_id = 'a240aa31-9303-41d1-9caf-a3389dedfd99' AND bucket_name = 'Rent'), 18000.00);
	
-- this throw error: cannot use subquery in CALL argument, So we have  2 options


-- option 01 [precompute variable]

DO $$
DECLARE
    v_bucket_id UUID;
BEGIN
    SELECT bucket_id
    INTO v_bucket_id
    FROM bucket_configs
    WHERE user_id = 'a240aa31-9303-41d1-9caf-a3389dedfd99'
      AND bucket_name = 'Rent';

    CALL allocate_bucket(
        'a240aa31-9303-41d1-9caf-a3389dedfd99',
        '2025-01',
        v_bucket_id,
        18000.00
    );
END $$;


-- option 02 [inline function] reusablility

CREATE FUNCTION get_bucket_id(p_user uuid, p_name text)
RETURNS uuid AS $$
    SELECT bucket_id
    FROM bucket_configs
    WHERE user_id = p_user
      AND bucket_name = p_name;
$$ LANGUAGE SQL;
-- usage

CALL allocate_bucket(
    'user-id',
    '2025-01',
    get_bucket_id('user-id', 'Rent'),
    18000.00
);