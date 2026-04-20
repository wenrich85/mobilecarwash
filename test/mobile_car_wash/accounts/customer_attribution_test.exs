defmodule MobileCarWash.Accounts.CustomerAttributionTest do
  @moduledoc """
  Marketing Phase 1 / Slice 3: every new Customer carries a
  first-touch attribution stamp. These tests pin the contract between
  the UTM-capture plug and the Customer resource.

  Pinned behavior:
    * Customer has utm_source / utm_medium / utm_campaign / utm_content
      / referrer / acquired_at / acquired_channel_id attributes
    * register_with_password accepts all of them
    * create_guest accepts all of them
    * When no acquired_channel_id is supplied, we derive one:
        - referred_by_id present  → referral channel
        - utm_medium in [cpc, paid_social, paid]  → google_paid or meta_paid
          (based on utm_source)
        - utm_medium in [organic, search]  → google_organic
        - else                    → unknown
    * acquired_at defaults to the create timestamp when not supplied
  """
  use MobileCarWash.DataCase, async: false

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Marketing
  alias MobileCarWash.Marketing.AcquisitionChannel

  setup do
    :ok = Marketing.seed_channels!()
    :ok
  end

  defp channel_by_slug!(slug) do
    {:ok, [chan]} =
      AcquisitionChannel
      |> Ash.Query.for_read(:by_slug, %{slug: slug})
      |> Ash.read(authorize?: false)

    chan
  end

  describe "register_with_password attribution" do
    test "persists UTM fields supplied at registration" do
      {:ok, c} =
        Customer
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "utm-#{System.unique_integer([:positive])}@test.com",
          password: "Password123!",
          password_confirmation: "Password123!",
          name: "UTM Test",
          phone: "+15125550001",
          utm_source: "meta",
          utm_medium: "cpc",
          utm_campaign: "spring_2026",
          utm_content: "ad_variant_a",
          referrer: "https://facebook.com/"
        })
        |> Ash.create()

      assert c.utm_source == "meta"
      assert c.utm_medium == "cpc"
      assert c.utm_campaign == "spring_2026"
      assert c.utm_content == "ad_variant_a"
      assert c.referrer == "https://facebook.com/"
      assert c.acquired_at != nil
    end

    test "derives :meta_paid from utm_source=meta + utm_medium=cpc" do
      meta = channel_by_slug!("meta_paid")

      {:ok, c} =
        Customer
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "derive-meta-#{System.unique_integer([:positive])}@test.com",
          password: "Password123!",
          password_confirmation: "Password123!",
          name: "Derive Meta",
          phone: "+15125550002",
          utm_source: "meta",
          utm_medium: "cpc"
        })
        |> Ash.create()

      assert c.acquired_channel_id == meta.id
    end

    test "derives :google_paid from utm_source=google + utm_medium=cpc" do
      google_paid = channel_by_slug!("google_paid")

      {:ok, c} =
        Customer
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "derive-gp-#{System.unique_integer([:positive])}@test.com",
          password: "Password123!",
          password_confirmation: "Password123!",
          name: "Derive Google Paid",
          phone: "+15125550003",
          utm_source: "google",
          utm_medium: "cpc"
        })
        |> Ash.create()

      assert c.acquired_channel_id == google_paid.id
    end

    test "derives :google_organic from utm_medium=organic" do
      google_organic = channel_by_slug!("google_organic")

      {:ok, c} =
        Customer
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "derive-go-#{System.unique_integer([:positive])}@test.com",
          password: "Password123!",
          password_confirmation: "Password123!",
          name: "Derive Organic",
          phone: "+15125550004",
          utm_source: "google",
          utm_medium: "organic"
        })
        |> Ash.create()

      assert c.acquired_channel_id == google_organic.id
    end

    test "derives :referral when referred_by_id is set (beats UTM)" do
      referral = channel_by_slug!("referral")

      {:ok, referrer} =
        Customer
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "ref-src-#{System.unique_integer([:positive])}@test.com",
          password: "Password123!",
          password_confirmation: "Password123!",
          name: "Referrer",
          phone: "+15125550005"
        })
        |> Ash.create()

      {:ok, c} =
        Customer
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "ref-dest-#{System.unique_integer([:positive])}@test.com",
          password: "Password123!",
          password_confirmation: "Password123!",
          name: "Referred",
          phone: "+15125550006",
          # Even though UTMs are present, referral should win.
          utm_source: "meta",
          utm_medium: "cpc"
        })
        |> Ash.Changeset.force_change_attribute(:referred_by_id, referrer.id)
        |> Ash.create()

      assert c.acquired_channel_id == referral.id
    end

    test "falls back to :unknown when no signals are present" do
      unknown = channel_by_slug!("unknown")

      {:ok, c} =
        Customer
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "unknown-#{System.unique_integer([:positive])}@test.com",
          password: "Password123!",
          password_confirmation: "Password123!",
          name: "Unknown",
          phone: "+15125550007"
        })
        |> Ash.create()

      assert c.acquired_channel_id == unknown.id
    end

    test "respects an explicit acquired_channel_id (admin manual tag)" do
      door = channel_by_slug!("door_hangers")

      {:ok, c} =
        Customer
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "explicit-#{System.unique_integer([:positive])}@test.com",
          password: "Password123!",
          password_confirmation: "Password123!",
          name: "Door Hanger Lead",
          phone: "+15125550008",
          utm_source: "meta",
          utm_medium: "cpc",
          acquired_channel_id: door.id
        })
        |> Ash.create()

      # Explicit wins over both UTM and referral derivation.
      assert c.acquired_channel_id == door.id
    end
  end

  describe "create_guest attribution" do
    test "accepts UTM fields and derives channel" do
      meta = channel_by_slug!("meta_paid")

      {:ok, c} =
        Customer
        |> Ash.Changeset.for_create(:create_guest, %{
          email: "guest-#{System.unique_integer([:positive])}@test.com",
          name: "Guest",
          phone: "+15125550009",
          utm_source: "meta",
          utm_medium: "cpc"
        })
        |> Ash.create()

      assert c.acquired_channel_id == meta.id
      assert c.utm_source == "meta"
    end
  end
end
