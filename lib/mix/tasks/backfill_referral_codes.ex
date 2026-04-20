defmodule Mix.Tasks.BackfillReferralCodes do
  @moduledoc """
  One-time backfill: mint a `referral_code` for every Customer row
  that's missing one (i.e. accounts created before migration
  20260405195018 added the column).

  `Referrals.share_link_for/1` handles the nil case lazily on first
  access, so running this isn't strictly required — but it's cheaper
  to do it once at maintenance time than to pay a write during a GET
  request on /appointments.

  Run with:

      mix backfill_referral_codes

  Safe to re-run — rows that already have a code are skipped.
  """
  use Mix.Task

  @shortdoc "Backfill referral_code for legacy customer rows"

  alias MobileCarWash.Accounts.Customer

  require Ash.Query

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    missing =
      Customer
      |> Ash.Query.filter(is_nil(referral_code))
      |> Ash.read!(authorize?: false)

    if missing == [] do
      IO.puts("All customers already have a referral_code. Nothing to do.")
    else
      IO.puts("Backfilling #{length(missing)} customer(s)…")

      {ok, err} =
        Enum.reduce(missing, {0, 0}, fn customer, {ok, err} ->
          case update_with_code(customer) do
            {:ok, updated} ->
              IO.puts("  ✓ #{customer.email} → #{updated.referral_code}")
              {ok + 1, err}

            {:error, reason} ->
              IO.puts("  ✗ #{customer.email}: #{inspect(reason)}")
              {ok, err + 1}
          end
        end)

      IO.puts("\nDone. #{ok} updated, #{err} failed.")
    end
  end

  defp update_with_code(customer) do
    customer
    |> Ash.Changeset.for_update(:update, %{})
    |> Ash.Changeset.force_change_attribute(:referral_code, generate_code())
    |> Ash.update(authorize?: false)
  end

  # Same recipe the Customer resource uses on create — kept in sync
  # deliberately since the format matters for URL encoding.
  defp generate_code do
    :crypto.strong_rand_bytes(5)
    |> Base.encode32(padding: false)
    |> String.slice(0, 8)
  end
end
