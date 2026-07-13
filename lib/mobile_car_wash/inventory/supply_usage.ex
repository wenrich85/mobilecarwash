defmodule MobileCarWash.Inventory.SupplyUsage do
  @moduledoc """
  Records supply consumption events tied to a specific appointment, technician, and/or van.
  Logging usage automatically decrements the supply's quantity_on_hand.
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Inventory,
    data_layer: AshPostgres.DataLayer

  alias MobileCarWash.Repo

  postgres do
    table("supply_usages")
    repo(MobileCarWash.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :quantity_used, :decimal do
      allow_nil?(false)
      public?(true)
    end

    attribute :notes, :string do
      allow_nil?(true)
      public?(true)
    end

    attribute :occurred_at, :utc_datetime do
      default(&DateTime.utc_now/0)
      allow_nil?(false)
      public?(true)
    end

    # FKs — all optional so usage can be logged partially
    attribute :supply_id, :uuid do
      allow_nil?(false)
      public?(true)
    end

    attribute :appointment_id, :uuid do
      allow_nil?(true)
      public?(true)
    end

    attribute :technician_id, :uuid do
      allow_nil?(true)
      public?(true)
    end

    attribute :van_id, :uuid do
      allow_nil?(true)
      public?(true)
    end

    create_timestamp(:inserted_at)
  end

  actions do
    defaults([:read])

    create :log do
      accept([
        :supply_id,
        :appointment_id,
        :technician_id,
        :van_id,
        :quantity_used,
        :notes,
        :occurred_at
      ])

      # Decrement supply quantity after creating the usage record
      change(
        after_action(fn _changeset, record, _context ->
          case Repo.query(
                 """
                 UPDATE supplies
                 SET quantity_on_hand = quantity_on_hand - $1,
                     updated_at = (now() AT TIME ZONE 'utc')
                 WHERE id = $2
                 """,
                 [record.quantity_used, Ecto.UUID.dump!(record.supply_id)]
               ) do
            {:ok, %{num_rows: 1}} -> {:ok, record}
            {:ok, _result} -> {:error, "Supply not found."}
            {:error, reason} -> {:error, reason}
          end
        end)
      )
    end

    read :for_appointment do
      argument(:appointment_id, :uuid, allow_nil?: false)
      filter(expr(appointment_id == ^arg(:appointment_id)))
    end

    read :for_technician do
      argument(:technician_id, :uuid, allow_nil?: false)
      filter(expr(technician_id == ^arg(:technician_id)))
    end

    read :for_van do
      argument(:van_id, :uuid, allow_nil?: false)
      filter(expr(van_id == ^arg(:van_id)))
    end

    read :for_supply do
      argument(:supply_id, :uuid, allow_nil?: false)
      filter(expr(supply_id == ^arg(:supply_id)))
    end
  end
end
