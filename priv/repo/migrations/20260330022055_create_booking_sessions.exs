defmodule MobileCarWash.Repo.Migrations.CreateBookingSessions do
  use Ecto.Migration

  def change do
    create table(:booking_sessions, primary_key: false) do
      add :session_id, :string, primary_key: true
      add :data, :text, null: false
      timestamps()
    end

    create index(:booking_sessions, [:updated_at])
  end
end
