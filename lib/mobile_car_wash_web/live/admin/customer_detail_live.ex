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

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Marketing.{AcquisitionChannel, Persona, PersonaMembership, Personas}
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
      lifetime_revenue: lifetime_revenue
    )
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
          <div class="flex gap-2 mt-2">
            <span class="badge badge-ghost">{@customer.role}</span>
            <span :if={@customer.email_verified_at} class="badge badge-success">Verified</span>
            <span :if={is_nil(@customer.email_verified_at)} class="badge badge-warning">Unverified</span>
          </div>
        </div>

        <div class="text-right">
          <div class="text-xs text-base-content/60">Lifetime revenue</div>
          <div class="text-2xl font-bold text-primary">{fmt_cents(@lifetime_revenue)}</div>
          <div class="text-xs text-base-content/60">
            Joined {Calendar.strftime(@customer.inserted_at, "%B %d, %Y")}
          </div>
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
