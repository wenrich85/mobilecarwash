defmodule MobileCarWash.Accounts.Customer do
  @moduledoc """
  Customer resource with authentication via email + password.
  Extensible for OAuth and magic link in future.
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAuthentication],
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "customers"
    repo MobileCarWash.Repo
  end

  authentication do
    tokens do
      enabled? true
      token_resource MobileCarWash.Accounts.Token
      require_token_presence_for_authentication? true
      signing_secret fn _, _ ->
        Application.fetch_env(:mobile_car_wash, :token_signing_secret)
      end
    end

    strategies do
      password :password do
        identity_field :email
        hashed_password_field :hashed_password

        register_action_accept [:name, :phone]
      end
    end
  end

  policies do
    # Allow all actions for now — will tighten as we build out roles
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :email, :ci_string do
      allow_nil? false
      public? true
    end

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :phone, :string do
      public? true
    end

    attribute :role, :atom do
      constraints one_of: [:customer, :technician, :admin, :guest]
      default :customer
      allow_nil? false
      public? true
    end

    attribute :hashed_password, :string do
      allow_nil? true
      sensitive? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_email, [:email]
  end

  actions do
    defaults [:read]

    create :create_guest do
      @doc "Creates a lightweight guest customer — no password required"
      accept [:email, :name, :phone]
      change set_attribute(:role, :guest)
    end

    read :by_email do
      argument :email, :ci_string, allow_nil?: false
      filter expr(email == ^arg(:email))
    end
  end
end
