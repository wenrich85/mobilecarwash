defmodule MobileCarWash.Repo.Migrations.CreateTechInvites do
  use Ecto.Migration

  def change do
    create table(:tech_invites, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :customer_id,
          references(:customers, type: :uuid, on_delete: :delete_all),
          null: false

      add :technician_id,
          references(:technicians, type: :uuid, on_delete: :delete_all),
          null: false

      add :token_hash, :text, null: false
      add :status, :text, null: false, default: "pending"
      add :expires_at, :utc_datetime_usec, null: false
      add :accepted_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:tech_invites, [:token_hash])
    create index(:tech_invites, [:customer_id])
    create index(:tech_invites, [:technician_id])
    create index(:tech_invites, [:status])
  end
end
