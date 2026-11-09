-- ARVION LAB: CEO TYCOON — v3: brigas dentro de cada andar
-- Rode inteiro no SQL Editor (depois do update-v2.sql). Pode rodar mais de uma vez.

-- Em cada andar (2 a 8), dois funcionários do mesmo cargo brigam (50% / 50%).
-- Quem perde desce um andar. Cargos mais altos têm brigas mais frequentes.
create or replace function run_brawls() returns void language plpgsql security definer set search_path=public as $$
declare r int; a record; b record; win record; los record; rr roles;
begin
  perform pg_advisory_xact_lock(42);
  for r in 2..8 loop
    if random() < 0.12 + 0.03*r then
      select * into a from players where role=r order by random() limit 1;
      select * into b from players where role=r and id<>a.id order by random() limit 1;
      if a.id is not null and b.id is not null then
        if random() < 0.5 then win := a; los := b; else win := b; los := a; end if;
        select * into rr from roles where id=r-1;
        update players set role=rr.id, salary=rr.salary, performance=rr.id*12, status='Perdeu a briga' where id=los.id;
        update players set status='Venceu a briga', happiness=least(100,happiness+3) where id=win.id;
        insert into feed(kind,handle,role,other) values('brawl',win.handle,r,los.handle);
      end if;
    end if;
  end loop;
end $$;

-- rodada completa: ações, quedas, disputas, sorteio e brigas
create or replace function tick_all() returns void language plpgsql security definer set search_path=public as $$
begin
  perform tick();
  perform run_brawls();
end $$;

revoke execute on function run_brawls(), tick_all() from anon, authenticated, public;

-- troca o agendamento para a rodada completa
select cron.unschedule(jobid) from cron.job where jobname in ('arvion-tick','arvion-draw');
select cron.schedule('arvion-tick','* * * * *','select tick_all()');
