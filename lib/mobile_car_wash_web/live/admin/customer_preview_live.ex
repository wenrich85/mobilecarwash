defmodule MobileCarWashWeb.Admin.CustomerPreviewLive do
  @moduledoc """
  Admin-only "view as customer" snapshot.

  Shows the target customer's upcoming + past appointments, styled
  like the customer-facing /appointments page, so support can answer
  "what does my account look like right now?" without needing to
  session-swap (which we deliberately do NOT support — no JWT
  forgery, no cookie stuffing).

  Everything here is read-only. No book/cancel/upload controls. On
  mount, a CustomerNote is auto-created so the customer's file shows
  who looked and when.
  """
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Accounts.{Customer, CustomerNote}
  alias MobileCarWash.Scheduling.{Appointment, ServiceType}

  require Ash.Query

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Ash.get(Customer, id, authorize?: false) do
      {:ok, customer} ->
        audit_preview_view!(customer.id, socket.assigns.current_customer.id)

        appointments =
          Appointment
          |> Ash.Query.filter(customer_id == ^customer.id)
          |> Ash.Query.sort(scheduled_at: :desc)
          |> Ash.read!(authorize?: false)

        service_types =
          ServiceType
          |> Ash.read!(authorize?: false)
          |> Map.new(&{&1.id, &1})

        {:ok,
         socket
         |> assign(
           page_title: "Preview — #{customer.name}",
           customer: customer,
           appointments: appointments,
           service_types: service_types
         )}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Customer not found")
         |> push_navigate(to: ~p"/admin/customers")}
    end
  end

  # --- Private ---

  defp audit_preview_view!(customer_id, admin_id) do
    CustomerNote
    |> Ash.Changeset.for_create(:add, %{
      customer_id: customer_id,
      author_id: admin_id,
      body: "Admin viewed this customer's preview (impersonate-lite).",
      pinned: false
    })
    |> Ash.create!(authorize?: false)
  end

  defp fmt_cents(nil), do: "$0.00"
  defp fmt_cents(0), do: "$0.00"

  defp fmt_cents(cents) when is_integer(cents),
    do: "$" <> :erlang.float_to_binary(cents / 100, decimals: 2)

  defp status_badge(:pending), do: "badge-ghost"
  defp status_badge(:confirmed), do: "badge-info"
  defp status_badge(:en_route), do: "badge-warning"
  defp status_badge(:on_site), do: "badge-warning"
  defp status_badge(:in_progress), do: "badge-warning"
  defp status_badge(:completed), do: "badge-success"
  defp status_badge(:cancelled), do: "badge-error"
  defp status_badge(_), do: "badge-ghost"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto py-8 px-4">
      <div class="mb-4">
        <.link
          navigate={~p"/admin/customers/#{@customer.id}"}
          class="text-sm link link-hover"
        >
          ← Back to customer
        </.link>
      </div>

      <div id="preview-banner" role="alert" class="alert alert-warning mb-6">
        <span class="hero-eye size-5 shrink-0"></span>
        <div>
          <div class="font-semibold">Admin preview — read-only</div>
          <div class="text-sm">
            You are viewing {@customer.name}'s account as if you were them. No actions here affect
            their data. A note has been added to their file recording this view.
          </div>
        </div>
      </div>

      <h1 class="text-3xl font-bold mb-2">My Appointments</h1>
      <p class="text-base-content/80 mb-6">
        {@customer.name} · {@customer.email}
      </p>

      <div :if={@appointments == []} class="card bg-base-100 border border-base-300">
        <div class="card-body text-center py-12">
          <p class="text-base-content/60">No appointments yet.</p>
        </div>
      </div>

      <ul :if={@appointments != []} class="space-y-3">
        <li :for={a <- @appointments} class="card bg-base-100 border border-base-300">
          <div class="card-body p-4">
            <div class="flex items-center justify-between gap-2 flex-wrap">
              <div>
                <div class="font-semibold">
                  {Map.get(@service_types, a.service_type_id, %{name: "Service"}).name}
                </div>
                <div class="text-sm text-base-content/70">
                  {Calendar.strftime(a.scheduled_at, "%A, %b %d, %Y · %I:%M %p")}
                </div>
              </div>
              <div class="text-right">
                <span class={"badge " <> status_badge(a.status)}>{a.status}</span>
                <div class="text-sm text-base-content/70 mt-1">
                  {fmt_cents(a.price_cents)}
                </div>
              </div>
            </div>
          </div>
        </li>
      </ul>
    </div>
    """
  end
end
