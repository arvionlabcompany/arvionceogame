-- ARVION LAB: CEO TYCOON — schema Supabase (rode no SQL Editor)
create extension if not exists pgcrypto;

create table roles(id int primary key, name text not null, salary int not null, capacity int); -- capacity null = ilimitado
insert into roles values
(1,'Estagiário',1500,null),(2,'Assistente',2200,60),(3,'Analista',3500,40),(4,'Coordenador',5000,25),
(5,'Gerente',8000,12),(6,'Diretor',15000,6),(7,'Vice-presidente',25000,3),(8,'CEO',50000,1);

create table players(
  id uuid primary key default gen_random_uuid(),
  handle text unique not null,
  role int not null default 1 references roles(id),
  money numeric not null default 500, salary int not null default 1500,
  health int not null default 100, happiness int not null default 50,
  fatigue int not null default 0, energy int not null default 100,
  performance int not null default 0,
  housing text not null default 'Quarto compartilhado', status text not null default 'Recém-contratado',
  x int not null default 400, last_action timestamptz not null default now(),
  created_at timestamptz not null default now());
create table player_secrets(player_id uuid primary key references players(id) on delete cascade, token text not null);
create table candidacies(player_id uuid primary key references players(id) on delete cascade, role int not null, created_at timestamptz default now());
create table feed(id bigserial primary key, kind text not null, handle text, role int, created_at timestamptz default now());

alter table roles enable row level security; alter table players enable row level security;
alter table player_secrets enable row level security; alter table candidacies enable row level security; alter table feed enable row level security;
create policy "ler" on roles for select to anon using (true);
create policy "ler" on players for select to anon using (true);
create policy "ler" on candidacies for select to anon using (true);
create policy "ler" on feed for select to anon using (true);
-- sem policies de escrita: toda escrita passa pelas funções abaixo (security definer)

create or replace function join_game(p_handle text) returns json language plpgsql security definer set search_path=public as $$
declare h text := lower(regexp_replace(trim(p_handle),'^@','')); pid uuid; tok text := encode(gen_random_bytes(16),'hex');
begin
  if h !~ '^[a-z0-9._]{1,30}$' then raise exception '@ inválido'; end if;
  if exists(select 1 from players where handle=h) then raise exception 'Esse @ já está na empresa'; end if;
  insert into players(handle,x) values(h, 100+floor(random()*700)) returning id into pid;
  insert into player_secrets values(pid,tok);
  insert into feed(kind,handle,role) values('hire',h,1);
  return json_build_object('id',pid,'token',tok);
end $$;

create or replace function do_action(p_token text, p_kind text) returns void language plpgsql security definer set search_path=public as $$
declare pid uuid;
begin
  select player_id into pid from player_secrets where token=p_token; if pid is null then raise exception 'sessão inválida'; end if;
  if p_kind='work' then
    update players set performance=performance+5, fatigue=least(100,fatigue+10), energy=greatest(0,energy-10),
      money=money+salary/100.0, happiness=greatest(0,happiness-1), last_action=now()
    where id=pid and energy>=10 and last_action<now()-interval '1 second';
  elsif p_kind='rest' then
    update players set fatigue=greatest(0,fatigue-15), energy=least(100,energy+15), happiness=least(100,happiness+2), last_action=now()
    where id=pid and last_action<now()-interval '1 second';
  elsif p_kind='eat' then
    update players set money=money-20, health=least(100,health+5), energy=least(100,energy+5), happiness=least(100,happiness+1), last_action=now()
    where id=pid and money>=20 and last_action<now()-interval '1 second';
  end if;
end $$;

create or replace function move_player(p_token text, p_x int) returns void language sql security definer set search_path=public as $$
  update players set x=greatest(20,least(900,p_x)) where id=(select player_id from player_secrets where token=p_token) $$;

create or replace function request_promotion(p_token text) returns text language plpgsql security definer set search_path=public as $$
declare p players; begin
  select pl.* into p from players pl join player_secrets s on s.player_id=pl.id where s.token=p_token;
  if p.id is null then raise exception 'sessão inválida'; end if;
  if p.role>=8 then return 'Você já é o CEO.'; end if;
  if p.performance < p.role*25 or p.fatigue>80 then return 'Requisitos: desempenho '||p.role*25||' e cansaço até 80.'; end if;
  insert into candidacies values(p.id,p.role+1) on conflict (player_id) do nothing;
  return 'Candidatura registrada. O sorteio roda a cada minuto.';
end $$;

-- Sorteio: cada candidato elegível tem peso idêntico (random() uniforme => 1/N por vaga)
create or replace function run_draw() returns void language plpgsql security definer set search_path=public as $$
declare r roles; open int; w record; begin
  perform pg_advisory_xact_lock(42);
  for r in select * from roles where id>=2 order by id desc loop
    open := r.capacity - (select count(*) from players where role=r.id);
    if open>0 then
      for w in select c.player_id, p.handle from candidacies c join players p on p.id=c.player_id
               where c.role=r.id and p.role=r.id-1 order by random() limit open loop
        update players set role=r.id, salary=r.salary, performance=0, status='Promovido a '||r.name where id=w.player_id;
        insert into feed(kind,handle,role) values('promo',w.handle,r.id);
      end loop;
    end if;
    delete from candidacies where role=r.id;  -- quem não ganhou precisa se candidatar de novo
  end loop;
end $$;

revoke execute on function run_draw() from anon, authenticated, public;
grant execute on function join_game(text), do_action(text,text), move_player(text,int), request_promotion(text) to anon;

alter publication supabase_realtime add table players, feed;

-- Agende o sorteio (Database > Extensions > ative pg_cron):
-- select cron.schedule('arvion-draw','* * * * *','select run_draw()');
