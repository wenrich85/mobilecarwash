defmodule MobileCarWash.Vehicles.NhtsaClientTest do
  # async: false — toggles the :nhtsa_client app env and uses a shared mock table
  use ExUnit.Case, async: false

  alias MobileCarWash.Vehicles.{NhtsaClient, NhtsaClientMock}

  describe "popular_makes/0" do
    test "returns a non-empty curated list that includes common makes" do
      makes = NhtsaClient.popular_makes()
      assert is_list(makes) and length(makes) >= 20
      assert "Toyota" in makes
      assert "Ford" in makes
    end
  end

  describe "body_class_to_size/1" do
    test "maps pickups and trucks to :pickup" do
      assert NhtsaClient.body_class_to_size("Pickup") == :pickup
      assert NhtsaClient.body_class_to_size("Truck-Tractor") == :pickup
      assert NhtsaClient.body_class_to_size("Crew Cab") == :pickup
    end

    test "maps SUVs, vans, minivans and wagons to :suv_van" do
      assert NhtsaClient.body_class_to_size(
               "Sport Utility Vehicle (SUV)/Multi-Purpose Vehicle (MPV)"
             ) == :suv_van

      assert NhtsaClient.body_class_to_size("Minivan") == :suv_van
      assert NhtsaClient.body_class_to_size("Van") == :suv_van
      assert NhtsaClient.body_class_to_size("Wagon") == :suv_van
    end

    test "maps sedans/coupes and unknowns/nil to :car" do
      assert NhtsaClient.body_class_to_size("Sedan/Saloon") == :car
      assert NhtsaClient.body_class_to_size("Coupe") == :car
      assert NhtsaClient.body_class_to_size("Spaceship") == :car
      assert NhtsaClient.body_class_to_size(nil) == :car
    end
  end

  describe "delegation to the configured mock" do
    setup do
      NhtsaClientMock.init()
      :ok
    end

    test "decode_vin routes to the mock and returns its canned result" do
      NhtsaClientMock.put_vin(
        "1HGCM82633A004352",
        {:ok,
         %{make: "Honda", model: "Accord", year: 2003, body_class: "Sedan/Saloon", size: :car}}
      )

      assert {:ok, %{make: "Honda", size: :car}} = NhtsaClient.decode_vin("1HGCM82633A004352")
    end

    test "decode_vin returns the mock's not-decoded error for an unknown VIN" do
      assert {:error, :vin_not_decoded} = NhtsaClient.decode_vin("BADVIN")
    end

    test "models_for_make_year routes to the mock and returns size-tagged models" do
      NhtsaClientMock.put_models("Toyota", 2021, [
        %{name: "Camry", size: :car},
        %{name: "RAV4", size: :suv_van}
      ])

      assert {:ok, [%{name: "Camry", size: :car}, %{name: "RAV4", size: :suv_van}]} =
               NhtsaClient.models_for_make_year("Toyota", 2021)
    end
  end

  describe "vehicle_type_to_size/1" do
    test "maps NHTSA vehicle-type tokens to size atoms" do
      assert NhtsaClient.vehicle_type_to_size("car") == :car
      assert NhtsaClient.vehicle_type_to_size("truck") == :pickup
      assert NhtsaClient.vehicle_type_to_size("mpv") == :suv_van
    end

    test "is case-insensitive and defaults unknown types to :car" do
      assert NhtsaClient.vehicle_type_to_size("MPV") == :suv_van
      assert NhtsaClient.vehicle_type_to_size("Truck") == :pickup
      assert NhtsaClient.vehicle_type_to_size("bus") == :car
    end
  end
end
