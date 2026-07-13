defmodule MobileCarWash.Repo.Migrations.AddFinalNotesToAppointmentChecklists do
  use Ecto.Migration

  def change do
    alter table(:appointment_checklists) do
      add :final_notes, :text
    end
  end
end
