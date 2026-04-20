defmodule MobileCarWashWeb.Admin.CustomerPreviewLiveTest do
  @moduledoc """
  Slice E4: admin-only "view as customer" preview. Read-only snapshot
  at /admin/customers/:id/preview. Auto-creates an audit note on
  every view.
  """
  use MobileCarWashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  require Ash.Query

  alias MobileCarWash.Accounts.{Customer, CustomerNote}
  alias MobileCarWash.Scheduling.{Appointment, ServiceType}

  defp register_admin! do
    {:ok, c} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "preview-admin-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Preview Admin",
        phone: "+15125550500"
      })
      |> Ash.create()

    c
    |> Ash.Changeset.for_update(:update, %{role: :admin})
    |> Ash.update!(authorize?: false)
  end

  defp register_customer!(name \\ "Preview Target") do
    {:ok, c} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "preview-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: name,
        phone:
          "+1512555#{:rand.uniform(9999) |> Integer.to_string() |> String.pad_leading(4, "0")}"
      })
      |> Ash.create()

    c
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

  defp create_appointment_for(customer_id) do
    {:ok, service} =
      ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Premium Wash",
        slug: "preview-svc-#{System.unique_integer([:positive])}",
        base_price_cents: 9_900,
        duration_minutes: 60
      })
      |> Ash.create()

    {:ok, vehicle} =
      MobileCarWash.Fleet.Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "Honda", model: "Civic"})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer_id)
      |> Ash.create()

    {:ok, address} =
      MobileCarWash.Fleet.Address
      |> Ash.Changeset.for_create(:create, %{
        street: "10 Preview Ln",
        city: "San Antonio",
        state: "TX",
        zip: "78261"
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer_id)
      |> Ash.create()

    {:ok, appt} =
      Appointment
      |> Ash.Changeset.for_create(:book, %{
        customer_id: customer_id,
        vehicle_id: vehicle.id,
        address_id: address.id,
        service_type_id: service.id,
        scheduled_at:
          DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second),
        price_cents: 9_900,
        duration_minutes: 60
      })
      |> Ash.create()

    appt
  end

  describe "auth guard" do
    test "anonymous redirects to /sign-in", %{conn: conn} do
      target = register_customer!()
      conn = get(conn, ~p"/admin/customers/#{target.id}/preview")
      assert redirected_to(conn) == "/sign-in"
    end

    test "signed-in non-admin is denied", %{conn: conn} do
      not_admin = register_customer!("Not Admin")
      target = register_customer!()
      conn = sign_in(conn, not_admin)

      # LV on_mount for admin scope halts with redirect.
      assert {:error, {:redirect, %{to: "/"}}} =
               live(conn, ~p"/admin/customers/#{target.id}/preview")
    end
  end

  describe "render" do
    test "shows the preview banner and the customer's appointments", %{conn: conn} do
      admin = register_admin!()
      target = register_customer!("Preview Xyz Customer")
      _appt = create_appointment_for(target.id)

      conn = sign_in(conn, admin)
      {:ok, _lv, html} = live(conn, ~p"/admin/customers/#{target.id}/preview")

      assert html =~ "Preview Xyz Customer"
      assert html =~ ~s(id="preview-banner")
      assert html =~ "Premium Wash"
    end

    test "creates an audit note when the admin views the preview", %{conn: conn} do
      admin = register_admin!()
      target = register_customer!()

      conn = sign_in(conn, admin)
      {:ok, _lv, _html} = live(conn, ~p"/admin/customers/#{target.id}/preview")

      {:ok, notes} =
        CustomerNote
        |> Ash.Query.for_read(:for_customer, %{customer_id: target.id})
        |> Ash.read(authorize?: false)

      assert Enum.any?(notes, fn n -> n.body =~ "preview" end)
    end

    test "empty state when customer has no appointments", %{conn: conn} do
      admin = register_admin!()
      target = register_customer!()

      conn = sign_in(conn, admin)
      {:ok, _lv, html} = live(conn, ~p"/admin/customers/#{target.id}/preview")

      assert html =~ "No appointments yet"
    end

    test "404s cleanly for a missing customer id", %{conn: conn} do
      admin = register_admin!()
      conn = sign_in(conn, admin)

      assert {:error, {:live_redirect, %{to: "/admin/customers"}}} =
               live(conn, ~p"/admin/customers/#{Ecto.UUID.generate()}/preview")
    end
  end
end
