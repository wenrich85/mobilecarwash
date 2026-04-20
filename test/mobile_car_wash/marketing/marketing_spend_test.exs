defmodule MobileCarWash.Marketing.MarketingSpendTest do
  @moduledoc """
  Marketing Phase 1 / Slice 2: MarketingSpend lets the admin enter
  ad spend per channel per day. Drives the denominator of every CAC
  calculation in Slice 4.

  Contract pinned here:
    * `:record` action creates a row given channel_id + spent_on + amount_cents
    * amount_cents is a non-negative integer
    * `:in_range` read filters by spent_on date range
    * `:by_channel` read filters by channel_id
    * `Marketing.total_spend_cents_in_range/2` sums across all channels
    * `Marketing.spend_cents_by_channel_in_range/2` returns a
      `channel_id => cents` map
  """
  use MobileCarWash.DataCase, async: false

  alias MobileCarWash.Marketing
  alias MobileCarWash.Marketing.{AcquisitionChannel, MarketingSpend}

  setup do
    :ok = Marketing.seed_channels!()

    {:ok, [meta]} =
      AcquisitionChannel
      |> Ash.Query.for_read(:by_slug, %{slug: "meta_paid"})
      |> Ash.read(authorize?: false)

    {:ok, [google]} =
      AcquisitionChannel
      |> Ash.Query.for_read(:by_slug, %{slug: "google_paid"})
      |> Ash.read(authorize?: false)

    %{meta: meta, google: google}
  end

  describe ":record create action" do
    test "persists a spend row", %{meta: meta} do
      {:ok, spend} =
        MarketingSpend
        |> Ash.Changeset.for_create(:record, %{
          channel_id: meta.id,
          spent_on: ~D[2026-04-22],
          amount_cents: 5_000,
          notes: "Saturday boost"
        })
        |> Ash.create(authorize?: false)

      assert spend.amount_cents == 5_000
      assert spend.spent_on == ~D[2026-04-22]
      assert spend.channel_id == meta.id
      assert spend.notes == "Saturday boost"
    end

    test "rejects a negative amount", %{meta: meta} do
      {:error, _} =
        MarketingSpend
        |> Ash.Changeset.for_create(:record, %{
          channel_id: meta.id,
          spent_on: ~D[2026-04-22],
          amount_cents: -100
        })
        |> Ash.create(authorize?: false)
    end

    test "requires channel_id, spent_on, amount_cents" do
      {:error, _} =
        MarketingSpend
        |> Ash.Changeset.for_create(:record, %{})
        |> Ash.create(authorize?: false)
    end
  end

  describe ":in_range read" do
    test "returns only rows whose spent_on falls within [from, to]",
         %{meta: meta} do
      Enum.each(
        [~D[2026-03-30], ~D[2026-04-05], ~D[2026-04-10], ~D[2026-04-25]],
        fn date ->
          MarketingSpend
          |> Ash.Changeset.for_create(:record, %{
            channel_id: meta.id,
            spent_on: date,
            amount_cents: 1_000
          })
          |> Ash.create!(authorize?: false)
        end
      )

      {:ok, rows} =
        MarketingSpend
        |> Ash.Query.for_read(:in_range, %{from: ~D[2026-04-01], to: ~D[2026-04-20]})
        |> Ash.read(authorize?: false)

      dates = Enum.map(rows, & &1.spent_on)
      assert ~D[2026-04-05] in dates
      assert ~D[2026-04-10] in dates
      refute ~D[2026-03-30] in dates
      refute ~D[2026-04-25] in dates
    end
  end

  describe ":by_channel read" do
    test "filters by channel_id", %{meta: meta, google: google} do
      MarketingSpend
      |> Ash.Changeset.for_create(:record, %{
        channel_id: meta.id,
        spent_on: ~D[2026-04-10],
        amount_cents: 2_000
      })
      |> Ash.create!(authorize?: false)

      MarketingSpend
      |> Ash.Changeset.for_create(:record, %{
        channel_id: google.id,
        spent_on: ~D[2026-04-10],
        amount_cents: 3_000
      })
      |> Ash.create!(authorize?: false)

      {:ok, rows} =
        MarketingSpend
        |> Ash.Query.for_read(:by_channel, %{channel_id: meta.id})
        |> Ash.read(authorize?: false)

      assert length(rows) == 1
      assert hd(rows).channel_id == meta.id
    end
  end

  describe "Marketing.total_spend_cents_in_range/2" do
    test "sums amount_cents across all channels in the range",
         %{meta: meta, google: google} do
      for {channel, date, amt} <- [
            {meta, ~D[2026-04-05], 1_000},
            {meta, ~D[2026-04-10], 2_000},
            {google, ~D[2026-04-15], 3_000},
            # Out-of-range row — must not be counted.
            {google, ~D[2026-05-01], 999_999}
          ] do
        MarketingSpend
        |> Ash.Changeset.for_create(:record, %{
          channel_id: channel.id,
          spent_on: date,
          amount_cents: amt
        })
        |> Ash.create!(authorize?: false)
      end

      total = Marketing.total_spend_cents_in_range(~D[2026-04-01], ~D[2026-04-30])
      assert total == 6_000
    end

    test "returns 0 when no rows exist in the range" do
      assert Marketing.total_spend_cents_in_range(~D[2026-04-01], ~D[2026-04-30]) == 0
    end
  end

  describe "Marketing.spend_cents_by_channel_in_range/2" do
    test "returns channel_id => cents map", %{meta: meta, google: google} do
      for {channel, date, amt} <- [
            {meta, ~D[2026-04-05], 1_000},
            {meta, ~D[2026-04-10], 2_000},
            {google, ~D[2026-04-15], 3_000}
          ] do
        MarketingSpend
        |> Ash.Changeset.for_create(:record, %{
          channel_id: channel.id,
          spent_on: date,
          amount_cents: amt
        })
        |> Ash.create!(authorize?: false)
      end

      by_channel =
        Marketing.spend_cents_by_channel_in_range(~D[2026-04-01], ~D[2026-04-30])

      assert by_channel[meta.id] == 3_000
      assert by_channel[google.id] == 3_000
    end
  end
end
