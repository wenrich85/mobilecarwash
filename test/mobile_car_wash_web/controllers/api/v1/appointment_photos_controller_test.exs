defmodule MobileCarWashWeb.Api.V1.AppointmentPhotosControllerTest do
  use MobileCarWashWeb.ApiCase

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Fleet.{Address, Vehicle}
  alias MobileCarWash.Operations.{Photo, Technician}
  alias MobileCarWash.Scheduling.{Appointment, ServiceType}

  defp register_and_sign_in_tech(conn) do
    {authed, user, _token} =
      register_and_sign_in(conn,
        email: "photo-tech-#{System.unique_integer([:positive])}@example.com"
      )

    {:ok, user} =
      user
      |> Ash.Changeset.for_update(:update, %{role: :technician})
      |> Ash.update(authorize?: false)

    {:ok, tech} =
      Technician
      |> Ash.Changeset.for_create(:create, %{name: user.name, phone: user.phone, active: true})
      |> Ash.create()

    {:ok, tech} =
      tech
      |> Ash.Changeset.for_update(:update, %{})
      |> Ash.Changeset.force_change_attribute(:user_account_id, user.id)
      |> Ash.update(authorize?: false)

    {authed, tech}
  end

  defp create_customer_appointment(tech_id, status) do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "photo-cust-#{System.unique_integer([:positive])}@example.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Photo Customer",
        phone: "+15125550001"
      })
      |> Ash.create()

    {:ok, service} =
      ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Photo Wash",
        slug: "photo-wash-#{System.unique_integer([:positive])}",
        base_price_cents: 5_000,
        duration_minutes: 45
      })
      |> Ash.create()

    {:ok, vehicle} =
      Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "Toyota", model: "Camry"})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, address} =
      Address
      |> Ash.Changeset.for_create(:create, %{
        street: "100 Photo Ave",
        city: "San Antonio",
        state: "TX",
        zip: "78259"
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, appointment} =
      Appointment
      |> Ash.Changeset.for_create(:book, %{
        customer_id: customer.id,
        vehicle_id: vehicle.id,
        address_id: address.id,
        service_type_id: service.id,
        scheduled_at:
          DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second),
        price_cents: 5_000,
        duration_minutes: 45
      })
      |> Ash.create()

    appointment
    |> Ash.Changeset.for_update(:update, %{})
    |> Ash.Changeset.force_change_attribute(:technician_id, tech_id)
    |> Ash.Changeset.force_change_attribute(:status, status)
    |> Ash.update!(authorize?: false)
  end

  defp create_photo(appointment_id, photo_type, car_part) do
    Photo
    |> Ash.Changeset.for_create(:upload, %{
      file_path: "/tmp/#{appointment_id}-#{photo_type}-#{car_part}.jpg",
      original_filename: "#{car_part}.jpg",
      content_type: "image/jpeg",
      photo_type: photo_type,
      uploaded_by: :technician,
      car_part: car_part
    })
    |> Ash.Changeset.force_change_attribute(:appointment_id, appointment_id)
    |> Ash.create(authorize?: false)
  end

  defp write_jpeg! do
    path = Path.join(System.tmp_dir!(), "photo-upload-#{System.unique_integer([:positive])}.jpg")
    File.write!(path, <<0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0, 0xFF, 0xD9>>)
    path
  end

  describe "GET /api/v1/appointments/:id/photos" do
    test "returns active photos for the assigned technician", %{conn: conn} do
      {authed, tech} = register_and_sign_in_tech(conn)
      appointment = create_customer_appointment(tech.id, :in_progress)
      {:ok, active} = create_photo(appointment.id, :before, :front)
      {:ok, deleted} = create_photo(appointment.id, :after, :front)

      deleted
      |> Ash.Changeset.for_update(:soft_delete, %{})
      |> Ash.update!(authorize?: false)

      conn = get(authed, ~p"/api/v1/appointments/#{appointment.id}/photos")
      body = json_response(conn, 200)

      assert [%{"id" => id, "photo_type" => "before", "car_part" => "front"}] = body["data"]
      assert id == active.id
    end
  end

  describe "POST /api/v1/appointments/:id/photos" do
    test "accepts step completion photos without a car part", %{conn: conn} do
      {authed, tech} = register_and_sign_in_tech(conn)
      appointment = create_customer_appointment(tech.id, :in_progress)
      upload = %Plug.Upload{path: write_jpeg!(), filename: "step.jpg", content_type: "image/jpeg"}

      conn =
        post(authed, ~p"/api/v1/appointments/#{appointment.id}/photos", %{
          "photo_type" => "step_completion",
          "idempotency_key" => Ecto.UUID.generate(),
          "file" => upload
        })

      body = json_response(conn, 201)
      assert body["data"]["photo_type"] == "step_completion"
      assert body["data"]["car_part"] == nil
    end
  end
end
