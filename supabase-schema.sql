-- Tanulás app: Supabase séma (táblák, jogosultságok, függvények)
-- Futtatás: Supabase Dashboard -> SQL Editor -> New query -> beillesztés -> Run
-- Biztonságosan újrafuttatható (create if not exists / or replace / drop policy if exists).

-- ============ TÁBLÁK ============

create table if not exists public.families (
  id uuid primary key default gen_random_uuid(),
  name text not null default 'Család',
  created_at timestamptz not null default now()
);

create table if not exists public.members (
  user_id uuid primary key references auth.users(id) on delete cascade,
  family_id uuid not null references public.families(id) on delete cascade,
  role text not null check (role in ('parent','child')),
  profile_id uuid,
  created_at timestamptz not null default now()
);

create table if not exists public.profiles (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  name text not null,
  grade int,
  created_at timestamptz not null default now()
);

alter table public.members
  drop constraint if exists members_profile_fk;
alter table public.members
  add constraint members_profile_fk foreign key (profile_id)
  references public.profiles(id) on delete cascade;

create table if not exists public.pairings (
  code text primary key,
  family_id uuid not null references public.families(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  expires_at timestamptz not null,
  used boolean not null default false
);

-- Válaszesemények (csak hozzáfűzünk). Az id-t az app generálja, így az újraküldés nem duplázza.
create table if not exists public.events (
  id uuid primary key,
  family_id uuid not null references public.families(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  device_id text,
  ts timestamptz not null,
  subject text not null,
  skill text not null,
  item text,
  ok boolean not null,
  tries int not null default 1,
  ms int,
  round_id uuid,
  created_at timestamptz not null default now()
);
create index if not exists events_profile_ts on public.events (profile_id, ts desc);

-- Körök összegzése
create table if not exists public.rounds (
  id uuid primary key,
  family_id uuid not null references public.families(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  ts timestamptz not null,
  subject text not null,
  n int not null,
  correct int not null,
  stars int not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists rounds_profile_ts on public.rounds (profile_id, ts desc);

-- Angol szavak (a szülő adja hozzá, a gyerek eszköze letölti)
create table if not exists public.words (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  profile_id uuid references public.profiles(id) on delete cascade,
  en text not null,
  hu text not null,
  created_at timestamptz not null default now()
);

-- Felhős mentés a gyerek eszközének állapotáról (jutalmak, haladás)
create table if not exists public.profile_state (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  family_id uuid not null references public.families(id) on delete cascade,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

-- ============ SEGÉDFÜGGVÉNYEK (security definer, hogy ne legyen RLS-rekurzió) ============

create or replace function public.my_family() returns uuid
language sql stable security definer set search_path = public as
$$ select family_id from public.members where user_id = auth.uid() $$;

create or replace function public.my_role() returns text
language sql stable security definer set search_path = public as
$$ select role from public.members where user_id = auth.uid() $$;

create or replace function public.my_profile() returns uuid
language sql stable security definer set search_path = public as
$$ select profile_id from public.members where user_id = auth.uid() $$;

-- ============ SZÜLŐI ÉS PÁROSÍTÓ FÜGGVÉNYEK ============

-- A szülő első belépés után létrehozza a családot és az első gyerekprofilt.
create or replace function public.create_family(fam_name text, child_name text, child_grade int)
returns json language plpgsql security definer set search_path = public as $$
declare fid uuid; pid uuid;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if exists (select 1 from public.members where user_id = auth.uid()) then
    raise exception 'already a member of a family';
  end if;
  insert into public.families(name) values (coalesce(nullif(fam_name,''),'Család')) returning id into fid;
  insert into public.members(user_id, family_id, role) values (auth.uid(), fid, 'parent');
  insert into public.profiles(family_id, name, grade) values (fid, child_name, child_grade) returning id into pid;
  return json_build_object('family_id', fid, 'profile_id', pid);
end $$;

-- A szülő 15 percig érvényes, 8 jegyű párosító kódot kér egy gyerekprofilhoz.
create or replace function public.create_pairing(p_profile uuid)
returns text language plpgsql security definer set search_path = public as $$
declare c text; tries int := 0;
begin
  if public.my_role() is distinct from 'parent' then raise exception 'only parent'; end if;
  if not exists (select 1 from public.profiles where id = p_profile and family_id = public.my_family()) then
    raise exception 'bad profile';
  end if;
  loop
    c := lpad((floor(random() * 100000000))::bigint::text, 8, '0');
    begin
      insert into public.pairings(code, family_id, profile_id, expires_at)
      values (c, public.my_family(), p_profile, now() + interval '15 minutes');
      return c;
    exception when unique_violation then
      tries := tries + 1;
      if tries > 5 then raise exception 'could not create code'; end if;
    end;
  end loop;
end $$;

-- A gyerek eszköze (névtelen belépéssel) beváltja a kódot, és a profilhoz kapcsolódik.
create or replace function public.claim_pairing(p_code text)
returns json language plpgsql security definer set search_path = public as $$
declare r public.pairings%rowtype;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if exists (select 1 from public.members where user_id = auth.uid()) then
    raise exception 'already a member';
  end if;
  select * into r from public.pairings
   where code = p_code and not used and expires_at > now() for update;
  if not found then raise exception 'invalid or expired code'; end if;
  insert into public.members(user_id, family_id, role, profile_id)
  values (auth.uid(), r.family_id, 'child', r.profile_id);
  update public.pairings set used = true where code = p_code;
  return json_build_object('family_id', r.family_id, 'profile_id', r.profile_id);
end $$;

revoke all on function public.create_family(text, text, int) from public, anon;
revoke all on function public.create_pairing(uuid) from public, anon;
revoke all on function public.claim_pairing(text) from public, anon;
grant execute on function public.create_family(text, text, int) to authenticated;
grant execute on function public.create_pairing(uuid) to authenticated;
grant execute on function public.claim_pairing(text) to authenticated;
grant execute on function public.my_family(), public.my_role(), public.my_profile() to authenticated;

-- ============ JOGOSULTSÁGOK (RLS) ============

alter table public.families      enable row level security;
alter table public.members       enable row level security;
alter table public.profiles      enable row level security;
alter table public.pairings      enable row level security;
alter table public.events        enable row level security;
alter table public.rounds        enable row level security;
alter table public.words         enable row level security;
alter table public.profile_state enable row level security;

grant select, insert, update, delete on all tables in schema public to authenticated;
revoke all on all tables in schema public from anon;

-- families
drop policy if exists families_select on public.families;
create policy families_select on public.families for select to authenticated
  using (id = public.my_family());
drop policy if exists families_update on public.families;
create policy families_update on public.families for update to authenticated
  using (id = public.my_family() and public.my_role() = 'parent')
  with check (id = public.my_family());

-- members: a család tagjait látják; csak a szülő törölhet (eszköz eltávolítása)
drop policy if exists members_select on public.members;
create policy members_select on public.members for select to authenticated
  using (family_id = public.my_family() and (public.my_role() = 'parent' or user_id = auth.uid()));
drop policy if exists members_delete on public.members;
create policy members_delete on public.members for delete to authenticated
  using (family_id = public.my_family() and public.my_role() = 'parent' and user_id <> auth.uid());

-- profiles
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
  using (family_id = public.my_family() and (public.my_role() = 'parent' or id = public.my_profile()));
drop policy if exists profiles_write on public.profiles;
create policy profiles_write on public.profiles for all to authenticated
  using (family_id = public.my_family() and public.my_role() = 'parent')
  with check (family_id = public.my_family() and public.my_role() = 'parent');

-- pairings: közvetlenül csak a szülő látja (a beváltás a függvényen át megy)
drop policy if exists pairings_parent on public.pairings;
create policy pairings_parent on public.pairings for all to authenticated
  using (family_id = public.my_family() and public.my_role() = 'parent')
  with check (family_id = public.my_family() and public.my_role() = 'parent');

-- events és rounds: a gyerek csak a saját profiljára írhat és olvashat; a szülő a család mindenét látja
drop policy if exists events_insert on public.events;
create policy events_insert on public.events for insert to authenticated
  with check (family_id = public.my_family() and (public.my_role() = 'parent' or profile_id = public.my_profile()));
drop policy if exists events_select on public.events;
create policy events_select on public.events for select to authenticated
  using (family_id = public.my_family() and (public.my_role() = 'parent' or profile_id = public.my_profile()));

drop policy if exists rounds_insert on public.rounds;
create policy rounds_insert on public.rounds for insert to authenticated
  with check (family_id = public.my_family() and (public.my_role() = 'parent' or profile_id = public.my_profile()));
drop policy if exists rounds_select on public.rounds;
create policy rounds_select on public.rounds for select to authenticated
  using (family_id = public.my_family() and (public.my_role() = 'parent' or profile_id = public.my_profile()));

-- words: a szülő kezeli, a gyerek a sajátját és a közös szavakat olvassa
drop policy if exists words_select on public.words;
create policy words_select on public.words for select to authenticated
  using (family_id = public.my_family()
         and (public.my_role() = 'parent' or profile_id is null or profile_id = public.my_profile()));
drop policy if exists words_write on public.words;
create policy words_write on public.words for all to authenticated
  using (family_id = public.my_family() and public.my_role() = 'parent')
  with check (family_id = public.my_family() and public.my_role() = 'parent');

-- profile_state: a gyerek a sajátját menti/olvassa, a szülő olvassa
drop policy if exists state_select on public.profile_state;
create policy state_select on public.profile_state for select to authenticated
  using (family_id = public.my_family() and (public.my_role() = 'parent' or profile_id = public.my_profile()));
drop policy if exists state_insert on public.profile_state;
create policy state_insert on public.profile_state for insert to authenticated
  with check (family_id = public.my_family() and (public.my_role() = 'parent' or profile_id = public.my_profile()));
drop policy if exists state_update on public.profile_state;
create policy state_update on public.profile_state for update to authenticated
  using (family_id = public.my_family() and (public.my_role() = 'parent' or profile_id = public.my_profile()))
  with check (family_id = public.my_family() and (public.my_role() = 'parent' or profile_id = public.my_profile()));
