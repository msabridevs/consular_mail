-- Run one account at a time AFTER creating its Auth user.
-- Edit only these values, then run the whole block in Supabase SQL Editor.
-- This is an administrator operation, never a browser/API call.
do $$
declare
 staff_email text := 'REPLACE_WITH_WORK_EMAIL';
 staff_name text := 'REPLACE_WITH_DISPLAY_NAME';
 staff_role private.staff_role := 'officer';
 staff_departments private.department[] := array['legalization']::private.department[];
 uid uuid;
begin
 select id into uid from auth.users where lower(email)=lower(staff_email);
 if uid is null then raise exception 'Create the Auth user first: %',staff_email; end if;
 insert into private.staff(user_id,display_name,role,departments,active)
 values(uid,staff_name,staff_role,staff_departments,true)
 on conflict(user_id) do update set display_name=excluded.display_name,role=excluded.role,departments=excluded.departments,active=true;
end $$;
-- Roles: admin | intake | officer | consul
-- Departments: legalization | visas | passports | civil
-- More than one: array['passports','civil']::private.department[]
-- admin/intake can use array[]::private.department[]; they already access all departments.
