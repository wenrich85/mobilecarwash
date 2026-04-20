defmodule MobileCarWash.Marketing.PersonasMatchPreviewTest do
  @moduledoc """
  Marketing Phase 2D / Slice 1: the rule engine gains `count_matching/1`
  and `sample_matching/2` so the interactive persona editor can show
  "N customers currently match" as the admin tweaks criteria.

  These functions take a raw criteria map (not a Persona record) so
  the admin doesn't need to save to see the live preview.
  """
  use MobileCarWash.DataCase, async: false

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Marketing
  alias MobileCarWash.Marketing.{AcquisitionChannel, Personas}

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

  defp register!(channel_id) do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "match-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Match Test",
        phone: "+15125557#{:rand.uniform(999) |> Integer.to_string() |> String.pad_leading(3, "0")}",
        acquired_channel_id: channel_id
      })
      |> Ash.create()

    customer
  end

  describe "count_matching/1" do
    test "returns the number of customers satisfying the criteria",
         %{meta: meta, google: google} do
      # 2 meta customers + 1 google customer
      register!(meta.id)
      register!(meta.id)
      register!(google.id)

      assert Personas.count_matching(%{"acquired_channel_slug" => "meta_paid"}) == 2
      assert Personas.count_matching(%{"acquired_channel_slug" => "google_paid"}) == 1
    end

    test "empty criteria counts every customer", %{meta: meta} do
      register!(meta.id)
      register!(meta.id)

      assert Personas.count_matching(%{}) >= 2
    end

    test "nil or non-map criteria is treated as empty and matches all",
         %{meta: meta} do
      register!(meta.id)

      assert Personas.count_matching(nil) >= 1
    end
  end

  describe "sample_matching/2" do
    test "returns up to `limit` matching customers", %{meta: meta} do
      for _ <- 1..5, do: register!(meta.id)

      sample = Personas.sample_matching(%{"acquired_channel_slug" => "meta_paid"}, 3)
      assert length(sample) == 3
    end

    test "returns every match when total is below limit", %{meta: meta, google: google} do
      register!(meta.id)
      register!(google.id)

      sample = Personas.sample_matching(%{"acquired_channel_slug" => "meta_paid"}, 10)
      assert length(sample) == 1
      assert hd(sample).acquired_channel_id == meta.id
    end

    test "returns [] when no customer matches", %{meta: _meta} do
      assert Personas.sample_matching(%{"acquired_channel_slug" => "totally_fake_channel"}, 5) == []
    end
  end
end
