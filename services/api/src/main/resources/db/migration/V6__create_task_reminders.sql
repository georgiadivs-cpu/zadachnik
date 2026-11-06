create table task_reminders (
    id uuid not null,
    user_id uuid not null references users (id) on delete cascade,
    task_id uuid not null,
    remind_at timestamptz not null,
    revision bigint not null default 1,
    created_at timestamptz not null,
    updated_at timestamptz not null,
    deleted_at timestamptz,
    primary key (user_id, id),
    foreign key (user_id, task_id) references tasks (user_id, id)
);

create unique index task_reminders_active_task_idx
    on task_reminders (user_id, task_id)
    where deleted_at is null;

create index task_reminders_user_remind_idx
    on task_reminders (user_id, remind_at);
