defmodule MobileCarWashWeb.AppointmentsPhotoUploadTest do
  @moduledoc """
  Verifies Slice B of the photo-uploader redesign: tapping "+ Problem
  Area Photos" on an appointment card opens the modal with the same
  Take Photo / Upload dual CTAs used by the booking flow.
  """
  use MobileCarWashWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Scheduling.Appointment

  defp register_customer do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "appt-photo-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Photo Customer",
        phone: "+15125557700"
      })
      |> Ash.create()

    customer
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

  defp create_appointment(customer_id) do
    {:ok, service} =
      MobileCarWash.Scheduling.ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Basic Wash",
        slug: "photo-slice-b-#{System.unique_integer([:positive])}",
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
        street: "77 Photo Ln",
        city: "San Antonio",
        state: "TX",
        zip: "78259"
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
        scheduled_at: DateTime.add(DateTime.utc_now(), 2 * 86_400, :second),
        price_cents: 5_000,
        duration_minutes: 45
      })
      |> Ash.create()

    appt
  end

  describe "Problem Area Photos modal" do
    test "opens with the Take Photo / Upload dual CTA", %{conn: conn} do
      customer = register_customer()
      appt = create_appointment(customer.id)
      conn = sign_in(conn, customer)

      {:ok, view, _html} = live(conn, ~p"/appointments")

      html =
        view
        |> element("button[phx-value-id='#{appt.id}']", "Problem Area Photos")
        |> render_click()

      assert html =~ "Take Photo"
      assert html =~ "Upload"
      # The camera input must set capture="environment" so tapping
      # goes straight to the rear camera on mobile browsers.
      assert html =~ ~s(capture="environment")
    end

    test "closes when the Done button is tapped", %{conn: conn} do
      customer = register_customer()
      appt = create_appointment(customer.id)
      conn = sign_in(conn, customer)

      {:ok, view, _html} = live(conn, ~p"/appointments")

      view
      |> element("button[phx-value-id='#{appt.id}']", "Problem Area Photos")
      |> render_click()

      html =
        view
        |> element("button", "Done")
        |> render_click()

      refute html =~ "Take Photo"
    end
  end

  describe "AI tag auto-apply" do
    test "renders the ✨ badge and auto-fills the caption when tags arrive",
         %{conn: conn} do
      customer = register_customer()
      appt = create_appointment(customer.id)
      conn = sign_in(conn, customer)

      # Pre-seed a problem-area photo on this appointment so the modal has
      # something to subscribe to on open.
      {:ok, photo} =
        MobileCarWash.Operations.Photo
        |> Ash.Changeset.for_create(:upload, %{
          file_path: "uploads/ai-preseed.jpg",
          photo_type: :problem_area,
          uploaded_by: :customer,
          original_filename: "ai.jpg",
          content_type: "image/jpeg"
        })
        |> Ash.Changeset.force_change_attribute(:appointment_id, appt.id)
        |> Ash.create()

      {:ok, view, _html} = live(conn, ~p"/appointments")

      view
      |> element("button[phx-value-id='#{appt.id}']", "Problem Area Photos")
      |> render_click()

      # Simulate the analyzer finishing and broadcasting the tags.
      tags = %{
        "is_vehicle_photo" => true,
        "body_part" => "bumper",
        "issue" => "scratch",
        "severity" => "light",
        "confidence" => 0.85,
        "description" => "Light scratch on lower rear bumper"
      }

      tagged_photo = %{photo | ai_tags: tags, ai_processed_at: DateTime.utc_now()}

      Phoenix.PubSub.broadcast(
        MobileCarWash.PubSub,
        "photo:#{photo.id}:ai",
        {:ai_tags, tagged_photo}
      )

      html = render(view)

      # Badge + auto-filled caption value — and the chip that matches
      # body_part should be rendered in its selected (btn-primary) style.
      assert html =~ "✨"
      assert html =~ "Light scratch on lower rear bumper"
    end
  end
end
