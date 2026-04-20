defmodule MobileCarWash.Marketing.AcquisitionChannelTest do
  @moduledoc """
  Marketing Phase 1 / Slice 1: the AcquisitionChannel resource is the
  canonical list of places customers come from ("Google Organic",
  "Meta Paid", "Referral", etc.). It anchors every downstream query
  (spend rollups, CAC per channel, retroactive word-of-mouth tagging).

  Contract pinned here:
    * slug is unique + required
    * display_name is required
    * category is one of :paid / :organic / :referral / :offline / :unknown
    * `active` filter action only returns active rows
    * seeding produces the six canonical + two bookkeeping channels
      (pre_launch, unknown) — drives the migration's backfill step
  """
  use MobileCarWash.DataCase, async: false

  alias MobileCarWash.Marketing
  alias MobileCarWash.Marketing.AcquisitionChannel

  describe "create" do
    test "persists a channel with valid attributes" do
      {:ok, chan} =
        AcquisitionChannel
        |> Ash.Changeset.for_create(:create, %{
          slug: "google_organic",
          display_name: "Google Organic",
          category: :organic,
          sort_order: 10
        })
        |> Ash.create(authorize?: false)

      assert chan.slug == "google_organic"
      assert chan.display_name == "Google Organic"
      assert chan.category == :organic
      assert chan.active == true
    end

    test "rejects an invalid category" do
      {:error, _} =
        AcquisitionChannel
        |> Ash.Changeset.for_create(:create, %{
          slug: "bogus",
          display_name: "Bogus",
          category: :not_a_real_category
        })
        |> Ash.create(authorize?: false)
    end

    test "enforces unique slug" do
      {:ok, _} =
        AcquisitionChannel
        |> Ash.Changeset.for_create(:create, %{
          slug: "dupe",
          display_name: "Dupe",
          category: :paid
        })
        |> Ash.create(authorize?: false)

      {:error, _} =
        AcquisitionChannel
        |> Ash.Changeset.for_create(:create, %{
          slug: "dupe",
          display_name: "Dupe Again",
          category: :paid
        })
        |> Ash.create(authorize?: false)
    end

    test "slug and display_name are required" do
      {:error, _} =
        AcquisitionChannel
        |> Ash.Changeset.for_create(:create, %{category: :paid})
        |> Ash.create(authorize?: false)
    end
  end

  describe ":active read" do
    test "returns only channels with active == true" do
      {:ok, _on} =
        AcquisitionChannel
        |> Ash.Changeset.for_create(:create, %{
          slug: "live",
          display_name: "Live",
          category: :paid
        })
        |> Ash.create(authorize?: false)

      {:ok, _off} =
        AcquisitionChannel
        |> Ash.Changeset.for_create(:create, %{
          slug: "retired",
          display_name: "Retired",
          category: :paid,
          active: false
        })
        |> Ash.create(authorize?: false)

      slugs =
        AcquisitionChannel
        |> Ash.Query.for_read(:active)
        |> Ash.read!(authorize?: false)
        |> Enum.map(& &1.slug)

      assert "live" in slugs
      refute "retired" in slugs
    end
  end

  describe ":by_slug read" do
    test "fetches a single channel by its slug" do
      {:ok, _} =
        AcquisitionChannel
        |> Ash.Changeset.for_create(:create, %{
          slug: "referral",
          display_name: "Referral",
          category: :referral
        })
        |> Ash.create(authorize?: false)

      {:ok, [chan]} =
        AcquisitionChannel
        |> Ash.Query.for_read(:by_slug, %{slug: "referral"})
        |> Ash.read(authorize?: false)

      assert chan.slug == "referral"
      assert chan.category == :referral
    end
  end

  describe "Marketing.seed_channels!/0" do
    test "seeds the canonical + bookkeeping channels idempotently" do
      assert :ok = Marketing.seed_channels!()

      slugs =
        AcquisitionChannel
        |> Ash.read!(authorize?: false)
        |> Enum.map(& &1.slug)
        |> MapSet.new()

      for expected <- ~w(google_organic meta_paid google_paid referral word_of_mouth nextdoor door_hangers pre_launch unknown) do
        assert expected in slugs, "missing canonical channel: #{expected}"
      end

      # Running again shouldn't duplicate rows.
      count_before = AcquisitionChannel |> Ash.read!(authorize?: false) |> length()
      assert :ok = Marketing.seed_channels!()
      count_after = AcquisitionChannel |> Ash.read!(authorize?: false) |> length()

      assert count_before == count_after
    end

    test "the referral channel has category :referral" do
      :ok = Marketing.seed_channels!()

      {:ok, [referral]} =
        AcquisitionChannel
        |> Ash.Query.for_read(:by_slug, %{slug: "referral"})
        |> Ash.read(authorize?: false)

      assert referral.category == :referral
    end
  end
end
