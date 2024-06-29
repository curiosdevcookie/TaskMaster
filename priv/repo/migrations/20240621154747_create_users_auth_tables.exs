defmodule TaskMaster.Repo.Migrations.CreateUsersAuthTables do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS citext", ""

    create table(:users, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :first_name, :string, null: false
      add :last_name, :string, null: false
      add :nick_name, :citext
      add :email, :citext, null: false
      add :roles, {:array, :string}, null: false, default: ["editor"]
      add :hashed_password, :string, null: false
      add :confirmed_at, :naive_datetime
      add :last_login_at, :naive_datetime

      timestamps()
    end

    create unique_index(:users, [:email])
    create unique_index(:users, [:nick_name])

    create table(:avatars, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :path, :string, null: false
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:avatars, [:user_id])

    create table(:users_tokens, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :user_id, references(:users, on_delete: :delete_all, type: :uuid), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string

      timestamps(updated_at: false)
    end

    create index(:users_tokens, [:user_id])
    create unique_index(:users_tokens, [:context, :token])
  end
end
