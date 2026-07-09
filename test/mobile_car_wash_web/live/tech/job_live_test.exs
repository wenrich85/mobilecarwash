defmodule MobileCarWashWeb.Tech.JobLiveTest do
  use MobileCarWashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Operations.{Procedure, ProcedureStep, Technician}
  alias MobileCarWash.Scheduling.{Appointment, ServiceType}

  defp create_tech_customer(name \\ "Job Tech") do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "job-tech-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: name,
        phone: "+15125550500"
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

  defp create_customer(name \\ "Job Customer") do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "job-customer-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: name,
        phone: "+15125550501"
      })
      |> Ash.create()

    customer
  end

  defp create_appointment(customer_id, technician_id, status) do
    {:ok, service} =
      ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Job Wash",
        slug: "job-wash-#{System.unique_integer([:positive])}",
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
        street: "100 Job Ave",
        city: "San Antonio",
        state: "TX",
        zip: "78259"
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer_id)
      |> Ash.create()

    {:ok, appointment} =
      Appointment
      |> Ash.Changeset.for_create(:book, %{
        customer_id: customer_id,
        vehicle_id: vehicle.id,
        address_id: address.id,
        service_type_id: service.id,
        scheduled_at:
          DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second),
        price_cents: 5_000,
        duration_minutes: 45
      })
      |> Ash.create()

    {:ok, appointment} =
      appointment
      |> Ash.Changeset.for_update(:update, %{})
      |> Ash.Changeset.force_change_attribute(:technician_id, technician_id)
      |> Ash.Changeset.force_change_attribute(:status, status)
      |> Ash.update(authorize?: false)

    appointment
  end

  defp reassign_appointment(appointment, technician_id) do
    {:ok, appointment} =
      appointment
      |> Ash.Changeset.for_update(:update, %{})
      |> Ash.Changeset.force_change_attribute(:technician_id, technician_id)
      |> Ash.update(authorize?: false)

    appointment
  end

  defp create_procedure_for_service(service_type_id) do
    {:ok, procedure} =
      Procedure
      |> Ash.Changeset.for_create(:create, %{
        name: "Job Wash SOP",
        slug: "job-wash-sop-#{System.unique_integer([:positive])}"
      })
      |> Ash.Changeset.force_change_attribute(:service_type_id, service_type_id)
      |> Ash.create()

    for n <- 1..2 do
      ProcedureStep
      |> Ash.Changeset.for_create(:create, %{
        step_number: n,
        title: "Step #{n}",
        estimated_minutes: 5
      })
      |> Ash.Changeset.force_change_attribute(:procedure_id, procedure.id)
      |> Ash.create!()
    end

    procedure
  end

  defp live_job(conn, appointment_id) do
    live(conn, ~p"/tech/appointments/#{appointment_id}", on_error: :warn)
  end

  describe "job brief page" do
    setup %{conn: conn} do
      user = create_tech_customer()
      tech = create_tech_record(user)
      customer = create_customer()

      {:ok, conn: sign_in(conn, user), user: user, tech: tech, customer: customer}
    end

    test "renders the assigned confirmed job brief", %{conn: conn, tech: tech, customer: customer} do
      appointment = create_appointment(customer.id, tech.id, :confirmed)

      {:ok, view, _html} = live_job(conn, appointment.id)

      assert has_element?(view, "#tech-job-brief")
      assert has_element?(view, "#job-head-out")
      assert render(view) =~ customer.name
      assert render(view) =~ "Toyota"
      assert render(view) =~ "78259"
    end

    test "denies access to another technician's appointment", %{conn: conn, customer: customer} do
      other_user = create_tech_customer("Other Tech")
      other_tech = create_tech_record(other_user)
      appointment = create_appointment(customer.id, other_tech.id, :confirmed)

      assert {:error, {:redirect, %{to: "/tech"}}} = live_job(conn, appointment.id)
    end

    test "denies access when another technician shares the same name", %{
      conn: conn,
      customer: customer
    } do
      shared_name = "Shared Tech"
      other_user = create_tech_customer(shared_name)
      other_tech = create_tech_record(other_user)

      signed_in_user = create_tech_customer(shared_name)
      _signed_in_tech = create_tech_record(signed_in_user)

      appointment = create_appointment(customer.id, other_tech.id, :confirmed)

      assert {:error, {:redirect, %{to: "/tech"}}} =
               conn
               |> sign_in(signed_in_user)
               |> live_job(appointment.id)
    end

    test "depart transitions confirmed job to en_route", %{
      conn: conn,
      tech: tech,
      customer: customer
    } do
      appointment = create_appointment(customer.id, tech.id, :confirmed)

      {:ok, view, _html} = live_job(conn, appointment.id)

      view
      |> element("#job-head-out")
      |> render_click()

      assert render(view) =~ "En route"
      assert has_element?(view, "#job-arrived")
    end

    test "depart denies mutation after appointment is reassigned", %{
      conn: conn,
      tech: tech,
      customer: customer
    } do
      appointment = create_appointment(customer.id, tech.id, :confirmed)
      other_user = create_tech_customer("Replacement Tech")
      other_tech = create_tech_record(other_user)

      {:ok, view, _html} = live_job(conn, appointment.id)

      _reassigned_appointment = reassign_appointment(appointment, other_tech.id)

      assert {:error, {:redirect, %{to: "/tech"}}} =
               view
               |> element("#job-head-out")
               |> render_click()

      {:ok, reloaded} = Ash.get(Appointment, appointment.id, authorize?: false)
      assert reloaded.status == :confirmed
      assert reloaded.technician_id == other_tech.id
    end

    test "arrive transitions en_route job to on_site", %{
      conn: conn,
      tech: tech,
      customer: customer
    } do
      appointment = create_appointment(customer.id, tech.id, :en_route)

      {:ok, view, _html} = live_job(conn, appointment.id)

      view
      |> element("#job-arrived")
      |> render_click()

      assert render(view) =~ "On site"
      assert has_element?(view, "#job-start-wash")
    end

    test "start wash creates a checklist and navigates to it", %{
      conn: conn,
      tech: tech,
      customer: customer
    } do
      appointment = create_appointment(customer.id, tech.id, :on_site)
      _procedure = create_procedure_for_service(appointment.service_type_id)

      {:ok, view, _html} = live_job(conn, appointment.id)

      assert {:error, {:live_redirect, %{to: to}}} =
               view
               |> element("#job-start-wash")
               |> render_click()

      assert to =~ "/tech/checklist/"

      checklist_id = String.replace_prefix(to, "/tech/checklist/", "")
      assert {:ok, _uuid} = Ecto.UUID.cast(checklist_id)
    end

    test "start wash denies checklist creation after appointment is reassigned", %{
      conn: conn,
      tech: tech,
      customer: customer
    } do
      appointment = create_appointment(customer.id, tech.id, :on_site)
      _procedure = create_procedure_for_service(appointment.service_type_id)
      other_user = create_tech_customer("Start Wash Replacement")
      other_tech = create_tech_record(other_user)

      {:ok, view, _html} = live_job(conn, appointment.id)

      _reassigned_appointment = reassign_appointment(appointment, other_tech.id)

      assert {:error, {:redirect, %{to: "/tech"}}} =
               view
               |> element("#job-start-wash")
               |> render_click()

      {:ok, reloaded} = Ash.get(Appointment, appointment.id, authorize?: false)
      assert reloaded.status == :on_site
      assert reloaded.technician_id == other_tech.id
    end
  end
end
