defmodule MobileCarWashWeb.Admin.CustomersLiveTest do
  @moduledoc """
  Admin customer list + detail pages.

  The detail page was the missing affordance for retroactively tagging
  offline acquisitions (word-of-mouth, door hangers) identified in the
  original Marketing Phase 1 plan.
  """
  use MobileCarWashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Billing.Payment
  alias MobileCarWash.Fleet.{Address, Vehicle}
  alias MobileCarWash.Marketing
  alias MobileCarWash.Marketing.{AcquisitionChannel, Persona, PersonaMembership}
  alias MobileCarWash.Scheduling.{Appointment, ServiceType}

  defp register_admin! do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "cdet-admin-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Customer Detail Admin",
        phone: "+15125557500"
      })
      |> Ash.create()

    customer
    |> Ash.Changeset.for_update(:update, %{role: :admin})
    |> Ash.update!(authorize?: false)
  end

  defp register_customer!(channel_id \\ nil, name \\ "Target Customer") do
    attrs = %{
      email: "c-#{System.unique_integer([:positive])}@test.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      name: name,
      phone: "+15125553#{:rand.uniform(999) |> Integer.to_string() |> String.pad_leading(3, "0")}"
    }

    attrs = if channel_id, do: Map.put(attrs, :acquired_channel_id, channel_id), else: attrs

    {:ok, c} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, attrs)
      |> Ash.create()

    c
  end

  defp pay!(customer, cents) do
    Payment
    |> Ash.Changeset.for_create(:create, %{
      amount_cents: cents,
      stripe_payment_intent_id: "pi_cust_list_#{System.unique_integer([:positive])}"
    })
    |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
    |> Ash.Changeset.force_change_attribute(:status, :succeeded)
    |> Ash.create!(authorize?: false)
  end

  defp complete_appointment!(customer, days_ago) do
    {:ok, service} =
      ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Basic",
        slug: "basic_cust_list_#{System.unique_integer([:positive])}",
        base_price_cents: 5000,
        duration_minutes: 45
      })
      |> Ash.create()

    {:ok, vehicle} =
      Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "T", model: "M", size: :car})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, address} =
      Address
      |> Ash.Changeset.for_create(:create, %{
        street: "1 A St",
        city: "San Antonio",
        state: "TX",
        zip: "78261"
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    # Book in the future (validation requires it), then backdate + complete.
    future =
      DateTime.utc_now() |> DateTime.add(86_400, :second) |> DateTime.truncate(:second)

    {:ok, appt} =
      Appointment
      |> Ash.Changeset.for_create(:book, %{
        customer_id: customer.id,
        vehicle_id: vehicle.id,
        address_id: address.id,
        service_type_id: service.id,
        scheduled_at: future,
        price_cents: 5000,
        duration_minutes: 45
      })
      |> Ash.create()

    backdated =
      DateTime.utc_now()
      |> DateTime.add(-days_ago * 86_400, :second)
      |> DateTime.truncate(:second)

    appt
    |> Ash.Changeset.for_update(:update, %{status: :completed})
    |> Ash.Changeset.force_change_attribute(:scheduled_at, backdated)
    |> Ash.update!(authorize?: false)
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

  describe "auth guard" do
    test "anonymous → sign-in (list)", %{conn: conn} do
      conn = get(conn, ~p"/admin/customers")
      assert redirected_to(conn) == "/sign-in"
    end

    test "anonymous → sign-in (detail)", %{conn: conn} do
      conn = get(conn, ~p"/admin/customers/#{Ecto.UUID.generate()}")
      assert redirected_to(conn) == "/sign-in"
    end
  end

  describe "list" do
    test "shows every customer with name + email", %{conn: conn} do
      admin = register_admin!()
      target = register_customer!()

      conn = sign_in(conn, admin)
      {:ok, _lv, html} = live(conn, ~p"/admin/customers")

      assert html =~ target.name
      assert html =~ to_string(target.email)
    end

    test "search narrows by name or email", %{conn: conn} do
      admin = register_admin!()
      needle = register_customer!()

      {:ok, _haystack} =
        Customer
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "other-#{System.unique_integer([:positive])}@test.com",
          password: "Password123!",
          password_confirmation: "Password123!",
          name: "Other Entirely Different",
          phone: "+15125554321"
        })
        |> Ash.create()

      conn = sign_in(conn, admin)
      {:ok, lv, _} = live(conn, ~p"/admin/customers")

      html =
        lv
        |> form("#customer-filters", %{"q" => needle.name})
        |> render_change()

      assert html =~ needle.name
      refute html =~ "Other Entirely Different"
    end

    test "filters by acquired channel", %{conn: conn} do
      :ok = Marketing.seed_channels!()

      {:ok, [meta]} =
        AcquisitionChannel
        |> Ash.Query.for_read(:by_slug, %{slug: "meta_paid"})
        |> Ash.read(authorize?: false)

      {:ok, [door]} =
        AcquisitionChannel
        |> Ash.Query.for_read(:by_slug, %{slug: "door_hangers"})
        |> Ash.read(authorize?: false)

      admin = register_admin!()
      on_meta = register_customer!(meta.id, "Meta Channel Target")
      on_door = register_customer!(door.id, "Door Hanger Target")

      conn = sign_in(conn, admin)

      {:ok, _lv, html} =
        live(conn, ~p"/admin/customers?channel=#{meta.id}")

      assert html =~ on_meta.name
      refute html =~ on_door.name
    end

    test "sorts by lifetime revenue descending", %{conn: conn} do
      admin = register_admin!()
      low = register_customer!(nil, "LTV Low Spender")
      high = register_customer!(nil, "LTV High Spender")

      pay!(low, 1_000)
      pay!(high, 50_000)

      conn = sign_in(conn, admin)
      {:ok, _lv, html} = live(conn, ~p"/admin/customers?sort=ltv_desc")

      # high-LTV customer's row must appear before low-LTV customer's row
      high_pos = :binary.match(html, high.name) |> elem(0)
      low_pos = :binary.match(html, low.name) |> elem(0)

      assert high_pos < low_pos
    end

    test "shows last wash date and churn-risk badge for a customer with recent completed wash",
         %{conn: conn} do
      admin = register_admin!()
      target = register_customer!()
      _appt = complete_appointment!(target, 10)

      conn = sign_in(conn, admin)
      {:ok, _lv, html} = live(conn, ~p"/admin/customers")

      assert html =~ "Last wash"
      # An "active" risk badge means days_since_last ≤ 30.
      assert html =~ "active"
    end

    test "paginates when customer count exceeds page size", %{conn: conn} do
      admin = register_admin!()
      # Page size is 50; create 51 customers to force a page 2.
      customers =
        for i <- 1..51 do
          register_customer!(
            nil,
            "Page Target #{String.pad_leading(Integer.to_string(i), 2, "0")}"
          )
        end

      last = List.last(customers)

      conn = sign_in(conn, admin)

      # Default sort is joined_desc; the oldest (first-created) customer
      # lands on page 2. `last` was registered most recently → page 1.
      {:ok, _lv, html_p1} = live(conn, ~p"/admin/customers?sort=joined_desc")
      assert html_p1 =~ last.name

      oldest = List.first(customers)
      {:ok, _lv, html_p2} = live(conn, ~p"/admin/customers?sort=joined_desc&page=2")
      assert html_p2 =~ oldest.name
      refute html_p2 =~ last.name
    end
  end

  describe "detail" do
    setup do
      :ok = Marketing.seed_channels!()

      {:ok, [door]} =
        AcquisitionChannel
        |> Ash.Query.for_read(:by_slug, %{slug: "door_hangers"})
        |> Ash.read(authorize?: false)

      {:ok, [meta]} =
        AcquisitionChannel
        |> Ash.Query.for_read(:by_slug, %{slug: "meta_paid"})
        |> Ash.read(authorize?: false)

      %{door: door, meta: meta}
    end

    test "renders the customer's core profile", %{conn: conn, meta: meta} do
      admin = register_admin!()
      target = register_customer!(meta.id)

      conn = sign_in(conn, admin)
      {:ok, _lv, html} = live(conn, ~p"/admin/customers/#{target.id}")

      assert html =~ target.name
      assert html =~ to_string(target.email)
      assert html =~ "Meta"
    end

    test "reassign_channel updates acquired_channel_id",
         %{conn: conn, door: door, meta: meta} do
      admin = register_admin!()
      target = register_customer!(meta.id)

      conn = sign_in(conn, admin)
      {:ok, lv, _} = live(conn, ~p"/admin/customers/#{target.id}")

      lv
      |> form("#reassign-channel", %{"channel_id" => door.id})
      |> render_submit()

      {:ok, reloaded} = Ash.get(Customer, target.id, authorize?: false)
      assert reloaded.acquired_channel_id == door.id
    end

    test "manually tagging a persona creates a membership", %{conn: conn} do
      admin = register_admin!()
      target = register_customer!()

      {:ok, persona} =
        Persona
        |> Ash.Changeset.for_create(:create, %{
          slug: "detail_persona",
          name: "Detail Persona",
          description: ""
        })
        |> Ash.create(authorize?: false)

      conn = sign_in(conn, admin)
      {:ok, lv, _} = live(conn, ~p"/admin/customers/#{target.id}")

      lv
      |> form("#assign-persona", %{"persona_id" => persona.id})
      |> render_submit()

      {:ok, memberships} =
        PersonaMembership
        |> Ash.Query.for_read(:for_customer, %{customer_id: target.id})
        |> Ash.read(authorize?: false)

      assert length(memberships) == 1
      assert hd(memberships).persona_id == persona.id
      assert hd(memberships).manually_assigned == true
    end

    test "recompute_personas button runs the rule engine", %{conn: conn, meta: meta} do
      admin = register_admin!()
      target = register_customer!(meta.id)

      {:ok, _persona} =
        Persona
        |> Ash.Changeset.for_create(:create, %{
          slug: "meta_auto_#{System.unique_integer([:positive])}",
          name: "Meta Auto",
          description: "",
          criteria: %{"acquired_channel_slug" => "meta_paid"}
        })
        |> Ash.create(authorize?: false)

      conn = sign_in(conn, admin)
      {:ok, lv, _} = live(conn, ~p"/admin/customers/#{target.id}")

      lv |> element("#recompute-personas") |> render_click()

      {:ok, memberships} =
        PersonaMembership
        |> Ash.Query.for_read(:for_customer, %{customer_id: target.id})
        |> Ash.read(authorize?: false)

      assert length(memberships) == 1
    end

    test "404s cleanly for a missing id", %{conn: conn} do
      admin = register_admin!()
      conn = sign_in(conn, admin)

      assert {:error, {:live_redirect, %{to: "/admin/customers"}}} =
               live(conn, ~p"/admin/customers/#{Ecto.UUID.generate()}")
    end
  end
end
