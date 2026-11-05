create table users (
    id uuid primary key,
    email text not null unique,
    password_hash text not null,
    status text not null check (status in ('ACTIVE', 'DISABLED')),
    created_at timestamptz not null,
    updated_at timestamptz not null
);

create table devices (
    id uuid primary key,
    user_id uuid not null references users (id) on delete cascade,
    name text not null,
    platform text not null check (platform in ('ANDROID', 'IOS', 'MACOS', 'WINDOWS')),
    created_at timestamptz not null,
    last_seen_at timestamptz,
    revoked_at timestamptz
);

create index devices_user_id_idx on devices (user_id);

create table refresh_tokens (
    id uuid primary key,
    user_id uuid not null references users (id) on delete cascade,
    device_id uuid not null references devices (id) on delete cascade,
    token_hash text not null unique,
    expires_at timestamptz not null,
    revoked_at timestamptz,
    replaced_by uuid references refresh_tokens (id),
    created_at timestamptz not null
);

create index refresh_tokens_device_idx on refresh_tokens (device_id);
create index refresh_tokens_user_idx on refresh_tokens (user_id);
