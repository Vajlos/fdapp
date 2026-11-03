-- Denník jedál: profily, jedlá, štatistiky, priatelia a fotky.
--
-- Čo používateľ vidí (bezplatná verzia):
--   * aktuálny týždeň             – konkrétne jedlá a fotky
--   * ostatné týždne mesiaca      – priemer za deň v týždni (týždne delené hranicou mesiaca)
--   * mesiace tohto a minulého roka – priemer za deň v mesiaci
--   * staršie roky                – priemer za deň v roku
--
-- Detail sa naozaj maže, ostávajú len súčty. Ukladá sa súčet a počet zapísaných
-- dní (logged_days), priemer = súčet / logged_days – dni bez zápisu priemer
-- nesťahujú. Premium má podľa plans.detail_weeks dlhšie uložené jedlá a fotky.

create extension if not exists pg_cron with schema pg_catalog;

-- ---------------------------------------------------------------------------
-- Pomocné funkcie na dátumy
-- ---------------------------------------------------------------------------

create function public.is_valid_timezone(tz text) returns boolean
language plpgsql immutable as $$
begin
  perform now() at time zone tz;
  return true;
exception when invalid_parameter_value then
  return false;
end $$;

-- pondelok týždňa, do ktorého patrí deň d
create function public.week_start(d date) returns date
language sql immutable as $$
  select d - (extract(isodow from d)::int - 1)
$$;

create function public.month_start(d date) returns date
language sql immutable as $$
  select date_trunc('month', d::timestamp)::date
$$;

create function public.year_start(d date) returns date
language sql immutable as $$
  select date_trunc('year', d::timestamp)::date
$$;

-- Kam patrí súčet dňa d, keď je dnes today: deň v tomto mesiaci ostáva dňom,
-- deň z tohto alebo minulého roka ide do mesiaca, starší do roka.
create function public.stat_bucket(
  d date, today date, out period text, out start_date date
) language plpgsql immutable as $$
begin
  if d >= public.month_start(today) then
    period := 'day';
    start_date := d;
  elsif d >= public.year_start(today) - interval '1 year' then
    period := 'month';
    start_date := public.month_start(d);
  else
    period := 'year';
    start_date := public.year_start(d);
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Plány
-- ---------------------------------------------------------------------------

create table public.plans (
  id text primary key,
  -- koľko celých týždňov pred aktuálnym ostanú jedlá a fotky v detaile
  detail_weeks int not null check (detail_weeks >= 0)
);

-- premium = dlhšie fotky; 4 týždne sú zatiaľ len odhad, mení sa jedným UPDATE
insert into public.plans (id, detail_weeks) values ('free', 0), ('premium', 4);

-- ---------------------------------------------------------------------------
-- Používateľ: verejný profil a súkromné nastavenia
-- ---------------------------------------------------------------------------

-- čo vidia ostatní (hľadanie priateľov, feed)
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username text unique check (username ~ '^[a-z0-9_.]{3,30}$'),
  display_name text check (char_length(display_name) <= 60),
  avatar_path text,
  created_at timestamptz not null default now()
);

-- čo vidí len používateľ sám
create table public.user_settings (
  user_id uuid primary key references auth.users (id) on delete cascade,
  timezone text not null default 'Europe/Bratislava'
    check (public.is_valid_timezone(timezone)),
  plan text not null default 'free' references public.plans (id),
  -- null = bez obmedzenia; po vypršaní sa správa ako free
  plan_expires_at timestamptz
);

create function public.user_today(uid uuid) returns date
language sql stable set search_path = '' as $$
  select (now() at time zone s.timezone)::date
  from public.user_settings s
  where s.user_id = uid
$$;

-- prvý deň, ktorého jedlá ešte existujú v detaile
create function public.detail_start(uid uuid) returns date
language sql stable set search_path = '' as $$
  select public.week_start((now() at time zone s.timezone)::date)
         - 7 * p.detail_weeks
  from public.user_settings s
  join public.plans p on p.id = case
    when s.plan_expires_at is null or s.plan_expires_at > now() then s.plan
    else 'free'
  end
  where s.user_id = uid
$$;

-- profil a nastavenia sa vytvoria pri registrácii
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    left(coalesce(
      new.raw_user_meta_data ->> 'full_name',
      new.raw_user_meta_data ->> 'name'
    ), 60)
  );
  insert into public.user_settings (user_id) values (new.id);
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Jedlá (detail)
-- ---------------------------------------------------------------------------

create table public.meals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  eaten_at timestamptz not null default now(),
  -- deň podľa časového pásma používateľa, dopĺňa trigger
  local_date date not null,
  meal_type text
    check (meal_type in ('breakfast', 'snack', 'lunch', 'dinner', 'other')),
  note text check (char_length(note) <= 500),
  -- cesta v buckete meal-photos: <user_id>/<meal_id>.jpg
  photo_path text,
  visibility text not null default 'private'
    check (visibility in ('private', 'friends')),
  created_at timestamptz not null default now()
);

