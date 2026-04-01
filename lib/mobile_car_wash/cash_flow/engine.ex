defmodule MobileCarWash.CashFlow.Engine do
  @moduledoc """
  Business logic for the cash flow system: threshold calculations and multi-account transfers.

  All public functions wrap their work in Repo.transaction for atomicity and call
  CashFlow.Broadcaster.broadcast_updated on success to notify LiveViews.
  """
  alias MobileCarWash.CashFlow
  alias MobileCarWash.CashFlow.{Account, Transaction, Broadcaster}
  alias MobileCarWash.Repo

  @doc """
  Fetch the singleton config record, creating it if missing.
  """
  def get_config! do
    CashFlow.get_config!()
  end

  @doc """
  Fetch all 5 accounts, sorted by a canonical order.
  """
  def get_all_accounts! do
    Account
    |> Ash.Query.sort(account_type: :asc)
    |> Ash.read!()
  end

  @doc """
  Compute expense and business savings thresholds from config.

  Returns: %{expense: integer, business_savings: integer}
  """
  def compute_thresholds(config) do
    expense_threshold = div(config.monthly_opex_cents * 125, 100)
    savings_threshold = expense_threshold * 4

    %{expense: expense_threshold, business_savings: savings_threshold}
  end

  @doc """
  Record income arriving in the Expense Account.
  Automatically cascades overflows to Tax Account and Business Savings.

  Returns: {:ok, map()} | {:error, term()}
  """
  def record_deposit(amount_cents, description) when is_integer(amount_cents) and amount_cents > 0 do
    Repo.transaction(fn ->
      # Deposit to Expense Account
      expense_acct = Ash.get!(Account, by_type(:expense))

      {:ok, _updated} =
        expense_acct
        |> Ash.Changeset.for_update(:deposit, %{amount_cents: amount_cents})
        |> Ash.update()

      # Record transaction
      {:ok, _txn} =
        Transaction
        |> Ash.Changeset.for_create(:record, %{
          type: :deposit,
          amount_cents: amount_cents,
          description: description,
          to_account_id: expense_acct.id,
          from_account_id: nil
        })
        |> Ash.create()

      # Check for overflow
      maybe_cascade_overflow()

      # Broadcast update
      Broadcaster.broadcast_updated()

      {:ok, "Deposit recorded"}
    end)
    |> case do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  def record_deposit(_amount, _description) do
    {:error, "Amount must be a positive integer in cents"}
  end

  @doc """
  Record an expense from the Expense Account.

  Returns: {:ok, map()} | {:error, :insufficient_funds} | {:error, term()}
  """
  def record_expense(amount_cents, description) when is_integer(amount_cents) and amount_cents > 0 do
    Repo.transaction(fn ->
      expense_acct = Ash.get!(Account, by_type(:expense))

      case expense_acct
           |> Ash.Changeset.for_update(:withdraw, %{amount_cents: amount_cents})
           |> Ash.update() do
        {:ok, _updated} ->
          # Record transaction
          {:ok, _txn} =
            Transaction
            |> Ash.Changeset.for_create(:record, %{
              type: :withdrawal,
              amount_cents: amount_cents,
              description: description,
              from_account_id: expense_acct.id,
              to_account_id: nil
            })
            |> Ash.create()

          Broadcaster.broadcast_updated()
          {:ok, "Expense recorded"}

        {:error, _} ->
          {:error, :insufficient_funds}
      end
    end)
    |> case do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  def record_expense(_amount, _description) do
    {:error, "Amount must be a positive integer in cents"}
  end

  @doc """
  Pay owner salary from Expense Account.
  Uses the salary_cents from config.

  Returns: {:ok, map()} | {:error, :insufficient_funds} | {:error, term()}
  """
  def pay_salary do
    Repo.transaction(fn ->
      config = CashFlow.get_config!()
      salary_amount = config.salary_cents

      if salary_amount <= 0 do
        {:error, "Salary not configured"}
      else
        expense_acct = Ash.get!(Account, by_type(:expense))
        personal_acct = Ash.get!(Account, by_type(:personal_salary))

        case expense_acct
             |> Ash.Changeset.for_update(:withdraw, %{amount_cents: salary_amount})
             |> Ash.update() do
          {:ok, _} ->
            {:ok, _} =
              personal_acct
              |> Ash.Changeset.for_update(:deposit, %{amount_cents: salary_amount})
              |> Ash.update()

            {:ok, _txn} =
              Transaction
              |> Ash.Changeset.for_create(:record, %{
                type: :salary_draw,
                amount_cents: salary_amount,
                description: "Owner salary draw",
                from_account_id: expense_acct.id,
                to_account_id: personal_acct.id
              })
              |> Ash.create()

            Broadcaster.broadcast_updated()
            {:ok, "Salary paid: $#{format_cents(salary_amount)}"}

          {:error, _} ->
            {:error, :insufficient_funds}
        end
      end
    end)
    |> case do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Manually transfer between any two accounts.

  Returns: {:ok, map()} | {:error, term()}
  """
  def manual_transfer(from_type, to_type, amount_cents, description)
      when is_atom(from_type) and is_atom(to_type) and is_integer(amount_cents) and amount_cents > 0 do
    Repo.transaction(fn ->
      from_acct = Ash.get!(Account, by_type(from_type))
      to_acct = Ash.get!(Account, by_type(to_type))

      case from_acct
           |> Ash.Changeset.for_update(:withdraw, %{amount_cents: amount_cents})
           |> Ash.update() do
        {:ok, _} ->
          {:ok, _} =
            to_acct
            |> Ash.Changeset.for_update(:deposit, %{amount_cents: amount_cents})
            |> Ash.update()

          {:ok, _txn} =
            Transaction
            |> Ash.Changeset.for_create(:record, %{
              type: :transfer,
              amount_cents: amount_cents,
              description: description,
              from_account_id: from_acct.id,
              to_account_id: to_acct.id
            })
            |> Ash.create()

          Broadcaster.broadcast_updated()

          # Check if transfer landed in Expense or Business Savings, and trigger cascade if needed
          if to_type in [:expense, :business_savings] do
            maybe_cascade_overflow()
          end

          {:ok, "Transfer recorded"}

        {:error, _} ->
          {:error, :insufficient_funds}
      end
    end)
    |> case do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  def manual_transfer(_from, _to, _amount, _desc) do
    {:error, "Invalid parameters"}
  end

  @doc """
  Update the config: monthly_opex_cents, salary_cents, investment_target_cents.

  Returns: {:ok, Config.t()} | {:error, term()}
  """
  def update_config(attrs) when is_map(attrs) do
    Repo.transaction(fn ->
      config = CashFlow.get_config!()

      config
      |> Ash.Changeset.for_update(:update_config, attrs)
      |> Ash.update()
    end)
    |> case do
      {:ok, config} ->
        Broadcaster.broadcast_updated()
        {:ok, config}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp by_type(type) when is_atom(type) do
    [account_type: type]
  end

  defp maybe_cascade_overflow do
    config = CashFlow.get_config!()
    thresholds = compute_thresholds(config)

    expense_acct = Ash.get!(Account, by_type(:expense))

    # Step 1: If expense > threshold, move excess to Tax + Business Savings
    if expense_acct.balance_cents > thresholds.expense do
      excess = expense_acct.balance_cents - thresholds.expense
      tax_share = div(excess, 2)
      savings_share = excess - tax_share

      # Move to Tax
      if tax_share > 0 do
        transfer_atomic(:expense, :tax, tax_share, :tax_reserve)
      end

      # Move to Business Savings
      if savings_share > 0 do
        transfer_atomic(:expense, :business_savings, savings_share, :savings_overflow)
      end
    end

    # Step 2: Re-fetch savings, check if it exceeds threshold
    savings_acct = Ash.get!(Account, by_type(:business_savings))

    if savings_acct.balance_cents > thresholds.business_savings do
      savings_excess = savings_acct.balance_cents - thresholds.business_savings
      transfer_atomic(:business_savings, :investment, savings_excess, :savings_overflow)
    end
  end

  defp transfer_atomic(from_type, to_type, amount_cents, txn_type) do
    from_acct = Ash.get!(Account, by_type(from_type))
    to_acct = Ash.get!(Account, by_type(to_type))

    # Guard: check that from_acct has sufficient balance
    if from_acct.balance_cents < amount_cents do
      raise "Insufficient funds in #{from_type} account"
    end

    {:ok, _} =
      from_acct
      |> Ash.Changeset.for_update(:adjust_balance, %{
        balance_cents: from_acct.balance_cents - amount_cents
      })
      |> Ash.update()

    {:ok, _} =
      to_acct
      |> Ash.Changeset.for_update(:adjust_balance, %{
        balance_cents: to_acct.balance_cents + amount_cents
      })
      |> Ash.update()

    {:ok, _} =
      Transaction
      |> Ash.Changeset.for_create(:record, %{
        type: txn_type,
        amount_cents: amount_cents,
        from_account_id: from_acct.id,
        to_account_id: to_acct.id,
        description: "Automatic cascade transfer"
      })
      |> Ash.create()
  end

  defp format_cents(cents) when is_integer(cents) do
    dollars = div(cents, 100)
    remainder = rem(cents, 100)
    "#{dollars}.#{String.pad_leading("#{remainder}", 2, "0")}"
  end
end
