defmodule MobileCarWashWeb.AppointmentStatusLiveTest do
  @moduledoc """
  Covers the customer-facing "Cancel booking" affordance on the appointment
  status page. Button is visible only when the appointment is pending or
  confirmed — hidden once the wash is in progress or completed, and hidden
  after a successful cancel.
  """
  use MobileCarWashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Scheduling.{Appointment, ServiceType}
  alias MobileCarWash.Fleet.{Address, Vehicle}
  alias MobileCarWash.Operations.Photo

  defp register_customer do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "cancel-live-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Cancel Live",
        phone: "+15125558000"
      })
      |> Ash.create()

    customer
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

  defp create_appointment(customer, status \\ :pending) do
    {:ok, service} =
      ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Basic Wash",
        slug: "cancel-live-#{System.unique_integer([:positive])}",
        base_price_cents: 5_000,
        duration_minutes: 45
      })
      |> Ash.create()

    {:ok, vehicle} =
      Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "Toyota", model: "Camry"})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, address} =
      Address
      |> Ash.Changeset.for_create(:create, %{
        street: "123 Cancel St",
        city: "San Antonio",
        state: "TX",
        zip: "78259"
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, appt} =
      Appointment
      |> Ash.Changeset.for_create(:book, %{
        customer_id: customer.id,
        vehicle_id: vehicle.id,
        address_id: address.id,
        service_type_id: service.id,
        scheduled_at: DateTime.add(DateTime.utc_now(), 2 * 86_400, :second),
        price_cents: 5_000,
        duration_minutes: 45
      })
      |> Ash.create()

    if status != :pending do
      {:ok, appt} =
        appt
        |> Ash.Changeset.for_update(:update, %{status: status})
        |> Ash.update()

      appt
    else
      appt
    end
  end

  defp create_photo(appt, photo_type, car_part, file_path) do
    {:ok, photo} =
      Photo
      |> Ash.Changeset.for_create(:upload, %{
        file_path: file_path,
        photo_type: photo_type,
        car_part: car_part,
        content_type: "image/jpeg",
        original_filename: Path.basename(file_path)
      })
      |> Ash.Changeset.force_change_attribute(:appointment_id, appt.id)
      |> Ash.create()

    photo
  end

  describe "cancel button visibility" do
    test "is rendered when the appointment is pending", %{conn: conn} do
      customer = register_customer()
      appt = create_appointment(customer, :pending)
      conn = sign_in(conn, customer)

      {:ok, _view, html} = live(conn, ~p"/appointments/#{appt.id}/status")
      assert html =~ "Cancel booking"
    end

    test "is rendered when the appointment is confirmed", %{conn: conn} do
      customer = register_customer()
      appt = create_appointment(customer, :confirmed)
      conn = sign_in(conn, customer)

      {:ok, _view, html} = live(conn, ~p"/appointments/#{appt.id}/status")
      assert html =~ "Cancel booking"
    end

    test "is hidden when the appointment is in_progress", %{conn: conn} do
      customer = register_customer()
      appt = create_appointment(customer, :in_progress)
      conn = sign_in(conn, customer)

      {:ok, _view, html} = live(conn, ~p"/appointments/#{appt.id}/status")
      refute html =~ "Cancel booking"
    end

    test "is hidden when the appointment is completed", %{conn: conn} do
      customer = register_customer()
      appt = create_appointment(customer, :completed)
      conn = sign_in(conn, customer)

      {:ok, _view, html} = live(conn, ~p"/appointments/#{appt.id}/status")
      refute html =~ "Cancel booking"
    end

    test "is hidden when the appointment is already cancelled", %{conn: conn} do
      customer = register_customer()
      appt = create_appointment(customer, :cancelled)
      conn = sign_in(conn, customer)

      {:ok, _view, html} = live(conn, ~p"/appointments/#{appt.id}/status")
      refute html =~ "Cancel booking"
    end
  end

  describe "cancel flow" do
    test "clicking cancel updates status and hides the button",
         %{conn: conn} do
      customer = register_customer()
      appt = create_appointment(customer, :pending)
      conn = sign_in(conn, customer)

      {:ok, view, _} = live(conn, ~p"/appointments/#{appt.id}/status")

      html =
        view
        |> element("button", "Cancel booking")
        |> render_click()

      refute html =~ "Cancel booking"
      assert html =~ "Appointment cancelled"

      {:ok, reloaded} = Ash.get(Appointment, appt.id, authorize?: false)
      assert reloaded.status == :cancelled
      assert reloaded.cancellation_reason
    end
  end

  describe "photo loading" do
    test "soft-deleted photos never render", %{conn: conn} do
      customer = register_customer()
      appt = create_appointment(customer, :in_progress)
      photo = create_photo(appt, :before, :front, "/uploads/front-old.jpg")

      {:ok, _} =
        photo
        |> Ash.Changeset.for_update(:soft_delete, %{})
        |> Ash.update()

      create_photo(appt, :before, :front, "/uploads/front-new.jpg")
      conn = sign_in(conn, customer)

      {:ok, _view, html} = live(conn, ~p"/appointments/#{appt.id}/status")
      refute html =~ "front-old.jpg"
      assert html =~ "front-new.jpg"
    end
  end

  describe "reveal mode (completed wash)" do
    test "renders a slider per complete pair, in priority order", %{conn: conn} do
      customer = register_customer()
      appt = create_appointment(customer, :completed)
      create_photo(appt, :before, :front, "/uploads/front-b.jpg")
      create_photo(appt, :after, :front, "/uploads/front-a.jpg")
      create_photo(appt, :before, :wheels, "/uploads/wheels-b.jpg")
      create_photo(appt, :after, :wheels, "/uploads/wheels-a.jpg")
      conn = sign_in(conn, customer)

      {:ok, _view, html} = live(conn, ~p"/appointments/#{appt.id}/status")

      assert html =~ ~s(id="reveal-front")
      assert html =~ ~s(id="reveal-wheels")
      assert html =~ ~s(phx-hook="BeforeAfterSlider")
      assert html =~ ~s(data-before-url="/uploads/front-b.jpg")
      assert html =~ ~s(data-after-url="/uploads/front-a.jpg")
      # priority order: front slider appears before wheels slider
      {front_pos, _} = :binary.match(html, ~s(id="reveal-front"))
      {wheels_pos, _} = :binary.match(html, ~s(id="reveal-wheels"))
      assert front_pos < wheels_pos
    end

    test "incomplete pairs fall to the More photos strip, empty areas render nothing", %{
      conn: conn
    } do
      customer = register_customer()
      appt = create_appointment(customer, :completed)
      # rear has only a before — no slider, lands in strip
      create_photo(appt, :before, :rear, "/uploads/rear-b.jpg")
      conn = sign_in(conn, customer)

      {:ok, _view, html} = live(conn, ~p"/appointments/#{appt.id}/status")

      refute html =~ ~s(id="reveal-rear")
      assert html =~ "More photos"
      assert html =~ "/uploads/rear-b.jpg"
      # no placeholder circles in reveal mode
      refute html =~ "○"
    end

    test "in-progress wash keeps the live grid, no sliders", %{conn: conn} do
      customer = register_customer()
      appt = create_appointment(customer, :in_progress)
      create_photo(appt, :before, :front, "/uploads/front-b.jpg")
      create_photo(appt, :after, :front, "/uploads/front-a.jpg")
      conn = sign_in(conn, customer)

      {:ok, _view, html} = live(conn, ~p"/appointments/#{appt.id}/status")

      refute html =~ "BeforeAfterSlider"
      assert html =~ "Before"
      assert html =~ "After"
      assert html =~ "/uploads/front-b.jpg"
    end
  end

  describe "share your wash" do
    defp completed_with_pair(conn) do
      customer = register_customer()
      appt = create_appointment(customer, :completed)
      create_photo(appt, :before, :front, "/uploads/front-b.jpg")
      create_photo(appt, :after, :front, "/uploads/front-a.jpg")
      create_photo(appt, :before, :wheels, "/uploads/wheels-b.jpg")
      create_photo(appt, :after, :wheels, "/uploads/wheels-a.jpg")
      {sign_in(conn, customer), appt}
    end

    test "CTA renders only when a complete pair exists", %{conn: conn} do
      {conn2, appt} = completed_with_pair(conn)
      {:ok, _view, html} = live(conn2, ~p"/appointments/#{appt.id}/status")
      assert html =~ "Share your wash"

      customer = register_customer()
      bare = create_appointment(customer, :completed)
      create_photo(bare, :before, :front, "/uploads/only-before.jpg")
      conn3 = sign_in(conn, customer)
      {:ok, _view, html} = live(conn3, ~p"/appointments/#{bare.id}/status")
      refute html =~ "Share your wash"
    end

    test "modal opens with the first pair preselected and referral data wired", %{conn: conn} do
      {conn, appt} = completed_with_pair(conn)
      {:ok, view, _html} = live(conn, ~p"/appointments/#{appt.id}/status")

      html = view |> element("button", "Share your wash") |> render_click()

      assert html =~ ~s(id="share-wash-card")
      assert html =~ ~s(phx-hook="ShareWashCard")
      assert html =~ ~s(data-before-url="/uploads/front-b.jpg")
      assert html =~ ~s(data-after-url="/uploads/front-a.jpg")
      assert html =~ "utm_source=referral"
      # referral code present and embedded in the share link
      assert [_, code] = Regex.run(~r/data-referral-code="([^"]+)"/, html)
      assert html =~ "ref=#{code}"
    end

    test "smart default is the first complete pair in priority order when front is incomplete",
         %{conn: conn} do
      customer = register_customer()
      appt = create_appointment(customer, :completed)
      # front has only a before (incomplete); wheels is the only complete pair
      create_photo(appt, :before, :front, "/uploads/front-b.jpg")
      create_photo(appt, :before, :wheels, "/uploads/wheels-b.jpg")
      create_photo(appt, :after, :wheels, "/uploads/wheels-a.jpg")
      conn = sign_in(conn, customer)

      {:ok, view, _html} = live(conn, ~p"/appointments/#{appt.id}/status")
      html = view |> element("button", "Share your wash") |> render_click()

      assert html =~ ~s(data-before-url="/uploads/wheels-b.jpg")
      assert html =~ ~s(data-after-url="/uploads/wheels-a.jpg")
    end

    test "selecting another pair updates the share button dataset", %{conn: conn} do
      {conn, appt} = completed_with_pair(conn)
      {:ok, view, _html} = live(conn, ~p"/appointments/#{appt.id}/status")
      view |> element("button", "Share your wash") |> render_click()

      html =
        view
        |> element(~s(button[phx-value-area="wheels"]))
        |> render_click()

      assert html =~ ~s(data-before-url="/uploads/wheels-b.jpg")
      assert html =~ ~s(data-after-url="/uploads/wheels-a.jpg")
    end

    test "open_share_modal is a no-op when no complete pair exists", %{conn: conn} do
      customer = register_customer()
      appt = create_appointment(customer, :completed)
      conn = sign_in(conn, customer)

      {:ok, view, _html} = live(conn, ~p"/appointments/#{appt.id}/status")
      html = render_hook(view, "open_share_modal", %{})

      refute html =~ ~s(id="share-wash-modal")
      assert Process.alive?(view.pid)
    end

    test "share_degraded and share_fallback_done render inline notices", %{conn: conn} do
      {conn, appt} = completed_with_pair(conn)
      {:ok, view, _html} = live(conn, ~p"/appointments/#{appt.id}/status")
      view |> element("button", "Share your wash") |> render_click()

      html = render_hook(view, "share_degraded", %{})
      assert html =~ "Couldn&#39;t attach the photo"

      html = render_hook(view, "share_fallback_done", %{"mode" => "image"})
      assert html =~ "Image saved — link copied"

      html = render_hook(view, "share_fallback_done", %{"mode" => "link"})
      assert html =~ "Link copied"

      html = render_hook(view, "share_fallback_done", %{"mode" => "image_only"})
      assert html =~ "Image saved"
      refute html =~ "Image saved — link copied"
    end

    test "modal closes without crashing when a PubSub reload empties the pairs while open",
         %{conn: conn} do
      customer = register_customer()
      appt = create_appointment(customer, :completed)
      before_photo = create_photo(appt, :before, :front, "/uploads/front-b.jpg")
      after_photo = create_photo(appt, :after, :front, "/uploads/front-a.jpg")
      conn = sign_in(conn, customer)

      {:ok, view, _html} = live(conn, ~p"/appointments/#{appt.id}/status")
      view |> element("button", "Share your wash") |> render_click()

      before_photo
      |> Ash.Changeset.for_update(:soft_delete, %{})
      |> Ash.update()

      after_photo
      |> Ash.Changeset.for_update(:soft_delete, %{})
      |> Ash.update()

      send(view.pid, {:appointment_update, %{event: :photo_uploaded, status: :completed}})
      html = render(view)

      refute html =~ ~s(id="share-wash-modal")
      assert Process.alive?(view.pid)
    end
  end

  describe "lightbox wiring" do
    test "completed page renders lightbox root once and wires unpaired + problem photos", %{
      conn: conn
    } do
      customer = register_customer()
      appt = create_appointment(customer, :completed)
      create_photo(appt, :before, :front, "/uploads/front-b.jpg")
      create_photo(appt, :after, :front, "/uploads/front-a.jpg")
      create_photo(appt, :before, :interior, "/uploads/interior-b.jpg")
      create_photo(appt, :problem_area, :bumper, "/uploads/problem.jpg")

      {:ok, _view, html} = conn |> sign_in(customer) |> live(~p"/appointments/#{appt.id}/status")

      assert html =~ ~s(id="lightbox-root")
      assert html =~ ~s(phx-hook="Lightbox")
      # unpaired interior before-photo goes to the More photos strip
      assert html =~ ~s(data-lightbox="more-photos")
      assert html =~ ~s(data-lightbox="problem-photos")
      # every wired img has alt text
      refute html =~ ~r/<img(?![^>]*alt=)[^>]*data-lightbox/
    end

    test "during-wash grid wires wash photos with alt", %{conn: conn} do
      customer = register_customer()
      appt = create_appointment(customer, :confirmed)
      create_photo(appt, :before, :front, "/uploads/front-b.jpg")

      {:ok, _view, html} = conn |> sign_in(customer) |> live(~p"/appointments/#{appt.id}/status")

      assert html =~ ~s(data-lightbox="wash-photos")
      assert html =~ ~s(alt="Before — Front")
      assert html =~ ~s(id="lightbox-root")
    end
  end
end