create index meals_user_date on public.meals (user_id, local_date);
create index meals_photo_path on public.meals (photo_path)
  where photo_path is not null;

create function public.meals_before_write() returns trigger
language plpgsql set search_path = '' as $$
begin
  select (new.eaten_at at time zone s.timezone)::date
  into new.local_date
  from public.user_settings s
  where s.user_id = new.user_id;
  -- staršie dni sú už zhrnuté v stat_periods, zápis by ich zdvojil
  if new.local_date < public.detail_start(new.user_id) then
    raise exception 'Jedlo je staršie ako obdobie, ktoré sa dá upravovať';
  end if;
  return new;
end $$;

create trigger meals_before_write
  before insert or update on public.meals
  for each row execute function public.meals_before_write();

create table public.meal_items (
  id uuid primary key default gen_random_uuid(),
  meal_id uuid not null references public.meals (id) on delete cascade,
  -- id z tabuľky foods; bez cudzieho kľúča, aby sa foods dala znova naimportovať
  food_id bigint,
  name text not null check (char_length(name) <= 120),
  grams numeric(7, 1) not null check (grams > 0 and grams <= 10000),
  kcal numeric(7, 1) not null check (kcal >= 0 and kcal <= 20000),
  position smallint not null default 0
);

create index meal_items_meal on public.meal_items (meal_id);

-- ---------------------------------------------------------------------------
-- Súhrny (ostávajú po zmazaní detailu)
-- ---------------------------------------------------------------------------

create table public.stat_periods (
  user_id uuid not null references auth.users (id) on delete cascade,
  period text not null check (period in ('day', 'month', 'year')),
  start_date date not null,
  kcal_sum numeric(12, 1) not null default 0,
  grams_sum numeric(12, 1) not null default 0,
  logged_days int not null default 0,
  entries int not null default 0,
  primary key (user_id, period, start_date)
);

