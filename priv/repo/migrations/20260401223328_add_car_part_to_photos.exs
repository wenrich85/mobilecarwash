defmodule MobileCarWash.Repo.Migrations.AddCarPartToPhotos do
  use Ecto.Migration

  def change do
    alter table(:photos) do
      add :car_part, :string, null: true
    end
  end
end
