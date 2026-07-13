defmodule MobileCarWashWeb.ChecklistLiveTest do
  use MobileCarWashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Inventory.{Supply, SupplyUsage}

  alias MobileCarWash.Operations.{
    AppointmentChecklist,
    ChecklistItem,
    Photo,
    Procedure,
    ProcedureStep,
    Technician
  }

  alias MobileCarWash.Scheduling.{Appointment, ServiceType}

  require Ash.Query

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

  defp create_admin_user do
    create_customer("Checklist Admin")
    |> Ash.Changeset.for_update(:update, %{role: :admin})
    |> Ash.update!(authorize?: false)
  end

  defp reassign_appointment(appointment, technician_id) do
    appointment
    |> Ash.Changeset.for_update(:update, %{})
    |> Ash.Changeset.force_change_attribute(:technician_id, technician_id)
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

  defp create_photo(appointment, photo_type, car_part, caption \\ nil) do
    {:ok, photo} =
      Photo
      |> Ash.Changeset.for_create(:upload, %{
        file_path: "appointments/#{appointment.id}/#{photo_type}_#{car_part}.jpg",
        photo_type: photo_type,
        car_part: car_part,
        content_type: "image/jpeg",
        original_filename: "#{photo_type}_#{car_part}.jpg",
        caption: caption
      })
      |> Ash.Changeset.force_change_attribute(:appointment_id, appointment.id)
      |> Ash.create()

    photo
  end

  defp create_all_photos!(appointment, photo_type) do
    for area <- [:front, :rear, :driver_side, :passenger_side, :interior, :wheels] do
      create_photo(appointment, photo_type, area)
    end
  end

  defp checklist_items(checklist) do
    ChecklistItem
    |> Ash.Query.filter(checklist_id == ^checklist.id)
    |> Ash.Query.sort(step_number: :asc)
    |> Ash.read!(authorize?: false)
  end

  defp start_item!(item) do
    item
    |> Ash.Changeset.for_update(:start_step, %{})
    |> Ash.update!(authorize?: false)
  end

  defp complete_item!(item) do
    item
    |> Ash.Changeset.for_update(:check, %{})
    |> Ash.update!(authorize?: false)
  end

  defp create_supply!(attrs \\ %{}) do
    attrs = Map.new(attrs)

    Supply
    |> Ash.Changeset.for_create(
      :create,
      Map.merge(
        %{
          name: "Soap #{System.unique_integer([:positive])}",
          category: :chemicals,
          unit: "oz",
          quantity_on_hand: Decimal.new("32"),
          active: true
        },
        attrs
      )
    )
    |> Ash.create!(authorize?: false)
  end

  defp save_wrap_up!(checklist) do
    checklist
    |> Ash.Changeset.for_update(:save_wrap_up, %{final_notes: "Everything looks good."})
    |> Ash.update!(authorize?: false)
  end

  defp primary_action_count(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find("[data-role='wash-primary-action']")
    |> length()
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
      create_all_photos!(appointment, :before)
      create_all_photos!(appointment, :after)

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

  describe "checklist ownership" do
    test "allows the assigned technician and an admin to open a checklist", %{conn: conn} do
      assigned_user = create_tech_customer("Assigned Tech")
      assigned_tech = create_tech_record(assigned_user)
      customer = create_customer()
      appointment = create_appointment(customer.id, assigned_tech.id, :in_progress)
      checklist = create_checklist(appointment, :in_progress)
      admin = create_admin_user()

      assert {:ok, _view, _html} =
               conn
               |> sign_in(assigned_user)
               |> live(~p"/tech/checklist/#{checklist.id}")

      assert {:ok, _view, _html} =
               conn
               |> sign_in(admin)
               |> live(~p"/tech/checklist/#{checklist.id}")
    end

    test "denies another technician before rendering the checklist", %{conn: conn} do
      assigned_user = create_tech_customer("Assigned Tech")
      assigned_tech = create_tech_record(assigned_user)
      other_user = create_tech_customer("Other Tech")
      _other_tech = create_tech_record(other_user)
      customer = create_customer()
      appointment = create_appointment(customer.id, assigned_tech.id, :in_progress)
      checklist = create_checklist(appointment, :in_progress)

      assert {:error, {:redirect, %{to: "/tech"}}} =
               conn
               |> sign_in(other_user)
               |> live(~p"/tech/checklist/#{checklist.id}")
    end

    test "denies a stale technician from starting a step after reassignment", %{conn: conn} do
      assigned_user = create_tech_customer("Assigned Tech")
      assigned_tech = create_tech_record(assigned_user)
      other_user = create_tech_customer("Other Tech")
      other_tech = create_tech_record(other_user)
      customer = create_customer()
      appointment = create_appointment(customer.id, assigned_tech.id, :in_progress)
      checklist = create_checklist(appointment, :in_progress)
      create_all_photos!(appointment, :before)
      [_first | _] = checklist_items(checklist)

      {:ok, view, _html} =
        conn
        |> sign_in(assigned_user)
        |> live(~p"/tech/checklist/#{checklist.id}")

      reassign_appointment(appointment, other_tech.id)

      assert {:error, {:redirect, %{to: "/tech"}}} =
               view
               |> element("#wash-command-start-step")
               |> render_click()

      refute checklist_items(checklist) |> hd() |> Map.fetch!(:started_at)
    end
  end

  describe "wash command card" do
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

    test "points to before photos when required before photos are missing", %{
      conn: conn,
      checklist: checklist
    } do
      {:ok, view, html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      assert has_element?(view, "#wash-command-card")
      assert has_element?(view, "#wash-command-before-photos[href='#before-photo-progress']")
      assert html =~ "Finish before photos"
      assert primary_action_count(html) == 1
    end

    test "starts the next step after before photos are complete", %{
      conn: conn,
      appointment: appointment,
      checklist: checklist
    } do
      create_all_photos!(appointment, :before)

      {:ok, view, html} = live(conn, ~p"/tech/checklist/#{checklist.id}")
      [first | _] = checklist_items(checklist)

      assert has_element?(
               view,
               "#wash-command-start-step[phx-click='start_step'][phx-value-id='#{first.id}']",
               "Start Pre-rinse"
             )

      assert primary_action_count(html) == 1
    end

    test "completes the active step when a step is running", %{
      conn: conn,
      appointment: appointment,
      checklist: checklist
    } do
      create_all_photos!(appointment, :before)
      [first | _] = checklist_items(checklist)
      start_item!(first)

      {:ok, view, html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      assert has_element?(
               view,
               "#wash-command-complete-step[phx-click='complete_step'][phx-value-id='#{first.id}']",
               "Complete Pre-rinse"
             )

      assert primary_action_count(html) == 1
    end

    test "points to after photos after required steps are complete", %{
      conn: conn,
      appointment: appointment,
      checklist: checklist
    } do
      create_all_photos!(appointment, :before)
      checklist |> checklist_items() |> Enum.each(&complete_item!/1)

      {:ok, view, html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      assert has_element?(view, "#wash-command-after-photos[href='#after-photo-progress']")
      assert html =~ "Finish after photos"
      assert primary_action_count(html) == 1
    end

    test "points to wrap-up after after photos complete", %{
      conn: conn,
      appointment: appointment,
      checklist: checklist
    } do
      create_all_photos!(appointment, :before)
      checklist |> checklist_items() |> Enum.each(&complete_item!/1)
      create_all_photos!(appointment, :after)

      {:ok, view, html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      assert has_element?(view, "#wash-command-wrap-up[href='#wrap-up-panel']")
      assert html =~ "Wrap up"
      assert primary_action_count(html) == 1
    end

    test "points to wrap-up for a completed checklist without final notes", %{
      conn: conn,
      tech: tech,
      customer: customer
    } do
      appointment = create_appointment(customer.id, tech.id, :in_progress)
      checklist = create_checklist(appointment, :completed)
      create_all_photos!(appointment, :before)
      create_all_photos!(appointment, :after)

      {:ok, view, html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      assert has_element?(view, "#wash-command-wrap-up[href='#wrap-up-panel']")
      refute has_element?(view, "#wash-command-dashboard")
      assert primary_action_count(html) == 1
    end

    test "completed checklist without final notes still points to wrap-up when photos are missing",
         %{
           conn: conn,
           tech: tech,
           customer: customer
         } do
      appointment = create_appointment(customer.id, tech.id, :in_progress)
      checklist = create_checklist(appointment, :completed)

      {:ok, view, html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      assert has_element?(view, "#wash-command-wrap-up[href='#wrap-up-panel']")
      assert has_element?(view, "#wrap-up-panel")
      refute has_element?(view, "#wash-command-before-photos")
      assert primary_action_count(html) == 1
    end

    test "points to dashboard for a completed checklist with final notes", %{
      conn: conn,
      tech: tech,
      customer: customer
    } do
      appointment = create_appointment(customer.id, tech.id, :in_progress)
      checklist = create_checklist(appointment, :completed)
      save_wrap_up!(checklist)

      {:ok, view, html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      assert has_element?(view, "#wash-command-dashboard[href='/tech']")
      refute has_element?(view, "#wash-command-wrap-up")
      assert primary_action_count(html) == 1
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

  describe "lightbox wiring" do
    test "problem strip and captured tiles are lightboxed with alt; root renders once", %{
      conn: conn
    } do
      user = create_tech_customer()
      tech = create_tech_record(user)
      customer = create_customer()
      appointment = create_appointment(customer.id, tech.id, :in_progress)
      checklist = create_checklist(appointment, :in_progress)

      create_photo(appointment, :problem_area, :front, "Scratch on hood")
      create_photo(appointment, :before, :front)

      conn = sign_in(conn, user)

      {:ok, _view, html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      assert html =~ ~s(id="lightbox-root")
      assert html =~ ~s(data-lightbox="problem-photos")
      assert html =~ ~s(data-lightbox-caption="Scratch on hood")
      assert html =~ ~s(data-lightbox="checklist-photos")
      # ghost overlay img must NOT be wired
      refute html =~ ~r/opacity-20[^>]*data-lightbox/
      refute html =~ ~r/<img(?![^>]*alt=)[^>]*data-lightbox/
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

  describe "wrap-up final notes" do
    setup %{conn: conn} do
      user = create_tech_customer()
      tech = create_tech_record(user)
      customer = create_customer()
      appointment = create_appointment(customer.id, tech.id, :in_progress)
      checklist = create_checklist(appointment, :in_progress)
      create_all_photos!(appointment, :before)
      checklist |> checklist_items() |> Enum.each(&complete_item!/1)
      create_all_photos!(appointment, :after)

      {:ok,
       conn: sign_in(conn, user),
       tech: tech,
       customer: customer,
       appointment: appointment,
       checklist: checklist}
    end

    test "persists final notes from the wrap-up form", %{conn: conn, checklist: checklist} do
      {:ok, view, _html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      assert has_element?(view, "#wrap-up-form")
      assert has_element?(view, "#wrap-up-final-notes")

      view
      |> form("#wrap-up-form", %{
        "wrap_up" => %{
          "final_notes" => "Customer requested extra attention on wheels.",
          "supplies" => %{}
        }
      })
      |> render_submit()

      reloaded = Ash.get!(AppointmentChecklist, checklist.id, authorize?: false)
      assert reloaded.final_notes == "Customer requested extra attention on wheels."
      assert has_element?(view, "#wrap-up-saved-final-notes")
      assert render(view) =~ "Customer requested extra attention on wheels."
    end

    test "rejects a crafted wrap-up save before required work and photos are complete", %{
      conn: conn,
      tech: tech,
      customer: customer
    } do
      appointment = create_appointment(customer.id, tech.id, :in_progress)
      checklist = create_checklist(appointment, :in_progress)

      {:ok, view, _html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      render_submit(view, "save_wrap_up", %{
        "wrap_up" => %{"final_notes" => "Premature", "supplies" => %{}}
      })

      assert has_element?(view, "#wrap-up-error", "Complete all required steps and after photos")
      assert Ash.get!(AppointmentChecklist, checklist.id, authorize?: false).final_notes == nil
    end

    test "can save wrap-up with blank notes", %{conn: conn, checklist: checklist} do
      {:ok, view, _html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      view
      |> form("#wrap-up-form", %{"wrap_up" => %{"final_notes" => "", "supplies" => %{}}})
      |> render_submit()

      reloaded = Ash.get!(AppointmentChecklist, checklist.id, authorize?: false)
      assert reloaded.final_notes == ""
      assert render(view) =~ "Wrap-up saved"
    end

    test "completed checklist command returns to dashboard", %{
      conn: conn,
      appointment: appointment,
      checklist: checklist
    } do
      create_all_photos!(appointment, :before)
      create_all_photos!(appointment, :after)

      {:ok, checklist} =
        checklist
        |> Ash.Changeset.for_update(:complete_checklist, %{})
        |> Ash.update(authorize?: false)

      {:ok, checklist} =
        checklist
        |> Ash.Changeset.for_update(:save_wrap_up, %{final_notes: "Wrap-up complete."})
        |> Ash.update(authorize?: false)

      {:ok, view, html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      assert has_element?(view, "#wash-command-dashboard[href='/tech']", "Back to dashboard")
      assert primary_action_count(html) == 1
      refute has_element?(view, "#before-photo-form input[type='file']")
      refute has_element?(view, "#after-photo-form input[type='file']")
    end

    test "saving wrap-up does not remove lightbox wiring or time analysis", %{
      conn: conn,
      appointment: appointment,
      checklist: checklist
    } do
      create_photo(appointment, :problem_area, :front, "Bug marks")

      {:ok, view, _html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      view
      |> form("#wrap-up-form", %{"wrap_up" => %{"final_notes" => "Done", "supplies" => %{}}})
      |> render_submit()

      html = render(view)
      assert html =~ ~s(data-lightbox="problem-photos")
      assert has_element?(view, "#wrap-up-panel")
      assert html =~ "Time Analysis"
    end

    test "logs supply usage and decrements inventory", %{
      conn: conn,
      tech: tech,
      appointment: appointment,
      checklist: checklist
    } do
      supply = create_supply!(name: "Foam Soap", quantity_on_hand: Decimal.new("16"))

      {:ok, view, _html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      view
      |> form("#wrap-up-form", %{
        "wrap_up" => %{
          "final_notes" => "Used normal soap amount.",
          "supplies" => %{
            "0" => %{
              "supply_id" => supply.id,
              "quantity_used" => "2.5",
              "notes" => "Foam pass"
            }
          }
        }
      })
      |> render_submit()

      usages =
        SupplyUsage
        |> Ash.Query.filter(appointment_id == ^appointment.id)
        |> Ash.read!(authorize?: false)

      assert [
               %{
                 supply_id: supply_id,
                 technician_id: technician_id,
                 quantity_used: quantity_used,
                 notes: "Foam pass"
               }
             ] = usages

      assert supply_id == supply.id
      assert technician_id == tech.id
      assert Decimal.equal?(quantity_used, Decimal.new("2.5"))

      reloaded_supply = Ash.get!(Supply, supply.id, authorize?: false)
      assert Decimal.equal?(reloaded_supply.quantity_on_hand, Decimal.new("13.5"))

      assert has_element?(view, "#wrap-up-usage-list")
      assert render(view) =~ "Foam Soap"
    end

    test "uses the assigned technician van for supply usage", %{
      conn: conn,
      tech: tech,
      appointment: appointment,
      checklist: checklist
    } do
      van =
        MobileCarWash.Operations.Van
        |> Ash.Changeset.for_create(:create, %{name: "Wrap-up Van"})
        |> Ash.create!(authorize?: false)

      tech
      |> Ash.Changeset.for_update(:update, %{})
      |> Ash.Changeset.force_change_attribute(:van_id, van.id)
      |> Ash.update!(authorize?: false)

      supply = create_supply!()
      {:ok, view, _html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      view
      |> form("#wrap-up-form", %{
        "wrap_up" => %{
          "final_notes" => "Van usage",
          "supplies" => %{
            "0" => %{"supply_id" => supply.id, "quantity_used" => "1", "notes" => ""}
          }
        }
      })
      |> render_submit()

      assert [%{van_id: van_id}] =
               SupplyUsage
               |> Ash.Query.filter(appointment_id == ^appointment.id)
               |> Ash.read!(authorize?: false)

      assert van_id == van.id
    end

    test "invalid supply quantity shows an inline error and creates no usage", %{
      conn: conn,
      appointment: appointment,
      checklist: checklist
    } do
      supply = create_supply!()

      {:ok, view, _html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      view
      |> form("#wrap-up-form", %{
        "wrap_up" => %{
          "final_notes" => "",
          "supplies" => %{
            "0" => %{"supply_id" => supply.id, "quantity_used" => "0", "notes" => ""}
          }
        }
      })
      |> render_submit()

      assert has_element?(view, "#wrap-up-error")
      assert render(view) =~ "Enter a quantity greater than 0"

      usages =
        SupplyUsage
        |> Ash.Query.filter(appointment_id == ^appointment.id)
        |> Ash.read!(authorize?: false)

      assert usages == []
    end

    test "preserves entered wrap-up values after supply validation fails", %{
      conn: conn,
      checklist: checklist
    } do
      supply = create_supply!()
      {:ok, view, _html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      view
      |> form("#wrap-up-form", %{
        "wrap_up" => %{
          "final_notes" => "Keep this note",
          "supplies" => %{
            "0" => %{
              "supply_id" => supply.id,
              "quantity_used" => "0",
              "notes" => "Keep this supply note"
            }
          }
        }
      })
      |> render_submit()

      assert has_element?(view, "#wrap-up-final-notes", "Keep this note")

      assert has_element?(view, "#wrap-up-supply-0 option[value='#{supply.id}'][selected]")
      assert has_element?(view, "#wrap-up-supply-0-quantity[value='0']")
      assert has_element?(view, "#wrap-up-supply-0-note[value='Keep this supply note']")
    end

    test "rejects repeat wrap-up submissions without duplicating supply usage", %{
      conn: conn,
      appointment: appointment,
      checklist: checklist
    } do
      supply = create_supply!(quantity_on_hand: Decimal.new("16"))
      {:ok, view, _html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      params = %{
        "wrap_up" => %{
          "final_notes" => "Saved once",
          "supplies" => %{
            "0" => %{"supply_id" => supply.id, "quantity_used" => "2", "notes" => ""}
          }
        }
      }

      view |> form("#wrap-up-form", params) |> render_submit()
      refute has_element?(view, "#wrap-up-form")

      render_submit(view, "save_wrap_up", params)

      assert has_element?(view, "#wrap-up-error", "Wrap-up has already been saved")

      assert [usage] =
               SupplyUsage
               |> Ash.Query.filter(appointment_id == ^appointment.id)
               |> Ash.read!(authorize?: false)

      assert Decimal.equal?(usage.quantity_used, Decimal.new("2"))

      assert Decimal.equal?(
               Ash.get!(Supply, supply.id, authorize?: false).quantity_on_hand,
               Decimal.new("14")
             )
    end

    test "denies a stale technician wrap-up submission after reassignment", %{
      conn: conn,
      customer: customer,
      appointment: appointment,
      checklist: checklist
    } do
      other_user = create_tech_customer("Replacement Tech")
      other_tech = create_tech_record(other_user)
      {:ok, view, _html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      reassign_appointment(appointment, other_tech.id)

      assert {:error, {:redirect, %{to: "/tech"}}} =
               view
               |> form("#wrap-up-form", %{
                 "wrap_up" => %{"final_notes" => "Not allowed", "supplies" => %{}}
               })
               |> render_submit()

      assert Ash.get!(AppointmentChecklist, checklist.id, authorize?: false).final_notes == nil
      assert customer.id == appointment.customer_id
    end

    test "rolls back final notes and usage when supply logging fails", %{
      conn: conn,
      appointment: appointment,
      checklist: checklist
    } do
      used_supply = create_supply!(name: "Available Soap")
      stale_supply = create_supply!(name: "Stale Cleaner")

      {:ok, view, _html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      MobileCarWash.Repo.query!("DELETE FROM supplies WHERE id = $1", [
        Ecto.UUID.dump!(stale_supply.id)
      ])

      view
      |> form("#wrap-up-form", %{
        "wrap_up" => %{
          "final_notes" => "This must not be saved.",
          "supplies" => %{
            "0" => %{
              "supply_id" => used_supply.id,
              "quantity_used" => "2.5",
              "notes" => "Valid first row"
            },
            "1" => %{
              "supply_id" => stale_supply.id,
              "quantity_used" => "2.5",
              "notes" => "Missing supply"
            }
          }
        }
      })
      |> render_submit()

      reloaded = Ash.get!(AppointmentChecklist, checklist.id, authorize?: false)
      assert reloaded.final_notes == nil

      usages =
        SupplyUsage
        |> Ash.Query.filter(appointment_id == ^appointment.id)
        |> Ash.read!(authorize?: false)

      assert usages == []
      reloaded_supply = Ash.get!(Supply, used_supply.id, authorize?: false)
      assert Decimal.equal?(reloaded_supply.quantity_on_hand, Decimal.new("32"))
      assert has_element?(view, "#wrap-up-error")
    end

    test "renders flat-rate earnings summary", %{conn: conn, checklist: checklist} do
      {:ok, view, _html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      assert has_element?(view, "#wrap-up-earnings")
      assert render(view) =~ "$25.00"
    end
  end
end
