-- Run ONCE on a new Supabase project as postgres. Atomic migration.
begin;
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
create type private.department as enum ('legalization','visas','passports','civil');
create type private.mail_status as enum ('registered','processing','waiting','returned');
create type private.staff_role as enum ('admin','intake','officer','consul');
create table private.staff (
 user_id uuid primary key references auth.users(id), display_name text not null check(length(display_name) between 1 and 120),
 role private.staff_role not null, departments private.department[] not null default '{}', active boolean not null default true,
 check(role in ('admin','intake') or cardinality(departments)>0)
);
create table private.mail (
 id uuid primary key default gen_random_uuid(), tracking text not null unique check(tracking ~ '^[A-Z0-9-]{6,50}$'),
 sender_name text not null check(length(trim(sender_name)) between 1 and 200), department private.department not null,
 amount_cents integer not null check(amount_cents between 0 and 99999999), currency text not null default 'EUR' check(currency='EUR'),
 status private.mail_status not null default 'registered', created_at timestamptz not null default now(),
 received_at timestamptz, returned_at timestamptz, updated_at timestamptz not null default now(),
 created_by uuid not null references private.staff(user_id), public_note_ar text not null default '' check(length(public_note_ar)<=2000),
 public_note_de text not null default '' check(length(public_note_de)<=2000), internal_note text not null default '' check(length(internal_note)<=4000),
 return_tracking text not null default '' check(length(return_tracking)<=50), version integer not null default 1
);
create index mail_department_status on private.mail(department,status,created_at desc);
create index mail_created on private.mail(created_at desc);
create table private.events (
 id bigint generated always as identity primary key, mail_id uuid not null references private.mail(id),
 actor_id uuid not null references private.staff(user_id), actor_name text not null, action text not null,
 at timestamptz not null default now(), before_data jsonb, after_data jsonb
);
create index events_mail on private.events(mail_id,at desc);
create table private.rate_limits (bucket text primary key, window_start timestamptz not null, hits integer not null);
create index rate_limits_window on private.rate_limits(window_start);
alter table private.staff enable row level security;
alter table private.mail enable row level security;
alter table private.events enable row level security;
alter table private.rate_limits enable row level security;
revoke all on all tables in schema private from public,anon,authenticated;
-- No policies: all direct client access is denied. Only narrowly scoped RPCs below.
create function private.actor() returns private.staff language plpgsql security definer set search_path='' as $$
declare a private.staff;
begin
 if coalesce(auth.jwt()->>'aal','') <> 'aal2' then raise exception 'MFA_REQUIRED'; end if;
 select * into a from private.staff where user_id=auth.uid() and active;
 if not found then raise exception 'ACCESS_DENIED'; end if;
 return a;
end $$;
create function private.can_read(a private.staff,d private.department) returns boolean language sql immutable set search_path='' as $$
 select a.role in ('admin','intake') or d=any(a.departments)
$$;
create function private.audit() returns trigger language plpgsql security definer set search_path='' as $$
declare a private.staff;
begin
 a:=private.actor();
 insert into private.events(mail_id,actor_id,actor_name,action,before_data,after_data)
 values(new.id,a.user_id,a.display_name,case when TG_OP='INSERT' then 'register' when old.status<>new.status then new.status::text else 'update' end,
 case when TG_OP='INSERT' then null else to_jsonb(old) end,to_jsonb(new));
 return new;
end $$;
create trigger mail_audit after insert or update on private.mail for each row execute function private.audit();
create function public.my_profile() returns jsonb language plpgsql security definer set search_path='' as $$
declare a private.staff; begin a:=private.actor(); return to_jsonb(a); end $$;
create function public.register_mail(p_tracking text,p_sender text,p_department text,p_amount integer) returns uuid
language plpgsql security definer set search_path='' as $$
declare a private.staff; result uuid;
begin
 a:=private.actor(); if a.role not in ('admin','intake') then raise exception 'ACCESS_DENIED'; end if;
 insert into private.mail(tracking,sender_name,department,amount_cents,created_by)
 values(upper(regexp_replace(trim(p_tracking),'\s','','g')),trim(p_sender),p_department::private.department,p_amount,a.user_id) returning id into result;
 return result;
