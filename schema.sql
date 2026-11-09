-- ARVION LAB: CEO TYCOON — v5: moradia com aluguel + conquistas
-- Rode inteiro no SQL Editor (depois do update-v4.sql). Pode rodar mais de uma vez.

-- 1) Conquistas
create table if not exists badges(
  handle text not null, code text not null, created_at timestamptz not null default now(),
  primary key (handle, code));
alter table badges enable row level security;
drop policy if exists "ler" on badges;
create policy "ler" on badges for select to anon using (true);

create or replace function award_badges() returns void language plpgsql security definer set search_path=public as $$
begin
  with cand(handle, code) as (
    select distinct handle, 'primeira_promocao'::text from feed where kind='promo'
    union select distinct handle, 'ja_foi_ceo'::text from reigns
    union select distinct handle, 'rei_10min'::text from reigns where coalesce(ended_at, now()) - started_at >= interval '10 minutes'
    union select handle, 'lutador'::text from feed where kind='brawl' group by handle having count(*) >= 3
    union select handle, 'rico'::text from players where money >= 10000
  ), ins as (
    insert into badges(handle, code) select handle, code from cand where handle is not null on conflict do nothing returning handle, code
  )
  insert into feed(kind, handle, other) select 'badge', handle, code from ins;
end $$;

-- 2) Moradia: o funcionário se mantém no melhor lugar que o dinheiro permite e paga o aluguel a cada rodada
create or replace function run_living() returns void language plpgsql security definer set search_path=public as $$
begin
  update players set
    housing = case when money >= 6000 then 'Cobertura' when money >= 1500 then 'Apartamento' when money >= 300 then 'Kitnet' else 'Quarto compartilhado' end,
    money = greatest(0, money - case when money >= 6000 then 40 when money >= 1500 then 12 when money >= 300 then 4 else 0 end),
    happiness = least(100, happiness + case when money >= 6000 then 2 when money >= 1500 then 1 else 0 end);
end $$;

-- 3) Rodada completa
create or replace function tick_all() returns void language plpgsql security definer set search_path=public as $$
begin
  perform tick();
  perform run_brawls();
  perform run_event();
  perform run_living();
  perform track_reign();
  perform award_badges();
end $$;

revoke execute on function award_badges(), run_living(), tick_all() from anon, authenticated, public;
