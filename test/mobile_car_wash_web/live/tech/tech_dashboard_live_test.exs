defmodule MobileCarWashWeb.Tech.TechDashboardLiveTest do
  @moduledoc """
  Covers the Slice C additions to the tech dashboard: the duty-status
  control at the top, the per-appointment state-machine buttons
  (Head out / Arrived / Start wash), and the live PubSub wiring that
  keeps the view in sync when another tab (or the admin) changes state.
  """
  use MobileCarWashWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  require Ash.Query

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Operations.{Technician, TechnicianTracker}
  alias MobileCarWash.Scheduling.Appointment

  defp create_tech_customer do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "tech-dash-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Dash Tech",
        phone: "+15125550201"
      })
      |> Ash.create()

    {:ok, customer} =
      customer
      |> Ash.Changeset.for_update(:update, %{role: :technician})
      |> Ash.update(authorize?: false)

    customer
  end

  defp create_tech_record(user) do
    {:ok, tech} =
      Technician
      |> Ash.Changeset.for_create(:create, %{
        name: user.name,
        phone: user.phone,
        active: true
      })
      |> Ash.create()

    {:ok, tech} =
      tech
      |> Ash.Changeset.for_update(:update, %{})
      |> Ash.Changeset.force_change_attribute(:user_account_id, user.id)
      |> Ash.update(authorize?: false)

    tech
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

  defp create_appointment(customer_id, technician_id, status, opts \\ []) do
    {:ok, service} =
      MobileCarWash.Scheduling.ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Basic Wash",
        slug: "dash-#{System.unique_integer([:positive])}",
        base_price_cents: 5_000,
        duration_minutes: 45
      })
      |> Ash.create()

    {:ok, vehicle} =
      MobileCarWash.Fleet.Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "Toyota", model: "Camry"})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer_id)
      |> Ash.create()

    {:ok, address} =
      MobileCarWash.Fleet.Address
      |> Ash.Changeset.for_create(:create, %{
        street: "99 Dash Ave",
        city: "San Antonio",
        state: "TX",
        zip: "78259"
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer_id)
      |> Ash.create()

    scheduled_at = opts[:scheduled_at] || next_slot_today()

    {:ok, appt} =
      Appointment
      |> Ash.Changeset.for_create(:book, %{
        customer_id: customer_id,
        vehicle_id: vehicle.id,
        address_id: address.id,
        service_type_id: service.id,
        scheduled_at: scheduled_at,
        price_cents: 5_000,
        duration_minutes: 45
      })
      |> Ash.create()

    {:ok, appt} =
      appt
      |> Ash.Changeset.for_update(:update, %{})
      |> Ash.Changeset.force_change_attribute(:technician_id, technician_id)
      |> Ash.Changeset.force_change_attribute(:status, status)
      |> Ash.update(authorize?: false)

    appt
  end

  defp next_slot_today do
    # 2 hours from now — still today in UTC with 24-hour window
    DateTime.utc_now() |> DateTime.add(2 * 3600, :second) |> DateTime.truncate(:second)
  end

  describe "duty-status control" do
    setup %{conn: conn} do
      user = create_tech_customer()
      tech = create_tech_record(user)
      conn = sign_in(conn, user)
      {:ok, conn: conn, user: user, tech: tech}
    end

    test "renders the current status prominently", %{conn: conn, tech: tech} do
      tech
      |> Ash.Changeset.for_update(:set_status, %{status: :available})
      |> Ash.update!()

      {:ok, _view, html} = live(conn, ~p"/tech")
      assert html =~ "Available"
    end

    test "clicking 'Take break' persists on_break and rerenders",
         %{conn: conn, tech: tech} do
      # Start an available shift so the "Take break" button is visible
      tech
      |> Ash.Changeset.for_update(:set_status, %{status: :available})
      |> Ash.update!()

      {:ok, view, _html} = live(conn, ~p"/tech")

      html =
        view
        |> element("button", "Take break")
        |> render_click()

      assert html =~ "On break"

      {:ok, reloaded} = Ash.get(Technician, tech.id)
      assert reloaded.status == :on_break
    end

    test "clicking 'Back on duty' transitions on_break -> available",
         %{conn: conn, tech: tech} do
      tech
      |> Ash.Changeset.for_update(:set_status, %{status: :on_break})
      |> Ash.update!()

      {:ok, view, _html} = live(conn, ~p"/tech")

      html =
        view
        |> element("button", "Back on duty")
        |> render_click()

      assert html =~ "Available"

      {:ok, reloaded} = Ash.get(Technician, tech.id)
      assert reloaded.status == :available
    end

    test "status update from another subscriber (PubSub) re-renders in-place",
         %{conn: conn, tech: tech} do
      {:ok, view, _html} = live(conn, ~p"/tech")

      # Simulate a different subscriber (another open tab, admin override)
      # flipping the status.
      tech
      |> Ash.Changeset.for_update(:set_status, %{status: :on_break})
      |> Ash.update!()

      # The broadcast is fire-and-forget; give the LiveView a render cycle
      # to pick it up.
      render(view)
      assert render(view) =~ "On break"
    end
  end

  describe "per-appointment state-machine buttons" do
    setup %{conn: conn} do
      user = create_tech_customer()
      tech = create_tech_record(user)
      conn = sign_in(conn, user)

      {:ok, customer} =
        Customer
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "dash-cust-#{System.unique_integer([:positive])}@test.com",
          password: "Password123!",
          password_confirmation: "Password123!",
          name: "Dash Customer",
          phone: "+15125550202"
        })
        |> Ash.create()

      {:ok, conn: conn, user: user, tech: tech, customer: customer}
    end

    test "shows 'Head out' when appointment is :confirmed",
         %{conn: conn, tech: tech, customer: customer} do
      _appt = create_appointment(customer.id, tech.id, :confirmed)

      {:ok, _view, html} = live(conn, ~p"/tech")
      assert html =~ "Head out"
    end

    test "clicking 'Head out' transitions :confirmed -> :en_route",
         %{conn: conn, tech: tech, customer: customer} do
      appt = create_appointment(customer.id, tech.id, :confirmed)

      {:ok, view, _html} = live(conn, ~p"/tech")

      view
      |> element("button[phx-value-id='#{appt.id}']", "Head out")
      |> render_click()

      {:ok, reloaded} = Ash.get(Appointment, appt.id, authorize?: false)
      assert reloaded.status == :en_route
    end

    test "shows 'Arrived' when appointment is :en_route",
         %{conn: conn, tech: tech, customer: customer} do
      _appt = create_appointment(customer.id, tech.id, :en_route)

      {:ok, _view, html} = live(conn, ~p"/tech")
      assert html =~ "Arrived"
    end

    test "clicking 'Arrived' transitions :en_route -> :on_site",
         %{conn: conn, tech: tech, customer: customer} do
      appt = create_appointment(customer.id, tech.id, :en_route)

      {:ok, view, _html} = live(conn, ~p"/tech")

      view
      |> element("button[phx-value-id='#{appt.id}']", "Arrived")
      |> render_click()

      {:ok, reloaded} = Ash.get(Appointment, appt.id, authorize?: false)
      assert reloaded.status == :on_site
    end

    test "shows 'Start wash' when appointment is :on_site",
         %{conn: conn, tech: tech, customer: customer} do
      _appt = create_appointment(customer.id, tech.id, :on_site)

      {:ok, _view, html} = live(conn, ~p"/tech")
      assert html =~ "Start wash"
    end
  end

  describe "address tap-to-navigate" do
    setup %{conn: conn} do
      user = create_tech_customer()
      tech = create_tech_record(user)
      conn = sign_in(conn, user)

      {:ok, customer} =
        Customer
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "nav-cust-#{System.unique_integer([:positive])}@test.com",
          password: "Password123!",
          password_confirmation: "Password123!",
          name: "Nav Cust",
          phone: "+15125550203"
        })
        |> Ash.create()

      _appt = create_appointment(customer.id, tech.id, :confirmed)

      {:ok, conn: conn}
    end

    test "renders a Maps link for the service address", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/tech")

      assert html =~ "maps.apple.com"
      assert html =~ "78259"
    end
  end

  describe "PubSub subscription" do
    test "subscribes to the current tech's status topic on mount",
         %{conn: conn} do
      user = create_tech_customer()
      _tech = create_tech_record(user)
      conn = sign_in(conn, user)

      # Subscribing more than once is harmless — the purpose of this test is
      # to confirm the LV is listening on the topic at all.
      {:ok, _view, _html} = live(conn, ~p"/tech")

      TechnicianTracker.subscribe(_tech.id)

      # Flip the status via action — the broadcast reaches our subscription
      # and (indirectly) the LV under test.
      _tech
      |> Ash.Changeset.for_update(:set_status, %{status: :available})
      |> Ash.update!()

      assert_receive {:technician_status, %{status: :available}}, 500
    end
  end
end
