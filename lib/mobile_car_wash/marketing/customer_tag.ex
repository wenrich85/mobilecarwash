defmodule MobileCarWash.Marketing.CustomerTag do
  @moduledoc """
  Join between a Customer and a Tag. Per-customer one row per tag
  (enforced via `unique_pair` identity).

  `reason` lives on the join, not as a separate note, because the
  reason is tag-specific ("complained twice about towel marks" lives
  with the At Risk tag; when the tag is removed the reason goes with
  it). Standalone observations belong in `CustomerNote`.
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Marketing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  require Ash.Query

  postgres do
    table("customer_tags")
    repo(MobileCarWash.Repo)

    references do
      reference(:customer, on_delete: :delete)
      reference(:tag, on_delete: :delete)
      reference(:author, on_delete: :nilify)
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :reason, :string do
      public?(true)
      constraints(max_length: 500)
    end

    create_timestamp(:inserted_at)
  end

  relationships do
    belongs_to :customer, MobileCarWash.Accounts.Customer do
      allow_nil?(false)
      public?(true)
    end

    belongs_to :tag, MobileCarWash.Marketing.Tag do
      allow_nil?(false)
      public?(true)
    end

    # Nullable — if the admin who applied the tag is later removed,
    # the tag stays with the customer.
    belongs_to :author, MobileCarWash.Accounts.Customer do
      allow_nil?(true)
      public?(true)
    end
  end

  identities do
    identity(:unique_pair, [:customer_id, :tag_id])
  end

  actions do
    defaults([:read, :destroy])

    create :tag do
      accept([:customer_id, :tag_id, :author_id, :reason])
    end

    read :for_customer do
      argument(:customer_id, :uuid, allow_nil?: false)
      filter(expr(customer_id == ^arg(:customer_id)))
      prepare(build(sort: [inserted_at: :desc]))
    end
  end

  policies do
    policy action_type([:read, :create, :destroy]) do
      authorize_if(expr(^actor(:role) == :admin))
    end
  end
end
