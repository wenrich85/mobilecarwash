defmodule MobileCarWashWeb.Admin.CustomerDetailLive do
  @moduledoc """
  Admin customer detail page. Everything you'd want to know about a
  single customer — profile + attribution + revenue + persona
  memberships + recent appointments — plus the two admin affordances
  that weren't previously accessible anywhere:

    * Reassign `acquired_channel_id` (for word-of-mouth / door-hanger
      leads that need retroactive tagging)
    * Manually tag a persona membership
    * Recompute auto-assigned personas via the rule engine
  """
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Accounts.{Customer, CustomerNote}
  alias MobileCarWash.Billing.{Subscription, SubscriptionPlan}
  alias MobileCarWash.Fleet.{Address, Vehicle}

  alias MobileCarWash.Marketing.{
    AcquisitionChannel,
    CustomerTag,
    Persona,
    PersonaMembership,
    Personas,
    Tag
  }

  alias MobileCarWash.Notifications.VerificationEmailWorker
  alias MobileCarWash.Repo
  alias MobileCarWash.Scheduling.Appointment

  import Ecto.Query
  require Ash.Query

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Ash.get(Customer, id, authorize?: false) do
      {:ok, customer} ->
        {:ok, load_detail(socket, customer)}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Customer not found")
         |> push_navigate(to: ~p"/admin/customers")}
    end
  end

  @impl true
  def handle_event("reassign_channel", %{"channel_id" => ""}, socket),
    do: {:noreply, put_flash(socket, :error, "Pick a channel")}

  def handle_event("reassign_channel", %{"channel_id" => channel_id}, socket) do
    {:ok, updated} =
      socket.assigns.customer
      |> Ash.Changeset.for_update(:update, %{})
      |> Ash.Changeset.force_change_attribute(:acquired_channel_id, channel_id)
      |> Ash.update(authorize?: false)

    {:noreply,
     socket
     |> put_flash(:info, "Channel reassigned")
     |> load_detail(updated)}
  end

  def handle_event("assign_persona", %{"persona_id" => ""}, socket),
    do: {:noreply, put_flash(socket, :error, "Pick a persona")}

  def handle_event("assign_persona", %{"persona_id" => persona_id}, socket) do
    case PersonaMembership
         |> Ash.Changeset.for_create(:assign, %{
           customer_id: socket.assigns.customer.id,
           persona_id: persona_id,
           manually_assigned: true
         })
         |> Ash.create(authorize?: false) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Persona tagged")
         |> load_detail(socket.assigns.customer)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Already tagged with that persona")}
    end
  end

  def handle_event("unassign_persona", %{"id" => id}, socket) do
    case Ash.get(PersonaMembership, id, authorize?: false) do
      {:ok, membership} -> Ash.destroy!(membership, authorize?: false)
      _ -> :ok
    end

    {:noreply, load_detail(socket, socket.assigns.customer)}
  end

  def handle_event("recompute_personas", _params, socket) do
    :ok = Personas.assign_matching!(socket.assigns.customer)

    {:noreply,
     socket
     |> put_flash(:info, "Persona memberships recomputed")
     |> load_detail(socket.assigns.customer)}
  end

  def handle_event("add_note", %{"note" => params}, socket) do
    body = params |> Map.get("body", "") |> to_string() |> String.trim()
    pinned = params |> Map.get("pinned", "false") |> truthy?()

    if body == "" do
      {:noreply, put_flash(socket, :error, "Note body is required")}
    else
      case CustomerNote
           |> Ash.Changeset.for_create(:add, %{
             customer_id: socket.assigns.customer.id,
             author_id: socket.assigns.current_customer.id,
             body: body,
             pinned: pinned
           })
           |> Ash.create(authorize?: false) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "Note added")
           |> load_detail(socket.assigns.customer)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not save note")}
      end
    end
  end

  def handle_event("delete_note", %{"id" => id}, socket) do
    case Ash.get(CustomerNote, id, authorize?: false) do
      {:ok, note} -> Ash.destroy!(note, authorize?: false)
      _ -> :ok
    end

    {:noreply, load_detail(socket, socket.assigns.customer)}
  end

  def handle_event("toggle_pin", %{"id" => id}, socket) do
    with {:ok, note} <- Ash.get(CustomerNote, id, authorize?: false),
         {:ok, _} <-
           note
           |> Ash.Changeset.for_update(:toggle_pin)
           |> Ash.update(authorize?: false) do
      {:noreply, load_detail(socket, socket.assigns.customer)}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not toggle pin")}
    end
  end

  def handle_event("resend_verification", _params, socket) do
    customer = socket.assigns.customer
    admin = socket.assigns.current_customer

    # Enqueue the worker — it no-ops if the customer is already verified,
    # so this is safe to click more than once.
    %{customer_id: customer.id}
    |> VerificationEmailWorker.new(queue: :notifications)
    |> Oban.insert()

    audit_note!(customer.id, admin.id, "Resent verification email to #{customer.email}.")

    {:noreply,
     socket
     |> put_flash(:info, "Verification email sent")
     |> load_detail(customer)}
  end

  def handle_event("apply_tag", %{"tag_id" => ""}, socket),
    do: {:noreply, put_flash(socket, :error, "Pick a tag")}

  def handle_event("apply_tag", %{"tag_id" => tag_id}, socket) do
    customer = socket.assigns.customer
    admin = socket.assigns.current_customer

    with {:ok, tag} <- Ash.get(Tag, tag_id, authorize?: false),
         {:ok, _ct} <-
           CustomerTag
           |> Ash.Changeset.for_create(:tag, %{
             customer_id: customer.id,
             tag_id: tag.id,
             author_id: admin.id
           })
           |> Ash.create(authorize?: false) do
      audit_note!(customer.id, admin.id, "Tagged customer: #{tag.name}.")

      {:noreply,
       socket
       |> put_flash(:info, "Tag added")
       |> load_detail(customer)}
    else
      {:error, _} ->
        # Most common case: unique-pair violation (already tagged).
        {:noreply, put_flash(socket, :error, "Already tagged with that tag")}
    end
  end

  def handle_event("untag", %{"id" => id}, socket) do
    customer = socket.assigns.customer
    admin = socket.assigns.current_customer

    with {:ok, ct} <- Ash.get(CustomerTag, id, authorize?: false),
         {:ok, tag} <- Ash.get(Tag, ct.tag_id, authorize?: false),
         :ok <- Ash.destroy(ct, authorize?: false) do
      audit_note!(customer.id, admin.id, "Untagged customer: #{tag.name}.")
      {:noreply, load_detail(socket, customer)}
    else
      _ ->
        {:noreply, load_detail(socket, customer)}
    end
  end

  def handle_event("apply_credit", %{"credit" => params}, socket) do
    case parse_credit_dollars(params["amount_dollars"]) do
      {:ok, cents} ->
        customer = socket.assigns.customer
        admin = socket.assigns.current_customer
        new_balance = (customer.referral_credit_cents || 0) + cents

        {:ok, updated} =
          customer
          |> Ash.Changeset.for_update(:update, %{referral_credit_cents: new_balance})
          |> Ash.update(authorize?: false)

        audit_note!(
          customer.id,
          admin.id,
          "Applied $#{format_dollars(cents)} credit. New balance: $#{format_dollars(new_balance)}."
        )

        {:noreply,
         socket
         |> put_flash(:info, "Credit applied")
         |> load_detail(updated)}

      {:error, msg} ->
        {:noreply, put_flash(socket, :error, msg)}
    end
  end

  defp truthy?(v) when v in [true, "true", "on", "1"], do: true
  defp truthy?(_), do: false

  defp parse_credit_dollars(value) do
    case value |> to_string() |> String.trim() |> Float.parse() do
      {amount, ""} when amount > 0 -> {:ok, round(amount * 100)}
      _ -> {:error, "Amount must be a positive number"}
    end
  end

  defp format_dollars(cents) when is_integer(cents) do
    :erlang.float_to_binary(cents / 100, decimals: 2)
  end

  # Tag color atom → DaisyUI badge class.
  defp badge_class_for(nil), do: "badge-neutral"
  defp badge_class_for(%{color: :primary}), do: "badge-primary"
  defp badge_class_for(%{color: :success}), do: "badge-success"
  defp badge_class_for(%{color: :warning}), do: "badge-warning"
  defp badge_class_for(%{color: :error}), do: "badge-error"
  defp badge_class_for(%{color: :info}), do: "badge-info"
  defp badge_class_for(_), do: "badge-neutral"

  defp audit_note!(customer_id, admin_id, body) do
    CustomerNote
    |> Ash.Changeset.for_create(:add, %{
      customer_id: customer_id,
      author_id: admin_id,
      body: body,
      pinned: false
    })
    |> Ash.create!(authorize?: false)
  end

  # --- Private ---

  defp load_detail(socket, customer) do
    channels =
      AcquisitionChannel
      |> Ash.Query.for_read(:active)
      |> Ash.read!(authorize?: false)

    personas_all =
      Persona
      |> Ash.Query.for_read(:active)
      |> Ash.read!(authorize?: false)

    memberships =
      PersonaMembership
      |> Ash.Query.for_read(:for_customer, %{customer_id: customer.id})
      |> Ash.read!(authorize?: false)

    persona_by_id = Map.new(personas_all, &{&1.id, &1})

    appointments = load_appointments(customer.id)
    lifetime_revenue = lifetime_revenue(customer.id)
    {subscription, plan} = load_subscription(customer.id)
    vehicles = load_vehicles(customer.id)
    addresses = load_addresses(customer.id)
    {notes, authors_by_id} = load_notes(customer.id)
    {customer_tags, tag_by_id, available_tags} = load_tags(customer.id)

    channel = Enum.find(channels, &(&1.id == customer.acquired_channel_id))

    socket
    |> assign(page_title: customer.name)
    |> assign(
      customer: customer,
      channels: channels,
      channel: channel,
      personas: personas_all,
      persona_by_id: persona_by_id,
      memberships: memberships,
      appointments: appointments,
      lifetime_revenue: lifetime_revenue,
      subscription: subscription,
      subscription_plan: plan,
      vehicles: vehicles,
      addresses: addresses,
      notes: notes,
      authors_by_id: authors_by_id,
      customer_tags: customer_tags,
      tag_by_id: tag_by_id,
      available_tags: available_tags
    )
  end

  defp load_tags(customer_id) do
    customer_tags =
      CustomerTag
      |> Ash.Query.for_read(:for_customer, %{customer_id: customer_id})
      |> Ash.read!(authorize?: false)

    all_active_tags =
      Tag
      |> Ash.Query.for_read(:active)
      |> Ash.read!(authorize?: false)

    tag_by_id = Map.new(all_active_tags, &{&1.id, &1})
    taken = MapSet.new(customer_tags, & &1.tag_id)
    available = Enum.reject(all_active_tags, &MapSet.member?(taken, &1.id))

    {customer_tags, tag_by_id, available}
  end

  defp load_notes(customer_id) do
    notes =
      CustomerNote
      |> Ash.Query.for_read(:for_customer, %{customer_id: customer_id})
      |> Ash.read!(authorize?: false)

    # One tiny lookup for all the authors so we can display names without
    # N+1 loads in the template.
    author_ids =
      notes
      |> Enum.map(& &1.author_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    authors_by_id =
      case author_ids do
        [] ->
          %{}

        ids ->
          Customer
          |> Ash.Query.filter(id in ^ids)
          |> Ash.read!(authorize?: false)
          |> Map.new(&{&1.id, &1})
      end

    {notes, authors_by_id}
  end

  # Most-recent non-cancelled subscription + its plan. Nil tuple if none.
  defp load_subscription(customer_id) do
    case Subscription
         |> Ash.Query.for_read(:active_for_customer, %{customer_id: customer_id})
         |> Ash.Query.sort(inserted_at: :desc)
         |> Ash.Query.limit(1)
         |> Ash.read(authorize?: false) do
      {:ok, [sub | _]} ->
        plan =
          case Ash.get(SubscriptionPlan, sub.plan_id, authorize?: false) do
            {:ok, p} -> p
            _ -> nil
          end

        {sub, plan}

      _ ->
        {nil, nil}
    end
  end

  defp load_vehicles(customer_id) do
    Vehicle
    |> Ash.Query.filter(customer_id == ^customer_id)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read!(authorize?: false)
  end

  defp load_addresses(customer_id) do
    Address
    |> Ash.Query.filter(customer_id == ^customer_id)
    |> Ash.Query.sort([{:is_default, :desc}, {:inserted_at, :desc}])
    |> Ash.read!(authorize?: false)
  end

  defp load_appointments(customer_id) do
    Appointment
    |> Ash.Query.filter(customer_id == ^customer_id)
    |> Ash.Query.sort(scheduled_at: :desc)
    |> Ash.Query.limit(10)
    |> Ash.read!(authorize?: false)
  end

  defp lifetime_revenue(customer_id) do
    uuid = Ecto.UUID.dump!(customer_id)

    query =
      from p in "payments",
        where: p.status == "succeeded",
        where: p.customer_id == ^uuid,
        select: coalesce(sum(p.amount_cents), 0)

    case Repo.one(query) do
      %Decimal{} = d -> Decimal.to_integer(d)
      n when is_integer(n) -> n
      _ -> 0
    end
  end

  defp fmt_cents(nil), do: "$0.00"
  defp fmt_cents(0), do: "$0.00"

  defp fmt_cents(cents) when is_integer(cents),
    do: "$" <> :erlang.float_to_binary(cents / 100, decimals: 2)

  defp fmt_date(nil), do: "—"
  defp fmt_date(%Date{} = d), do: Calendar.strftime(d, "%b %d, %Y")
  defp fmt_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %d, %Y")

  # Subscription status pill color. `:active` is green, paused is amber,
  # past_due is red, cancelled is ghost.
  defp sub_status_class(:active), do: "badge-success"
  defp sub_status_class(:paused), do: "badge-warning"
  defp sub_status_class(:past_due), do: "badge-error"
  defp sub_status_class(_), do: "badge-ghost"

  defp format_vehicle(v) do
    [v.year, v.color, v.make, v.model]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end

  defp format_address_line(a) do
    [a.street, "#{a.city}, #{a.state} #{a.zip}"]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" · ")
  end

  defp unassigned_personas(personas, memberships) do
    taken = MapSet.new(memberships, & &1.persona_id)
    Enum.reject(personas, &MapSet.member?(taken, &1.id))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto py-8 px-4">
      <div class="mb-4">
        <.link navigate={~p"/admin/customers"} class="text-sm link link-hover">
          ← All customers
        </.link>
      </div>

      <div class="flex flex-wrap items-start justify-between gap-4 mb-6">
        <div>
          <h1 class="text-3xl font-bold">{@customer.name}</h1>
          <p class="text-base-content/80">{@customer.email} · {@customer.phone}</p>
          <div class="flex gap-2 mt-2 flex-wrap">
            <span class="badge badge-ghost">{@customer.role}</span>
            <span :if={@customer.email_verified_at} class="badge badge-success">Verified</span>
            <span :if={is_nil(@customer.email_verified_at)} class="badge badge-warning">
              Unverified
            </span>

            <span
              :for={ct <- @customer_tags}
              :if={Map.has_key?(@tag_by_id, ct.tag_id)}
              class={"badge gap-1 " <> badge_class_for(Map.get(@tag_by_id, ct.tag_id))}
            >
              {Map.get(@tag_by_id, ct.tag_id).name}
              <button
                id={"untag-#{ct.id}"}
                phx-click="untag"
                phx-value-id={ct.id}
                type="button"
                class="hover:opacity-80"
                aria-label="Remove tag"
              >
                ×
              </button>
            </span>
          </div>

          <form
            :if={@available_tags != []}
            id="apply-tag"
            phx-submit="apply_tag"
            class="join mt-3"
          >
            <select name="tag_id" class="select select-bordered select-sm join-item">
              <option value="">+ Add tag…</option>
              <option :for={t <- @available_tags} value={t.id}>{t.name}</option>
            </select>
            <button type="submit" class="btn btn-sm btn-primary join-item">Apply</button>
          </form>
        </div>

        <div class="text-right">
          <div class="text-xs text-base-content/60">Lifetime revenue</div>
          <div class="text-2xl font-bold text-primary">{fmt_cents(@lifetime_revenue)}</div>
          <div class="text-xs text-base-content/60">
            Joined {Calendar.strftime(@customer.inserted_at, "%B %d, %Y")}
          </div>
          <div class="text-xs text-base-content/60 mt-1">
            Credit balance: {fmt_cents(@customer.referral_credit_cents)}
          </div>
        </div>
      </div>
      
    <!-- Admin actions strip -->
      <div class="card bg-base-100 border border-base-300 mb-6">
        <div class="card-body flex flex-col md:flex-row md:items-center gap-4 py-4">
          <div class="flex-1">
            <h2 class="font-semibold">Admin actions</h2>
            <p class="text-xs text-base-content/60">
              All actions are recorded as notes for audit.
            </p>
          </div>

          <button
            :if={is_nil(@customer.email_verified_at)}
            id="resend-verification"
            phx-click="resend_verification"
            class="btn btn-outline btn-sm"
          >
            Resend verification
          </button>

          <form
            id="apply-credit"
            phx-submit="apply_credit"
            class="join"
          >
            <span class="join-item btn btn-sm btn-ghost no-animation cursor-default">$</span>
            <input
              type="number"
              step="0.01"
              min="0"
              name="credit[amount_dollars]"
              placeholder="25"
              class="input input-bordered input-sm join-item w-24"
            />
            <button type="submit" class="btn btn-primary btn-sm join-item">Apply credit</button>
          </form>
        </div>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <!-- Attribution -->
        <div class="card bg-base-200 lg:col-span-2">
          <div class="card-body">
            <h2 class="card-title">Attribution</h2>
            <dl class="grid grid-cols-2 gap-y-2 text-sm">
              <dt class="text-base-content/60">Channel</dt>
              <dd>{if @channel, do: @channel.display_name, else: "—"}</dd>

              <dt class="text-base-content/60">utm_source</dt>
              <dd><code>{@customer.utm_source || "—"}</code></dd>

              <dt class="text-base-content/60">utm_medium</dt>
              <dd><code>{@customer.utm_medium || "—"}</code></dd>

              <dt class="text-base-content/60">utm_campaign</dt>
              <dd><code>{@customer.utm_campaign || "—"}</code></dd>

              <dt class="text-base-content/60">Referrer</dt>
              <dd class="truncate">{@customer.referrer || "—"}</dd>

              <dt class="text-base-content/60">Referral code</dt>
              <dd><code>{@customer.referral_code}</code></dd>

              <dt class="text-base-content/60">Referral credit</dt>
              <dd>{fmt_cents(@customer.referral_credit_cents)}</dd>
            </dl>

            <form
              id="reassign-channel"
              phx-submit="reassign_channel"
              class="mt-4 join w-full"
            >
              <select name="channel_id" class="select select-bordered join-item flex-1">
                <option value="">Reassign channel…</option>
                <option
                  :for={c <- @channels}
                  value={c.id}
                  selected={c.id == @customer.acquired_channel_id}
                >
                  {c.display_name}
                </option>
              </select>
              <button type="submit" class="btn btn-primary join-item">Update</button>
            </form>
          </div>
        </div>
        
    <!-- Personas -->
        <div class="card bg-base-100 border border-base-300">
          <div class="card-body">
            <div class="flex items-center justify-between">
              <h2 class="card-title">Personas</h2>
              <button
                id="recompute-personas"
                phx-click="recompute_personas"
                class="btn btn-ghost btn-xs"
                title="Run the rule engine against this customer"
              >
                Recompute
              </button>
            </div>

            <ul :if={@memberships != []} class="space-y-2">
              <li :for={m <- @memberships} class="flex items-center justify-between">
                <div>
                  <span class="font-medium">
                    {Map.get(@persona_by_id, m.persona_id, %{name: "—"}).name}
                  </span>
                  <span class={"badge badge-xs ml-1 " <> if(m.manually_assigned, do: "badge-warning", else: "badge-ghost")}>
                    {if m.manually_assigned, do: "manual", else: "auto"}
                  </span>
                </div>
                <button
                  phx-click="unassign_persona"
                  phx-value-id={m.id}
                  class="btn btn-ghost btn-xs text-error"
                >
                  Remove
                </button>
              </li>
            </ul>

            <p :if={@memberships == []} class="text-sm text-base-content/60">
              No persona memberships yet.
            </p>

            <form
              :if={unassigned_personas(@personas, @memberships) != []}
              id="assign-persona"
              phx-submit="assign_persona"
              class="mt-3 join w-full"
            >
              <select name="persona_id" class="select select-bordered select-sm join-item flex-1">
                <option value="">Tag a persona…</option>
                <option :for={p <- unassigned_personas(@personas, @memberships)} value={p.id}>
                  {p.name}
                </option>
              </select>
              <button type="submit" class="btn btn-primary btn-sm join-item">Tag</button>
            </form>
          </div>
        </div>
      </div>
      
    <!-- Subscription -->
      <div class="card bg-base-100 border border-base-300 mt-6">
        <div class="card-body">
          <h2 class="card-title">Subscription</h2>

          <div :if={is_nil(@subscription)} class="text-sm text-base-content/60 py-2">
            No active subscription.
          </div>

          <div :if={@subscription} class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <dl class="text-sm space-y-2">
              <div>
                <dt class="text-base-content/60 inline">Plan</dt>
                <dd class="inline font-medium ml-1">
                  {(@subscription_plan && @subscription_plan.name) || "—"}
                </dd>
              </div>
              <div>
                <dt class="text-base-content/60 inline">Price</dt>
                <dd class="inline font-medium ml-1">
                  {fmt_cents(@subscription_plan && @subscription_plan.price_cents)}/mo
                </dd>
              </div>
              <div>
                <dt class="text-base-content/60 inline">Status</dt>
                <dd class="inline ml-1">
                  <span class={"badge badge-sm " <> sub_status_class(@subscription.status)}>
                    {@subscription.status}
                  </span>
                </dd>
              </div>
            </dl>

            <dl class="text-sm space-y-2">
              <div>
                <dt class="text-base-content/60 inline">Current period</dt>
                <dd class="inline ml-1">
                  {fmt_date(@subscription.current_period_start)} → {fmt_date(
                    @subscription.current_period_end
                  )}
                </dd>
              </div>
              <div :if={@subscription.stripe_subscription_id}>
                <dt class="text-base-content/60 inline">Stripe ID</dt>
                <dd class="inline ml-1">
                  <code class="text-xs">{@subscription.stripe_subscription_id}</code>
                </dd>
              </div>
            </dl>
          </div>
        </div>
      </div>
      
    <!-- Notes -->
      <div class="card bg-base-100 border border-base-300 mt-6">
        <div class="card-body">
          <h2 class="card-title">
            Notes <span class="badge badge-sm badge-ghost ml-2">{length(@notes)}</span>
          </h2>

          <form
            id="add-note"
            phx-submit="add_note"
            class="flex flex-col gap-2 mb-4"
          >
            <textarea
              name="note[body]"
              rows="2"
              placeholder="Add an internal note — customer can't see this."
              class="textarea textarea-bordered w-full"
            ></textarea>

            <div class="flex items-center justify-between">
              <label class="label cursor-pointer gap-2">
                <input type="checkbox" name="note[pinned]" value="true" class="checkbox checkbox-sm" />
                <span class="label-text text-sm">Pin this note to the top</span>
              </label>

              <button type="submit" class="btn btn-primary btn-sm">Save note</button>
            </div>
          </form>

          <div :if={@notes == []} class="text-sm text-base-content/60 py-2">
            No notes yet.
          </div>

          <ul :if={@notes != []} class="divide-y divide-base-300">
            <li :for={n <- @notes} class="py-3">
              <div class="flex items-start justify-between gap-3">
                <div class="flex-1 min-w-0">
                  <div class="flex items-center gap-2 mb-1">
                    <span :if={n.pinned} class="badge badge-primary badge-xs">Pinned</span>
                    <span class="text-xs text-base-content/60">
                      {Map.get(@authors_by_id, n.author_id, %{name: "Unknown"}).name} · {Calendar.strftime(
                        n.inserted_at,
                        "%b %d, %Y %I:%M %p"
                      )}
                    </span>
                  </div>
                  <p class="text-sm whitespace-pre-wrap">{n.body}</p>
                </div>

                <div class="flex gap-1 shrink-0">
                  <button
                    id={"toggle-pin-#{n.id}"}
                    phx-click="toggle_pin"
                    phx-value-id={n.id}
                    class="btn btn-ghost btn-xs"
                    title={if n.pinned, do: "Unpin", else: "Pin"}
                  >
                    {if n.pinned, do: "Unpin", else: "Pin"}
                  </button>
                  <button
                    id={"delete-note-#{n.id}"}
                    phx-click="delete_note"
                    phx-value-id={n.id}
                    data-confirm="Delete this note?"
                    class="btn btn-ghost btn-xs text-error"
                  >
                    Delete
                  </button>
                </div>
              </div>
            </li>
          </ul>
        </div>
      </div>
      
    <!-- Vehicles -->
      <div class="card bg-base-100 border border-base-300 mt-6">
        <div class="card-body">
          <h2 class="card-title">
            Vehicles <span class="badge badge-sm badge-ghost ml-2">{length(@vehicles)}</span>
          </h2>

          <div :if={@vehicles == []} class="text-sm text-base-content/60 py-2">
            No vehicles on file.
          </div>

          <ul :if={@vehicles != []} class="divide-y divide-base-300">
            <li :for={v <- @vehicles} class="py-2 flex justify-between items-center">
              <span class="font-medium">{format_vehicle(v)}</span>
              <span class="badge badge-sm badge-ghost">{v.size}</span>
            </li>
          </ul>
        </div>
      </div>
      
    <!-- Addresses -->
      <div class="card bg-base-100 border border-base-300 mt-6">
        <div class="card-body">
          <h2 class="card-title">
            Service addresses
            <span class="badge badge-sm badge-ghost ml-2">{length(@addresses)}</span>
          </h2>

          <div :if={@addresses == []} class="text-sm text-base-content/60 py-2">
            No addresses on file.
          </div>

          <ul :if={@addresses != []} class="divide-y divide-base-300">
            <li :for={a <- @addresses} class="py-2 flex justify-between items-center">
              <span>{format_address_line(a)}</span>
              <span :if={a.is_default} class="badge badge-sm badge-primary">Default</span>
            </li>
          </ul>
        </div>
      </div>
      
    <!-- Appointments -->
      <div class="card bg-base-100 border border-base-300 mt-6">
        <div class="card-body">
          <h2 class="card-title">Recent appointments</h2>

          <div :if={@appointments == []} class="text-sm text-base-content/60 py-2">
            No appointments yet.
          </div>

          <table :if={@appointments != []} class="table table-sm">
            <thead>
              <tr>
                <th>Scheduled</th>
                <th>Status</th>
                <th class="text-right">Price</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={a <- @appointments} class="hover">
                <td>{Calendar.strftime(a.scheduled_at, "%b %d, %Y %I:%M %p")}</td>
                <td><span class="badge badge-sm badge-ghost">{a.status}</span></td>
                <td class="text-right">{fmt_cents(a.price_cents)}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end
end
