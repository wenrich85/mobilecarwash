defmodule MobileCarWash.Repo.Migrations.AddShowOnLandingToServiceTypes do
  use Ecto.Migration

  def change do
    alter table(:service_types) do
      add :show_on_landing, :boolean, null: false, default: true
    end
  end
end
