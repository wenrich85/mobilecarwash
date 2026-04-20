defmodule MobileCarWash.CashFlow.Transaction do
  @moduledoc """
  Ledger entry recording every balance transfer between accounts.

  Each transaction has a type (deposit, withdrawal, transfer, salary_draw, etc.),
  amount in cents, optional from/to accounts, description, and timestamp.
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.CashFlow,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("cash_flow_transactions")
    repo(MobileCarWash.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :type, :atom do
      constraints(
        one_of: [:deposit, :withdrawal, :transfer, :salary_draw, :tax_reserve, :savings_overflow]
      )

      allow_nil?(false)
    end

    attribute :amount_cents, :integer do
      allow_nil?(false)
    end

    attribute(:description, :string)

    attribute :occurred_at, :utc_datetime do
      default(&DateTime.utc_now/0)
      allow_nil?(false)
    end

    create_timestamp(:inserted_at)
  end

  relationships do
    belongs_to :from_account, MobileCarWash.CashFlow.Account do
      allow_nil?(true)
    end

    belongs_to :to_account, MobileCarWash.CashFlow.Account do
      allow_nil?(true)
    end
  end

  actions do
    defaults([:read])

    create :record do
      accept([:type, :amount_cents, :description, :from_account_id, :to_account_id, :occurred_at])
    end

    read :by_account do
      argument :account_id, :uuid do
        allow_nil?(false)
      end

      filter(expr(from_account_id == ^arg(:account_id) or to_account_id == ^arg(:account_id)))
    end
  end
end
