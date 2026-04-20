defmodule MobileCarWash.Marketing do
  @moduledoc """
  Marketing domain — acquisition channels, spend, and CAC rollups.

  Phase 1 (this slice): AcquisitionChannel resource + seed helper.
  Later phases: MarketingSpend, Marketing.CAC query module, admin
  dashboard, UTM-capture plug, referral unification.
  """
  use Ash.Domain

  alias MobileCarWash.Marketing.AcquisitionChannel

  resources do
    resource AcquisitionChannel
  end

  @canonical_channels [
    %{slug: "google_organic", display_name: "Google Organic", category: :organic, sort_order: 10},
    %{slug: "google_paid", display_name: "Google Ads", category: :paid, sort_order: 20},
    %{slug: "meta_paid", display_name: "Meta (Facebook + Instagram)", category: :paid, sort_order: 30},
    %{slug: "nextdoor", display_name: "Nextdoor", category: :paid, sort_order: 40},
    %{slug: "referral", display_name: "Referral", category: :referral, sort_order: 50},
    %{slug: "word_of_mouth", display_name: "Word of Mouth", category: :offline, sort_order: 60},
    %{slug: "door_hangers", display_name: "Door Hangers / Flyers", category: :offline, sort_order: 70},
    %{slug: "pre_launch", display_name: "Pre-Launch (Legacy)", category: :unknown, sort_order: 900},
    %{slug: "unknown", display_name: "Unknown", category: :unknown, sort_order: 999}
  ]

  @doc """
  Idempotently inserts the canonical channels. Safe to re-run — uses
  upsert on the `:slug` identity so re-running never duplicates rows
  and existing rows keep their admin-edited `display_name`/`active`
  values.
  """
  @spec seed_channels!() :: :ok
  def seed_channels! do
    Enum.each(@canonical_channels, fn attrs ->
      case Ash.read_one(
             Ash.Query.for_read(AcquisitionChannel, :by_slug, %{slug: attrs.slug}),
             authorize?: false
           ) do
        {:ok, nil} ->
          AcquisitionChannel
          |> Ash.Changeset.for_create(:create, attrs)
          |> Ash.create!(authorize?: false)

        {:ok, _existing} ->
          :ok
      end
    end)

    :ok
  end

  @doc "Canonical channel slug → used by plugs / changes to derive acquired_channel_id."
  @spec canonical_slugs() :: [String.t()]
  def canonical_slugs, do: Enum.map(@canonical_channels, & &1.slug)
end
