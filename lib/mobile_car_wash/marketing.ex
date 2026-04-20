defmodule MobileCarWash.Marketing do
  @moduledoc """
  Marketing domain — acquisition channels, spend, and CAC rollups.

  Phase 1 (this slice): AcquisitionChannel resource + seed helper.
  Later phases: MarketingSpend, Marketing.CAC query module, admin
  dashboard, UTM-capture plug, referral unification.
  """
  use Ash.Domain

  require Ash.Query

  alias MobileCarWash.Marketing.{
    AcquisitionChannel,
    CustomerTag,
    MarketingSpend,
    Persona,
    PersonaMembership,
    Post,
    Tag
  }

  resources do
    resource(AcquisitionChannel)
    resource(CustomerTag)
    resource(MarketingSpend)
    resource(Persona)
    resource(PersonaMembership)
    resource(Post)
    resource(Tag)
  end

  @canonical_channels [
    %{slug: "google_organic", display_name: "Google Organic", category: :organic, sort_order: 10},
    %{slug: "google_paid", display_name: "Google Ads", category: :paid, sort_order: 20},
    %{
      slug: "meta_paid",
      display_name: "Meta (Facebook + Instagram)",
      category: :paid,
      sort_order: 30
    },
    %{slug: "nextdoor", display_name: "Nextdoor", category: :paid, sort_order: 40},
    %{slug: "referral", display_name: "Referral", category: :referral, sort_order: 50},
    %{slug: "word_of_mouth", display_name: "Word of Mouth", category: :offline, sort_order: 60},
    %{
      slug: "door_hangers",
      display_name: "Door Hangers / Flyers",
      category: :offline,
      sort_order: 70
    },
    %{
      slug: "pre_launch",
      display_name: "Pre-Launch (Legacy)",
      category: :unknown,
      sort_order: 900
    },
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

  @canonical_tags [
    %{
      slug: "vip",
      name: "VIP",
      description: "Top lifetime value — white-glove service.",
      color: :success,
      icon: "hero-star",
      protected: true
    },
    %{
      slug: "at_risk",
      name: "At Risk",
      description: "Hasn't booked recently or flagged for retention follow-up.",
      color: :warning,
      icon: "hero-exclamation-triangle",
      protected: true
    },
    %{
      slug: "do_not_service",
      name: "Do Not Service",
      description: "Do not accept new bookings. Non-payment, abuse, or other operational block.",
      color: :error,
      icon: "hero-no-symbol",
      affects_booking: true,
      protected: true
    },
    %{
      slug: "complaint_pending",
      name: "Open Complaint",
      description: "Active complaint in resolution.",
      color: :warning,
      icon: "hero-chat-bubble-bottom-center-text",
      protected: true
    },
    %{
      slug: "referrer",
      name: "Referrer",
      description: "Brought in ≥1 paying friend.",
      color: :info,
      icon: "hero-gift"
    },
    %{
      slug: "veteran",
      name: "Veteran",
      description: "Fellow service member — noted for rapport.",
      color: :primary,
      icon: "hero-flag"
    }
  ]

  @doc """
  Idempotently inserts the canonical tags. Safe to re-run — uses the
  `:unique_slug` identity so existing rows keep admin edits
  (description, color, active).
  """
  @spec seed_tags!() :: :ok
  def seed_tags! do
    Enum.each(@canonical_tags, fn attrs ->
      attrs = Map.put_new(attrs, :affects_booking, false)

      case Ash.read_one(
             Ash.Query.for_read(MobileCarWash.Marketing.Tag, :by_slug, %{slug: attrs.slug}),
             authorize?: false
           ) do
        {:ok, nil} ->
          MobileCarWash.Marketing.Tag
          |> Ash.Changeset.for_create(:create, attrs)
          |> Ash.create!(authorize?: false)

        {:ok, _existing} ->
          :ok
      end
    end)

    :ok
  end

  @doc """
  Sum of all MarketingSpend rows whose spent_on falls within [from, to].
  Range is inclusive on both ends.
  """
  @spec total_spend_cents_in_range(Date.t(), Date.t()) :: non_neg_integer()
  def total_spend_cents_in_range(from, to) do
    MarketingSpend
    |> Ash.Query.for_read(:in_range, %{from: from, to: to})
    |> Ash.read!(authorize?: false)
    |> Enum.reduce(0, fn spend, acc -> acc + spend.amount_cents end)
  end

  @doc """
  Per-channel spend totals for [from, to]. Returns a map of
  channel_id (UUID string) => cents.
  """
  @spec spend_cents_by_channel_in_range(Date.t(), Date.t()) :: %{binary() => non_neg_integer()}
  def spend_cents_by_channel_in_range(from, to) do
    MarketingSpend
    |> Ash.Query.for_read(:in_range, %{from: from, to: to})
    |> Ash.read!(authorize?: false)
    |> Enum.group_by(& &1.channel_id)
    |> Map.new(fn {cid, rows} ->
      {cid, Enum.reduce(rows, 0, fn r, acc -> acc + r.amount_cents end)}
    end)
  end
end
