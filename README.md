3rd Party lib's:
@tanstack :
react-table
react-form
react-query

zustand
zod
sonner

shadcn
clsx, tailwind-merge, tw-animate-css, lucide-react

<!-- DB Workflow -->

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

****\*\*****\*\*****\*\*****\_****\*\*****\*\*****\*\*****-

based on above tables data now i will descripe few procedures step on few tables where i am planning to follow our secure ACID properties we discussed earlier okay

procedure_01:
name :paycheck_record_entry

workflow:
a. Insert a record into paychecks and grab it's month
b. make sure bucket_configs have display_type = 'RESERVE' with it's respective bucket_id, then grab its's bucket_id
c.if we don't have respective display_type = 'RESERVE' with bucket_id then Throw an exception by saying Create bucket record first.
d.create a record in monthly_entries with month as reference to paychecks.month , bucket_id as reference to bucekt_configs.bucket_id , user_id as reference to paychecks.user_id and allocated will be derived as (SUM(allocated) of user_id with month of all bucket_types.type_name except bucket_types.type_name = 'RESERVE' - paychecks.salary)

here this is 1st entry of user_id with month of all bucket_types.type_name except bucket_types.type_name = 'RESERVE'so it's equal to paycheck.salary

NOTE:This might be trigger i guess we can only update paychecks.salary only when user_id, month of monthly_entries records have only bucket_types.type_name = 'RESERVE' and the allocated value is equal to paychecks.salary or else we should block the update of paycheck.salary from paycheck UPDATE operation

d.Pre-check: when we try to INSERT new record to monthly_entries of same month, user_id of all bucket_types.type_name except bucket_types.type_name = 'RESERVE'then before INSERT this record, we should have cumpulsory record of bucket_types.type_name = 'RESERVE' of that same month, user_id

this is postgresql DB okay
any doubts ask me and create necessary procedures

This is phase-01 only , if we pass this we can keep on adding fe business logics

---

validation:
1.present_ledger_amt must be +
2.check paycheck record existance
3.check blue bucket of that month open or not
4.check blue bucket was orginally present in bucket_configs are not
5.accept only blue_bucket only
6.check monthly_entries do have blue_bucket record or not

check_point:
pick allocated and spent as v_allocated and v_current_spent
Operation:  
closure:

Example:[Blue]
add record to ledger and update monthly_entries, blue_vault, cash_in_blue_treasure and cash_out_blue_treasure.

test_case_scenarios:
present_ledger_amt > me.allocated Then throw error "insufficient amt"
pre-checks:
SUM(ledger_amt of all similar buckets of that specific month and user) as prev_ledger_amt
prev_ledger_amt
