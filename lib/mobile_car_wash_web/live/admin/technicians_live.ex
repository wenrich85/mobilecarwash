defmodule MobileCarWashWeb.Admin.TechniciansLive do
  @moduledoc """
  Admin index of all technicians. Each row links to the detailed profile view.
  Also supports creating technician account invites.
  """
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Operations.{TechInvite, TechInvites, Technician, Van}
  alias MobileCarWash.Zones

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Technicians",
       technicians: load_technicians(),
       invite_by_technician: load_invite_by_technician(),
       vans: load_vans(),
       editing: nil,
       latest_invite_url: nil,
       invite_error: nil
     )}
  end

  @impl true
  def handle_event("invite_technician", %{"invite" => params}, socket) do
    attrs = %{
      name: params["name"],
      email: params["email"],
      phone: blank_to_nil(params["phone"]),
      home_zip: blank_to_nil(params["home_zip"]),
      preferred_zone: parse_zone(params["preferred_zone"]),
      assigned_zone: parse_zone(params["assigned_zone"]) || parse_zone(params["preferred_zone"]),
      availability_weekdays: truthy?(params["availability_weekdays"]),
      availability_weekends: truthy?(params["availability_weekends"]),
      availability_mornings: truthy?(params["availability_mornings"]),
      availability_afternoons: truthy?(params["availability_afternoons"]),
      availability_evenings: truthy?(params["availability_evenings"]),
      experience_level: parse_experience(params["experience_level"]),
      has_valid_driver_license: truthy?(params["has_valid_driver_license"]),
      has_reliable_transportation: truthy?(params["has_reliable_transportation"]),
      can_lift_supplies: truthy?(params["can_lift_supplies"]),
      desired_hours_per_week: parse_int(params["desired_hours_per_week"]),
      emergency_contact_name: blank_to_nil(params["emergency_contact_name"]),
      emergency_contact_phone: blank_to_nil(params["emergency_contact_phone"]),
      experience_notes: blank_to_nil(params["experience_notes"]),
      schedule_notes: blank_to_nil(params["schedule_notes"]),
      accepted_pay_rate_cents: parse_int(params["accepted_pay_rate_cents"]) || 2500,
      active: false
    }

    case TechInvites.create_admin_invite(attrs) do
      {:ok, result} ->
        {:noreply,
         socket
         |> assign(technicians: load_technicians())
         |> assign(invite_by_technician: load_invite_by_technician())
         |> assign(latest_invite_url: result.invite_url, invite_error: nil)
         |> put_flash(:info, "Technician invite created.")}

      {:error, :email_taken} ->
        {:noreply,
         assign(socket,
           invite_error: "Email already belongs to an account.",
           latest_invite_url: nil
         )}

      {:error, _} ->
        {:noreply,
         assign(socket,
           invite_error: "Could not create technician invite.",
           latest_invite_url: nil
         )}
    end
  end

  def handle_event("toggle_active", %{"id" => id}, socket) do
    case Ash.get(Technician, id) do
      {:ok, tech} ->
        tech
        |> Ash.Changeset.for_update(:update, %{active: !tech.active})
        |> Ash.update!()

        {:noreply,
         socket
         |> assign(technicians: load_technicians())
         |> assign(invite_by_technician: load_invite_by_technician())}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto py-8 px-4">
      <div class="flex justify-between items-start mb-6">
        <div>
          <h1 class="text-3xl font-bold mb-2">Technicians</h1>
          <p class="text-base-content/80">
            Manage technician accounts, setup links, zones, pay rates, and active access.
          </p>
        </div>
      </div>
      
    <!-- Invite technician -->
      <div class="card bg-base-100 shadow mb-6">
        <div class="card-body p-4">
          <div class="mb-3">
            <h3 class="font-bold">Invite Technician</h3>
            <p class="text-sm text-base-content/70">
              Create the account, accepted profile, inactive technician record, and setup link.
            </p>
          </div>

          <div :if={@invite_error} class="alert alert-error mb-4">
            {@invite_error}
          </div>

          <div :if={@latest_invite_url} class="alert alert-success mb-4">
            <div class="w-full">
              <p class="font-semibold">Technician invite created</p>
              <input
                id="latest-tech-invite-url"
                class="input input-bordered input-sm mt-2 w-full"
                readonly
                value={@latest_invite_url}
              />
            </div>
          </div>

          <form
            id="admin-tech-invite-form"
            phx-submit="invite_technician"
            class="grid grid-cols-1 md:grid-cols-4 gap-3"
          >
            <div class="form-control">
              <label class="label label-text text-xs">Email</label>
              <input type="email" name="invite[email]" class="input input-bordered input-sm" required />
            </div>
            <div class="form-control">
              <label class="label label-text text-xs">Name</label>
              <input type="text" name="invite[name]" class="input input-bordered input-sm" required />
            </div>
            <div class="form-control">
              <label class="label label-text text-xs">Phone</label>
              <input
                type="text"
                name="invite[phone]"
                class="input input-bordered input-sm"
                placeholder="512-555-0000"
              />
            </div>
            <div class="form-control">
              <label class="label label-text text-xs">Home ZIP</label>
              <input type="text" name="invite[home_zip]" class="input input-bordered input-sm" />
            </div>
            <div class="form-control">
              <label class="label label-text text-xs">Preferred zone</label>
              <select name="invite[preferred_zone]" class="select select-bordered select-sm">
                <option value="">Any (floater)</option>
                <option value="nw">NW</option>
                <option value="ne">NE</option>
                <option value="sw">SW</option>
                <option value="se">SE</option>
              </select>
            </div>
            <div class="form-control">
              <label class="label label-text text-xs">Assigned zone</label>
              <select name="invite[assigned_zone]" class="select select-bordered select-sm">
                <option value="">Match preferred</option>
                <option value="nw">NW</option>
                <option value="ne">NE</option>
                <option value="sw">SW</option>
                <option value="se">SE</option>
              </select>
            </div>
            <div class="form-control">
              <label class="label label-text text-xs">Pay rate (cents/wash)</label>
              <input
                type="number"
                name="invite[accepted_pay_rate_cents]"
                class="input input-bordered input-sm"
                value="2500"
                min="0"
              />
            </div>
            <div class="form-control">
              <label class="label label-text text-xs">Desired hours/week</label>
              <input
                type="number"
                name="invite[desired_hours_per_week]"
                class="input input-bordered input-sm"
                min="0"
              />
            </div>
            <div class="form-control">
              <label class="label label-text text-xs">Experience</label>
              <select name="invite[experience_level]" class="select select-bordered select-sm">
                <option value="none">None</option>
                <option value="some" selected>Some</option>
                <option value="professional">Professional</option>
              </select>
            </div>

            <fieldset class="md:col-span-2 rounded-lg border border-base-300 p-3">
              <legend class="px-1 text-xs font-semibold uppercase text-base-content/60">
                Availability
              </legend>
              <div class="grid grid-cols-2 sm:grid-cols-5 gap-2 text-sm">
                <label class="label cursor-pointer justify-start gap-2">
                  <input
                    type="checkbox"
                    name="invite[availability_weekdays]"
                    value="true"
                    class="checkbox checkbox-sm"
                  />
                  <span>Weekdays</span>
                </label>
                <label class="label cursor-pointer justify-start gap-2">
                  <input
                    type="checkbox"
                    name="invite[availability_weekends]"
                    value="true"
                    class="checkbox checkbox-sm"
                  />
                  <span>Weekends</span>
                </label>
                <label class="label cursor-pointer justify-start gap-2">
                  <input
                    type="checkbox"
                    name="invite[availability_mornings]"
                    value="true"
                    class="checkbox checkbox-sm"
                  />
                  <span>Mornings</span>
                </label>
                <label class="label cursor-pointer justify-start gap-2">
                  <input
                    type="checkbox"
                    name="invite[availability_afternoons]"
                    value="true"
                    class="checkbox checkbox-sm"
                  />
                  <span>Afternoons</span>
                </label>
                <label class="label cursor-pointer justify-start gap-2">
                  <input
                    type="checkbox"
                    name="invite[availability_evenings]"
                    value="true"
                    class="checkbox checkbox-sm"
                  />
                  <span>Evenings</span>
                </label>
              </div>
            </fieldset>

            <fieldset class="md:col-span-2 rounded-lg border border-base-300 p-3">
              <legend class="px-1 text-xs font-semibold uppercase text-base-content/60">
                Requirements
              </legend>
              <div class="grid grid-cols-1 sm:grid-cols-3 gap-2 text-sm">
                <label class="label cursor-pointer justify-start gap-2">
                  <input
                    type="checkbox"
                    name="invite[has_valid_driver_license]"
                    value="true"
                    class="checkbox checkbox-sm"
                  />
                  <span>Driver license</span>
                </label>
                <label class="label cursor-pointer justify-start gap-2">
                  <input
                    type="checkbox"
                    name="invite[has_reliable_transportation]"
                    value="true"
                    class="checkbox checkbox-sm"
                  />
                  <span>Transportation</span>
                </label>
                <label class="label cursor-pointer justify-start gap-2">
                  <input
                    type="checkbox"
                    name="invite[can_lift_supplies]"
                    value="true"
                    class="checkbox checkbox-sm"
                  />
                  <span>Can lift supplies</span>
                </label>
              </div>
            </fieldset>

            <div class="form-control">
              <label class="label label-text text-xs">Emergency contact</label>
              <input
                type="text"
                name="invite[emergency_contact_name]"
                class="input input-bordered input-sm"
              />
            </div>
            <div class="form-control">
              <label class="label label-text text-xs">Emergency phone</label>
              <input
                type="text"
                name="invite[emergency_contact_phone]"
                class="input input-bordered input-sm"
              />
            </div>
            <div class="form-control md:col-span-2">
              <label class="label label-text text-xs">Notes</label>
              <input
                type="text"
                name="invite[experience_notes]"
                class="input input-bordered input-sm"
              />
            </div>

            <div class="md:col-span-4 flex justify-end">
              <button type="submit" class="btn btn-primary btn-sm">Create invite</button>
            </div>
          </form>
        </div>
      </div>
      
    <!-- List -->
      <div :if={@technicians == []} class="text-center py-12 text-base-content/70">
        No technicians yet. Invite one above.
      </div>

      <div class="space-y-3">
        <div
          :for={tech <- @technicians}
          class={["card bg-base-100 shadow-sm", !tech.active && "opacity-50"]}
        >
          <div class="card-body p-4 flex-row items-center justify-between">
            <div>
              <div class="flex items-center gap-2 flex-wrap">
                <h4 class="font-bold">{tech.name}</h4>
                <span :if={tech.zone} class={["badge badge-sm", Zones.badge_class(tech.zone)]}>
                  {Zones.short_label(tech.zone)}
                </span>
                <span :if={!tech.active} class="badge badge-sm badge-error">Inactive</span>
                {invite_badge(@invite_by_technician, tech)}
              </div>
              <p class="text-sm text-base-content/80 mt-1">
                {account_email(tech)} · {tech.phone || "No phone"} · ${div(
                  tech.pay_rate_cents || 0,
                  100
                )}/wash <span :if={tech.van_id}>· van assigned</span>
              </p>
            </div>
            <div class="flex gap-2">
              <.link
                navigate={~p"/admin/technicians/#{tech.id}"}
                class="btn btn-primary btn-sm"
              >
                Open Profile
              </.link>
              <button
                class={["btn btn-xs", if(tech.active, do: "btn-warning", else: "btn-success")]}
                phx-click="toggle_active"
                phx-value-id={tech.id}
              >
                {if tech.active, do: "Deactivate", else: "Activate"}
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # --- helpers ---

  defp load_technicians do
    Technician
    |> Ash.Query.sort([{:active, :desc}, :name])
    |> Ash.Query.load(:user_account)
    |> Ash.read!(authorize?: false)
  end

  defp load_invite_by_technician do
    TechInvite
    |> Ash.Query.new()
    |> Ash.read!(authorize?: false)
    |> Map.new(&{&1.technician_id, &1})
  end

  defp load_vans do
    Van |> Ash.Query.filter(active == true) |> Ash.read!()
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(s), do: s

  defp parse_zone(""), do: nil
  defp parse_zone(nil), do: nil

  defp parse_zone(z) when is_binary(z) do
    case z do
      "nw" -> :nw
      "ne" -> :ne
      "sw" -> :sw
      "se" -> :se
      _ -> nil
    end
  end

  defp parse_experience("professional"), do: :professional
  defp parse_experience("some"), do: :some
  defp parse_experience("none"), do: :none
  defp parse_experience(_), do: :none

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil
  defp parse_int(n) when is_integer(n), do: n

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} -> n
      _ -> nil
    end
  end

  defp truthy?(value) when value in [true, "true", "1", 1, "on"], do: true
  defp truthy?(_), do: false

  defp account_email(%{user_account: %{email: email}}), do: to_string(email)
  defp account_email(_tech), do: "No account"

  defp invite_badge(invite_by_technician, tech) do
    case Map.get(invite_by_technician, tech.id) do
      %{status: :pending} ->
        Phoenix.HTML.raw(~s(<span class="badge badge-sm badge-warning">Pending invite</span>))

      %{status: :accepted} ->
        Phoenix.HTML.raw(~s(<span class="badge badge-sm badge-success">Invite accepted</span>))

      %{status: :expired} ->
        Phoenix.HTML.raw(~s(<span class="badge badge-sm badge-error">Invite expired</span>))

      %{status: :revoked} ->
        Phoenix.HTML.raw(~s(<span class="badge badge-sm">Invite revoked</span>))

      _ ->
        nil
    end
  end
end
