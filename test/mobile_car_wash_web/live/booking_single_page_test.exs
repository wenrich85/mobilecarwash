defmodule MobileCarWashWeb.BookingSinglePageTest do
  use MobileCarWashWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias MobileCarWash.Scheduling.{ServiceType, AppointmentBlock}
  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Fleet.{Vehicle, Address}
  alias MobileCarWash.Fleet.GeocoderClientMock
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

  test "confirm_booking with nothing selected is a safe no-op (server-side payable? guard)",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, "/book")
    # Fire confirm_booking with no selections at all — must not crash
    html = render_click(view, "confirm_booking", %{})
    # Page still renders (no crash / no redirect)
    assert html =~ "Book a Wash" or html =~ "Service"
    # Error flash shown, not a server crash
    assert html =~ "Please complete all sections before paying."
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

  test "guest address summary card appears after manual save_address",
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
    # Manual entry form is always present in the DOM (inside <details>)
    assert html =~ ~s(name="address[street]")
  end

  test "typing an address shows geocoder suggestions", %{conn: conn} do
    GeocoderClientMock.init()

    GeocoderClientMock.put_suggestions("123 main st san antonio", [
      %{
        label: "123 MAIN ST, SAN ANTONIO, TX, 78261",
        street: "123 MAIN ST",
        city: "SAN ANTONIO",
        state: "TX",
        zip: "78261",
        lat: 29.6512,
        lng: -98.4187
      }
    ])

    {:ok, view, _} = live(conn, "/book")

    render_hook(view, "address_search", %{"q" => "123 main st san antonio"})
    html = render_async(view)

    assert html =~ "123 MAIN ST, SAN ANTONIO, TX, 78261"
  end

  test "selecting a suggestion autofills the address, shows the zone, and mounts the map",
       %{conn: conn} do
    GeocoderClientMock.init()

    GeocoderClientMock.put_suggestions("123 main st san antonio", [
      %{
        label: "123 MAIN ST, SAN ANTONIO, TX, 78261",
        street: "123 MAIN ST",
        city: "SAN ANTONIO",
        state: "TX",
        zip: "78261",
        lat: 29.6512,
        lng: -98.4187
      }
    ])

    {:ok, view, _} = live(conn, "/book")

    render_hook(view, "address_search", %{"q" => "123 main st san antonio"})
    render_async(view)

    html = render_click(view, "select_suggestion", %{"index" => "0"})

    # Autofilled summary
    assert html =~ "123 MAIN ST"
    # ZIP 78261 is in the curated map → :ne → "Northeast", in service area
    assert html =~ "In service area"
    assert html =~ "Northeast"
    # Confirmation map mounted with the geocoded coordinates
    assert html =~ ~s(phx-hook="AddressMap")
    assert html =~ ~s(data-lat="29.6512")
  end

  test "selecting a suggestion outside the service area warns but is allowed", %{conn: conn} do
    GeocoderClientMock.init()

    GeocoderClientMock.put_suggestions("1 elsewhere rd", [
      %{
        label: "1 ELSEWHERE RD, AUSTIN, TX, 73301",
        street: "1 ELSEWHERE RD",
        city: "AUSTIN",
        state: "TX",
        zip: "73301",
        lat: 30.2672,
        lng: -97.7431
      }
    ])

    {:ok, view, _} = live(conn, "/book")

    render_hook(view, "address_search", %{"q" => "1 elsewhere rd"})
    render_async(view)

    html = render_click(view, "select_suggestion", %{"index" => "0"})

    # ZIP 73301 not in curated map → zone nil → outside-area warning
    assert html =~ "Outside our service area"
  end

  test "signed-in: Ash create failure on select_suggestion shows error, keeps suggestions, does not set selected_address",
       %{conn: conn} do
    GeocoderClientMock.init()

    # Stage a suggestion with an empty street — Ash will reject it with
    # Required(:street) because allow_nil?(false) treats "" as absent.
    GeocoderClientMock.put_suggestions("bad address", [
      %{
        label: "BAD ADDRESS, SAN ANTONIO, TX, 78261",
        street: "",
        city: "SAN ANTONIO",
        state: "TX",
        zip: "78261",
        lat: 29.6512,
        lng: -98.4187
      }
    ])

    # Sign in a real customer so choose_geocoded_address takes the Ash-create path.
    {:ok, customer} =
      MobileCarWash.Accounts.Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "geocoder-fail-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Geocoder Fail Test",
        phone: "+15125550099"
      })
      |> Ash.create()

    authed_conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> post("/auth/customer/password/sign_in", %{
        "customer" => %{
          "email" => to_string(customer.email),
          "password" => "Password123!"
        }
      })
      |> recycle()

    {:ok, view, _html} = live(authed_conn, "/book")

    # Drive the geocoder search and await the async result.
    render_hook(view, "address_search", %{"q" => "bad address"})
    render_async(view)

    # Select the suggestion — the Ash create will fail.
    html = render_click(view, "select_suggestion", %{"index" => "0"})

    # (a) Error flash is shown.
    assert html =~ "Could not save that address"

    # (b) Suggestions list is still present (not cleared on failure).
    assert html =~ "BAD ADDRESS, SAN ANTONIO, TX, 78261"

    # (c) No selected_address was set.
    refute html =~ ~s(phx-hook="AddressMap")
  end

  test "guest geocoded address persists the precise coordinates (not the ZIP centroid)",
       %{conn: conn} do
    GeocoderClientMock.init()

    # 78250 centroid in Zones is {29.5050, -98.6350}; stage distinct coords
    # so we can prove the precise geocoded point is what gets persisted.
    GeocoderClientMock.put_suggestions("789 pine st san antonio", [
      %{
        label: "789 PINE ST, SAN ANTONIO, TX, 78250",
        street: "789 PINE ST",
        city: "SAN ANTONIO",
        state: "TX",
        zip: "78250",
        lat: 29.5099,
        lng: -98.6399
      }
    ])

    service = ServiceType |> Ash.Query.filter(slug == "basic_wash") |> Ash.read!() |> hd()
    block = create_open_block(service)

    {:ok, view, _html} = live(conn, "/book")

    render_click(view, "select_service", %{"slug" => "basic_wash"})

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

    # Address via geocoder selection (not manual entry)
    render_hook(view, "address_search", %{"q" => "789 pine st san antonio"})
    render_async(view)
    render_click(view, "select_suggestion", %{"index" => "0"})

    block_date = block.starts_at |> DateTime.to_date() |> Date.to_string()
    render_click(view, "select_date", %{"date" => block_date})
    render_click(view, "select_block", %{"id" => block.id})

    guest_email = "guest-#{System.unique_integer([:positive])}@example.com"

    render_change(view, "guest_form_change", %{
      "guest" => %{"name" => "Geo Guest", "email" => guest_email, "phone" => "5125550133"}
    })

    assert {:error, {:redirect, %{to: _url}}} = render_click(view, "confirm_booking", %{})

    addresses =
      Address
      |> Ash.Query.filter(street == "789 PINE ST")
      |> Ash.read!(authorize?: false)

    assert length(addresses) == 1
    saved = hd(addresses)
    assert saved.zip == "78250"
    assert_in_delta saved.latitude, 29.5099, 0.0001
    assert_in_delta saved.longitude, -98.6399, 0.0001
  end
end
