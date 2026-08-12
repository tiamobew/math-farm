alter table public.questions
  add column if not exists score integer not null default 1;

alter table public.questions
  drop constraint if exists questions_score_check;
alter table public.questions
  add constraint questions_score_check check (score between 0 and 100000);

alter table public.question_attempts
  add column if not exists score_awarded integer not null default 0;

alter table public.question_attempts
  drop constraint if exists question_attempts_score_awarded_check;
alter table public.question_attempts
  add constraint question_attempts_score_awarded_check check (score_awarded >= 0);

create or replace function public.list_question_prompts()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', q.id,
        'question', q.question,
        'coins', q.coins,
        'score', q.score,
        'subject', q.subject
      )
      order by q.sort_order, q.created_at
    ),
    '[]'::jsonb
  )
  from public.questions q
  where q.active;
$$;

create or replace function public.submit_answer(p_question_id text, p_answer text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  q public.questions%rowtype;
  v_correct boolean;
  v_coins bigint;
  v_points bigint;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;

  select * into q
  from public.questions
  where id = p_question_id and active
  for share;
  if not found then raise exception 'ไม่พบคำถาม'; end if;

  v_correct := private.answers_equal(p_answer, q.answer);
  if v_correct then
    update public.profiles
    set coins = coins + q.coins,
        points = points + q.score
    where id = auth.uid()
    returning coins, points into v_coins, v_points;
  else
    select coins, points into v_coins, v_points
    from public.profiles
    where id = auth.uid();
  end if;

  insert into public.question_attempts(
    user_id, question_id, submitted_answer, correct, reward, score_awarded
  ) values (
    auth.uid(), q.id, left(p_answer, 500), v_correct,
    case when v_correct then q.coins else 0 end,
    case when v_correct then q.score else 0 end
  );

  return jsonb_build_object(
    'correct', v_correct,
    'reward', case when v_correct then q.coins else 0 end,
    'score', case when v_correct then q.score else 0 end,
    'coins', v_coins,
    'points', v_points
  );
end;
$$;

revoke all on function public.list_question_prompts() from public, anon;
grant execute on function public.list_question_prompts() to authenticated;
revoke all on function public.submit_answer(text, text) from public, anon;
grant execute on function public.submit_answer(text, text) to authenticated;
