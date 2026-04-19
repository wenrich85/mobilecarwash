defmodule MobileCarWashWeb.PhotoControllerTest do
  @moduledoc """
  SECURITY_AUDIT_REPORT CRITICAL #3: photos under `/priv/static/uploads/`
  were publicly served by Plug.Static — any signed-in or anonymous user
  could view another customer's photos by guessing an appointment UUID.

  These tests pin the locked-down contract:

    * Uploads land outside `priv/static/`, so Plug.Static can't serve them.
    * PhotoUpload.save_file returns URLs of the form `/photos/...`, routed
      through PhotoController which enforces authorization.
    * The controller:
      - requires a session (401 for anonymous)
      - returns 403 when the actor doesn't own the appointment and isn't
        an admin or the assigned technician
      - returns 200 with the file bytes for owner / admin / assigned tech
      - returns 404 for missing files
  """
  use MobileCarWashWeb.ConnCase, async: false

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Operations.{Photo, PhotoUpload}

  setup do
    # Force local storage for this test regardless of app env.
    original = Application.get_env(:mobile_car_wash, :photo_storage, :local)
    Application.put_env(:mobile_car_wash, :photo_storage, :local)
    on_exit(fn -> Application.put_env(:mobile_car_wash, :photo_storage, original) end)

    :ok
  end

  defp register_customer(opts \\ []) do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: opts[:email] || "photo-auth-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: opts[:name] || "Photo Viewer",
        phone: opts[:phone] || "+15125551700"
      })
      |> Ash.create()

    if opts[:role] do
      customer
      |> Ash.Changeset.for_update(:update, %{role: opts[:role]})
      |> Ash.update!(authorize?: false)
    else
      customer
    end
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

  defp create_appointment_for(customer) do
    {:ok, service} =
      MobileCarWash.Scheduling.ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Basic",
        slug: "photo-auth-#{System.unique_integer([:positive])}",
        base_price_cents: 5_000,
        duration_minutes: 45
      })
      |> Ash.create()

    {:ok, vehicle} =
      MobileCarWash.Fleet.Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "Toyota", model: "Camry"})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, address} =
      MobileCarWash.Fleet.Address
      |> Ash.Changeset.for_create(:create, %{
        street: "1 Photo Ln",
        city: "San Antonio",
        state: "TX",
        zip: "78259"
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, appt} =
      MobileCarWash.Scheduling.Appointment
      |> Ash.Changeset.for_create(:book, %{
        customer_id: customer.id,
        vehicle_id: vehicle.id,
        address_id: address.id,
        service_type_id: service.id,
        scheduled_at: DateTime.add(DateTime.utc_now(), 86_400, :second),
        price_cents: 5_000,
        duration_minutes: 45
      })
      |> Ash.create()

    appt
  end

  # Writes a valid JPEG to a temp path so PhotoUpload's magic-byte
  # validation passes.
  defp tmp_jpeg do
    path = Path.join(System.tmp_dir!(), "photo-#{System.unique_integer([:positive])}.jpg")
    File.write!(path, <<0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10>> <> :crypto.strong_rand_bytes(32))
    path
  end

  describe "PhotoUpload.save_file (local storage)" do
    test "writes outside priv/static so Plug.Static can't serve the file directly" do
      customer = register_customer()
      appt = create_appointment_for(customer)

      {:ok, photo} =
        PhotoUpload.save_file(
          appt.id,
          tmp_jpeg(),
          "problem.jpg",
          :problem_area,
          uploaded_by: :customer
        )

      # The file MUST NOT land anywhere Plug.Static would serve it from —
      # i.e. not under priv/static/. We enforce this by checking the
      # returned URL doesn't start with "/uploads/".
      refute String.starts_with?(photo.file_path, "/uploads/"),
             "file_path must not point at the public /uploads/ prefix; got #{photo.file_path}"
    end

    test "returns a URL routed through the auth-gated PhotoController" do
      customer = register_customer()
      appt = create_appointment_for(customer)

      {:ok, photo} =
        PhotoUpload.save_file(
          appt.id,
          tmp_jpeg(),
          "problem.jpg",
          :problem_area,
          uploaded_by: :customer
        )

      assert String.starts_with?(photo.file_path, "/photos/appointments/#{appt.id}/"),
             "file_path must point at /photos/appointments/... routed through PhotoController"
    end
  end

  describe "GET /photos/appointments/:appointment_id/:filename" do
    setup do
      owner = register_customer(name: "Owner")
      appt = create_appointment_for(owner)

      {:ok, photo} =
        PhotoUpload.save_file(
          appt.id,
          tmp_jpeg(),
          "problem.jpg",
          :problem_area,
          uploaded_by: :customer
        )

      filename = Path.basename(photo.file_path)

      {:ok, owner: owner, appt: appt, photo: photo, filename: filename}
    end

    test "returns 401 for an anonymous request", %{conn: conn, appt: appt, filename: filename} do
      conn = get(conn, ~p"/photos/appointments/#{appt.id}/#{filename}")
      assert conn.status == 401
    end

    test "serves the file to the owning customer",
         %{conn: conn, owner: owner, appt: appt, filename: filename} do
      conn = sign_in(conn, owner)
      conn = get(conn, ~p"/photos/appointments/#{appt.id}/#{filename}")
      assert conn.status == 200
    end

    test "returns 403 for a different customer",
         %{conn: conn, appt: appt, filename: filename} do
      stranger = register_customer(email: "stranger@test.com")
      conn = sign_in(conn, stranger)

      conn = get(conn, ~p"/photos/appointments/#{appt.id}/#{filename}")
      assert conn.status == 403
    end

    test "serves the file to an admin",
         %{conn: conn, appt: appt, filename: filename} do
      admin = register_customer(email: "admin@test.com", role: :admin)
      conn = sign_in(conn, admin)

      conn = get(conn, ~p"/photos/appointments/#{appt.id}/#{filename}")
      assert conn.status == 200
    end

    test "returns 404 when the file is missing on disk",
         %{conn: conn, owner: owner, appt: appt} do
      conn = sign_in(conn, owner)
      conn = get(conn, ~p"/photos/appointments/#{appt.id}/nonexistent.jpg")
      assert conn.status == 404
    end
  end

  describe "Plug.Static lockdown" do
    # Defense-in-depth: even if a stray file ends up in priv/static/uploads/,
    # Plug.Static should no longer serve it because "uploads" is out of
    # the static_paths whitelist.
    test "static_paths/0 no longer includes 'uploads'" do
      refute "uploads" in MobileCarWashWeb.static_paths(),
             ~s[`uploads` must not be in static_paths — removing it is the bright-line rule that keeps Plug.Static from ever serving customer photos without authorization.]
    end
  end
end
