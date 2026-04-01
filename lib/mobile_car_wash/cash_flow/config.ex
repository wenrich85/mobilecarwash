defmodule MobileCarWash.CashFlow.Config do
  @moduledoc """
  Singleton configuration record for cash flow system settings.

  Only one row should ever exist. Contains:
  - monthly_opex_cents: Used to calculate expense account threshold (opex * 1.25)
  - salary_cents: Amount to draw when paying owner salary
  - investment_target_cents: Target balance for investment account (displayed but not enforced as hard threshold)
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.CashFlow,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "cash_flow_config"
    repo MobileCarWash.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :monthly_opex_cents, :integer do
      allow_nil? false
      default 0
    end

    attribute :salary_cents, :integer do
      allow_nil? false
      default 0
    end

    attribute :investment_target_cents, :integer do
      allow_nil? false
      default 0
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  actions do
    defaults [:read]

    create :create do
      accept [:monthly_opex_cents, :salary_cents, :investment_target_cents]
    end

    update :update_config do
      accept [:monthly_opex_cents, :salary_cents, :investment_target_cents]
    end
  end
end
