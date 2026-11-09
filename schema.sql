-- ARVION LAB: CEO TYCOON — v4: reinado do CEO + eventos globais
-- Rode inteiro no SQL Editor (depois do update-v3.sql). Pode rodar mais de uma vez.

-- 1) Reinados do CEO (hall da fama)
create table if not exists reigns(
  id bigserial primary key, handle text not null,
  started_at timestamptz not null default now(), ended_at timestamptz);
alter table reigns enable row level security;
drop policy if exists "ler" on reigns;
create policy "ler" on reigns for select to anon using (true);

create or replace function track_reign() returns void language plpgsql security definer set search_path=public as $$
declare c text; oid bigint; oh text;
begin
  select handle into c from players where role=8 limit 1;
  select id, handle into oid, oh from reigns where ended_at is null order by id desc limit 1;
  if oid is not null and (c is null or c <> oh) then update reigns set ended_at=now() where id=oid; oid := null; end if;
  if c is not null and oid is null then insert into reigns(handle) values(c); end if;
end $$;

-- 2) Eventos globais surpresa (em média 1 por hora)
--    65%: Avaliação de Desempenho — os 20% de menor desempenho de cada andar descem um cargo
--    35%: Bônus Geral — todos ganham 20% do salário
create or replace function run_event() returns void language plpgsql security definer set search_path=public as $$
declare r int; p record; rr roles; n int; total int := 0;
begin
  perform pg_advisory_xact_lock(42);
  if random() >= 1.0/60 then return; end if;
  if random() < 0.65 then
    for r in 2..8 loop
      select count(*) into n from players where role=r;
      if n >= 3 or (r = 8 and n = 1 and random() < 0.25) then
        select * into rr from roles where id=r-1;
        for p in select id, handle from players where role=r order by performance asc, random() limit greatest(1, n/5) loop
          update players set role=rr.id, salary=rr.salary, performance=rr.id*12, status='Cortado na avaliação' where id=p.id;
          insert into feed(kind,handle,role) values('demote',p.handle,rr.id);
          total := total + 1;
        end loop;
      end if;
    end loop;
    insert into feed(kind,handle,role) values('review','ARVION LAB',total);
  else
    update players set money=money+salary/5.0, happiness=least(100,happiness+5);
    insert into feed(kind,handle,role) values('bonus','ARVION LAB',0);
  end if;
end $$;

-- 3) Rodada completa
create or replace function tick_all() returns void language plpgsql security definer set search_path=public as $$
begin
  perform tick();
  perform run_brawls();
  perform run_event();
  perform track_reign();
end $$;

revoke execute on function track_reign(), run_event(), tick_all() from anon, authenticated, public;
select track_reign();  -- registra o CEO atual, se já houver
