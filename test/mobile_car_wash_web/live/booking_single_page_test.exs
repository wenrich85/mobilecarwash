defmodule MobileCarWashWeb.BookingSinglePageTest do
  use MobileCarWashWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias MobileCarWash.Scheduling.{ServiceType, AppointmentBlock}
  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Fleet.{Vehicle, Address}
  alias MobileCarWash.Operations.Technician

  require Ash.Query

  setup do
    ServiceType
    |> Ash.Changeset.for_create(:create, %{
      name: "Basic Wash",
      slug: "basic_wash",
      description: "x",
      base_price_cents: 5_000,
      duration_minutes: 45
    })
    |> Ash.create!()

    :ok
  end

  # Creates an open appointment block 2 days from now for the given service.
  defp create_open_block(service) do
    tech =
      Technician
      |> Ash.Changeset.for_create(:create, %{
        name: "Test Tech #{System.unique_integer([:positive])}"
      })
      |> Ash.create!()

    starts_at =
      DateTime.utc_now()
      |> DateTime.add(2 * 86_400, :second)
      |> DateTime.truncate(:second)

    ends_at = DateTime.add(starts_at, 3 * 3600, :second)
    closes_at = DateTime.add(starts_at, -3600, :second)

    AppointmentBlock
    |> Ash.Changeset.for_create(:create, %{
      service_type_id: service.id,
      technician_id: tech.id,
      starts_at: starts_at,
      ends_at: ends_at,
      closes_at: closes_at,
      capacity: 5,
      status: :open
    })
    |> Ash.create!()
  end

  # Extracts the markup of a single <section id="..."> up to the next <section
  # (or end), so per-section assertions don't bleed into neighbouring sections.
  defp section_html(html, id) do
    case Regex.run(~r/<section id="#{id}".*?(?=<section |<\/main>|$)/s, html) do
      [chunk] -> chunk
      _ -> ""
    end
  end

  test "all six sections render on one page; later ones start locked", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/book")

    for t <- [
          "Service",
          "Add-ons",
          "Your vehicle",
          "Service location",
          "Pick a time",
          "Review &amp; Pay"
        ] do
      assert html =~ t
    end

    # Vehicle section is locked (disabled fieldset) before a service is chosen
    assert section_html(html, "section-vehicle") =~ "<fieldset disabled"
  end

  test "choosing a service unlocks the vehicle section and updates the hero", %{conn: conn} do
    {:ok, view, _} = live(conn, "/book")
    html = render_click(view, "select_service", %{"slug" => "basic_wash"})
    assert html =~ "$50.00"
    # vehicle section no longer disabled
    refute section_html(html, "section-vehicle") =~ "<fieldset disabled"
  end

  test "Pay is disabled until all required sections + contact are present", %{conn: conn} do
    {:ok, view, _} = live(conn, "/book")
    html = render_click(view, "select_service", %{"slug" => "basic_wash"})
    assert html =~ ~r/phx-click="confirm_booking"[^>]*disabled/
  end

  test "the page no longer renders the step wizard controls", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/book")
    refute html =~ ~s(phx-click="next_step")
    refute html =~ ~s(phx-click="prev_step")
  end

  # ---------------------------------------------------------------------------
  # Guest e2e: vehicle + address held in-memory, persisted at Pay
  # ---------------------------------------------------------------------------

  test "guest can complete booking — vehicle/address deferred until Pay, then persisted",
       %{conn: conn} do
    # Look up the service created in setup so we can attach a block to it.
    service = ServiceType |> Ash.Query.filter(slug == "basic_wash") |> Ash.read!() |> hd()
    block = create_open_block(service)

    {:ok, view, _html} = live(conn, "/book")

    # 1. Select service
    render_click(view, "select_service", %{"slug" => "basic_wash"})

    # 2. Guest saves vehicle (no current_customer — held in-memory)
    html =
      render_submit(view, "save_vehicle", %{
        "vehicle" => %{
          "make" => "Toyota",
          "model" => "Camry",
          "year" => "2022",
          "color" => "Silver",
          "size" => "car",
          "vin" => "",
          "body_class" => ""
        }
      })

    # Guest vehicle summary card should appear; form hidden
    assert html =~ "2022"
    assert html =~ "Toyota"
    assert html =~ "Camry"

    # 3. Guest saves address (held in-memory)
    html =
      render_submit(view, "save_address", %{
        "address" => %{
          "street" => "456 Oak Lane",
          "city" => "San Antonio",
          "state" => "TX",
          "zip" => "78250"
        }
      })

    # Guest address summary card should appear; form hidden
    assert html =~ "456 Oak Lane"

    # 4. Load the correct date and select the schedule block.
    #    The block starts 2 days from now; the default selected_date is tomorrow.
    block_date = block.starts_at |> DateTime.to_date() |> Date.to_string()
    render_click(view, "select_date", %{"date" => block_date})
    render_click(view, "select_block", %{"id" => block.id})

    # 5. Fill in guest contact info (capture email before confirm, since confirm redirects)
    guest_email = "guest-#{System.unique_integer([:positive])}@example.com"

    render_change(view, "guest_form_change", %{
      "guest" => %{
        "name" => "Guest User",
        "email" => guest_email,
        "phone" => "5125550199"
      }
    })

    # 6. Confirm booking — this should create customer + persist vehicle/address + book.
    #    The mock Stripe checkout module returns a fake URL → LiveView redirects externally.
    assert {:error, {:redirect, %{to: checkout_url}}} =
             render_click(view, "confirm_booking", %{})

    assert String.starts_with?(checkout_url, "https://checkout.stripe.com/")

    # 7. Assert DB state: guest customer created with correct email
    vehicles =
      Vehicle
      |> Ash.Query.filter(make == "Toyota" and model == "Camry")
      |> Ash.read!(authorize?: false)

    assert length(vehicles) == 1
    saved_vehicle = hd(vehicles)
    assert saved_vehicle.make == "Toyota"
    assert saved_vehicle.model == "Camry"
    assert saved_vehicle.year == 2022
    assert saved_vehicle.size == :car

    addresses =
      Address
      |> Ash.Query.filter(street == "456 Oak Lane")
      |> Ash.read!(authorize?: false)

    assert length(addresses) == 1
    saved_address = hd(addresses)
    assert saved_address.city == "San Antonio"
    assert saved_address.state == "TX"
    assert saved_address.zip == "78250"

    # Vehicle and address belong to the same (guest) customer
    assert saved_vehicle.customer_id == saved_address.customer_id

    # That customer is a guest with the email we typed
    {:ok, guest_customer} = Ash.get(Customer, saved_vehicle.customer_id, authorize?: false)
    assert guest_customer.role == :guest
    assert to_string(guest_customer.email) == guest_email

    # An appointment was created for this customer
    appointments =
      MobileCarWash.Scheduling.Appointment
      |> Ash.Query.filter(customer_id == ^guest_customer.id)
      |> Ash.read!(authorize?: false)

    assert length(appointments) == 1
    appt = hd(appointments)
    assert appt.vehicle_id == saved_vehicle.id
    assert appt.address_id == saved_address.id
  end

  test "guest vehicle summary card appears and Change button reopens the form",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, "/book")
    render_click(view, "select_service", %{"slug" => "basic_wash"})

    # After saving, the form is hidden and the summary card shows
    html =
      render_submit(view, "save_vehicle", %{
        "vehicle" => %{
          "make" => "Honda",
          "model" => "Civic",
          "year" => "2020",
          "color" => "Blue",
          "size" => "car",
          "vin" => "",
          "body_class" => ""
        }
      })

    assert html =~ "2020"
    assert html =~ "Honda"
    assert html =~ "Civic"
    # The vehicle form should be hidden now (not show_new_vehicle_form)
    refute html =~ ~s(name="vehicle[make]")

    # Clicking Change reopens the form
    html = render_click(view, "show_new_vehicle", %{})
    assert html =~ ~s(name="vehicle[make]")
  end

  test "guest address summary card appears and Change button reopens the form",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, "/book")
    render_click(view, "select_service", %{"slug" => "basic_wash"})

    html =
      render_submit(view, "save_address", %{
        "address" => %{
          "street" => "789 Pine Ave",
          "city" => "Austin",
          "state" => "TX",
          "zip" => "78701"
        }
      })

    assert html =~ "789 Pine Ave"
    # Form should be hidden
    refute html =~ ~s(name="address[street]")

    html = render_click(view, "show_new_address", %{})
    assert html =~ ~s(name="address[street]")
  end
end
