defmodule MobileCarWash.Operations.Technician do
  @moduledoc """
  A technician who performs car washes. For MVP, there's only one (the owner).
  Multi-technician support is Phase 2.
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Operations,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("technicians")
    repo(MobileCarWash.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :phone, :string do
      public?(true)
    end

    attribute :active, :boolean do
      default(true)
      public?(true)
    end

    attribute :pay_rate_cents, :integer do
      default(2500)
      public?(true)
      description("Legacy flat per-wash pay rate in cents. Superseded by pay_rate_pct when set.")
    end

    attribute :pay_rate_pct, :decimal do
      allow_nil?(true)
      public?(true)

      description(
        "Per-wash pay as a fraction of the wash price (e.g., 0.30 = 30%). When set, supersedes pay_rate_cents."
      )
    end

    attribute :pay_period_start_day, :integer do
      default(1)
      public?(true)
      description("Day of week pay period starts: 1=Monday..7=Sunday")
    end

    attribute :zone, :atom do
      constraints(one_of: [:nw, :ne, :sw, :se])
      public?(true)
      description("Assigned service zone. Nil = floater (covers any zone).")
    end

    # Tech-level duty status, orthogonal to any per-appointment state.
    # Admin dispatch reads this to show "on break" / "available" / "off
    # duty" alongside whatever appointment each tech is currently tied to.
    attribute :status, :atom do
      constraints(one_of: [:off_duty, :available, :on_break])
      default(:off_duty)
      allow_nil?(false)
      public?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :van, MobileCarWash.Operations.Van do
      allow_nil?(true)
    end

    belongs_to :user_account, MobileCarWash.Accounts.Customer do
      allow_nil?(true)
      description("Links this technician to a login account")
    end
  end

  actions do
    defaults([:read, create: :*, update: :*])

    update :set_status do
      require_atomic?(false)
      accept([:status])

      change(
        after_action(fn _changeset, record, _context ->
          MobileCarWash.Operations.TechnicianTracker.broadcast_status(record)
          {:ok, record}
        end)
      )
    end
  end
end
