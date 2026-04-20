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
  alias MobileCarWash.Billing.{Payment, Subscription, SubscriptionPlan}
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

    test "renders applied tag chip in row", %{conn: conn} do
      # Use a unique custom tag name that won't appear anywhere else on
      # the page (e.g. in the layout/footer).
      {:ok, custom_tag} =
        MobileCarWash.Marketing.Tag
        |> Ash.Changeset.for_create(:create, %{
          slug: "list_test_tag_#{System.unique_integer([:positive])}",
          name: "ZZZ_ListColumnTag",
          color: :info
        })
        |> Ash.create(authorize?: false)

      admin = register_admin!()
      tagged = register_customer!(nil, "Tagged Target Customer")

      {:ok, _} =
        MobileCarWash.Marketing.CustomerTag
        |> Ash.Changeset.for_create(:tag, %{
          customer_id: tagged.id,
          tag_id: custom_tag.id,
          author_id: admin.id
        })
        |> Ash.create(authorize?: false)

      conn = sign_in(conn, admin)
      {:ok, _lv, html} = live(conn, ~p"/admin/customers")

      assert html =~ "Tagged Target Customer"
      assert html =~ "ZZZ_ListColumnTag"
    end

    test "shows pinned note inline under customer name", %{conn: conn} do
      admin = register_admin!()
      target = register_customer!(nil, "Pin Note Target")

      {:ok, _} =
        MobileCarWash.Accounts.CustomerNote
        |> Ash.Changeset.for_create(:add, %{
          customer_id: target.id,
          author_id: admin.id,
          body: "GATE CODE 1234 — ring bell twice",
          pinned: true
        })
        |> Ash.create(authorize?: false)

      conn = sign_in(conn, admin)
      {:ok, _lv, html} = live(conn, ~p"/admin/customers")

      assert html =~ "Pin Note Target"
      assert html =~ "GATE CODE 1234"
    end

    test "does not show unpinned notes inline", %{conn: conn} do
      admin = register_admin!()
      target = register_customer!(nil, "Unpinned Only Target")

      {:ok, _} =
        MobileCarWash.Accounts.CustomerNote
        |> Ash.Changeset.for_create(:add, %{
          customer_id: target.id,
          author_id: admin.id,
          body: "SECRET_UNPINNED_NOTE_MARKER",
          pinned: false
        })
        |> Ash.create(authorize?: false)

      conn = sign_in(conn, admin)
      {:ok, _lv, html} = live(conn, ~p"/admin/customers")

      refute html =~ "SECRET_UNPINNED_NOTE_MARKER"
    end

    test "bulk-tag toolbar is hidden when nothing is selected", %{conn: conn} do
      :ok = Marketing.seed_tags!()
      admin = register_admin!()
      _c = register_customer!()

      conn = sign_in(conn, admin)
      {:ok, _lv, html} = live(conn, ~p"/admin/customers")

      refute html =~ ~s(id="bulk-toolbar")
    end

    test "bulk apply tags every selected customer", %{conn: conn} do
      :ok = Marketing.seed_tags!()

      {:ok, [vip]} =
        MobileCarWash.Marketing.Tag
        |> Ash.Query.for_read(:by_slug, %{slug: "vip"})
        |> Ash.read(authorize?: false)

      admin = register_admin!()
      a = register_customer!(nil, "Bulk Target A")
      b = register_customer!(nil, "Bulk Target B")

      conn = sign_in(conn, admin)
      {:ok, lv, _} = live(conn, ~p"/admin/customers")

      lv |> element("#select-#{a.id}") |> render_click()
      lv |> element("#select-#{b.id}") |> render_click()

      lv
      |> form("#bulk-tag-form", %{"tag_id" => vip.id})
      |> render_submit()

      for cid <- [a.id, b.id] do
        {:ok, tags} =
          MobileCarWash.Marketing.CustomerTag
          |> Ash.Query.for_read(:for_customer, %{customer_id: cid})
          |> Ash.read(authorize?: false)

        assert length(tags) == 1
        assert hd(tags).tag_id == vip.id
      end
    end

    test "bulk apply creates audit notes per customer", %{conn: conn} do
      :ok = Marketing.seed_tags!()

      {:ok, [vip]} =
        MobileCarWash.Marketing.Tag
        |> Ash.Query.for_read(:by_slug, %{slug: "vip"})
        |> Ash.read(authorize?: false)

      admin = register_admin!()
      target = register_customer!(nil, "Bulk Audit Target")

      conn = sign_in(conn, admin)
      {:ok, lv, _} = live(conn, ~p"/admin/customers")

      lv |> element("#select-#{target.id}") |> render_click()

      lv
      |> form("#bulk-tag-form", %{"tag_id" => vip.id})
      |> render_submit()

      {:ok, notes} =
        MobileCarWash.Accounts.CustomerNote
        |> Ash.Query.for_read(:for_customer, %{customer_id: target.id})
        |> Ash.read(authorize?: false)

      assert Enum.any?(notes, fn n -> n.body =~ "VIP" and n.body =~ "Tagged" end)
    end

    test "bulk apply skips customers already tagged (no error)", %{conn: conn} do
      :ok = Marketing.seed_tags!()

      {:ok, [vip]} =
        MobileCarWash.Marketing.Tag
        |> Ash.Query.for_read(:by_slug, %{slug: "vip"})
        |> Ash.read(authorize?: false)

      admin = register_admin!()
      already = register_customer!(nil, "Already Tagged")
      fresh = register_customer!(nil, "Fresh Tag Target")

      # Pre-tag `already` with VIP.
      {:ok, _} =
        MobileCarWash.Marketing.CustomerTag
        |> Ash.Changeset.for_create(:tag, %{
          customer_id: already.id,
          tag_id: vip.id,
          author_id: admin.id
        })
        |> Ash.create(authorize?: false)

      conn = sign_in(conn, admin)
      {:ok, lv, _} = live(conn, ~p"/admin/customers")

      lv |> element("#select-#{already.id}") |> render_click()
      lv |> element("#select-#{fresh.id}") |> render_click()

      lv
      |> form("#bulk-tag-form", %{"tag_id" => vip.id})
      |> render_submit()

      # Fresh customer now has the tag.
      {:ok, tags} =
        MobileCarWash.Marketing.CustomerTag
        |> Ash.Query.for_read(:for_customer, %{customer_id: fresh.id})
        |> Ash.read(authorize?: false)

      assert length(tags) == 1

      # Already-tagged customer still has exactly one row (no dup).
      {:ok, tags} =
        MobileCarWash.Marketing.CustomerTag
        |> Ash.Query.for_read(:for_customer, %{customer_id: already.id})
        |> Ash.read(authorize?: false)

      assert length(tags) == 1
    end

    test "filter by tag narrows the list", %{conn: conn} do
      :ok = Marketing.seed_tags!()

      {:ok, [vip]} =
        MobileCarWash.Marketing.Tag
        |> Ash.Query.for_read(:by_slug, %{slug: "vip"})
        |> Ash.read(authorize?: false)

      admin = register_admin!()
      tagged = register_customer!(nil, "Has VIP Tag")
      untagged = register_customer!(nil, "No Tag On Me")

      {:ok, _} =
        MobileCarWash.Marketing.CustomerTag
        |> Ash.Changeset.for_create(:tag, %{
          customer_id: tagged.id,
          tag_id: vip.id,
          author_id: admin.id
        })
        |> Ash.create(authorize?: false)

      conn = sign_in(conn, admin)
      {:ok, _lv, html} = live(conn, ~p"/admin/customers?tag=#{vip.id}")

      assert html =~ tagged.name
      refute html =~ untagged.name
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

    test "shows active subscription plan name", %{conn: conn} do
      admin = register_admin!()
      target = register_customer!()

      {:ok, plan} =
        SubscriptionPlan
        |> Ash.Changeset.for_create(:create, %{
          name: "Gold Shine Plan",
          slug: "gold_shine_#{System.unique_integer([:positive])}",
          price_cents: 12_500,
          basic_washes_per_month: 4,
          deep_cleans_per_month: 0,
          deep_clean_discount_percent: 30,
          description: ""
        })
        |> Ash.create(authorize?: false)

      {:ok, _sub} =
        Subscription
        |> Ash.Changeset.for_create(:create, %{
          status: :active,
          current_period_start: Date.utc_today(),
          current_period_end: Date.add(Date.utc_today(), 30),
          stripe_subscription_id: "sub_test_#{System.unique_integer([:positive])}"
        })
        |> Ash.Changeset.force_change_attribute(:customer_id, target.id)
        |> Ash.Changeset.force_change_attribute(:plan_id, plan.id)
        |> Ash.create(authorize?: false)

      conn = sign_in(conn, admin)
      {:ok, _lv, html} = live(conn, ~p"/admin/customers/#{target.id}")

      assert html =~ "Gold Shine Plan"
      assert html =~ "active"
    end

    test "renders 'No active subscription' when customer has none", %{conn: conn} do
      admin = register_admin!()
      target = register_customer!()

      conn = sign_in(conn, admin)
      {:ok, _lv, html} = live(conn, ~p"/admin/customers/#{target.id}")

      assert html =~ "No active subscription"
    end

    test "shows customer's vehicles", %{conn: conn} do
      admin = register_admin!()
      target = register_customer!()

      {:ok, _v} =
        Vehicle
        |> Ash.Changeset.for_create(:create, %{
          make: "Subaru",
          model: "Outback",
          year: 2022,
          color: "Steel Blue",
          size: :suv_van
        })
        |> Ash.Changeset.force_change_attribute(:customer_id, target.id)
        |> Ash.create()

      conn = sign_in(conn, admin)
      {:ok, _lv, html} = live(conn, ~p"/admin/customers/#{target.id}")

      assert html =~ "Subaru"
      assert html =~ "Outback"
    end

    test "shows customer's service addresses", %{conn: conn} do
      admin = register_admin!()
      target = register_customer!()

      {:ok, _a} =
        Address
        |> Ash.Changeset.for_create(:create, %{
          street: "777 Driveway Lane",
          city: "San Antonio",
          state: "TX",
          zip: "78261"
        })
        |> Ash.Changeset.force_change_attribute(:customer_id, target.id)
        |> Ash.create()

      conn = sign_in(conn, admin)
      {:ok, _lv, html} = live(conn, ~p"/admin/customers/#{target.id}")

      assert html =~ "777 Driveway Lane"
      assert html =~ "78261"
    end
  end

  describe "detail — notes" do
    alias MobileCarWash.Accounts.CustomerNote

    test "admin adds a note via the form", %{conn: conn} do
      admin = register_admin!()
      target = register_customer!()

      conn = sign_in(conn, admin)
      {:ok, lv, _} = live(conn, ~p"/admin/customers/#{target.id}")

      lv
      |> form("#add-note", %{"note" => %{"body" => "Called — likes early slots."}})
      |> render_submit()

      {:ok, notes} =
        CustomerNote
        |> Ash.Query.for_read(:for_customer, %{customer_id: target.id})
        |> Ash.read(authorize?: false)

      assert [note] = notes
      assert note.body == "Called — likes early slots."
      assert note.author_id == admin.id

      html = render(lv)
      assert html =~ "Called \xe2\x80\x94 likes early slots."
    end

    test "empty note body is rejected", %{conn: conn} do
      admin = register_admin!()
      target = register_customer!()

      conn = sign_in(conn, admin)
      {:ok, lv, _} = live(conn, ~p"/admin/customers/#{target.id}")

      lv
      |> form("#add-note", %{"note" => %{"body" => "   "}})
      |> render_submit()

      {:ok, notes} =
        CustomerNote
        |> Ash.Query.for_read(:for_customer, %{customer_id: target.id})
        |> Ash.read(authorize?: false)

      assert notes == []
    end

    test "pinned notes sort before unpinned", %{conn: conn} do
      admin = register_admin!()
      target = register_customer!()

      {:ok, _older} =
        CustomerNote
        |> Ash.Changeset.for_create(:add, %{
          customer_id: target.id,
          author_id: admin.id,
          body: "OLDER UNPINNED NOTE",
          pinned: false
        })
        |> Ash.create(authorize?: false)

      {:ok, _newer_pinned} =
        CustomerNote
        |> Ash.Changeset.for_create(:add, %{
          customer_id: target.id,
          author_id: admin.id,
          body: "PINNED NOTE",
          pinned: true
        })
        |> Ash.create(authorize?: false)

      conn = sign_in(conn, admin)
      {:ok, _lv, html} = live(conn, ~p"/admin/customers/#{target.id}")

      pinned_pos = :binary.match(html, "PINNED NOTE") |> elem(0)
      unpinned_pos = :binary.match(html, "OLDER UNPINNED NOTE") |> elem(0)

      assert pinned_pos < unpinned_pos
    end

    test "admin deletes a note", %{conn: conn} do
      admin = register_admin!()
      target = register_customer!()

      {:ok, note} =
        CustomerNote
        |> Ash.Changeset.for_create(:add, %{
          customer_id: target.id,
          author_id: admin.id,
          body: "Will delete me",
          pinned: false
        })
        |> Ash.create(authorize?: false)

      conn = sign_in(conn, admin)
      {:ok, lv, _} = live(conn, ~p"/admin/customers/#{target.id}")

      lv |> element("#delete-note-#{note.id}") |> render_click()

      {:ok, notes} =
        CustomerNote
        |> Ash.Query.for_read(:for_customer, %{customer_id: target.id})
        |> Ash.read(authorize?: false)

      assert notes == []
    end

    test "admin toggles pin on an existing note", %{conn: conn} do
      admin = register_admin!()
      target = register_customer!()

      {:ok, note} =
        CustomerNote
        |> Ash.Changeset.for_create(:add, %{
          customer_id: target.id,
          author_id: admin.id,
          body: "Toggle me",
          pinned: false
        })
        |> Ash.create(authorize?: false)

      conn = sign_in(conn, admin)
      {:ok, lv, _} = live(conn, ~p"/admin/customers/#{target.id}")

      lv |> element("#toggle-pin-#{note.id}") |> render_click()

      {:ok, reloaded} = Ash.get(CustomerNote, note.id, authorize?: false)
      assert reloaded.pinned == true
    end

    test "empty state when no notes exist", %{conn: conn} do
      admin = register_admin!()
      target = register_customer!()

      conn = sign_in(conn, admin)
      {:ok, _lv, html} = live(conn, ~p"/admin/customers/#{target.id}")

      assert html =~ "No notes yet"
    end
  end

  describe "detail — admin actions" do
    alias MobileCarWash.Accounts.CustomerNote

    test "Resend verification button hidden when customer already verified",
         %{conn: conn} do
      admin = register_admin!()
      target = register_customer!()

      # Stamp verified.
      target
      |> Ash.Changeset.for_update(:update, %{})
      |> Ash.Changeset.force_change_attribute(:email_verified_at, DateTime.utc_now())
      |> Ash.update!(authorize?: false)

      conn = sign_in(conn, admin)
      {:ok, _lv, html} = live(conn, ~p"/admin/customers/#{target.id}")

      refute html =~ "Resend verification"
    end

    test "Resend verification action creates an audit note", %{conn: conn} do
      admin = register_admin!()
      target = register_customer!()

      conn = sign_in(conn, admin)
      {:ok, lv, _} = live(conn, ~p"/admin/customers/#{target.id}")

      lv |> element("#resend-verification") |> render_click()

      {:ok, notes} =
        CustomerNote
        |> Ash.Query.for_read(:for_customer, %{customer_id: target.id})
        |> Ash.read(authorize?: false)

      assert Enum.any?(notes, fn n -> n.body =~ "verification email" end)
    end

    test "Apply credit increments referral_credit_cents", %{conn: conn} do
      admin = register_admin!()
      target = register_customer!()

      conn = sign_in(conn, admin)
      {:ok, lv, _} = live(conn, ~p"/admin/customers/#{target.id}")

      lv
      |> form("#apply-credit", %{"credit" => %{"amount_dollars" => "25"}})
      |> render_submit()

      {:ok, reloaded} = Ash.get(Customer, target.id, authorize?: false)
      assert reloaded.referral_credit_cents == 2_500
    end

    test "Apply credit creates an audit note", %{conn: conn} do
      admin = register_admin!()
      target = register_customer!()

      conn = sign_in(conn, admin)
      {:ok, lv, _} = live(conn, ~p"/admin/customers/#{target.id}")

      lv
      |> form("#apply-credit", %{"credit" => %{"amount_dollars" => "10"}})
      |> render_submit()

      {:ok, notes} =
        CustomerNote
        |> Ash.Query.for_read(:for_customer, %{customer_id: target.id})
        |> Ash.read(authorize?: false)

      assert Enum.any?(notes, fn n -> n.body =~ "$10" and n.body =~ "credit" end)
    end

    test "Disable button submits reason and disables the customer", %{conn: conn} do
      admin = register_admin!()
      target = register_customer!()

      conn = sign_in(conn, admin)
      {:ok, lv, _} = live(conn, ~p"/admin/customers/#{target.id}")

      lv
      |> form("#disable-account", %{"disable" => %{"reason" => "Repeated no-shows"}})
      |> render_submit()

      {:ok, reloaded} = Ash.get(Customer, target.id, authorize?: false)
      assert reloaded.disabled_at
      assert reloaded.disabled_reason == "Repeated no-shows"
    end

    test "Re-enable clears disabled_at", %{conn: conn} do
      admin = register_admin!()
      target = register_customer!()

      # Disable first.
      {:ok, _} =
        target
        |> Ash.Changeset.for_update(:disable, %{reason: "test"})
        |> Ash.update(authorize?: false)

      conn = sign_in(conn, admin)
      {:ok, lv, _} = live(conn, ~p"/admin/customers/#{target.id}")

      lv |> element("#reenable-account") |> render_click()

      {:ok, reloaded} = Ash.get(Customer, target.id, authorize?: false)
      assert is_nil(reloaded.disabled_at)
    end

    test "Apply credit rejects non-positive amounts", %{conn: conn} do
      admin = register_admin!()
      target = register_customer!()

      conn = sign_in(conn, admin)
      {:ok, lv, _} = live(conn, ~p"/admin/customers/#{target.id}")

      lv
      |> form("#apply-credit", %{"credit" => %{"amount_dollars" => "0"}})
      |> render_submit()

      {:ok, reloaded} = Ash.get(Customer, target.id, authorize?: false)
      assert reloaded.referral_credit_cents == 0

      lv
      |> form("#apply-credit", %{"credit" => %{"amount_dollars" => "-5"}})
      |> render_submit()

      {:ok, reloaded} = Ash.get(Customer, target.id, authorize?: false)
      assert reloaded.referral_credit_cents == 0
    end
  end

  describe "detail — tags" do
    alias MobileCarWash.Accounts.CustomerNote
    alias MobileCarWash.Marketing.{CustomerTag, Tag}

    setup do
      :ok = Marketing.seed_tags!()

      {:ok, [vip]} =
        Tag
        |> Ash.Query.for_read(:by_slug, %{slug: "vip"})
        |> Ash.read(authorize?: false)

      {:ok, [dns]} =
        Tag
        |> Ash.Query.for_read(:by_slug, %{slug: "do_not_service"})
        |> Ash.read(authorize?: false)

      %{vip: vip, dns: dns}
    end

    test "renders customer's tags as chips", %{conn: conn, vip: vip} do
      admin = register_admin!()
      target = register_customer!()

      {:ok, _} =
        CustomerTag
        |> Ash.Changeset.for_create(:tag, %{
          customer_id: target.id,
          tag_id: vip.id,
          author_id: admin.id
        })
        |> Ash.create(authorize?: false)

      conn = sign_in(conn, admin)
      {:ok, _lv, html} = live(conn, ~p"/admin/customers/#{target.id}")

      assert html =~ "VIP"
    end

    test "admin tags customer with a seeded tag", %{conn: conn, vip: vip} do
      admin = register_admin!()
      target = register_customer!()

      conn = sign_in(conn, admin)
      {:ok, lv, _} = live(conn, ~p"/admin/customers/#{target.id}")

      lv
      |> form("#apply-tag", %{"tag_id" => vip.id})
      |> render_submit()

      {:ok, tags} =
        CustomerTag
        |> Ash.Query.for_read(:for_customer, %{customer_id: target.id})
        |> Ash.read(authorize?: false)

      assert [ct] = tags
      assert ct.tag_id == vip.id
      assert ct.author_id == admin.id
    end

    test "admin removes a tag", %{conn: conn, vip: vip} do
      admin = register_admin!()
      target = register_customer!()

      {:ok, ct} =
        CustomerTag
        |> Ash.Changeset.for_create(:tag, %{
          customer_id: target.id,
          tag_id: vip.id,
          author_id: admin.id
        })
        |> Ash.create(authorize?: false)

      conn = sign_in(conn, admin)
      {:ok, lv, _} = live(conn, ~p"/admin/customers/#{target.id}")

      lv |> element("#untag-#{ct.id}") |> render_click()

      {:ok, tags} =
        CustomerTag
        |> Ash.Query.for_read(:for_customer, %{customer_id: target.id})
        |> Ash.read(authorize?: false)

      assert tags == []
    end

    test "tagging creates an audit note", %{conn: conn, vip: vip} do
      admin = register_admin!()
      target = register_customer!()

      conn = sign_in(conn, admin)
      {:ok, lv, _} = live(conn, ~p"/admin/customers/#{target.id}")

      lv
      |> form("#apply-tag", %{"tag_id" => vip.id})
      |> render_submit()

      {:ok, notes} =
        CustomerNote
        |> Ash.Query.for_read(:for_customer, %{customer_id: target.id})
        |> Ash.read(authorize?: false)

      assert Enum.any?(notes, fn n -> n.body =~ "VIP" and n.body =~ "Tagged" end)
    end

    test "untagging creates an audit note", %{conn: conn, vip: vip} do
      admin = register_admin!()
      target = register_customer!()

      {:ok, ct} =
        CustomerTag
        |> Ash.Changeset.for_create(:tag, %{
          customer_id: target.id,
          tag_id: vip.id,
          author_id: admin.id
        })
        |> Ash.create(authorize?: false)

      conn = sign_in(conn, admin)
      {:ok, lv, _} = live(conn, ~p"/admin/customers/#{target.id}")

      lv |> element("#untag-#{ct.id}") |> render_click()

      {:ok, notes} =
        CustomerNote
        |> Ash.Query.for_read(:for_customer, %{customer_id: target.id})
        |> Ash.read(authorize?: false)

      assert Enum.any?(notes, fn n -> n.body =~ "VIP" and n.body =~ "Untagged" end)
    end

    test "already-applied tag is not in the add-tag dropdown",
         %{conn: conn, vip: vip} do
      admin = register_admin!()
      target = register_customer!()

      {:ok, _} =
        CustomerTag
        |> Ash.Changeset.for_create(:tag, %{
          customer_id: target.id,
          tag_id: vip.id,
          author_id: admin.id
        })
        |> Ash.create(authorize?: false)

      conn = sign_in(conn, admin)
      {:ok, _lv, html} = live(conn, ~p"/admin/customers/#{target.id}")

      # Parse out the <select name="tag_id"> options and ensure VIP's id
      # is not among them.
      refute html =~ ~s(value="#{vip.id}")
    end

    test "banner shown when customer has an affects_booking tag",
         %{conn: conn, dns: dns} do
      admin = register_admin!()
      target = register_customer!()

      {:ok, _} =
        CustomerTag
        |> Ash.Changeset.for_create(:tag, %{
          customer_id: target.id,
          tag_id: dns.id,
          author_id: admin.id
        })
        |> Ash.create(authorize?: false)

      conn = sign_in(conn, admin)
      {:ok, _lv, html} = live(conn, ~p"/admin/customers/#{target.id}")

      assert html =~ ~s(id="booking-flag-alert")
      assert html =~ "Do Not Service"
    end

    test "no banner when only non-affects_booking tags are applied",
         %{conn: conn, vip: vip} do
      admin = register_admin!()
      target = register_customer!()

      {:ok, _} =
        CustomerTag
        |> Ash.Changeset.for_create(:tag, %{
          customer_id: target.id,
          tag_id: vip.id,
          author_id: admin.id
        })
        |> Ash.create(authorize?: false)

      conn = sign_in(conn, admin)
      {:ok, _lv, html} = live(conn, ~p"/admin/customers/#{target.id}")

      refute html =~ ~s(id="booking-flag-alert")
    end
  end
end
