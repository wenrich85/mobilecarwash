defmodule MobileCarWash.Fleet.AddressGeocodeTest do
  @moduledoc """
  Addresses should have lat/lng populated on create. If the caller doesn't
  provide them, the ZIP centroid is used as a fallback (sufficient for the
  route optimizer's MVP haversine math).
  """
  use MobileCarWash.DataCase, async: false

  alias MobileCarWash.Fleet.Address

  defp create_customer do
    MobileCarWash.Accounts.Customer
    |> Ash.Changeset.for_create(:create_guest, %{
      email: "geocode-#{:rand.uniform(100_000)}@example.com",
      name: "Geocode Test",
      phone: "512-555-0000"
    })
    |> Ash.create!()
  end

  defp create_address(customer_id, attrs) do
    defaults = %{
      street: "100 Test St",
      city: "San Antonio",
      state: "TX",
      zip: "78261"
    }

    Address
    |> Ash.Changeset.for_create(:create, Map.merge(defaults, attrs))
    |> Ash.Changeset.force_change_attribute(:customer_id, customer_id)
    |> Ash.create!()
  end

  describe "auto-geocode on create" do
    test "populates lat/lng from ZIP centroid when caller doesn't supply them" do
      c = create_customer()
      address = create_address(c.id, %{zip: "78261"})

      # 78261 centroid per MobileCarWash.Zones.coordinates_for_zip
      assert address.latitude == 29.65
      assert address.longitude == -98.42
    end

    test "preserves explicitly supplied lat/lng (doesn't overwrite with ZIP centroid)" do
      c = create_customer()

      address =
        create_address(c.id, %{
          zip: "78261",
          latitude: 29.6789,
          longitude: -98.4123
        })

      assert address.latitude == 29.6789
      assert address.longitude == -98.4123
    end

    test "leaves lat/lng nil when ZIP is outside service area (no centroid available)" do
      c = create_customer()
      address = create_address(c.id, %{zip: "99999"})

      assert address.latitude == nil
      assert address.longitude == nil
    end
  end

  describe "auto-geocode on update" do
    test "refreshes lat/lng from ZIP when ZIP changes and lat/lng not supplied" do
      c = create_customer()
      address = create_address(c.id, %{zip: "78261"})

      {:ok, updated} =
        address
        |> Ash.Changeset.for_update(:update, %{zip: "78259"})
        |> Ash.update()

      # 78259 centroid
      assert updated.latitude == 29.6100
      assert updated.longitude == -98.4600
    end
  end
end
