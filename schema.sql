-- ARVION LAB: CEO TYCOON — v2: ações automáticas, quedas de cargo e disputas
-- Rode inteiro no SQL Editor (pode rodar mais de uma vez).
alter table feed add column if not exists other text;

create or replace function tick() returns void language plpgsql security definer set search_path=public as $$
declare
  p record; ch record; inc record; rr roles; r int; x float8;
  base float8[] := array[0,0.01,0.015,0.02,0.03,0.04,0.06,0.10]; -- chance de queda por rodada, por cargo (1..8)
begin
  perform pg_advisory_xact_lock(42);

  -- 1) cada funcionário age sozinho
  for p in select * from players loop
    x := random();
    if x < 0.55 and p.energy >= 10 then            -- trabalhar
      update players set performance=performance+5, fatigue=least(100,fatigue+10), energy=energy-10,
        money=money+salary/100.0, happiness=greatest(0,happiness-1) where id=p.id;
    elsif x < 0.80 or p.energy < 10 then           -- descansar
      update players set fatigue=greatest(0,fatigue-15), energy=least(100,energy+15), happiness=least(100,happiness+2) where id=p.id;
    elsif x < 0.90 and p.money >= 20 then          -- comer
      update players set money=money-20, health=least(100,health+5), energy=least(100,energy+5), happiness=least(100,happiness+1) where id=p.id;
    elsif x < 0.95 then                            -- bônus
      update players set money=money+salary/10.0, happiness=least(100,happiness+5) where id=p.id;
    else                                           -- crise
      update players set performance=greatest(0,performance-10), happiness=greatest(0,happiness-5) where id=p.id;
    end if;
  end loop;

  -- 2) quedas: quanto maior o cargo e o cansaço, maior o risco (CEO é o mais instável)
  for p in select * from players where role>=2 loop
    if random() < base[p.role] * (1 + p.fatigue/100.0) then
      select * into rr from roles where id=p.role-1;
      update players set role=rr.id, salary=rr.salary, performance=rr.id*12, status='Rebaixado a '||rr.name where id=p.id;
      insert into feed(kind,handle,role) values('demote',p.handle,rr.id);
    end if;
  end loop;

  -- 3) candidatura automática de quem atingiu os requisitos
  delete from candidacies c using players pl where pl.id=c.player_id and c.role<>pl.role+1;
  insert into candidacies(player_id,role)
    select id, role+1 from players where role<8 and performance>=role*25 and fatigue<=80
    on conflict (player_id) do nothing;

  -- 4) disputas: um candidato desafia quem ocupa o cargo (50% / 50%); quanto mais alto o cargo, mais frequentes
  for r in 2..8 loop
    if random() < 0.10 + 0.03*r then
      select * into inc from players where role=r order by random() limit 1;
      select pl.* into ch from candidacies c join players pl on pl.id=c.player_id where c.role=r and pl.role=r-1 order by random() limit 1;
      if inc.id is not null and ch.id is not null then
        if random() < 0.5 then
          select * into rr from roles where id=r;
          update players set role=r, salary=rr.salary, performance=0, status='Venceu a disputa por '||rr.name where id=ch.id;
          select * into rr from roles where id=r-1;
          update players set role=r-1, salary=rr.salary, performance=(r-1)*12, status='Perdeu a disputa' where id=inc.id;
          insert into feed(kind,handle,role,other) values('duel',ch.handle,r,inc.handle);
        else
          update players set performance=greatest(0,performance-15), status='Perdeu a disputa' where id=ch.id;
          update players set status='Defendeu o cargo' where id=inc.id;
          insert into feed(kind,handle,role,other) values('duel',inc.handle,r,ch.handle);
        end if;
        delete from candidacies where player_id=ch.id;
      end if;
    end if;
  end loop;

  -- 5) vagas abertas: sorteio entre candidatos (1/N)
  perform run_draw();
end $$;

-- o navegador não controla mais as ações
revoke execute on function tick() from anon, authenticated, public;
revoke execute on function do_action(text,text), request_promotion(text) from anon, authenticated;

-- troca o agendamento: remove o antigo e agenda o tick (a cada minuto)
select cron.unschedule(jobid) from cron.job where jobname='arvion-draw';
select cron.schedule('arvion-tick','* * * * *','select tick()');
