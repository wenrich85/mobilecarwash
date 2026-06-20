defmodule MobileCarWash.Fleet.VehicleTest do
  use MobileCarWash.DataCase, async: true

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Fleet.Vehicle

  setup do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "veh-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Veh Test",
        phone: "+15125550000"
      })
      |> Ash.create()

    %{customer: customer}
  end

  test "persists optional vin and body_class as provenance", %{customer: customer} do
    vehicle =
      Vehicle
      |> Ash.Changeset.for_create(:create, %{
        make: "Honda",
        model: "Accord",
        year: 2003,
        size: :car,
        vin: "1HGCM82633A004352",
        body_class: "Sedan/Saloon"
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create!()

    assert vehicle.vin == "1HGCM82633A004352"
    assert vehicle.body_class == "Sedan/Saloon"
    assert vehicle.size == :car
  end

  test "vin and body_class are optional (nil when omitted)", %{customer: customer} do
    vehicle =
      Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "Toyota", model: "Camry", year: 2021})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create!()

    assert is_nil(vehicle.vin)
    assert is_nil(vehicle.body_class)
  end
end
