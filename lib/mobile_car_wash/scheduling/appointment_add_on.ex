defmodule MobileCarWash.Scheduling.AppointmentAddOn do
  @moduledoc """
  Join row linking an appointment to a selected add-on, capturing the
  add-on price at booking time so historical receipts stay correct even
  if the add-on's price later changes.
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Scheduling,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("appointment_add_ons")
    repo(MobileCarWash.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :price_cents, :integer do
      allow_nil?(false)
      public?(true)
    end

    create_timestamp(:inserted_at)
  end

  relationships do
    belongs_to :appointment, MobileCarWash.Scheduling.Appointment do
      allow_nil?(false)
    end

    belongs_to :add_on, MobileCarWash.Scheduling.AddOn do
      allow_nil?(false)
    end
  end

  actions do
    defaults([:read])

    create :create do
      primary?(true)
      accept([:appointment_id, :add_on_id, :price_cents])
    end
  end
end
