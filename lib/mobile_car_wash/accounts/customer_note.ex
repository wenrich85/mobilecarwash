defmodule MobileCarWash.Accounts.CustomerNote do
  @moduledoc """
  Admin-only internal note attached to a customer. Think of it as the
  sticky-note on the folder: "called about missed appt", "VIP — don't
  miss", "gate code 1234". Not visible to the customer.

  Pinned notes float to the top of the panel so the most important
  context is always in view. Deletion is allowed; editing is not (for
  audit clarity — delete and re-add instead).
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  require Ash.Query

  postgres do
    table("customer_notes")
    repo(MobileCarWash.Repo)

    references do
      # If the customer is ever hard-deleted, their notes go with them.
      # The author ref is nilified so a deleted admin doesn't take their
      # notes off the other customer's files.
      reference(:customer, on_delete: :delete)
      reference(:author, on_delete: :nilify)
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :body, :string do
      allow_nil?(false)
      public?(true)
      constraints(min_length: 1, max_length: 4000, trim?: true, allow_empty?: false)
    end

    attribute :pinned, :boolean do
      allow_nil?(false)
      default(false)
      public?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :customer, MobileCarWash.Accounts.Customer do
      allow_nil?(false)
      public?(true)
    end

    # Nullable — if the admin who wrote a note is later removed, the
    # note itself stays with the customer's file.
    belongs_to :author, MobileCarWash.Accounts.Customer do
      allow_nil?(true)
      public?(true)
    end
  end

  actions do
    defaults([:read, :destroy])

    create :add do
      accept([:customer_id, :author_id, :body, :pinned])
    end

    update :toggle_pin do
      require_atomic?(false)

      change(fn changeset, _context ->
        current = Ash.Changeset.get_attribute(changeset, :pinned) || false
        Ash.Changeset.force_change_attribute(changeset, :pinned, !current)
      end)
    end

    read :for_customer do
      argument(:customer_id, :uuid, allow_nil?: false)
      filter(expr(customer_id == ^arg(:customer_id)))
      # Pinned first, then newest-first.
      prepare(build(sort: [pinned: :desc, inserted_at: :desc]))
    end
  end

  policies do
    # Admin-only for every action. These are internal notes — regular
    # customers must never see them.
    policy action_type([:read, :create, :update, :destroy]) do
      authorize_if(expr(^actor(:role) == :admin))
    end
  end
end
