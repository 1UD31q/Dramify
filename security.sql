-- =====================================================================
-- Dramify · защита базы (Row Level Security для таблицы kv_store)
-- Запускать в Supabase → SQL Editor целиком, один раз. Повторный запуск безопасен.
--
-- Что получится:
--   • не вошедшие — ничего не видят и не пишут;
--   • вошедшие через Google, но которых нет в списке сотрудников, — ничего не видят;
--   • сотрудники — читают данные, пишут статусы заказов и время продаж
--     (app:ordersOverlay, saletime:*) и добавляют СВОИ отметки прихода/ухода
--     (att:*) — только с текущим временем (±10 минут), без права править и удалять;
--   • автозакрытие забытой смены (уход ровно в целый час, в прошлом) может
--     записать любой сотрудник — так работает закрытие в 23:00;
--   • тимлиды — плюс график выходных и список сотрудников;
--   • админы (app_metadata.role = 'admin') — всё.
-- =====================================================================

-- Список сотрудников из ключа app:employees (значение — JSON-строка).
-- security definer: функция читает таблицу в обход RLS, иначе правило
-- «сотрудник ли ты» не смогло бы само себя проверить.
create or replace function public.dramify_employees()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  raw text;
begin
  select value::text into raw from public.kv_store where key = 'app:employees';
  if raw is null then return '[]'::jsonb; end if;
  -- если колонка jsonb и в ней лежит строка — разворачиваем её
  if left(raw, 1) = '"' then raw := raw::jsonb #>> '{}'; end if;
  return coalesce(raw::jsonb, '[]'::jsonb);
exception when others then
  return '[]'::jsonb;
end;
$$;

create or replace function public.dramify_is_admin()
returns boolean
language sql
stable
as $$
  select coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'admin';
$$;

-- Сотрудник = его почта есть в списке сотрудников
create or replace function public.dramify_is_staff()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.dramify_is_admin() or exists (
    select 1 from jsonb_array_elements(public.dramify_employees()) e
    where lower(coalesce(e ->> 'email', '')) <> ''
      and lower(e ->> 'email') = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

create or replace function public.dramify_is_teamlead()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from jsonb_array_elements(public.dramify_employees()) e
    where lower(coalesce(e ->> 'email', '')) <> ''
      and lower(e ->> 'email') = lower(coalesce(auth.jwt() ->> 'email', ''))
      and e ->> 'role' = 'teamlead'
  );
$$;

-- id сотрудника, под чьей почтой вошли (или null)
create or replace function public.dramify_my_emp_id()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select e ->> 'id' from jsonb_array_elements(public.dramify_employees()) e
  where lower(coalesce(e ->> 'email', '')) <> ''
    and lower(e ->> 'email') = lower(coalesce(auth.jwt() ->> 'email', ''))
  limit 1;
$$;

-- Можно ли ИЗМЕНЯТЬ уже существующий ключ (отметки att:* сюда не входят — их не правят)
create or replace function public.dramify_can_update(k text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.dramify_is_admin()
    or (public.dramify_is_staff() and (k = 'app:ordersOverlay' or k like 'saletime:%'))
    or (public.dramify_is_teamlead() and k in ('app:schedules', 'app:employees'));
$$;

-- Отметка прихода/ухода: ключ att:ГГГГ-ММ:<empId>:<ts>, значение {empId, type, ts, auto?}
create or replace function public.dramify_att_ok(k text, v text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  j jsonb;
  emp text := split_part(k, ':', 3);
  ts_txt text := split_part(k, ':', 4);
  ts bigint;
  now_ms bigint := (extract(epoch from now()) * 1000)::bigint;
begin
  if k not like 'att:%' or emp = '' or ts_txt !~ '^[0-9]{10,15}$' then return false; end if;
  if left(v, 1) = '"' then v := v::jsonb #>> '{}'; end if;
  j := v::jsonb;
  ts := ts_txt::bigint;
  if j ->> 'empId' is distinct from emp or (j ->> 'ts') is distinct from ts_txt then return false; end if;
  if j ->> 'type' not in ('in', 'out') then return false; end if;
  -- автозакрытие: уход ровно в целый час (23:00), уже наступивший
  if coalesce((j ->> 'auto')::boolean, false) then
    return j ->> 'type' = 'out' and ts <= now_ms and ts % 3600000 = 0
       and ts > now_ms - 40::bigint * 86400000;
  end if;
  -- обычная отметка: только своя и только «сейчас»
  return emp = public.dramify_my_emp_id() and abs(ts - now_ms) <= 600000;
exception when others then
  return false;
end;
$$;

-- Можно ли ДОБАВИТЬ ключ
create or replace function public.dramify_can_insert(k text, v text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.dramify_is_admin()
    or (k not like 'att:%' and public.dramify_can_update(k))
    or (k like 'att:%' and public.dramify_is_staff() and public.dramify_att_ok(k, v));
$$;

-- старое общее правило больше не используется
drop function if exists public.dramify_can_write(text) cascade;

-- Включаем RLS и убираем все старые правила (часто там «разрешено всем»)
alter table public.kv_store enable row level security;

do $$
declare p record;
begin
  for p in select policyname from pg_policies
           where schemaname = 'public' and tablename = 'kv_store'
  loop
    execute format('drop policy %I on public.kv_store', p.policyname);
  end loop;
end $$;

create policy dramify_read on public.kv_store
  for select to authenticated
  using (public.dramify_is_staff());

create policy dramify_insert on public.kv_store
  for insert to authenticated
  with check (public.dramify_can_insert(key, value::text));

create policy dramify_update on public.kv_store
  for update to authenticated
  using (public.dramify_can_update(key))
  with check (public.dramify_can_update(key));

create policy dramify_delete on public.kv_store
  for delete to authenticated
  using (public.dramify_is_admin());

-- Не вошедшим (роль anon) — никакого доступа к таблице вообще
revoke all on public.kv_store from anon;

-- Проверка: должно показать 4 правила dramify_*
select policyname, cmd from pg_policies
where schemaname = 'public' and tablename = 'kv_store'
order by policyname;
