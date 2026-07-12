defmodule MobileCarWashWeb.AppointmentStatusLiveTest do
  @moduledoc """
  Covers the customer-facing "Cancel booking" affordance on the appointment
  status page. Button is visible only when the appointment is pending or
  confirmed — hidden once the wash is in progress or completed, and hidden
  after a successful cancel.
  """
  use MobileCarWashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Scheduling.{Appointment, ServiceType}
  alias MobileCarWash.Fleet.{Address, Vehicle}
  alias MobileCarWash.Operations.Photo

  defp register_customer do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "cancel-live-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Cancel Live",
        phone: "+15125558000"
      })
      |> Ash.create()

    customer
  end

  defp sign_in(conn, customer) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> post("/auth/customer/password/sign_in", %{
      "customer" => %{
        "email" => to_string(customer.email),
        "password" => "Password123!"
      }
    })
    |> recycle()
  end

  defp create_appointment(customer, status \\ :pending) do
    {:ok, service} =
      ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Basic Wash",
        slug: "cancel-live-#{System.unique_integer([:positive])}",
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
        street: "123 Cancel St",
        city: "San Antonio",
        state: "TX",
        zip: "78259"
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, appt} =
      Appointment
      |> Ash.Changeset.for_create(:book, %{
        customer_id: customer.id,
        vehicle_id: vehicle.id,
        address_id: address.id,
        service_type_id: service.id,
        scheduled_at: DateTime.add(DateTime.utc_now(), 2 * 86_400, :second),
        price_cents: 5_000,
        duration_minutes: 45
      })
      |> Ash.create()

    if status != :pending do
      {:ok, appt} =
        appt
        |> Ash.Changeset.for_update(:update, %{status: status})
        |> Ash.update()

      appt
    else
      appt
    end
  end

  defp create_photo(appt, photo_type, car_part, file_path) do
    {:ok, photo} =
      Photo
      |> Ash.Changeset.for_create(:upload, %{
        file_path: file_path,
        photo_type: photo_type,
        car_part: car_part,
        content_type: "image/jpeg",
        original_filename: Path.basename(file_path)
      })
      |> Ash.Changeset.force_change_attribute(:appointment_id, appt.id)
      |> Ash.create()

    photo
  end

  describe "cancel button visibility" do
    test "is rendered when the appointment is pending", %{conn: conn} do
      customer = register_customer()
      appt = create_appointment(customer, :pending)
      conn = sign_in(conn, customer)

      {:ok, _view, html} = live(conn, ~p"/appointments/#{appt.id}/status")
      assert html =~ "Cancel booking"
    end

    test "is rendered when the appointment is confirmed", %{conn: conn} do
      customer = register_customer()
      appt = create_appointment(customer, :confirmed)
      conn = sign_in(conn, customer)

      {:ok, _view, html} = live(conn, ~p"/appointments/#{appt.id}/status")
      assert html =~ "Cancel booking"
    end

    test "is hidden when the appointment is in_progress", %{conn: conn} do
      customer = register_customer()
      appt = create_appointment(customer, :in_progress)
      conn = sign_in(conn, customer)

      {:ok, _view, html} = live(conn, ~p"/appointments/#{appt.id}/status")
      refute html =~ "Cancel booking"
    end

    test "is hidden when the appointment is completed", %{conn: conn} do
      customer = register_customer()
      appt = create_appointment(customer, :completed)
      conn = sign_in(conn, customer)

      {:ok, _view, html} = live(conn, ~p"/appointments/#{appt.id}/status")
      refute html =~ "Cancel booking"
    end

    test "is hidden when the appointment is already cancelled", %{conn: conn} do
      customer = register_customer()
      appt = create_appointment(customer, :cancelled)
      conn = sign_in(conn, customer)

      {:ok, _view, html} = live(conn, ~p"/appointments/#{appt.id}/status")
      refute html =~ "Cancel booking"
    end
  end

  describe "cancel flow" do
    test "clicking cancel updates status and hides the button",
         %{conn: conn} do
      customer = register_customer()
      appt = create_appointment(customer, :pending)
      conn = sign_in(conn, customer)

      {:ok, view, _} = live(conn, ~p"/appointments/#{appt.id}/status")

      html =
        view
        |> element("button", "Cancel booking")
        |> render_click()

      refute html =~ "Cancel booking"
      assert html =~ "Appointment cancelled"

      {:ok, reloaded} = Ash.get(Appointment, appt.id, authorize?: false)
      assert reloaded.status == :cancelled
      assert reloaded.cancellation_reason
    end
  end

  describe "photo loading" do
    test "soft-deleted photos never render", %{conn: conn} do
      customer = register_customer()
      appt = create_appointment(customer, :in_progress)
      photo = create_photo(appt, :before, :front, "/uploads/front-old.jpg")

      {:ok, _} =
        photo
        |> Ash.Changeset.for_update(:soft_delete, %{})
        |> Ash.update()

      create_photo(appt, :before, :front, "/uploads/front-new.jpg")
      conn = sign_in(conn, customer)

      {:ok, _view, html} = live(conn, ~p"/appointments/#{appt.id}/status")
      refute html =~ "front-old.jpg"
      assert html =~ "front-new.jpg"
    end
  end
end
