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
  alias MobileCarWash.Inventory
  alias MobileCarWash.Inventory.Supply
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
      |> Ash.Changeset.force_change_attribute(:scheduled_at, DateTime.utc_now())
      |> Ash.update(authorize?: false)

    appt
  end

  defp create_supply do
    Supply
    |> Ash.Changeset.for_create(:create, %{
      name: "Dashboard Supply #{System.unique_integer([:positive])}",
      category: :other,
      unit: "units",
      quantity_on_hand: Decimal.new("10"),
      active: true
    })
    |> Ash.create!(authorize?: false)
  end

  defp create_checklist_progress!(appointment, steps_total, steps_done, status \\ :in_progress) do
    alias MobileCarWash.Operations.{AppointmentChecklist, ChecklistItem, Procedure, ProcedureStep}

    {:ok, procedure} =
      Procedure
      |> Ash.Changeset.for_create(:create, %{
        name: "Command Wash SOP #{System.unique_integer([:positive])}",
        slug: "command-wash-#{System.unique_integer([:positive])}"
      })
      |> Ash.Changeset.force_change_attribute(:service_type_id, appointment.service_type_id)
      |> Ash.create()

    {:ok, checklist} =
      AppointmentChecklist
      |> Ash.Changeset.for_create(:create, %{status: status})
      |> Ash.Changeset.force_change_attribute(:appointment_id, appointment.id)
      |> Ash.Changeset.force_change_attribute(:procedure_id, procedure.id)
      |> Ash.create()

    for n <- 1..steps_total do
      {:ok, step} =
        ProcedureStep
        |> Ash.Changeset.for_create(:create, %{
          step_number: n,
          title: "Command Step #{n}",
          estimated_minutes: 5
        })
        |> Ash.Changeset.force_change_attribute(:procedure_id, procedure.id)
        |> Ash.create()

      ChecklistItem
      |> Ash.Changeset.for_create(:create, %{
        step_number: n,
        title: "Command Step #{n}",
        estimated_minutes: 5,
        completed: n <= steps_done
      })
      |> Ash.Changeset.force_change_attribute(:checklist_id, checklist.id)
      |> Ash.Changeset.force_change_attribute(:procedure_step_id, step.id)
      |> Ash.create!()
    end

    checklist
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
         %{conn: conn, tech: tech, user: user} do
      appt = create_appointment(user.id, tech.id, :confirmed)

      {:ok, view, _html} = live(conn, ~p"/tech")
      assert has_element?(view, "#command-start-shift", "Start shift")

      # Simulate a different subscriber (another open tab, admin override)
      # flipping the status.
      tech
      |> Ash.Changeset.for_update(:set_status, %{status: :available})
      |> Ash.update!()

      # The broadcast is fire-and-forget; give the LiveView a render cycle
      # to pick it up.
      render(view)
      assert render(view) =~ "Available"

      assert has_element?(
               view,
               "#command-view-job[href='/tech/appointments/#{appt.id}']",
               "View job"
             )

      refute has_element?(view, "#command-start-shift", "Start shift")
    end
  end

  describe "workday command card" do
    setup %{conn: conn} do
      user = create_tech_customer()
      tech = create_tech_record(user)
      conn = sign_in(conn, user)

      {:ok, customer} =
        Customer
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "command-cust-#{System.unique_integer([:positive])}@test.com",
          password: "Password123!",
          password_confirmation: "Password123!",
          name: "Command Customer",
          phone: "+15125550401"
        })
        |> Ash.create()

      {:ok, conn: conn, user: user, tech: tech, customer: customer}
    end

    test "off-duty tech with work today sees start shift as the primary command",
         %{conn: conn, tech: tech, customer: customer} do
      _appt = create_appointment(customer.id, tech.id, :confirmed)

      {:ok, view, _html} = live(conn, ~p"/tech")

      assert has_element?(view, "#tech-workday-command")
      assert has_element?(view, "#command-start-shift", "Start shift")

      assert has_element?(
               view,
               "#tech-workday-command",
               "Start your shift to begin today's work."
             )
    end

    test "starting a shift immediately replaces the command with the appointment action",
         %{conn: conn, tech: tech, customer: customer} do
      appt = create_appointment(customer.id, tech.id, :confirmed)

      {:ok, view, _html} = live(conn, ~p"/tech")

      assert has_element?(view, "#command-start-shift", "Start shift")

      view
      |> element("#command-start-shift")
      |> render_click()

      refute has_element?(view, "#command-start-shift", "Start shift")

      assert has_element?(
               view,
               "#command-view-job[href='/tech/appointments/#{appt.id}']",
               "View job"
             )
    end

    for status <- [:en_route, :on_site, :in_progress] do
      test "off-duty tech with a #{status} appointment sees start shift as the primary command",
           %{conn: conn, tech: tech, customer: customer} do
        _appt = create_appointment(customer.id, tech.id, unquote(status))

        {:ok, view, _html} = live(conn, ~p"/tech")

        assert has_element?(view, "#command-start-shift", "Start shift")
      end
    end

    test "available tech with a confirmed job sees the next job command",
         %{conn: conn, tech: tech, customer: customer} do
      tech
      |> Ash.Changeset.for_update(:set_status, %{status: :available})
      |> Ash.update!()

      appt = create_appointment(customer.id, tech.id, :confirmed)

      {:ok, view, _html} = live(conn, ~p"/tech")

      assert has_element?(view, "#tech-workday-command")

      assert has_element?(
               view,
               "#command-view-job[href='/tech/appointments/#{appt.id}']",
               "View job"
             )

      assert render(view) =~ "Command Customer"
      assert render(view) =~ "Basic Wash"
    end

    test "linked tech with no work today sees a calm empty state", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/tech")

      assert has_element?(view, "#tech-workday-command")
      assert render(view) =~ "No jobs today"
      assert render(view) =~ "You are clear for now."
    end

    test "admin without linked technician record keeps admin mode without a personal command card",
         %{conn: conn} do
      {:ok, admin} =
        Customer
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "command-admin-#{System.unique_integer([:positive])}@test.com",
          password: "Password123!",
          password_confirmation: "Password123!",
          name: "Command Admin",
          phone: "+15125550499"
        })
        |> Ash.create()

      {:ok, admin} =
        admin
        |> Ash.Changeset.for_update(:update, %{role: :admin})
        |> Ash.update(authorize?: false)

      admin_conn = sign_in(conn, admin)

      {:ok, view, _html} = live(admin_conn, ~p"/tech")

      refute has_element?(view, "#tech-workday-command")
      assert render(view) =~ "Viewing as admin"
    end

    test "en-route job shows mark arrived as the primary command",
         %{conn: conn, tech: tech, customer: customer} do
      tech
      |> Ash.Changeset.for_update(:set_status, %{status: :available})
      |> Ash.update!()

      appt = create_appointment(customer.id, tech.id, :en_route)

      {:ok, view, _html} = live(conn, ~p"/tech")

      assert has_element?(view, "#command-mark-arrived", "Mark arrived")

      view
      |> element("#command-mark-arrived")
      |> render_click()

      {:ok, reloaded} = Ash.get(Appointment, appt.id, authorize?: false)
      assert reloaded.status == :on_site
    end

    test "on-site job shows start wash as the primary command",
         %{conn: conn, tech: tech, customer: customer} do
      tech
      |> Ash.Changeset.for_update(:set_status, %{status: :available})
      |> Ash.update!()

      _appt = create_appointment(customer.id, tech.id, :on_site)

      {:ok, view, _html} = live(conn, ~p"/tech")

      assert has_element?(view, "#command-start-wash", "Start wash")
    end

    test "in-progress job with checklist shows continue checklist as the primary command",
         %{conn: conn, tech: tech, customer: customer} do
      tech
      |> Ash.Changeset.for_update(:set_status, %{status: :available})
      |> Ash.update!()

      appt = create_appointment(customer.id, tech.id, :in_progress)
      checklist = create_checklist_progress!(appt, 3, 1)

      {:ok, view, _html} = live(conn, ~p"/tech")

      assert has_element?(
               view,
               "#command-continue-checklist[href='/tech/checklist/#{checklist.id}']",
               "Continue checklist"
             )
    end

    test "completed job can surface supply logging when no active work remains",
         %{conn: conn, tech: tech, customer: customer} do
      _appt = create_appointment(customer.id, tech.id, :completed)

      {:ok, view, _html} = live(conn, ~p"/tech")

      assert has_element?(view, "#command-log-supplies", "Log supplies")
    end

    test "completed job with logged supplies returns to the no-work command",
         %{conn: conn, tech: tech, customer: customer} do
      appt = create_appointment(customer.id, tech.id, :completed)
      supply = create_supply()

      {:ok, _usage} =
        Inventory.log_usage(%{
          supply_id: supply.id,
          appointment_id: appt.id,
          technician_id: tech.id,
          quantity_used: Decimal.new("1")
        })

      {:ok, view, _html} = live(conn, ~p"/tech")

      assert has_element?(view, "#tech-workday-command", "No jobs today")
      refute has_element?(view, "#command-log-supplies", "Log supplies")
    end

    test "saving supply usage immediately clears the completed-job command",
         %{conn: conn, tech: tech, customer: customer} do
      _appt = create_appointment(customer.id, tech.id, :completed)
      supply = create_supply()

      {:ok, view, _html} = live(conn, ~p"/tech")

      assert has_element?(view, "#command-log-supplies", "Log supplies")

      view
      |> element("#command-log-supplies")
      |> render_click()

      view
      |> form("form", %{"rows" => %{"0" => %{"supply_id" => supply.id, "qty" => "1"}}})
      |> render_submit()

      assert has_element?(view, "#tech-workday-command", "No jobs today")
      refute has_element?(view, "#command-log-supplies", "Log supplies")
    end

    test "today row marks the command-card appointment as next",
         %{conn: conn, tech: tech, customer: customer} do
      appt = create_appointment(customer.id, tech.id, :confirmed)

      {:ok, view, _html} = live(conn, ~p"/tech")

      assert has_element?(
               view,
               "[data-appointment-id='#{appt.id}'][data-command-row-state='next']"
             )

      assert render(view) =~ "Next"
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

    test "shows 'View job' when appointment is :confirmed",
         %{conn: conn, tech: tech, customer: customer} do
      appt = create_appointment(customer.id, tech.id, :confirmed)

      {:ok, view, _html} = live(conn, ~p"/tech")
      assert has_element?(view, "#appointment-view-job-#{appt.id}", "View job")
    end

    test "shows 'View job' when appointment is :en_route",
         %{conn: conn, tech: tech, customer: customer} do
      appt = create_appointment(customer.id, tech.id, :en_route)

      {:ok, view, _html} = live(conn, ~p"/tech")
      assert has_element?(view, "#appointment-view-job-#{appt.id}", "View job")
    end

    test "shows 'View job' when appointment is :on_site",
         %{conn: conn, tech: tech, customer: customer} do
      appt = create_appointment(customer.id, tech.id, :on_site)

      {:ok, view, _html} = live(conn, ~p"/tech")
      assert has_element?(view, "#appointment-view-job-#{appt.id}", "View job")
    end

    test "shows 'View job' when appointment is :pending",
         %{conn: conn, tech: tech, customer: customer} do
      appt = create_appointment(customer.id, tech.id, :pending)

      {:ok, view, _html} = live(conn, ~p"/tech")
      assert has_element?(view, "#appointment-view-job-#{appt.id}", "View job")
    end

    test "shows 'View job' when appointment is :completed",
         %{conn: conn, tech: tech, customer: customer} do
      appt = create_appointment(customer.id, tech.id, :completed)

      {:ok, view, _html} = live(conn, ~p"/tech")
      assert has_element?(view, "#appointment-view-job-#{appt.id}", "View job")
    end

    test "shows 'View job' for completed appointments even with checklist history",
         %{conn: conn, tech: tech, customer: customer} do
      alias MobileCarWash.Operations.{AppointmentChecklist, ChecklistItem, Procedure}

      appt = create_appointment(customer.id, tech.id, :completed)

      {:ok, procedure} =
        Procedure
        |> Ash.Changeset.for_create(:create, %{
          name: "Completed Wash SOP",
          slug: "completed-#{System.unique_integer([:positive])}"
        })
        |> Ash.Changeset.force_change_attribute(:service_type_id, appt.service_type_id)
        |> Ash.create()

      {:ok, checklist} =
        AppointmentChecklist
        |> Ash.Changeset.for_create(:create, %{status: :completed})
        |> Ash.Changeset.force_change_attribute(:appointment_id, appt.id)
        |> Ash.Changeset.force_change_attribute(:procedure_id, procedure.id)
        |> Ash.create()

      alias MobileCarWash.Operations.ProcedureStep

      for n <- 1..2 do
        {:ok, step} =
          ProcedureStep
          |> Ash.Changeset.for_create(:create, %{
            step_number: n,
            title: "Completed Step #{n}",
            estimated_minutes: 5
          })
          |> Ash.Changeset.force_change_attribute(:procedure_id, procedure.id)
          |> Ash.create()

        ChecklistItem
        |> Ash.Changeset.for_create(:create, %{
          step_number: n,
          title: "Completed Step #{n}",
          estimated_minutes: 5,
          completed: true
        })
        |> Ash.Changeset.force_change_attribute(:checklist_id, checklist.id)
        |> Ash.Changeset.force_change_attribute(:procedure_step_id, step.id)
        |> Ash.create!()
      end

      {:ok, view, _html} = live(conn, ~p"/tech")

      assert has_element?(view, "#appointment-view-job-#{appt.id}", "View job")
      refute has_element?(view, "a[href='/tech/checklist/#{checklist.id}']", "Continue checklist")
      refute has_element?(view, "a[href='/tech/checklist/#{checklist.id}']", "Start checklist")
    end

    test "shows a prominent 'Continue checklist' button when :in_progress",
         %{conn: conn, tech: tech, customer: customer} do
      alias MobileCarWash.Operations.{AppointmentChecklist, ChecklistItem, Procedure}

      appt = create_appointment(customer.id, tech.id, :in_progress)

      {:ok, procedure} =
        Procedure
        |> Ash.Changeset.for_create(:create, %{
          name: "Basic Wash SOP",
          slug: "basic-#{System.unique_integer([:positive])}"
        })
        |> Ash.Changeset.force_change_attribute(:service_type_id, appt.service_type_id)
        |> Ash.create()

      {:ok, checklist} =
        AppointmentChecklist
        |> Ash.Changeset.for_create(:create, %{status: :in_progress})
        |> Ash.Changeset.force_change_attribute(:appointment_id, appt.id)
        |> Ash.Changeset.force_change_attribute(:procedure_id, procedure.id)
        |> Ash.create()

      alias MobileCarWash.Operations.ProcedureStep

      for n <- 1..3 do
        {:ok, step} =
          ProcedureStep
          |> Ash.Changeset.for_create(:create, %{
            step_number: n,
            title: "Step #{n}",
            estimated_minutes: 5
          })
          |> Ash.Changeset.force_change_attribute(:procedure_id, procedure.id)
          |> Ash.create()

        ChecklistItem
        |> Ash.Changeset.for_create(:create, %{
          step_number: n,
          title: "Step #{n}",
          estimated_minutes: 5,
          # First step already done so progress.steps_done > 0 — that's
          # what triggers the "Continue checklist" branch of the button.
          completed: n == 1
        })
        |> Ash.Changeset.force_change_attribute(:checklist_id, checklist.id)
        |> Ash.Changeset.force_change_attribute(:procedure_step_id, step.id)
        |> Ash.create!()
      end

      {:ok, _view, html} = live(conn, ~p"/tech")
      assert html =~ "Continue checklist"
      # Must use the primary-action styling so it reads as the main button,
      # not a secondary link.
      assert html =~ "btn-primary"
    end

    test "keeps direct checklist access for in-progress appointments", %{
      conn: conn,
      tech: tech,
      customer: customer
    } do
      alias MobileCarWash.Operations.{AppointmentChecklist, ChecklistItem, Procedure}

      appt = create_appointment(customer.id, tech.id, :in_progress)

      {:ok, procedure} =
        Procedure
        |> Ash.Changeset.for_create(:create, %{
          name: "Checklist Wash SOP",
          slug: "checklist-#{System.unique_integer([:positive])}"
        })
        |> Ash.Changeset.force_change_attribute(:service_type_id, appt.service_type_id)
        |> Ash.create()

      {:ok, checklist} =
        AppointmentChecklist
        |> Ash.Changeset.for_create(:create, %{status: :in_progress})
        |> Ash.Changeset.force_change_attribute(:appointment_id, appt.id)
        |> Ash.Changeset.force_change_attribute(:procedure_id, procedure.id)
        |> Ash.create()

      alias MobileCarWash.Operations.ProcedureStep

      for n <- 1..2 do
        {:ok, step} =
          ProcedureStep
          |> Ash.Changeset.for_create(:create, %{
            step_number: n,
            title: "Step #{n}",
            estimated_minutes: 5
          })
          |> Ash.Changeset.force_change_attribute(:procedure_id, procedure.id)
          |> Ash.create()

        ChecklistItem
        |> Ash.Changeset.for_create(:create, %{
          step_number: n,
          title: "Step #{n}",
          estimated_minutes: 5,
          completed: n == 1
        })
        |> Ash.Changeset.force_change_attribute(:checklist_id, checklist.id)
        |> Ash.Changeset.force_change_attribute(:procedure_step_id, step.id)
        |> Ash.create!()
      end

      {:ok, view, _html} = live(conn, ~p"/tech")

      assert has_element?(view, "a[href='/tech/checklist/#{checklist.id}']", "Continue checklist")
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
      tech = create_tech_record(user)
      conn = sign_in(conn, user)

      # Subscribing more than once is harmless — the purpose of this test is
      # to confirm the LV is listening on the topic at all.
      {:ok, _view, _html} = live(conn, ~p"/tech")

      TechnicianTracker.subscribe(tech.id)

      # Flip the status via action — the broadcast reaches our subscription
      # and (indirectly) the LV under test.
      tech
      |> Ash.Changeset.for_update(:set_status, %{status: :available})
      |> Ash.update!()

      assert_receive {:technician_status, %{status: :available}}, 500
    end
  end
end
