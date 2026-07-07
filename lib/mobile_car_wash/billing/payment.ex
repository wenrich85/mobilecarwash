defmodule MobileCarWash.Billing.Payment do
  @moduledoc """
  Payment record — tracks both one-time appointment payments
  and subscription billing events via Stripe.
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Billing,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("payments")
    repo(MobileCarWash.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :stripe_payment_intent_id, :string do
      public?(true)
    end

    attribute :stripe_checkout_session_id, :string do
      public?(true)
    end

    attribute :amount_cents, :integer do
      allow_nil?(false)
      public?(true)
    end

    attribute :status, :atom do
      constraints(one_of: [:pending, :succeeded, :failed, :refunded])
      default(:pending)
      allow_nil?(false)
      public?(true)
    end

    attribute :paid_at, :utc_datetime do
      public?(true)
    end

    attribute :collected_cents, :integer do
      public?(true)

      description(
        "Amount actually taken in. Differs from amount_cents on comped bookings (0 collected)."
      )
    end

    attribute :comped, :boolean do
      default(false)
      allow_nil?(false)
      public?(true)
    end

    attribute :comp_reason, :string do
      public?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :customer, MobileCarWash.Accounts.Customer do
      allow_nil?(false)
    end

    belongs_to :appointment, MobileCarWash.Scheduling.Appointment do
      allow_nil?(true)
    end

    belongs_to :subscription, MobileCarWash.Billing.Subscription do
      allow_nil?(true)
    end
  end

  actions do
    defaults([:read, create: :*, update: :*])

    update :complete do
      require_atomic?(false)
      accept([:stripe_payment_intent_id])
      change(set_attribute(:status, :succeeded))
      change(set_attribute(:paid_at, &DateTime.utc_now/0))

      change(fn changeset, _context ->
        Ash.Changeset.change_attribute(
          changeset,
          :collected_cents,
          changeset.data.amount_cents
        )
      end)

      # Fire the one-time referral reward after the Payment row has
      # committed. Silent no-op when the customer has no referrer or
      # the reward already fired (idempotent).
      change(fn changeset, _context ->
        Ash.Changeset.after_action(changeset, fn _cs, payment ->
          if payment.customer_id do
            _ = MobileCarWash.Marketing.Referrals.issue_reward(payment.customer_id)
          end

          {:ok, payment}
        end)
      end)
    end

    create :record_manual do
      @doc "Records a manually-created payment (admin comp or off-platform collection). Always succeeded."
      accept([:amount_cents, :collected_cents, :comped, :comp_reason])

      change(set_attribute(:status, :succeeded))
      change(set_attribute(:paid_at, &DateTime.utc_now/0))

      validate(present(:comp_reason),
        where: [attribute_equals(:comped, true)],
        message: "comp_reason is required when comping a booking"
      )
    end

    update :fail do
      change(set_attribute(:status, :failed))
    end

    read :by_checkout_session do
      argument(:session_id, :string, allow_nil?: false)
      filter(expr(stripe_checkout_session_id == ^arg(:session_id)))
    end

    read :by_appointment do
      argument(:appointment_id, :uuid, allow_nil?: false)
      filter(expr(appointment_id == ^arg(:appointment_id)))
    end
  end
end
