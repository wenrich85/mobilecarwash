defmodule MobileCarWashWeb.Tech.JobLiveTest do
  use MobileCarWashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Operations.{Photo, Procedure, ProcedureStep, Technician}
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

  defp with_notes(appointment, notes) do
    appointment
    |> Ash.Changeset.for_update(:update, %{})
    |> Ash.Changeset.force_change_attribute(:notes, notes)
    |> Ash.update!(authorize?: false)
  end

  defp create_problem_photo!(appointment, attrs \\ %{}) do
    defaults = %{
      file_path: "/photos/appointments/#{appointment.id}/problem_area_front.jpg",
      original_filename: "problem_area_front.jpg",
      content_type: "image/jpeg",
      photo_type: :problem_area,
      caption: "Bird droppings on the front bumper",
      uploaded_by: :customer,
      car_part: :front
    }

    Photo
    |> Ash.Changeset.for_create(:upload, Map.merge(defaults, attrs))
    |> Ash.Changeset.force_change_attribute(:appointment_id, appointment.id)
    |> Ash.create!(authorize?: false)
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

  defp create_checklist_progress!(appointment) do
    procedure = create_procedure_for_service(appointment.service_type_id)

    {:ok, checklist} =
      MobileCarWash.Operations.AppointmentChecklist
      |> Ash.Changeset.for_create(:create, %{status: :in_progress})
      |> Ash.Changeset.force_change_attribute(:appointment_id, appointment.id)
      |> Ash.Changeset.force_change_attribute(:procedure_id, procedure.id)
      |> Ash.create()

    appointment
    |> Ash.Changeset.for_update(:update, %{})
    |> Ash.Changeset.force_change_attribute(:status, :in_progress)
    |> Ash.update!(authorize?: false)

    checklist
  end

  defp count_id(html, id), do: length(Regex.scan(~r/id="#{id}"/, html))

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

    test "renders prep cards for service vehicle address customer and notes", %{
      conn: conn,
      tech: tech,
      customer: customer
    } do
      appointment =
        customer.id
        |> create_appointment(tech.id, :confirmed)
        |> with_notes("Customer asked us to focus on the front bumper.")

      {:ok, view, html} = live_job(conn, appointment.id)

      assert has_element?(view, "#job-prep-cards")
      assert has_element?(view, "#job-service-card")
      assert has_element?(view, "#job-vehicle-card")
      assert has_element?(view, "#job-address-card")
      assert has_element?(view, "#job-customer-card")
      assert has_element?(view, "#job-notes-card")
      assert html =~ "Job Wash"
      assert html =~ "Toyota"
      assert html =~ "100 Job Ave"
      assert html =~ customer.phone
      assert html =~ "Customer asked us to focus on the front bumper."
    end

    test "renders a calm notes fallback when the appointment has no notes", %{
      conn: conn,
      tech: tech,
      customer: customer
    } do
      appointment = create_appointment(customer.id, tech.id, :confirmed)

      {:ok, view, html} = live_job(conn, appointment.id)

      assert has_element?(view, "#job-notes-card")
      assert html =~ "No appointment notes"
    end

    test "confirmed job renders one command header head-out action", %{
      conn: conn,
      tech: tech,
      customer: customer
    } do
      appointment = create_appointment(customer.id, tech.id, :confirmed)

      {:ok, view, html} = live_job(conn, appointment.id)

      assert has_element?(view, "#job-command-card")
      assert has_element?(view, "#job-head-out[data-role='job-primary-action']", "Head out")
      assert html =~ "Leave for this service stop"
      assert count_id(html, "job-head-out") == 1
    end

    test "command header includes a Maps-linked destination summary", %{
      conn: conn,
      tech: tech,
      customer: customer
    } do
      appointment = create_appointment(customer.id, tech.id, :confirmed)

      {:ok, view, _html} = live_job(conn, appointment.id)

      assert has_element?(
               view,
               "#job-header-address[href*='maps.apple.com']",
               "100 Job Ave, San Antonio, TX 78259"
             )
    end

    test "en-route job renders one command header arrived action", %{
      conn: conn,
      tech: tech,
      customer: customer
    } do
      appointment = create_appointment(customer.id, tech.id, :en_route)

      {:ok, view, html} = live_job(conn, appointment.id)

      assert has_element?(view, "#job-arrived[data-role='job-primary-action']", "Arrived")
      assert html =~ "Mark yourself on site"
      assert count_id(html, "job-arrived") == 1
    end

    test "on-site job renders one command header start-wash action", %{
      conn: conn,
      tech: tech,
      customer: customer
    } do
      appointment = create_appointment(customer.id, tech.id, :on_site)

      {:ok, view, html} = live_job(conn, appointment.id)

      assert has_element?(view, "#job-start-wash[data-role='job-primary-action']", "Start wash")
      assert html =~ "Start the wash"
      assert count_id(html, "job-start-wash") == 1
    end

    test "in-progress job renders one command header checklist link", %{
      conn: conn,
      tech: tech,
      customer: customer
    } do
      appointment = create_appointment(customer.id, tech.id, :on_site)
      checklist = create_checklist_progress!(appointment)

      {:ok, view, html} = live_job(conn, appointment.id)

      assert has_element?(
               view,
               "#job-open-checklist[data-role='job-primary-action'][href='/tech/checklist/#{checklist.id}']",
               "Continue checklist"
             )

      assert html =~ "Continue the active wash checklist"
      assert count_id(html, "job-open-checklist") == 1
    end

    test "pending job renders a non-clickable command state", %{
      conn: conn,
      tech: tech,
      customer: customer
    } do
      appointment = create_appointment(customer.id, tech.id, :pending)

      {:ok, view, html} = live_job(conn, appointment.id)

      assert has_element?(view, "#job-primary-waiting")
      assert html =~ "Waiting on dispatch"
      refute has_element?(view, "[data-role='job-primary-action']")
    end

    test "completed job renders a non-clickable command state", %{
      conn: conn,
      tech: tech,
      customer: customer
    } do
      appointment = create_appointment(customer.id, tech.id, :completed)

      {:ok, view, html} = live_job(conn, appointment.id)

      assert has_element?(view, "#job-primary-waiting")
      assert html =~ "Completed stop"
      assert html =~ "Review the completed service details."
      refute has_element?(view, "[data-role='job-primary-action']")
    end

    test "cancelled job renders a non-clickable command state", %{
      conn: conn,
      tech: tech,
      customer: customer
    } do
      appointment = create_appointment(customer.id, tech.id, :cancelled)

      {:ok, view, html} = live_job(conn, appointment.id)

      assert has_element?(view, "#job-primary-waiting")
      assert html =~ "Cancelled stop"
      assert html =~ "No field action is available for this appointment."
      refute has_element?(view, "[data-role='job-primary-action']")
    end

    test "renders customer problem photos with caption and car part", %{
      conn: conn,
      tech: tech,
      customer: customer
    } do
      appointment = create_appointment(customer.id, tech.id, :confirmed)
      photo = create_problem_photo!(appointment)

      non_problem_photo =
        create_problem_photo!(appointment, %{
          file_path: "/photos/appointments/#{appointment.id}/before_front.jpg",
          original_filename: "before_front.jpg",
          photo_type: :before
        })

      soft_deleted_problem_photo =
        appointment
        |> create_problem_photo!(%{
          file_path: "/photos/appointments/#{appointment.id}/problem_area_rear.jpg",
          original_filename: "problem_area_rear.jpg",
          car_part: :rear
        })
        |> Ash.Changeset.for_update(:soft_delete, %{})
        |> Ash.update!(authorize?: false)

      {:ok, view, html} = live_job(conn, appointment.id)

      assert has_element?(view, "#job-problem-photos")
      assert has_element?(view, "#job-problem-photo-#{photo.id}")
      assert html =~ ~s(src="#{photo.file_path}")
      assert html =~ "Bird droppings on the front bumper"
      assert html =~ "Front"
      refute has_element?(view, "#job-problem-photo-empty")
      refute has_element?(view, "#job-problem-photo-#{non_problem_photo.id}")
      refute has_element?(view, "#job-problem-photo-#{soft_deleted_problem_photo.id}")
    end

    test "renders an empty problem-photo state when the customer uploaded none", %{
      conn: conn,
      tech: tech,
      customer: customer
    } do
      appointment = create_appointment(customer.id, tech.id, :confirmed)

      {:ok, view, html} = live_job(conn, appointment.id)

      assert has_element?(view, "#job-problem-photos")
      assert has_element?(view, "#job-problem-photo-empty")
      assert html =~ "No customer problem photos"
    end

    test "problem photos are lightboxed and the overlay root renders", %{
      conn: conn,
      tech: tech,
      customer: customer
    } do
      appointment = create_appointment(customer.id, tech.id, :confirmed)
      create_problem_photo!(appointment)

      {:ok, _view, html} = live_job(conn, appointment.id)

      assert html =~ ~s(id="lightbox-root")
      assert html =~ ~s(data-lightbox="problem-photos")
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
