defmodule MobileCarWashWeb.Admin.DispatchLiveTagFlagTest do
  @moduledoc """
  Slice E2: dispatch cards show a warning marker when the customer has
  any applied tag with `affects_booking: true`. Level A — warn only,
  don't block.
  """
  use MobileCarWashWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  require Ash.Query

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Marketing
  alias MobileCarWash.Marketing.{CustomerTag, Tag}

  defp create_admin do
    {:ok, admin} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "admin-flag-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Flag Admin",
        phone: "+15125550401"
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
      "customer" => %{
        "email" => to_string(user.email),
        "password" => "Password123!"
      }
    })
    |> recycle()
  end

  defp create_appointment_for(customer_name) do
    {:ok, service} =
      MobileCarWash.Scheduling.ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Basic Wash",
        slug: "flag-test-#{System.unique_integer([:positive])}",
        base_price_cents: 5_000,
        duration_minutes: 45
      })
      |> Ash.create()

    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "flag-cust-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: customer_name,
        phone:
          "+1512555#{:rand.uniform(9999) |> Integer.to_string() |> String.pad_leading(4, "0")}"
      })
      |> Ash.create()

    {:ok, vehicle} =
      MobileCarWash.Fleet.Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "Toyota", model: "Camry"})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, address} =
      MobileCarWash.Fleet.Address
      |> Ash.Changeset.for_create(:create, %{
        street: "50 Flag St",
        city: "San Antonio",
        state: "TX",
        zip: "78259"
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, appt} =
      MobileCarWash.Scheduling.Appointment
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

    {customer, appt}
  end

  describe "booking-flag marker" do
    setup %{conn: conn} do
      :ok = Marketing.seed_tags!()
      admin = create_admin()
      conn = sign_in(conn, admin)
      {:ok, conn: conn, admin: admin}
    end

    test "card shows booking-flag badge when customer has affects_booking tag",
         %{conn: conn, admin: admin} do
      {:ok, [dns]} =
        Tag
        |> Ash.Query.for_read(:by_slug, %{slug: "do_not_service"})
        |> Ash.read(authorize?: false)

      {flagged_customer, _appt} = create_appointment_for("Flagged Customer Xyz")

      {:ok, _} =
        CustomerTag
        |> Ash.Changeset.for_create(:tag, %{
          customer_id: flagged_customer.id,
          tag_id: dns.id,
          author_id: admin.id
        })
        |> Ash.create(authorize?: false)

      {:ok, _lv, html} = live(conn, ~p"/admin/dispatch")

      assert html =~ "Flagged Customer Xyz"
      # Marker we're going to render.
      assert html =~ "booking-flag"
    end

    test "no badge for customers without booking-flag tags",
         %{conn: conn} do
      {_customer, _appt} = create_appointment_for("Unflagged Customer Xyz")

      {:ok, _lv, html} = live(conn, ~p"/admin/dispatch")

      assert html =~ "Unflagged Customer Xyz"
      refute html =~ "booking-flag"
    end
  end
end
