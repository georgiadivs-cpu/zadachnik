create table categories (
    id text primary key,
    name text not null,
    sort_order integer not null,
    created_at timestamptz not null,
    updated_at timestamptz not null
);

create table notes (
    id uuid primary key,
    title text not null check (char_length(title) between 1 and 200),
    content_markdown text not null default '',
    category_id text references categories (id),
    revision bigint not null default 1,
    created_at timestamptz not null,
    updated_at timestamptz not null,
    deleted_at timestamptz
);

create index notes_updated_at_idx on notes (updated_at);
create index notes_deleted_at_idx on notes (deleted_at);

insert into categories (id, name, sort_order, created_at, updated_at)
values
    ('work', 'Работа', 0, now(), now()),
    ('personal', 'Личное', 1, now(), now()),
    ('family', 'Семья', 2, now(), now());
