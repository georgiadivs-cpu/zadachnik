create table attachments (
    id uuid not null,
    user_id uuid not null references users (id) on delete cascade,
    owner_type text not null check (owner_type in ('NOTE', 'TASK')),
    owner_id uuid not null,
    file_name text not null check (char_length(file_name) between 1 and 255),
    mime_type text not null,
    size_bytes bigint not null check (size_bytes > 0),
    sha256 text not null check (char_length(sha256) = 64),
    storage_key text not null,
    revision bigint not null default 1,
    created_at timestamptz not null,
    updated_at timestamptz not null,
    deleted_at timestamptz,
    primary key (user_id, id)
);

create index attachments_user_owner_idx
    on attachments (user_id, owner_type, owner_id);

create index attachments_user_updated_idx
    on attachments (user_id, updated_at);