end $$;
create function public.list_mail(p_query text default '',p_department text default '',p_status text default '',p_page integer default 0,p_overdue boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a private.staff; result jsonb;
begin
 a:=private.actor(); if p_page<0 or p_page>100000 or length(p_query)>200 then raise exception 'INVALID_INPUT'; end if;
 with filtered as (
 select m.* from private.mail m where private.can_read(a,m.department)
 and (p_department='' or m.department::text=p_department) and (p_status='' or m.status::text=p_status)
 and (p_query='' or position(lower(p_query) in lower(m.tracking))>0 or position(lower(p_query) in lower(m.sender_name))>0)
 and (not p_overdue or (m.status<>'returned' and m.created_at<now()-interval '7 days'))
 ), page as (select * from filtered order by created_at desc,id limit 50 offset p_page*50)
 select jsonb_build_object('total',(select count(*) from filtered),'items',coalesce((select jsonb_agg(to_jsonb(page)) from page),'[]'::jsonb)) into result;
 return result;
end $$;
create function public.dashboard() returns jsonb language plpgsql security definer set search_path='' as $$
declare a private.staff; result jsonb;
begin a:=private.actor();
 select coalesce(jsonb_agg(to_jsonb(s)),'[]'::jsonb) into result from (
 select department,count(*) as total,count(*) filter(where status='registered') as registered,
 count(*) filter(where status='processing') as processing,count(*) filter(where status='waiting') as waiting,
 count(*) filter(where status='returned') as returned,
 count(*) filter(where status<>'returned' and created_at<now()-interval '7 days') as overdue,
 count(*) filter(where (returned_at at time zone 'Europe/Berlin')::date=(now() at time zone 'Europe/Berlin')::date) as returned_today,
 round(avg(extract(epoch from returned_at-created_at)/86400) filter(where status='returned'),1) as average_days
 from private.mail where private.can_read(a,department) group by department) s;
 return result; end $$;
-- Atomic batches, row locks in deterministic order, optimistic versions, max 100.
create function public.transition_mail(p_items jsonb,p_action text) returns integer language plpgsql security definer set search_path='' as $$
declare a private.staff; m private.mail; wanted private.mail_status; n integer:=0; item jsonb;
begin
 a:=private.actor(); if a.role not in ('admin','officer') then raise exception 'ACCESS_DENIED'; end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items) not between 1 and 100 then raise exception 'INVALID_INPUT'; end if;
 if p_action not in ('receive','wait','resume','return') then raise exception 'INVALID_INPUT'; end if;
 for item in select value from jsonb_array_elements(p_items) order by value->>'id' loop
 select * into m from private.mail where id=(item->>'id')::uuid for update;
 if not found or not private.can_read(a,m.department) then raise exception 'ACCESS_DENIED'; end if;
 if m.version is distinct from (item->>'version')::integer then raise exception 'CONFLICT'; end if;
 if p_action='receive' and m.status='registered' then wanted:='processing';
 elsif p_action='wait' and m.status='processing' then wanted:='waiting';
 elsif p_action='resume' and m.status='waiting' then wanted:='processing';
 elsif p_action='return' and m.status='processing' then wanted:='returned';
 else raise exception 'INVALID_TRANSITION'; end if;
 update private.mail set status=wanted,received_at=case when p_action='receive' then now() else received_at end,
 returned_at=case when p_action='return' then now() else returned_at end,updated_at=now(),version=version+1 where id=m.id;
 n:=n+1;
 end loop;
 return n;
