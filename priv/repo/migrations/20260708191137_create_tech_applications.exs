defmodule MobileCarWash.Repo.Migrations.CreateTechApplications do
  use Ecto.Migration

  def change do
    create table(:tech_applications, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :customer_id, references(:customers, type: :uuid, on_delete: :delete_all), null: false
      add :status, :text, null: false, default: "draft"
      add :preferred_name, :text, null: false
      add :phone, :text
      add :home_zip, :text
      add :preferred_zone, :text
      add :availability_weekdays, :boolean, null: false, default: false
      add :availability_weekends, :boolean, null: false, default: false
      add :availability_mornings, :boolean, null: false, default: false
      add :availability_afternoons, :boolean, null: false, default: false
      add :availability_evenings, :boolean, null: false, default: false
      add :experience_level, :text, null: false, default: "none"
      add :has_valid_driver_license, :boolean, null: false, default: false
      add :has_reliable_transportation, :boolean, null: false, default: false
      add :can_lift_supplies, :boolean, null: false, default: false
      add :desired_hours_per_week, :integer
      add :earliest_start_date, :date
      add :emergency_contact_name, :text
      add :emergency_contact_phone, :text
      add :why_work_with_us, :text
      add :experience_notes, :text
      add :schedule_notes, :text
      add :review_notes, :text
      add :decision_note, :text
      add :accepted_pay_rate_cents, :integer
      add :accepted_pay_rate_pct, :decimal
      add :assigned_zone, :text
      add :van_id, references(:vans, type: :uuid, on_delete: :nilify_all)
      add :active, :boolean, null: false, default: true
      add :submitted_at, :utc_datetime_usec
      add :reviewed_at, :utc_datetime_usec
      add :decided_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:tech_applications, [:customer_id])
    create index(:tech_applications, [:status])
  end
end
