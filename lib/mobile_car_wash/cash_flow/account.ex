defmodule MobileCarWash.CashFlow.Account do
  @moduledoc """
  Represents one of the 5 cash flow buckets: Expense, Tax, Business Savings, Investment, Personal Salary.

  Each account has a balance that changes via :deposit and :withdraw actions.
  The account_type is unique (enforced by identity) — exactly 5 rows will exist at startup.
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.CashFlow,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("cash_flow_accounts")
    repo(MobileCarWash.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :account_type, :atom do
      constraints(one_of: [:expense, :tax, :business_savings, :investment, :personal_salary])
      allow_nil?(false)
    end

    attribute :name, :string do
      allow_nil?(false)
    end

    attribute :balance_cents, :integer do
      default(0)
      allow_nil?(false)
    end

    attribute :color, :atom do
      constraints(one_of: [:blue, :red, :green])
      allow_nil?(false)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  identities do
    identity(:unique_type, [:account_type])
  end

  actions do
    defaults([:read])

    create :create do
      accept([:account_type, :name, :balance_cents, :color])
    end

    update :adjust_balance do
      require_atomic?(false)
      accept([:balance_cents])

      validate(fn changeset, _ ->
        balance = Ash.Changeset.get_attribute(changeset, :balance_cents)

        if balance && balance >= 0 do
          :ok
        else
          {:error, field: :balance_cents, message: "account balance cannot be negative"}
        end
      end)
    end

    update :deposit do
      argument :amount_cents, :integer do
        allow_nil?(false)
      end

      change(atomic_update(:balance_cents, expr(balance_cents + ^arg(:amount_cents))))
    end

    update :withdraw do
      require_atomic?(false)

      argument :amount_cents, :integer do
        allow_nil?(false)
      end

      validate(fn changeset, _ ->
        current = changeset.data.balance_cents
        amount = Ash.Changeset.get_argument(changeset, :amount_cents)

        if current >= amount do
          :ok
        else
          {:error, field: :amount_cents, message: "insufficient funds"}
        end
      end)

      change(atomic_update(:balance_cents, expr(balance_cents - ^arg(:amount_cents))))
    end
  end
end
