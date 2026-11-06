create table board_lanes (
    id uuid not null,
    user_id uuid not null references users (id) on delete cascade,
    name text not null check (char_length(name) between 1 and 60),
    sort_order integer not null check (sort_order >= 0),
    revision bigint not null default 1,
    created_at timestamptz not null,
    updated_at timestamptz not null,
    deleted_at timestamptz,
    primary key (user_id, id)
);

create index board_lanes_user_sort_idx on board_lanes (user_id, sort_order);

create table tasks (
    id uuid not null,
    user_id uuid not null references users (id) on delete cascade,
    title text not null check (char_length(title) between 1 and 200),
    description text not null default '',
    lane_id uuid not null,
    system_state text not null check (system_state in ('ACTIVE', 'CANCELLED')),
    category_id text references categories (id),
    priority text not null check (priority in ('LOW', 'NORMAL', 'HIGH')),
    planned_start_at timestamptz,
    planned_end_at timestamptz,
    actual_start_at timestamptz,
    actual_end_at timestamptz,
    revision bigint not null default 1,
    created_at timestamptz not null,
    updated_at timestamptz not null,
    deleted_at timestamptz,
    primary key (user_id, id),
    foreign key (user_id, lane_id) references board_lanes (user_id, id)
);

create index tasks_user_lane_idx on tasks (user_id, lane_id);
create index tasks_user_updated_idx on tasks (user_id, updated_at);

insert into board_lanes (id, user_id, name, sort_order, revision, created_at, updated_at)
select seed.id, users.id, seed.name, seed.sort_order, 1, now(), now()
from users
cross join (
    values
        ('00000000-0000-4000-8000-000000000101'::uuid, 'Новые', 0),
        ('00000000-0000-4000-8000-000000000102'::uuid, 'В работе', 1),
        ('00000000-0000-4000-8000-000000000103'::uuid, 'Проверка', 2),
        ('00000000-0000-4000-8000-000000000104'::uuid, 'Готово', 3)
) as seed(id, name, sort_order)
on conflict (user_id, id) do nothing;
