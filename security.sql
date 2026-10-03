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
--   • задачи (task:*): видят админ, исполнитель, автор и тимлид отдела исполнителя;
--     ставят — админ (кому угодно) и тимлид (себе и своему отделу); не-автор
--     может двигать статус, отмечать чек-лист и дописывать комментарии, но не
--     менять название, срок и исполнителя; удаляет только админ;
--   • подписи админов (app:admins — имя и должность): каждый админ меняет только
--     свою строку, чужие не трогает;
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

-- ── Задачи (ключи task:<id>) ─────────────────────────────────────────────
-- Значение — JSON-строка задачи: {id, title, desc, who, by, due, time, pri,
-- status, rep, cl, cm, hist, doneLog, createdAt}. who — id сотрудника,
-- by — id сотрудника-автора или '@почта' для админа.
create or replace function public.dramify_json(v text)
returns jsonb
language plpgsql
immutable
as $$
begin
  if v is null then return null; end if;
  if left(v, 1) = '"' then v := v::jsonb #>> '{}'; end if;
  return v::jsonb;
exception when others then
  return null;
end;
$$;

create or replace function public.dramify_emp_dept(emp text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select lower(trim(e ->> 'department')) from jsonb_array_elements(public.dramify_employees()) e
  where e ->> 'id' = emp limit 1;
$$;

-- Есть ли у текущего пользователя доступ к задаче (видеть и двигать)
create or replace function public.dramify_task_access(j jsonb)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select j is not null and (
    public.dramify_is_admin()
    or j ->> 'who' = public.dramify_my_emp_id()
    or j ->> 'by'  = public.dramify_my_emp_id()
    or (public.dramify_is_teamlead()
        and public.dramify_emp_dept(j ->> 'who') = public.dramify_emp_dept(public.dramify_my_emp_id()))
  );
$$;

-- Может ли текущий пользователь поставить такую задачу (как автор)
create or replace function public.dramify_task_assign_ok(j jsonb)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select j is not null and (
    public.dramify_is_admin()
    or (public.dramify_is_teamlead()
        and j ->> 'by' = public.dramify_my_emp_id()
        and (j ->> 'who' = public.dramify_my_emp_id()
             or public.dramify_emp_dept(j ->> 'who') = public.dramify_emp_dept(public.dramify_my_emp_id())))
  );
$$;

-- Проверка изменения задачи: что именно поменяли и кто
create or replace function public.dramify_task_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  o jsonb := public.dramify_json(old.value::text);
  n jsonb := public.dramify_json(new.value::text);
  me text := public.dramify_my_emp_id();
  f text;
  i int;
begin
  if public.dramify_is_admin() then return new; end if;
  if n is null or o is null then raise exception 'задача: неверные данные'; end if;
  if (n ->> 'id') is distinct from (o ->> 'id') or (n ->> 'by') is distinct from (o ->> 'by') then
    raise exception 'задача: нельзя менять автора и номер';
  end if;
  if o ->> 'by' = me then
    -- автор-тимлид меняет что угодно, но исполнитель — только он сам или его отдел
    if not public.dramify_task_assign_ok(n) then raise exception 'задача: этого исполнителя ставить нельзя'; end if;
    return new;
  end if;
  -- не автор: только статус, галочки чек-листа, новые комментарии и записи истории
  foreach f in array array['title','desc','who','time','pri','rep','createdAt'] loop
    if (n -> f) is distinct from (o -> f) then raise exception 'задача: поле % меняет только автор', f; end if;
  end loop;
  if (n -> 'due') is distinct from (o -> 'due') then
    -- срок сдвигается сам только при закрытии повторяющейся задачи
    if coalesce(o ->> 'rep', 'none') = 'none'
       or coalesce(jsonb_array_length(n -> 'doneLog'), 0) <> coalesce(jsonb_array_length(o -> 'doneLog'), 0) + 1
       or coalesce(n ->> 'due', '') <= coalesce(o ->> 'due', '') then
      raise exception 'задача: срок меняет только автор';
    end if;
  end if;
  if coalesce(jsonb_array_length(n -> 'cl'), 0) <> coalesce(jsonb_array_length(o -> 'cl'), 0) then
    raise exception 'задача: пункты чек-листа меняет только автор';
  end if;
  for i in 0 .. coalesce(jsonb_array_length(o -> 'cl'), 0) - 1 loop
    if (n -> 'cl' -> i ->> 't') is distinct from (o -> 'cl' -> i ->> 't') then
      raise exception 'задача: пункты чек-листа меняет только автор';
    end if;
  end loop;
  foreach f in array array['cm','hist','doneLog'] loop
    if coalesce(jsonb_array_length(n -> f), 0) < coalesce(jsonb_array_length(o -> f), 0) then
      raise exception 'задача: % можно только дополнять', f;
    end if;
    for i in 0 .. coalesce(jsonb_array_length(o -> f), 0) - 1 loop
      if (n -> f -> i) is distinct from (o -> f -> i) then
        raise exception 'задача: % можно только дополнять', f;
      end if;
    end loop;
  end loop;
  return new;
end;
$$;

drop trigger if exists dramify_task_guard on public.kv_store;
create trigger dramify_task_guard
  before update on public.kv_store
  for each row
  when (new.key like 'task:%')
  execute function public.dramify_task_guard();

-- Добавление ключа с учётом задач (поверх общего правила)
create or replace function public.dramify_can_insert_any(k text, v text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when k like 'task:%' then
      public.dramify_task_assign_ok(public.dramify_json(v))
      and k = 'task:' || (public.dramify_json(v) ->> 'id')
    else public.dramify_can_insert(k, v)
  end;
$$;

-- ── Подписи админов (ключ app:admins = { почта: {name, title, at} }) ─────────
-- Каждый админ меняет только свою подпись. Из SQL Editor (без входа) — можно всё.
create or replace function public.dramify_admins_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  me text := lower(coalesce(auth.jwt() ->> 'email', ''));
  o jsonb;
  n jsonb := coalesce(public.dramify_json(new.value::text), '{}'::jsonb);
begin
  if auth.jwt() is null then return new; end if;
  -- «вставить или заменить» сначала проверяется как вставка: сравниваем с тем, что уже лежит в базе
  if tg_op = 'UPDATE' then o := public.dramify_json(old.value::text);
  else select public.dramify_json(value::text) into o from public.kv_store where key = new.key; end if;
  o := coalesce(o, '{}'::jsonb);
  if (o - me) is distinct from (n - me) then
    raise exception 'подпись админа меняет только он сам';
  end if;
  return new;
end;
$$;

drop trigger if exists dramify_admins_guard on public.kv_store;
create trigger dramify_admins_guard
  before insert or update on public.kv_store
  for each row
  when (new.key = 'app:admins')
  execute function public.dramify_admins_guard();

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
  using (public.dramify_is_staff()
         and (key not like 'task:%' or public.dramify_task_access(public.dramify_json(value::text))));

create policy dramify_insert on public.kv_store
  for insert to authenticated
  with check (public.dramify_can_insert_any(key, value::text));

create policy dramify_update on public.kv_store
  for update to authenticated
  using (case when key like 'task:%' then public.dramify_task_access(public.dramify_json(value::text))
              else public.dramify_can_update(key) end)
  with check (case when key like 'task:%' then public.dramify_task_access(public.dramify_json(value::text))
                   else public.dramify_can_update(key) end);

create policy dramify_delete on public.kv_store
  for delete to authenticated
  using (public.dramify_is_admin());

-- Не вошедшим (роль anon) — никакого доступа к таблице вообще
revoke all on public.kv_store from anon;

-- Проверка: должно показать 4 правила dramify_*
select policyname, cmd from pg_policies
where schemaname = 'public' and tablename = 'kv_store'
order by policyname;
