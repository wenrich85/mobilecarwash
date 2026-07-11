defmodule MobileCarWashWeb.ChecklistLiveTest do
  use MobileCarWashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MobileCarWash.Accounts.Customer

  alias MobileCarWash.Operations.{
    AppointmentChecklist,
    ChecklistItem,
    Procedure,
    ProcedureStep,
    Technician
  }

  alias MobileCarWash.Scheduling.{Appointment, ServiceType}

  defp create_tech_customer(name \\ "Checklist Tech") do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "checklist-tech-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: name,
        phone: "+15125550600"
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

  defp create_customer(name \\ "Checklist Customer") do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "checklist-customer-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: name,
        phone: "+15125550601"
      })
      |> Ash.create()

    customer
  end

  defp create_appointment(customer_id, technician_id, status) do
    {:ok, service} =
      ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Checklist Wash",
        slug: "checklist-wash-#{System.unique_integer([:positive])}",
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
        street: "100 Step Ave",
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

  defp create_checklist(appointment, status) do
    {:ok, procedure} =
      Procedure
      |> Ash.Changeset.for_create(:create, %{
        name: "Checklist SOP",
        slug: "checklist-sop-#{System.unique_integer([:positive])}"
      })
      |> Ash.Changeset.force_change_attribute(:service_type_id, appointment.service_type_id)
      |> Ash.create()

    {:ok, checklist} =
      AppointmentChecklist
      |> Ash.Changeset.for_create(:create, %{status: status})
      |> Ash.Changeset.force_change_attribute(:appointment_id, appointment.id)
      |> Ash.Changeset.force_change_attribute(:procedure_id, procedure.id)
      |> Ash.create()

    for {title, step_number} <- [{"Pre-rinse", 1}, {"Foam cannon", 2}] do
      {:ok, step} =
        ProcedureStep
        |> Ash.Changeset.for_create(:create, %{
          step_number: step_number,
          title: title,
          estimated_minutes: 5
        })
        |> Ash.Changeset.force_change_attribute(:procedure_id, procedure.id)
        |> Ash.create()

      ChecklistItem
      |> Ash.Changeset.for_create(:create, %{
        step_number: step_number,
        title: title,
        estimated_minutes: 5,
        required: true,
        completed: status == :completed
      })
      |> Ash.Changeset.force_change_attribute(:checklist_id, checklist.id)
      |> Ash.Changeset.force_change_attribute(:procedure_step_id, step.id)
      |> Ash.create!()
    end

    checklist
  end

  defp open_overlay(view) do
    view
    |> element("#before-photo-progress button[phx-value-type='before'][phx-value-area='front']")
    |> render_click()
  end

  defp jpeg_entry do
    %{
      name: "front.jpg",
      content: <<0xFF, 0xD8, 0xFF, 0xE0>> <> :binary.copy(<<0>>, 60_000),
      type: "image/jpeg"
    }
  end

  describe "active wash regions" do
    setup %{conn: conn} do
      user = create_tech_customer()
      tech = create_tech_record(user)
      customer = create_customer()

      {:ok, conn: sign_in(conn, user), tech: tech, customer: customer}
    end

    test "renders stable regions for an in-progress checklist", %{
      conn: conn,
      tech: tech,
      customer: customer
    } do
      appointment = create_appointment(customer.id, tech.id, :in_progress)
      checklist = create_checklist(appointment, :in_progress)

      {:ok, view, _html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      assert has_element?(view, "#active-wash")
      assert has_element?(view, "#before-photo-progress")
      assert has_element?(view, "#active-step-card")
      assert has_element?(view, "#all-steps-list")
      assert has_element?(view, "#after-photo-progress")
      assert has_element?(view, "#before-photo-progress [phx-click='show_upload']")
      refute has_element?(view, "#wrap-up-panel")
    end

    test "renders wrap-up panel for a completed checklist", %{
      conn: conn,
      tech: tech,
      customer: customer
    } do
      appointment = create_appointment(customer.id, tech.id, :in_progress)
      checklist = create_checklist(appointment, :completed)

      {:ok, view, _html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      assert has_element?(view, "#active-wash")
      assert has_element?(view, "#before-photo-progress")
      assert has_element?(view, "#active-step-card")
      assert has_element?(view, "#all-steps-list")
      assert has_element?(view, "#after-photo-progress")
      assert has_element?(view, "#wrap-up-panel")
      refute has_element?(view, "#before-photo-progress [phx-click='show_upload']")
    end
  end

  describe "photo upload overlay" do
    setup %{conn: conn} do
      user = create_tech_customer()
      tech = create_tech_record(user)
      customer = create_customer()
      appointment = create_appointment(customer.id, tech.id, :in_progress)
      checklist = create_checklist(appointment, :in_progress)

      {:ok,
       conn: sign_in(conn, user),
       tech: tech,
       customer: customer,
       appointment: appointment,
       checklist: checklist}
    end

    test "streams the upload in the background with a downscale hook", %{
      conn: conn,
      checklist: checklist
    } do
      {:ok, view, _html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      html = open_overlay(view)

      assert html =~ "data-phx-auto-upload"

      # The downscale hook must sit on a WRAPPER of the file input — the
      # input itself is claimed by LiveView's internal LiveFileUpload
      # hook (data-phx-hook wins over phx-hook), so a hook placed
      # directly on the input never mounts.
      assert has_element?(
               view,
               "[phx-hook='ImageDownscale'] input[type='file']"
             )

      refute has_element?(view, "input[type='file'][phx-hook]")
    end

    test "Save is gated until the transfer completes and shows progress", %{
      conn: conn,
      checklist: checklist
    } do
      {:ok, view, _html} = live(conn, ~p"/tech/checklist/#{checklist.id}")
      open_overlay(view)

      save_button = "#checklist-photo-form button[type='submit']"
      assert has_element?(view, "#{save_button}[disabled]")

      photo = file_input(view, "#checklist-photo-form", :photo, [jpeg_entry()])
      render_upload(photo, "front.jpg", 50)

      # Mid-transfer: progress bar visible, Save still disabled
      assert has_element?(view, "#checklist-photo-form progress")
      assert has_element?(view, "#{save_button}[disabled]")

      # Submitting mid-transfer must not crash or claim success
      html = view |> element("#checklist-photo-form") |> render_submit()
      refute html =~ "Photo saved."
      assert has_element?(view, "#checklist-photo-form")

      # percent is incremental — this second half completes the transfer
      render_upload(photo, "front.jpg", 50)
      refute has_element?(view, "#{save_button}[disabled]")
    end

    test "submitting with no photo keeps the overlay open and reports the problem", %{
      conn: conn,
      checklist: checklist
    } do
      {:ok, view, _html} = live(conn, ~p"/tech/checklist/#{checklist.id}")
      open_overlay(view)

      html = view |> element("#checklist-photo-form") |> render_submit()

      refute html =~ "Photo saved."
      assert html =~ "Select a photo first"
      assert has_element?(view, "#checklist-photo-form")
    end

    test "saving a completed upload stores the photo and confirms", %{
      conn: conn,
      checklist: checklist,
      appointment: appointment
    } do
      {:ok, view, _html} = live(conn, ~p"/tech/checklist/#{checklist.id}")
      open_overlay(view)

      photo = file_input(view, "#checklist-photo-form", :photo, [jpeg_entry()])
      render_upload(photo, "front.jpg", 100)

      html = view |> element("#checklist-photo-form") |> render_submit()

      assert html =~ "Photo saved."
      refute has_element?(view, "#checklist-photo-form")

      require Ash.Query

      saved =
        MobileCarWash.Operations.Photo
        |> Ash.Query.filter(appointment_id == ^appointment.id and photo_type == :before)
        |> Ash.read!()

      assert [%{car_part: :front, uploaded_by: :technician}] = saved
    end
  end
end
