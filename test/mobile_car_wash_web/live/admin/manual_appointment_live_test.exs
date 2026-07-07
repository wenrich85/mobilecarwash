defmodule MobileCarWashWeb.Admin.ManualAppointmentLiveTest do
  use MobileCarWashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  require Ash.Query

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Scheduling.{ServiceType, Appointment}
  alias MobileCarWash.Billing.Payment

  defp create_admin do
    {:ok, admin} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "admin-manual-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Manual Admin",
        phone: "+15125550302"
      })
      |> Ash.create()

    admin
    |> Ash.Changeset.for_update(:update, %{role: :admin})
    |> Ash.update!(authorize?: false)
  end

  defp sign_in(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> post("/auth/customer/password/sign_in", %{
      "customer" => %{"email" => to_string(user.email), "password" => "Password123!"}
    })
    |> recycle()
  end

  defp service do
    ServiceType
    |> Ash.Changeset.for_create(:create, %{
      name: "Basic Wash",
      slug: "basic_#{System.unique_integer([:positive])}",
      base_price_cents: 5000,
      duration_minutes: 45
    })
    |> Ash.create!(authorize?: false)
  end

  test "renders the manual appointment form", %{conn: conn} do
    conn = sign_in(conn, create_admin())
    {:ok, view, _html} = live(conn, ~p"/admin/appointments/new")
    assert has_element?(view, "#manual-appointment-form")
  end

  test "creates a comped appointment for a brand-new client", %{conn: conn} do
    svc = service()
    conn = sign_in(conn, create_admin())
    {:ok, view, _html} = live(conn, ~p"/admin/appointments/new")

    when_iso =
      DateTime.utc_now()
      |> DateTime.add(2 * 86_400, :second)
      |> Calendar.strftime("%Y-%m-%dT%H:%M")

    params = %{
      "client_mode" => "new",
      "new_customer_name" => "Walk Up",
      "new_customer_email" => "walkup-#{System.unique_integer([:positive])}@test.com",
      "new_customer_phone" => "+15125550188",
      "vehicle_make" => "Kia",
      "vehicle_model" => "Soul",
      "vehicle_size" => "car",
      "address_street" => "5 Elm",
      "address_city" => "Austin",
      "address_state" => "TX",
      "address_zip" => "78701",
      "service_type_id" => svc.id,
      "scheduled_at" => when_iso,
      "waive" => "true",
      "comp_reason" => "Owner comp",
      "notify_client" => "false"
    }

    result =
      view
      |> form("#manual-appointment-form", manual_appointment: params)
      |> render_submit()

    # LiveView redirects to dispatch on success.
    assert {:error, {:redirect, %{to: "/admin/dispatch"}}} = result

    appt = Appointment |> Ash.read!(authorize?: false) |> List.first()
    assert appt.status == :confirmed
    payment = Payment |> Ash.read!(authorize?: false) |> List.first()
    assert payment.comped == true
    assert payment.collected_cents == 0
  end
end
