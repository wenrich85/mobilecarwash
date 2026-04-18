defmodule MobileCarWashWeb.Api.V1.BookingsControllerTest do
  use MobileCarWashWeb.ApiCase

  alias MobileCarWash.Scheduling.{AppointmentBlock, ServiceType}
  alias MobileCarWash.Operations.Technician

  defp create_service do
    ServiceType
    |> Ash.Changeset.for_create(:create, %{
      name: "Basic",
      slug: "basic_api_book_#{:rand.uniform(100_000)}",
      base_price_cents: 5000,
      duration_minutes: 45
    })
    |> Ash.create!()
  end

  defp create_block(service) do
    {:ok, tech} =
      Technician |> Ash.Changeset.for_create(:create, %{name: "BT"}) |> Ash.create()

    starts_at =
      DateTime.utc_now()
      |> DateTime.add(2 * 86_400, :second)
      |> DateTime.truncate(:second)

    AppointmentBlock
    |> Ash.Changeset.for_create(:create, %{
      service_type_id: service.id,
      technician_id: tech.id,
      starts_at: starts_at,
      ends_at: DateTime.add(starts_at, 3 * 3600, :second),
      closes_at: DateTime.add(starts_at, -3600, :second),
      capacity: 3,
      status: :open
    })
    |> Ash.create!()
  end

  defp create_vehicle(customer_id) do
    MobileCarWash.Fleet.Vehicle
    |> Ash.Changeset.for_create(:create, %{make: "Toyota", model: "Camry", size: :car})
    |> Ash.Changeset.force_change_attribute(:customer_id, customer_id)
    |> Ash.create!()
  end

  defp create_address(customer_id) do
    MobileCarWash.Fleet.Address
    |> Ash.Changeset.for_create(:create, %{
      street: "100 Main",
      city: "San Antonio",
      state: "TX",
      zip: "78261"
    })
    |> Ash.Changeset.force_change_attribute(:customer_id, customer_id)
    |> Ash.create!()
  end

  describe "POST /api/v1/bookings" do
    test "requires authentication", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/bookings", %{})
      assert json_response(conn, 401)
    end

    test "creates an appointment and returns a PaymentIntent client_secret", %{conn: conn} do
      {authed, customer, _} = register_and_sign_in(conn)
      service = create_service()
      block = create_block(service)
      vehicle = create_vehicle(customer.id)
      address = create_address(customer.id)

      conn =
        post(authed, ~p"/api/v1/bookings", %{
          service_type_id: service.id,
          appointment_block_id: block.id,
          vehicle_id: vehicle.id,
          address_id: address.id
        })

      body = json_response(conn, 201)

      assert body["appointment"]["id"]
      assert body["appointment"]["appointment_block_id"] == block.id
      assert body["payment_intent_client_secret"] =~ "pi_test_"
    end

    test "returns 422 when block is full", %{conn: conn} do
      {authed, customer, _} = register_and_sign_in(conn)
      service = create_service()
      vehicle = create_vehicle(customer.id)
      address = create_address(customer.id)

      # Build a capacity-0 block to simulate "full" without needing to fill it
      {:ok, tech} =
        Technician |> Ash.Changeset.for_create(:create, %{name: "FT"}) |> Ash.create()

      starts_at =
        DateTime.utc_now() |> DateTime.add(86_400, :second) |> DateTime.truncate(:second)

      {:ok, block} =
        AppointmentBlock
        |> Ash.Changeset.for_create(:create, %{
          service_type_id: service.id,
          technician_id: tech.id,
          starts_at: starts_at,
          ends_at: DateTime.add(starts_at, 3 * 3600, :second),
          closes_at: DateTime.add(starts_at, -3600, :second),
          capacity: 0,
          status: :open
        })
        |> Ash.create()

      conn =
        post(authed, ~p"/api/v1/bookings", %{
          service_type_id: service.id,
          appointment_block_id: block.id,
          vehicle_id: vehicle.id,
          address_id: address.id
        })

      assert %{"error" => "block_full"} = json_response(conn, 422)
    end
  end
end