end $$;
create function public.update_notes(p_id uuid,p_version integer,p_ar text,p_de text,p_internal text,p_return_tracking text)
returns void language plpgsql security definer set search_path='' as $$
declare a private.staff; m private.mail;
begin
 a:=private.actor(); if a.role not in ('admin','officer') then raise exception 'ACCESS_DENIED'; end if;
 select * into m from private.mail where id=p_id for update;
 if not found or not private.can_read(a,m.department) then raise exception 'ACCESS_DENIED'; end if;
 if m.version is distinct from p_version then raise exception 'CONFLICT'; end if;
 update private.mail set public_note_ar=p_ar,public_note_de=p_de,internal_note=p_internal,return_tracking=upper(trim(p_return_tracking)),version=version+1,updated_at=now() where id=p_id;
end $$;
create function public.correct_mail(p_id uuid,p_version integer,p_tracking text,p_sender text,p_department text,p_amount integer)
returns void language plpgsql security definer set search_path='' as $$
declare a private.staff; m private.mail;
begin
 a:=private.actor(); if a.role<>'admin' then raise exception 'ACCESS_DENIED'; end if;
 select * into m from private.mail where id=p_id for update;
 if not found then raise exception 'ACCESS_DENIED'; end if;
 if m.version is distinct from p_version then raise exception 'CONFLICT'; end if;
 if m.status<>'registered' and m.department::text<>p_department then raise exception 'INVALID_TRANSITION'; end if;
 update private.mail set tracking=upper(regexp_replace(trim(p_tracking),'\s','','g')),sender_name=trim(p_sender),department=p_department::private.department,amount_cents=p_amount,updated_at=now(),version=version+1 where id=p_id;
end $$;
create function public.mail_history(p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare a private.staff; d private.department; result jsonb;
begin
 a:=private.actor(); select department into d from private.mail where id=p_id;
 if not found or not private.can_read(a,d) then raise exception 'ACCESS_DENIED'; end if;
 select coalesce(jsonb_agg(to_jsonb(e) order by e.at desc,e.id desc),'[]'::jsonb) into result from private.events e where mail_id=p_id;
 return result;
end $$;
-- Server-only RPC. Deliberately returns an explicit minimal projection.
create function public.lookup_public(p_tracking text) returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_object('tracking',tracking,'registered_date',(created_at at time zone 'Europe/Berlin')::date,'status',status,'note_ar',public_note_ar,'note_de',public_note_de)
 from private.mail where tracking=p_tracking
$$;
create function public.take_rate_limit(p_bucket text) returns boolean language plpgsql security definer set search_path='' as $$
declare n integer;
begin
 if length(p_bucket)<>64 then raise exception 'INVALID_INPUT'; end if;
 -- Retain only short-lived pseudonymous IP buckets.
 delete from private.rate_limits where window_start<now()-interval '1 day';
 insert into private.rate_limits(bucket,window_start,hits) values(p_bucket,now(),1)
 on conflict(bucket) do update set
 hits=case when private.rate_limits.window_start<now()-interval '10 minutes' then 1 else private.rate_limits.hits+1 end,
 window_start=case when private.rate_limits.window_start<now()-interval '10 minutes' then now() else private.rate_limits.window_start end
 returning hits into n;
 return n<=20;
end $$;
revoke all on all functions in schema private from public,anon,authenticated;
revoke all on function public.my_profile(),public.register_mail(text,text,text,integer),public.list_mail(text,text,text,integer,boolean),public.dashboard(),public.transition_mail(jsonb,text),public.update_notes(uuid,integer,text,text,text,text),public.correct_mail(uuid,integer,text,text,text,integer),public.mail_history(uuid),public.lookup_public(text),public.take_rate_limit(text) from public,anon,authenticated;
grant execute on function public.my_profile(),public.register_mail(text,text,text,integer),public.list_mail(text,text,text,integer,boolean),public.dashboard(),public.transition_mail(jsonb,text),public.update_notes(uuid,integer,text,text,text,text),public.correct_mail(uuid,integer,text,text,text,integer),public.mail_history(uuid) to authenticated;
grant execute on function public.lookup_public(text),public.take_rate_limit(text) to service_role;
commit;
