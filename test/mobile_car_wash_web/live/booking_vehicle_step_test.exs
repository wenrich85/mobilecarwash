defmodule MobileCarWashWeb.BookingVehicleStepTest do
  # async: false — sign-in writes a session token; mock NHTSA table is shared
  use MobileCarWashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Scheduling.ServiceType
  alias MobileCarWash.Fleet.Vehicle
  alias MobileCarWash.Vehicles.NhtsaClientMock

  require Ash.Query

  setup %{conn: conn} do
    NhtsaClientMock.init()

    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "veh-step-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Veh Step",
        phone: "+15125550000"
      })
      |> Ash.create()

    ServiceType
    |> Ash.Changeset.for_create(:create, %{
      name: "Basic Wash",
      slug: "basic_wash",
      description: "x",
      base_price_cents: 5_000,
      duration_minutes: 45
    })
    |> Ash.create!()

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> post("/auth/customer/password/sign_in", %{
        "customer" => %{"email" => to_string(customer.email), "password" => "Password123!"}
      })
      |> recycle()

    %{conn: conn, customer: customer}
  end

  # Signed-in: select_service → next_step (:add_ons) → next_step (auth skipped → :vehicle)
  defp to_vehicle_step(view) do
    render_click(view, "select_service", %{"slug" => "basic_wash"})
    render_click(view, "next_step", %{})
    html = render_click(view, "next_step", %{})
    assert html =~ "Autofill from VIN"
    html
  end

  test "vehicle step renders the make dropdown with curated makes", %{conn: conn} do
    {:ok, view, _} = live(conn, "/book")
    html = to_vehicle_step(view)

    assert html =~ "Autofill from VIN"
    assert html =~ ~s(name="vehicle[make]")
    assert html =~ "Toyota"
    assert html =~ "Honda"
  end

  test "choosing make + year loads models from NHTSA into the model dropdown", %{conn: conn} do
    NhtsaClientMock.put_models("Toyota", 2021, [
      %{name: "Camry", size: :car},
      %{name: "Corolla", size: :car},
      %{name: "RAV4", size: :suv_van}
    ])

    NhtsaClientMock.put_models("Honda", 2021, [
      %{name: "Accord", size: :car},
      %{name: "Civic", size: :car}
    ])

    {:ok, view, _} = live(conn, "/book")
    to_vehicle_step(view)

    # Note: Phoenix LiveViewTest's form/3 enforces that disabled fields must not
    # be set. The model <select> starts disabled (no models loaded yet), so
    # form/3 + render_change would error. We send the event directly via
    # render_change/2 to bypass DOM pre-validation — same event, same params,
    # same server behavior and assertions; only the harness path differs.
    html =
      render_change(view, "vehicle_form_change", %{
        "vehicle" => %{
          "make" => "Toyota",
          "year" => "2021",
          "model" => "",
          "color" => "Silver",
          "size" => "car"
        }
      })

    assert html =~ "Camry"
    assert html =~ "RAV4"

    # Changing the make resets and reloads the model list
    html =
      render_change(view, "vehicle_form_change", %{
        "vehicle" => %{
          "make" => "Honda",
          "year" => "2021",
          "model" => "",
          "color" => "Silver",
          "size" => "car"
        }
      })

    assert html =~ "Accord"
    assert html =~ "Civic"
  end

  test "VIN autofill populates the form and auto-selects size from body class", %{conn: conn} do
    NhtsaClientMock.put_vin(
      "1HGCM82633A004352",
      {:ok, %{make: "Honda", model: "Accord", year: 2003, body_class: "Sedan/Saloon", size: :car}}
    )

    {:ok, view, _} = live(conn, "/book")
    to_vehicle_step(view)

    html = render_submit(view, "decode_vin", %{"vin" => "1HGCM82633A004352"})

    # Decoded make/model rendered as selected options
    assert html =~ "Honda"
    assert html =~ "Accord"
    # size=car radio is checked
    assert html =~ ~r/name="vehicle\[size\]" value="car"[^>]*checked/
  end

  test "an undecodable VIN shows an inline error and never blocks manual entry", %{conn: conn} do
    {:ok, view, _} = live(conn, "/book")
    to_vehicle_step(view)

    html = render_submit(view, "decode_vin", %{"vin" => "NOTAVIN"})

    assert html =~ "Couldn&#39;t read that VIN"
    # Manual dropdowns still present
    assert html =~ ~s(name="vehicle[make]")
  end

  test "saving a vehicle from the dropdowns persists it and advances", %{
    conn: conn,
    customer: customer
  } do
    NhtsaClientMock.put_models("Toyota", 2021, [%{name: "Camry", size: :car}])

    {:ok, view, _} = live(conn, "/book")
    to_vehicle_step(view)

    render_submit(view, "save_vehicle", %{
      "vehicle" => %{
        "make" => "Toyota",
        "model" => "Camry",
        "year" => "2021",
        "color" => "Silver",
        "size" => "suv_van",
        "vin" => "",
        "body_class" => ""
      }
    })

    vehicle =
      Vehicle
      |> Ash.Query.filter(customer_id == ^customer.id)
      |> Ash.read!()
      |> hd()

    assert vehicle.make == "Toyota"
    assert vehicle.model == "Camry"
    assert vehicle.size == :suv_van
    assert is_nil(vehicle.vin)
  end

  test "selecting a model auto-fills the size from its NHTSA vehicle type", %{conn: conn} do
    NhtsaClientMock.put_models("Ford", 2023, [
      %{name: "F-150", size: :pickup},
      %{name: "Focus", size: :car},
      %{name: "Escape", size: :suv_van}
    ])

    {:ok, view, _} = live(conn, "/book")
    to_vehicle_step(view)

    # Load models for Ford 2023
    render_change(view, "vehicle_form_change", %{
      "vehicle" => %{"make" => "Ford", "year" => "2023", "model" => "", "color" => "", "size" => "car"}
    })

    # Pick a pickup → size auto-selects pickup (even though the radio sent "car")
    html =
      render_change(view, "vehicle_form_change", %{
        "vehicle" => %{"make" => "Ford", "year" => "2023", "model" => "F-150", "color" => "", "size" => "car"}
      })

    assert html =~ ~r/name="vehicle\[size\]" value="pickup"[^>]*checked/

    # Pick an SUV → size auto-selects suv_van
    html =
      render_change(view, "vehicle_form_change", %{
        "vehicle" => %{"make" => "Ford", "year" => "2023", "model" => "Escape", "color" => "", "size" => "pickup"}
      })

    assert html =~ ~r/name="vehicle\[size\]" value="suv_van"[^>]*checked/
  end

  test "an auto-filled size remains user-editable", %{conn: conn} do
    NhtsaClientMock.put_models("Ford", 2023, [%{name: "F-150", size: :pickup}])

    {:ok, view, _} = live(conn, "/book")
    to_vehicle_step(view)

    render_change(view, "vehicle_form_change", %{
      "vehicle" => %{"make" => "Ford", "year" => "2023", "model" => "", "color" => "", "size" => "car"}
    })

    # Model picks pickup automatically...
    render_change(view, "vehicle_form_change", %{
      "vehicle" => %{"make" => "Ford", "year" => "2023", "model" => "F-150", "color" => "", "size" => "car"}
    })

    # ...then the user overrides to car (model unchanged) — override sticks.
    html =
      render_change(view, "vehicle_form_change", %{
        "vehicle" => %{"make" => "Ford", "year" => "2023", "model" => "F-150", "color" => "", "size" => "car"}
      })

    assert html =~ ~r/name="vehicle\[size\]" value="car"[^>]*checked/
  end
end
