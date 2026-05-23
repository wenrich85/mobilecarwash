defmodule MobileCarWash.Repo.Migrations.AddPhotoIdempotencyAndSoftDelete do
  use Ecto.Migration

  def change do
    alter table(:photos) do
      add :idempotency_key, :string
      add :deleted_at, :utc_datetime_usec
    end

    create unique_index(:photos, [:idempotency_key],
             where: "idempotency_key IS NOT NULL",
             name: :photos_idempotency_key_unique_index
           )
  end
end
