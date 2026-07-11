defmodule MobileCarWash.Repo.Migrations.AddSourceToTechApplications do
  use Ecto.Migration

  def change do
    alter table(:tech_applications) do
      add :source, :text, null: false, default: "applicant"
    end

    create index(:tech_applications, [:source])
  end
end