-- Presunie jedlá mimo detailného obdobia do súhrnov a zhrnie staré súhrny
-- do hrubších (dni → mesiace → roky).
create function public.rollup_user(uid uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  today date := public.user_today(uid);
  keep_from date := public.detail_start(uid);
begin
  -- 1. staré jedlá → súčet za deň (alebo rovno mesiac/rok, ak sú ešte staršie)
  with gone as (
    delete from public.meals m
    where m.user_id = uid and m.local_date < keep_from
    returning m.id, m.local_date
  ), days as (
    select g.local_date as d, sum(i.kcal) as kcal, sum(i.grams) as grams,
           count(*) as n
    from gone g
    join public.meal_items i on i.meal_id = g.id
    group by g.local_date
  )
  insert into public.stat_periods as s
    (user_id, period, start_date, kcal_sum, grams_sum, logged_days, entries)
  select uid, b.period, b.start_date, sum(days.kcal), sum(days.grams),
         count(*), sum(days.n)
  from days, lateral public.stat_bucket(days.d, today) b
  group by b.period, b.start_date
  on conflict (user_id, period, start_date) do update set
    kcal_sum = s.kcal_sum + excluded.kcal_sum,
    grams_sum = s.grams_sum + excluded.grams_sum,
    logged_days = s.logged_days + excluded.logged_days,
    entries = s.entries + excluded.entries;

  -- 2. dni minulých mesiacov → mesiac, mesiace predminulého roka → rok
  with gone as (
    delete from public.stat_periods sp
    where sp.user_id = uid
      and (
        sp.period = 'day' and sp.start_date < public.month_start(today)
        or sp.period = 'month'
          and sp.start_date < public.year_start(today) - interval '1 year'
      )
    returning sp.*
  )
  insert into public.stat_periods as s
    (user_id, period, start_date, kcal_sum, grams_sum, logged_days, entries)
  select uid, b.period, b.start_date, sum(gone.kcal_sum), sum(gone.grams_sum),
         sum(gone.logged_days), sum(gone.entries)
  from gone, lateral public.stat_bucket(gone.start_date, today) b
  group by b.period, b.start_date
  on conflict (user_id, period, start_date) do update set
    kcal_sum = s.kcal_sum + excluded.kcal_sum,
    grams_sum = s.grams_sum + excluded.grams_sum,
    logged_days = s.logged_days + excluded.logged_days,
    entries = s.entries + excluded.entries;
end $$;

create function public.rollup_all() returns void
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid;
begin
  for uid in select user_id from public.user_settings loop
    perform public.rollup_user(uid);
  end loop;
end $$;

-- každú hodinu, lebo používatelia majú rôzne časové pásma (pre nikoho
-- nespraví nič, kým sa mu neskončí týždeň/mesiac/rok)
select cron.schedule('rollup-stats', '7 * * * *', 'select public.rollup_all()');

-- Štatistiky prihláseného používateľa pre obrazovku s grafmi:
--   week  – týždne aktuálneho mesiaca
--   month – mesiace tohto a minulého roka
--   year  – všetky roky (minulý sa počíta z mesiacov)
-- Zahŕňa aj dni, ktoré sú ešte v detaile.
create function public.get_stats()
returns table (
  period text,
  start_date date,
  end_date date,
  kcal_sum numeric,
  grams_sum numeric,
  logged_days int,
  avg_kcal numeric,
  avg_grams numeric
)
language sql stable set search_path = '' as $$
  with me as (
    select s.user_id, (now() at time zone s.timezone)::date as today
    from public.user_settings s
    where s.user_id = auth.uid()
  ),
  stored as (
    select sp.* from public.stat_periods sp join me using (user_id)
  ),
  -- jeden riadok za každý zapísaný deň
  days as (
    select x.d, sum(x.kcal) as kcal, sum(x.grams) as grams
    from (
      select m.local_date as d, i.kcal, i.grams
      from public.meals m
      join me using (user_id)
      join public.meal_items i on i.meal_id = m.id
      union all
      select st.start_date, st.kcal_sum, st.grams_sum
      from stored st where st.period = 'day'
    ) x
    group by x.d
  ),
  months as (
    select x.m, sum(x.kcal) as kcal, sum(x.grams) as grams,
           sum(x.days)::int as days
    from (
      select public.month_start(d) as m, kcal, grams, 1 as days from days
      union all
      select st.start_date, st.kcal_sum, st.grams_sum, st.logged_days
      from stored st where st.period = 'month'
    ) x
    group by x.m
  ),
  years as (
    select x.y, sum(x.kcal) as kcal, sum(x.grams) as grams,
           sum(x.days)::int as days
    from (
      select public.year_start(m) as y, kcal, grams, days from months
      union all
      select st.start_date, st.kcal_sum, st.grams_sum, st.logged_days
      from stored st where st.period = 'year'
    ) x
    group by x.y
  ),
  -- týždne aktuálneho mesiaca, týždeň na prelome začína prvým dňom mesiaca
  weeks as (
    select greatest(public.week_start(days.d), public.month_start(me.today)) as w,
           sum(days.kcal) as kcal, sum(days.grams) as grams,
           count(*)::int as days
    from days, me
    where days.d >= public.month_start(me.today)
    group by 1
  ),
  result as (
    select 'week' as period, w as start_date,
           least(public.week_start(w) + 6,
                 (public.month_start(w) + interval '1 month - 1 day')::date)
             as end_date,
           kcal, grams, days
    from weeks
    union all
    select 'month', m, (m + interval '1 month - 1 day')::date, kcal, grams, days
    from months, me
    where m >= public.year_start(me.today) - interval '1 year'
    union all
    select 'year', y, (y + interval '1 year - 1 day')::date, kcal, grams, days
    from years
  )
  select r.period, r.start_date, r.end_date, r.kcal, r.grams, r.days,
         round(r.kcal / nullif(r.days, 0), 1),
         round(r.grams / nullif(r.days, 0), 1)
  from result r
  order by r.period, r.start_date
$$;

-- ---------------------------------------------------------------------------
-- Priatelia a reakcie
-- ---------------------------------------------------------------------------

create table public.friendships (
  requester_id uuid not null references auth.users (id) on delete cascade,
  addressee_id uuid not null references auth.users (id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  primary key (requester_id, addressee_id),
  check (requester_id <> addressee_id)
);

-- A→B a B→A je tá istá dvojica
create unique index friendships_pair on public.friendships (
  least(requester_id, addressee_id), greatest(requester_id, addressee_id)
);
create index friendships_addressee on public.friendships (addressee_id);

create function public.is_friend(other uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.friendships f
    where f.status = 'accepted'
      and (
        f.requester_id = auth.uid() and f.addressee_id = other
        or f.addressee_id = auth.uid() and f.requester_id = other
      )
  )
$$;

create table public.meal_reactions (
  meal_id uuid not null references public.meals (id) on delete cascade,
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  emoji text not null check (char_length(emoji) <= 16),
  created_at timestamptz not null default now(),
  primary key (meal_id, user_id)
);

-- ---------------------------------------------------------------------------
-- Fotky
-- ---------------------------------------------------------------------------

-- Súbory v Storage sa nedajú zmazať z SQL, preto sa cesty zapíšu sem
-- a zmaže ich Edge Function (pribudne spolu s nahrávaním fotiek).
create table public.storage_deletions (
  path text primary key,
  queued_at timestamptz not null default now()
);

create function public.queue_photo_deletion() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if old.photo_path is not null
     and (tg_op = 'DELETE' or new.photo_path is distinct from old.photo_path) then
    insert into public.storage_deletions (path) values (old.photo_path)
    on conflict do nothing;
  end if;
  return null;
end $$;

create trigger meals_queue_photo_deletion
  after delete or update of photo_path on public.meals
  for each row execute function public.queue_photo_deletion();

insert into storage.buckets (id, name, public)
values ('meal-photos', 'meal-photos', false)
on conflict (id) do nothing;

create policy "meal photos: owner uploads" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'meal-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- vidí ju ten, kto vidí jedlo (RLS na meals platí aj tu)
create policy "meal photos: visible with meal" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'meal-photos'
    and (
      (storage.foldername(name))[1] = (select auth.uid())::text
      or exists (select 1 from public.meals m where m.photo_path = objects.name)
    )
  );

create policy "meal photos: owner deletes" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'meal-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- ---------------------------------------------------------------------------
-- Prístup (Row Level Security)
-- ---------------------------------------------------------------------------

alter table public.plans enable row level security;
alter table public.profiles enable row level security;
alter table public.user_settings enable row level security;
alter table public.meals enable row level security;
alter table public.meal_items enable row level security;
alter table public.stat_periods enable row level security;
alter table public.friendships enable row level security;
alter table public.meal_reactions enable row level security;
alter table public.storage_deletions enable row level security;

revoke all on
  public.plans, public.profiles, public.user_settings, public.meals,
  public.meal_items, public.stat_periods, public.friendships,
  public.meal_reactions, public.storage_deletions
from anon;

-- len čítanie: plány, súhrny (zapisuje ich iba rollup), front mazania
revoke insert, update, delete on public.plans, public.stat_periods
  from authenticated;
revoke all on public.storage_deletions from authenticated;

-- plán a dátum vypršania nesmie meniť používateľ, len platby
revoke insert, update, delete on public.profiles, public.user_settings
  from authenticated;
grant update (username, display_name, avatar_path) on public.profiles
  to authenticated;
grant update (timezone) on public.user_settings to authenticated;

-- žiadosť o priateľstvo sa dá len prijať, nie inak meniť
revoke update on public.friendships from authenticated;
grant update (status) on public.friendships to authenticated;

revoke execute on function
  public.rollup_user(uuid), public.rollup_all(), public.handle_new_user(),
  public.queue_photo_deletion()
from public, anon, authenticated;

create policy "plans: readable" on public.plans
  for select to authenticated using (true);

create policy "profiles: readable" on public.profiles
  for select to authenticated using (true);
create policy "profiles: owner updates" on public.profiles
  for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy "settings: owner reads" on public.user_settings
  for select to authenticated using (user_id = (select auth.uid()));
create policy "settings: owner updates" on public.user_settings
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy "meals: owner or friends read" on public.meals
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or visibility = 'friends' and public.is_friend(user_id)
  );
