defmodule MobileCarWashWeb.BookingPriceHeaderTest do
  # async: false required for the restore test: SessionCache.put/2 writes to the
  # DB-backed booking_sessions table in the test process, and the LiveView mount
  # runs in a separate spawned process. With the SQL sandbox in shared mode
  # (async: false), both processes share the same transaction so the cached row
  # is visible during the restore mount.
  use MobileCarWashWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  require Ash.Query
  alias MobileCarWash.Scheduling.ServiceType
  alias MobileCarWash.Booking.SessionCache

  setup do
    service =
      ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Basic Wash",
        slug: "basic_wash",
        description: "x",
        base_price_cents: 5_000,
        duration_minutes: 45
      })
      |> Ash.create!()

    %{service: service}
  end

  test "hero shows base price once a service is selected", %{conn: conn} do
    {:ok, view, html} = live(conn, "/book")
    # Before selecting: prompt to pick a service.
    assert html =~ "Select a service to see your price"

    html = render_click(view, "select_service", %{"slug" => "basic_wash"})
    assert html =~ "$50.00"
  end

  test "tapping the hero toggles the itemized receipt", %{conn: conn} do
    {:ok, view, _} = live(conn, "/book")
    render_click(view, "select_service", %{"slug" => "basic_wash"})

    html = render_click(view, "toggle_receipt", %{})
    assert html =~ "Total"
    assert html =~ "Base"
  end

  # Regression: a restored session with selected_service and selected_vehicle must
  # compute price_breakdown on mount, not leave it nil. Before the fix, mount/3
  # statically assigned `price_breakdown: nil` and only recomputed it inside event
  # handlers. Any reconnect/restore that landed on :review would crash because the
  # template accesses @price_breakdown.total_cents without a nil guard.
  #
  # Strategy:
  #   1. GET /book to establish a real session with a real CSRF token.
  #   2. Read the CSRF token → derive session_id = "booking_<csrf_token>".
  #   3. Seed SessionCache with that session_id (service + vehicle, step :vehicle).
  #   4. recycle(conn) to carry the session into the next live() call.
  #   5. live(recycled_conn, "/book") → mount/3 restores from cache.
  #   6. Assert hero shows "$50.00" (price_breakdown was computed on mount).
  #
  # The session ID match is verified by debug tests: GET + recycle gives a live/3
  # mount that derives the exact same session_id as the GET response's CSRF token.
  #
  # Requires async: false so the SessionCache.put/2 write is visible to the
  # LiveView process (shared SQL sandbox).
  test "restored session computes price breakdown on mount — hero shows total, does not crash",
       %{conn: conn, service: service} do
    # Create guest customer + vehicle so cache restore can load them from the DB.
    customer =
      MobileCarWash.Accounts.Customer
      |> Ash.Changeset.for_create(:create_guest, %{
        email: "restore_price_header_#{System.unique_integer([:positive])}@example.com",
        name: "Restore Test",
        phone: "+15125550001"
      })
      |> Ash.create!()

    vehicle =
      MobileCarWash.Fleet.Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "Honda", model: "Civic", size: :car})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create!()

    # Step 1: a real GET /book establishes a Plug session with a real CSRF token.
    conn1 = get(conn, "/book")
    csrf_token = get_session(conn1, "_csrf_token")
    session_id = "booking_#{csrf_token}"

    # Step 2: seed the cache with the session_id the LiveView will derive on
    # the next mount (same CSRF token → same "booking_<token>" key).
    # step: :vehicle — StateMachine.resolve_step will walk this back to :auth
    # because current_customer is nil in the on_mount hook (not signed in).
    # That is fine: what we are testing is that assign_price_breakdown/1 runs
    # in mount/3 even when the step is restored from cache, so the hero shows
    # the total rather than the "Select a service" placeholder.
    :ok =
      SessionCache.put(session_id, %{
        step: :vehicle,
        guest_mode: true,
        customer_id: customer.id,
        service_id: service.id,
        vehicle_id: vehicle.id,
        address_id: nil,
        block_id: nil
      })

    # Step 3: recycle the GET conn so live() uses the same Plug session
    # (and thus the same CSRF token → same booking_session_id).
    conn2 = recycle(conn1)

    # Must not crash. Before the fix mount/3 always assigned price_breakdown: nil,
    # so the hero showed the "Select a service" placeholder on every restore.
    # After the fix, assign_price_breakdown/1 runs in the mount/3 pipeline
    # immediately after the assigns block, computing the total from
    # selected_service + selected_vehicle.
    {:ok, _view, html} = live(conn2, "/book")

    # The hero must NOT show the "no service selected" placeholder.
    refute html =~ "Select a service to see your price"

    # The hero must show the computed price ($50.00 — base car wash, no size multiplier).
    assert html =~ "$50.00"
  end
end
