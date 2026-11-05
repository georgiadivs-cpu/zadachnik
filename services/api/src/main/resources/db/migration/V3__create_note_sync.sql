alter table notes add column user_id uuid references users (id);

create index notes_user_id_idx on notes (user_id);
create index notes_user_updated_idx on notes (user_id, updated_at);

create table change_log (
    seq bigserial primary key,
    user_id uuid not null references users (id) on delete cascade,
    entity_type text not null,
    entity_id uuid not null,
    operation_id uuid not null unique,
    operation_type text not null check (operation_type in ('CREATE', 'UPDATE', 'DELETE')),
    revision bigint not null,
    payload jsonb not null,
    device_id uuid not null references devices (id),
    changed_at timestamptz not null
);

create index change_log_user_seq_idx on change_log (user_id, seq);

create table processed_operations (
    operation_id uuid primary key,
    user_id uuid not null references users (id) on delete cascade,
    result text not null,
    revision bigint not null,
    change_seq bigint,
    processed_at timestamptz not null
);