create policy "meals: owner inserts" on public.meals
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "meals: owner updates" on public.meals
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy "meals: owner deletes" on public.meals
  for delete to authenticated using (user_id = (select auth.uid()));

-- položky vidí ten, kto vidí jedlo; meniť ich môže len majiteľ jedla
create policy "items: readable with meal" on public.meal_items
  for select to authenticated
  using (exists (select 1 from public.meals m where m.id = meal_id));
create policy "items: owner writes" on public.meal_items
  for all to authenticated
  using (exists (
    select 1 from public.meals m
    where m.id = meal_id and m.user_id = (select auth.uid())
  ))
  with check (exists (
    select 1 from public.meals m
    where m.id = meal_id and m.user_id = (select auth.uid())
  ));

create policy "stats: owner reads" on public.stat_periods
  for select to authenticated using (user_id = (select auth.uid()));

create policy "friendships: parties read" on public.friendships
  for select to authenticated
  using ((select auth.uid()) in (requester_id, addressee_id));
create policy "friendships: request" on public.friendships
  for insert to authenticated
  with check (requester_id = (select auth.uid()) and status = 'pending');
create policy "friendships: addressee accepts" on public.friendships
  for update to authenticated
  using (addressee_id = (select auth.uid()))
  with check (status = 'accepted');
create policy "friendships: parties remove" on public.friendships
  for delete to authenticated
  using ((select auth.uid()) in (requester_id, addressee_id));

create policy "reactions: readable with meal" on public.meal_reactions
  for select to authenticated
  using (exists (select 1 from public.meals m where m.id = meal_id));
create policy "reactions: react to visible meal" on public.meal_reactions
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (select 1 from public.meals m where m.id = meal_id)
  );
create policy "reactions: owner changes" on public.meal_reactions
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy "reactions: owner removes" on public.meal_reactions
  for delete to authenticated using (user_id = (select auth.uid()));
