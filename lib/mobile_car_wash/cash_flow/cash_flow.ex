defmodule MobileCarWash.CashFlow do
  @moduledoc """
  Ash Domain for the cash flow management system.
  Registers all cash flow resources: Account, Transaction, Config.
  """
  use Ash.Domain

  resources do
    resource MobileCarWash.CashFlow.Account
    resource MobileCarWash.CashFlow.Transaction
    resource MobileCarWash.CashFlow.Config
  end

  @doc """
  Get or create the singleton config record.
  Returns the single config row, creating one with zero defaults if it doesn't exist.
  """
  def get_config! do
    case Ash.read_one(MobileCarWash.CashFlow.Config) do
      {:ok, config} when not is_nil(config) ->
        config

      _ ->
        # Create default config if none exists
        {:ok, config} =
          MobileCarWash.CashFlow.Config
          |> Ash.Changeset.for_create(:create, %{
            monthly_opex_cents: 0,
            salary_cents: 0,
            investment_target_cents: 0
          })
          |> Ash.create()

        config
    end
  end
end
