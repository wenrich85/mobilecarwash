defmodule MobileCarWash.Inventory.SupplyUsage do
  @moduledoc """
  Records supply consumption events tied to a specific appointment, technician, and/or van.
  Logging usage automatically decrements the supply's quantity_on_hand.
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Inventory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "supply_usages"
    repo MobileCarWash.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :quantity_used, :decimal do
      allow_nil? false
      public? true
    end

    attribute :notes, :string do
      allow_nil? true
      public? true
    end

    attribute :occurred_at, :utc_datetime do
      default &DateTime.utc_now/0
      allow_nil? false
      public? true
    end

    # FKs — all optional so usage can be logged partially
    attribute :supply_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :appointment_id, :uuid do
      allow_nil? true
      public? true
    end

    attribute :technician_id, :uuid do
      allow_nil? true
      public? true
    end

    attribute :van_id, :uuid do
      allow_nil? true
      public? true
    end

    create_timestamp :inserted_at
  end

  actions do
    defaults [:read]

    create :log do
      accept [:supply_id, :appointment_id, :technician_id, :van_id,
              :quantity_used, :notes, :occurred_at]

      # Decrement supply quantity after creating the usage record
      after_action fn changeset, record, _context ->
        supply = Ash.get!(MobileCarWash.Inventory.Supply, record.supply_id, authorize?: false)

        supply
        |> Ash.Changeset.for_update(:use_quantity, %{quantity: record.quantity_used})
        |> Ash.update(authorize?: false)

        {:ok, record}
      end
    end

    read :for_appointment do
      argument :appointment_id, :uuid, allow_nil?: false
      filter expr(appointment_id == ^arg(:appointment_id))
    end

    read :for_technician do
      argument :technician_id, :uuid, allow_nil?: false
      filter expr(technician_id == ^arg(:technician_id))
    end

    read :for_van do
      argument :van_id, :uuid, allow_nil?: false
      filter expr(van_id == ^arg(:van_id))
    end

    read :for_supply do
      argument :supply_id, :uuid, allow_nil?: false
      filter expr(supply_id == ^arg(:supply_id))
    end
  end
end
