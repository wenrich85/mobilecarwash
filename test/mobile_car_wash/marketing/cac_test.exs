defmodule MobileCarWash.Marketing.CACTest do
  @moduledoc """
  Marketing Phase 1 / Slice 4: per-channel CAC + lifetime revenue
  rollup. Feeds the /admin/marketing dashboard.

  Per channel, within a [from, to] window:
    * spend_cents — sum of MarketingSpend rows
    * new_customers — count of customers whose acquired_at falls in
      the window AND acquired_channel_id points here
    * cac_cents — spend / new_customers (nil if 0 customers)
    * revenue_cents — sum of succeeded Payments from those new
      customers (lifetime — we include all their payments to date,
      not just the window)
    * avg_revenue_cents — revenue / customers
    * roi_pct — 100 * (revenue - spend) / spend (nil if spend 0)
  """
  use MobileCarWash.DataCase, async: false

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Billing.Payment
  alias MobileCarWash.Marketing
  alias MobileCarWash.Marketing.{AcquisitionChannel, CAC, MarketingSpend}

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

    {:ok, [referral]} =
      AcquisitionChannel
      |> Ash.Query.for_read(:by_slug, %{slug: "referral"})
      |> Ash.read(authorize?: false)

    %{meta: meta, google: google, referral: referral}
  end

  defp make_customer!(email_suffix, channel_id, acquired_at) do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "cac-#{email_suffix}-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "CAC #{email_suffix}",
        phone: "+15125559#{:rand.uniform(999) |> Integer.to_string() |> String.pad_leading(3, "0")}",
        acquired_at: acquired_at,
        acquired_channel_id: channel_id
      })
      |> Ash.create()

    customer
  end

  defp record_spend!(channel_id, date, cents) do
    MarketingSpend
    |> Ash.Changeset.for_create(:record, %{
      channel_id: channel_id,
      spent_on: date,
      amount_cents: cents
    })
    |> Ash.create!(authorize?: false)
  end

  defp pay!(customer, cents) do
    Payment
    |> Ash.Changeset.for_create(:create, %{
      amount_cents: cents,
      stripe_payment_intent_id: "pi_cac_#{System.unique_integer([:positive])}"
    })
    |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
    |> Ash.Changeset.force_change_attribute(:status, :succeeded)
    |> Ash.create!(authorize?: false)
  end

  describe "per_channel/2" do
    test "computes spend, new customers, CAC, revenue, ROI for each channel",
         %{meta: meta, google: google, referral: referral} do
      from = ~D[2026-04-01]
      to = ~D[2026-04-30]

      # Meta: $100 spend, 2 new customers, each paid $50 lifetime
      record_spend!(meta.id, ~D[2026-04-10], 10_000)
      m1 = make_customer!("m1", meta.id, ~U[2026-04-05 12:00:00Z])
      m2 = make_customer!("m2", meta.id, ~U[2026-04-15 12:00:00Z])
      pay!(m1, 5_000)
      pay!(m2, 5_000)

      # Google: $200 spend, 1 new customer, $150 revenue
      record_spend!(google.id, ~D[2026-04-12], 20_000)
      g1 = make_customer!("g1", google.id, ~U[2026-04-20 12:00:00Z])
      pay!(g1, 15_000)

      # Referral: 0 spend, 3 new customers, $90 total revenue
      r1 = make_customer!("r1", referral.id, ~U[2026-04-02 12:00:00Z])
      r2 = make_customer!("r2", referral.id, ~U[2026-04-08 12:00:00Z])
      r3 = make_customer!("r3", referral.id, ~U[2026-04-25 12:00:00Z])
      pay!(r1, 3_000)
      pay!(r2, 3_000)
      pay!(r3, 3_000)

      # Out-of-window customer on Meta (should NOT count)
      oob = make_customer!("oob", meta.id, ~U[2026-05-05 12:00:00Z])
      pay!(oob, 999_999)

      rows = CAC.per_channel(from, to)
      by_id = Map.new(rows, &{&1.channel_id, &1})

      meta_row = by_id[meta.id]
      assert meta_row.spend_cents == 10_000
      assert meta_row.new_customers == 2
      assert meta_row.cac_cents == 5_000
      assert meta_row.revenue_cents == 10_000
      assert meta_row.avg_revenue_cents == 5_000
      assert meta_row.roi_pct == 0

      google_row = by_id[google.id]
      assert google_row.spend_cents == 20_000
      assert google_row.new_customers == 1
      assert google_row.cac_cents == 20_000
      assert google_row.revenue_cents == 15_000
      # ROI = (15000-20000)/20000 * 100 = -25
      assert google_row.roi_pct == -25

      referral_row = by_id[referral.id]
      assert referral_row.spend_cents == 0
      assert referral_row.new_customers == 3
      # CAC nil for zero-spend channels
      assert referral_row.cac_cents == nil
      assert referral_row.revenue_cents == 9_000
      assert referral_row.avg_revenue_cents == 3_000
      # ROI nil because spend is 0
      assert referral_row.roi_pct == nil
    end

    test "returns zero-row entries for channels with no activity",
         %{meta: meta} do
      from = ~D[2026-04-01]
      to = ~D[2026-04-30]

      rows = CAC.per_channel(from, to)
      meta_row = Enum.find(rows, &(&1.channel_id == meta.id))

      assert meta_row.spend_cents == 0
      assert meta_row.new_customers == 0
      assert meta_row.cac_cents == nil
      assert meta_row.revenue_cents == 0
      assert meta_row.roi_pct == nil
    end

    test "each row includes channel_slug + category for the dashboard",
         %{meta: meta} do
      rows = CAC.per_channel(~D[2026-04-01], ~D[2026-04-30])
      meta_row = Enum.find(rows, &(&1.channel_id == meta.id))

      assert meta_row.channel_slug == "meta_paid"
      assert meta_row.channel_name == "Meta (Facebook + Instagram)"
      assert meta_row.category == :paid
    end
  end

  describe "summary/2" do
    test "returns blended KPIs across all channels", %{meta: meta, referral: referral} do
      from = ~D[2026-04-01]
      to = ~D[2026-04-30]

      record_spend!(meta.id, ~D[2026-04-10], 10_000)
      m1 = make_customer!("m1", meta.id, ~U[2026-04-05 12:00:00Z])
      pay!(m1, 15_000)

      r1 = make_customer!("r1", referral.id, ~U[2026-04-02 12:00:00Z])
      pay!(r1, 2_000)

      s = CAC.summary(from, to)
      assert s.total_spend_cents == 10_000
      # 2 new customers total
      assert s.new_customers == 2
      # blended CAC = spend / total new = 10000/2 = 5000
      assert s.blended_cac_cents == 5_000
      # total revenue = 15000 + 2000 = 17000
      assert s.total_revenue_cents == 17_000
    end

    test "blended CAC is nil when no new customers" do
      s = CAC.summary(~D[2026-04-01], ~D[2026-04-30])
      assert s.new_customers == 0
      assert s.blended_cac_cents == nil
    end
  end
end
