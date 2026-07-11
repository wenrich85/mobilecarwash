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

  defp jpeg_entry(name) do
    %{
      name: name,
      content: <<0xFF, 0xD8, 0xFF, 0xE0>> <> :binary.copy(<<0>>, 60_000),
      type: "image/jpeg"
    }
  end

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
      assert has_element?(view, "#before-photo-form input[type='file']")
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
      refute has_element?(view, "#before-photo-form input[type='file']")
    end
  end

  describe "tile-based photo capture" do
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

    test "every key area tile exposes its own camera-direct input", %{
      conn: conn,
      checklist: checklist
    } do
      {:ok, view, html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      for area <- ~w(front rear driver_side passenger_side interior wheels) do
        assert has_element?(
                 view,
                 "#before-photo-form input[type='file'][name='before_#{area}']"
               )
      end

      # Tapping a tile opens the rear camera directly.
      assert html =~ ~s(capture="environment")

      # Downscale hook wraps the grid (the input itself is claimed by
      # LiveView's internal LiveFileUpload hook).
      assert has_element?(view, "#before-photo-form[phx-hook='ImageDownscale']")

      # The overlay and its Save button are gone.
      refute has_element?(view, "#checklist-photo-form")
      refute html =~ "Save Photo"
    end

    test "completed checklists hide all capture inputs", %{
      conn: conn,
      tech: tech,
      customer: customer
    } do
      appointment = create_appointment(customer.id, tech.id, :in_progress)
      checklist = create_checklist(appointment, :completed)

      {:ok, view, _html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      # Completed checklist: capture affordances hidden on both grids.
      refute has_element?(view, "#after-photo-form input[type='file']")
    end

    test "a completed tile upload auto-saves with its area and type", %{
      conn: conn,
      checklist: checklist,
      appointment: appointment
    } do
      {:ok, view, _html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      front = file_input(view, "#before-photo-form", :before_front, [jpeg_entry("front.jpg")])

      render_upload(front, "front.jpg", 50)
      # Mid-transfer: progress bar lives in the tile the photo belongs to.
      assert has_element?(view, "#tile-before-front progress")

      # percent is incremental — the second half completes the transfer
      # and the progress callback consumes + saves automatically.
      render_upload(front, "front.jpg", 50)

      html = render(view)
      refute html =~ "Photo saved."

      require Ash.Query

      saved =
        MobileCarWash.Operations.Photo
        |> Ash.Query.filter(appointment_id == ^appointment.id and photo_type == :before)
        |> Ash.read!()

      assert [%{car_part: :front, uploaded_by: :technician}] = saved

      # Tile now renders the persisted photo.
      assert has_element?(view, "#tile-before-front img")
      refute has_element?(view, "#tile-before-front progress")
    end

    test "two tiles upload concurrently, each with its own progress", %{
      conn: conn,
      checklist: checklist,
      appointment: appointment
    } do
      {:ok, view, _html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      front = file_input(view, "#before-photo-form", :before_front, [jpeg_entry("front.jpg")])
      rear = file_input(view, "#before-photo-form", :before_rear, [jpeg_entry("rear.jpg")])

      render_upload(front, "front.jpg", 50)
      render_upload(rear, "rear.jpg", 50)

      assert has_element?(view, "#tile-before-front progress")
      assert has_element?(view, "#tile-before-rear progress")

      render_upload(front, "front.jpg", 50)
      render_upload(rear, "rear.jpg", 50)

      require Ash.Query

      saved =
        MobileCarWash.Operations.Photo
        |> Ash.Query.filter(appointment_id == ^appointment.id and photo_type == :before)
        |> Ash.read!()

      assert Enum.sort(Enum.map(saved, & &1.car_part)) == [:front, :rear]
    end

    test "an oversized upload reports on its tile with a retry control", %{
      conn: conn,
      checklist: checklist
    } do
      {:ok, view, _html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      big = %{
        name: "huge.jpg",
        content: :binary.copy(<<0xFF>>, 10_000_001),
        type: "image/jpeg"
      }

      input = file_input(view, "#before-photo-form", :before_front, [big])
      assert {:error, [[_ref, :too_large]]} = render_upload(input, "huge.jpg")

      assert render(view) =~ "That photo is too large"
      assert has_element?(view, "#tile-before-front button", "Try again")

      # Try again clears the dead entry and returns the tile to capture state.
      view |> element("#tile-before-front button", "Try again") |> render_click()

      refute render(view) =~ "That photo is too large"
      assert has_element?(view, "#tile-before-front label[for]")
    end

    test "a failed save reports on the tile, not via flash", %{
      conn: conn,
      checklist: checklist,
      appointment: appointment
    } do
      {:ok, view, _html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      # A file under 4 bytes trips PhotoUpload's "File too small to
      # validate" — a deterministic, non-destructive save failure.
      tiny = %{name: "tiny.jpg", content: <<0xFF, 0xD8>>, type: "image/jpeg"}

      input = file_input(view, "#before-photo-form", :before_rear, [tiny])
      render_upload(input, "tiny.jpg")

      html = render(view)
      assert html =~ "Could not save photo"
      refute html =~ "Photo saved."

      require Ash.Query

      assert [] =
               MobileCarWash.Operations.Photo
               |> Ash.Query.filter(appointment_id == ^appointment.id and photo_type == :before)
               |> Ash.read!()

      # Tile is immediately retakeable (entry was consumed).
      assert has_element?(view, "#tile-before-rear label[for]")
    end
  end

  describe "external uploads (s3 backend)" do
    setup %{conn: conn} do
      prev_storage = Application.get_env(:mobile_car_wash, :photo_storage, :local)
      prev_key = Application.get_env(:ex_aws, :access_key_id)
      prev_secret = Application.get_env(:ex_aws, :secret_access_key)

      Application.put_env(:mobile_car_wash, :photo_storage, :s3)
      Application.put_env(:ex_aws, :access_key_id, "test-access-key")
      Application.put_env(:ex_aws, :secret_access_key, "test-secret-key")

      on_exit(fn ->
        Application.put_env(:mobile_car_wash, :photo_storage, prev_storage)
        Application.put_env(:ex_aws, :access_key_id, prev_key)
        Application.put_env(:ex_aws, :secret_access_key, prev_secret)
      end)

      user = create_tech_customer()
      tech = create_tech_record(user)
      customer = create_customer()
      appointment = create_appointment(customer.id, tech.id, :in_progress)
      checklist = create_checklist(appointment, :in_progress)

      {:ok, conn: sign_in(conn, user), appointment: appointment, checklist: checklist}
    end

    test "tile preflight returns S3PUT meta with a presigned key", %{
      conn: conn,
      checklist: checklist,
      appointment: appointment
    } do
      {:ok, view, _html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      input = file_input(view, "#before-photo-form", :before_front, [jpeg_entry("front.jpg")])

      {:ok, resp} = preflight_upload(input)
      meta = resp.entries |> Map.values() |> hd()

      # NOTE: if these fail with a KeyError, the preflight reply
      # string-encodes keys — switch to meta["uploader"], meta["url"],
      # meta["key"] accordingly. Assert the same values either way.
      assert meta.uploader == "S3PUT"
      assert meta.url =~ "X-Amz-Expires=300"
      assert meta.key =~ "appointments/#{appointment.id}/before_"
    end

    test "a completed external upload auto-saves the object key", %{
      conn: conn,
      checklist: checklist,
      appointment: appointment
    } do
      {:ok, view, _html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      input = file_input(view, "#before-photo-form", :before_front, [jpeg_entry("front.jpg")])
      render_upload(input, "front.jpg")

      require Ash.Query

      saved =
        MobileCarWash.Operations.Photo
        |> Ash.Query.filter(appointment_id == ^appointment.id and photo_type == :before)
        |> Ash.read!()

      assert [%{car_part: :front} = photo] = saved
      assert photo.file_path =~ ~r|^appointments/#{appointment.id}/before_[0-9a-f-]{36}\.jpg$|
    end
  end
end
