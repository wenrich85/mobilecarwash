defmodule MobileCarWashWeb.Admin.PersonasLive do
  @moduledoc """
  Marketing Phase 2B / Slice 3: admin CRUD for Persona records.

  One page lists every persona and offers an inline "new / edit"
  form. Deleting cascades to PersonaMembership rows.

  Next phase (2D) wraps this in an interactive builder with live
  AI image regeneration, but the underlying data model is what's
  pinned here.
  """
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Marketing.Persona

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Personas")
     |> assign(form_error: nil)
     |> assign(editing: nil)
     |> load_personas()}
  end

  @impl true
  def handle_event("start_create", _params, socket) do
    {:noreply, assign(socket, editing: :new, form_error: nil)}
  end

  def handle_event("start_edit", %{"id" => id}, socket) do
    persona = Enum.find(socket.assigns.personas, &(&1.id == id))
    {:noreply, assign(socket, editing: persona, form_error: nil)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing: nil, form_error: nil)}
  end

  def handle_event("save_persona", %{"persona" => attrs}, socket) do
    attrs = normalize(attrs)

    result =
      case socket.assigns.editing do
        %Persona{} = existing ->
          existing
          |> Ash.Changeset.for_update(:update, attrs)
          |> Ash.update(authorize?: false)

        _ ->
          Persona
          |> Ash.Changeset.for_create(:create, attrs)
          |> Ash.create(authorize?: false)
      end

    case result do
      {:ok, _p} ->
        {:noreply,
         socket
         |> assign(editing: nil, form_error: nil)
         |> load_personas()}

      {:error, changeset} ->
        {:noreply, assign(socket, form_error: friendly_error(changeset))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    persona = Enum.find(socket.assigns.personas, &(&1.id == id))

    if persona do
      Ash.destroy!(persona, authorize?: false)
    end

    {:noreply, load_personas(socket)}
  end

  # --- Private ---

  defp load_personas(socket) do
    personas =
      Persona
      |> Ash.read!(authorize?: false)
      |> Enum.sort_by(&{&1.sort_order, &1.name})

    assign(socket, personas: personas)
  end

  defp normalize(attrs) do
    %{
      slug: attrs["slug"],
      name: attrs["name"],
      description: attrs["description"] || "",
      image_prompt: attrs["image_prompt"],
      active: attrs["active"] in ["true", true, "on"],
      sort_order: parse_int(attrs["sort_order"]) || 100
    }
  end

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil
  defp parse_int(n) when is_integer(n), do: n

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} -> n
      _ -> nil
    end
  end

  defp friendly_error(%Ash.Error.Invalid{errors: errors}) do
    cond do
      Enum.any?(errors, &(&1.__struct__ == Ash.Error.Changes.InvalidAttribute && &1.field == :slug)) ->
        "Slug is already taken"

      true ->
        Enum.map_join(errors, ", ", fn err -> Exception.message(err) end)
    end
  end

  defp friendly_error(other), do: inspect(other)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto py-8 px-4">
      <div class="flex justify-between items-center mb-6">
        <div>
          <h1 class="text-3xl font-bold">Personas</h1>
          <p class="text-base-content/80">Named customer archetypes for targeted marketing.</p>
        </div>
        <button class="btn btn-primary btn-sm" phx-click="start_create">
          New Persona
        </button>
      </div>

      <div :if={@editing} class="card bg-base-200 mb-6">
        <div class="card-body">
          <h2 class="card-title">
            <%= if match?(%Persona{}, @editing) do %>
              Edit Persona
            <% else %>
              New Persona
            <% end %>
          </h2>

          <form id="persona-form" phx-submit="save_persona" class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <label class="form-control">
              <span class="label-text">Slug</span>
              <input
                type="text"
                name="persona[slug]"
                value={persona_val(@editing, :slug)}
                class="input input-bordered"
                required
              />
            </label>

            <label class="form-control">
              <span class="label-text">Name</span>
              <input
                type="text"
                name="persona[name]"
                value={persona_val(@editing, :name)}
                class="input input-bordered"
                required
              />
            </label>

            <label class="form-control md:col-span-2">
              <span class="label-text">Description</span>
              <textarea name="persona[description]" rows="3" class="textarea textarea-bordered">{persona_val(@editing, :description)}</textarea>
            </label>

            <label class="form-control md:col-span-2">
              <span class="label-text">Image prompt (for AI generation — Phase 2C)</span>
              <input
                type="text"
                name="persona[image_prompt]"
                value={persona_val(@editing, :image_prompt)}
                class="input input-bordered"
              />
            </label>

            <label class="form-control">
              <span class="label-text">Sort order</span>
              <input
                type="number"
                name="persona[sort_order]"
                value={persona_val(@editing, :sort_order) || 100}
                class="input input-bordered"
              />
            </label>

            <label class="form-control cursor-pointer justify-center">
              <span class="label-text">
                <input
                  type="checkbox"
                  name="persona[active]"
                  value="true"
                  checked={persona_val(@editing, :active) != false}
                  class="checkbox checkbox-primary"
                /> Active
              </span>
            </label>

            <div :if={@form_error} class="md:col-span-2 alert alert-error">
              <span>{@form_error}</span>
            </div>

            <div class="md:col-span-2 flex justify-end gap-2">
              <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel_edit">Cancel</button>
              <button type="submit" class="btn btn-primary btn-sm">Save</button>
            </div>
          </form>
        </div>
      </div>

      <div class="overflow-x-auto bg-base-100 rounded-lg border border-base-300">
        <table class="table">
          <thead>
            <tr>
              <th>Name</th>
              <th>Slug</th>
              <th>Description</th>
              <th>Active</th>
              <th class="text-right">Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={p <- @personas} class="hover">
              <td class="font-medium">{p.name}</td>
              <td><code>{p.slug}</code></td>
              <td class="max-w-sm truncate">{p.description}</td>
              <td>
                <span class={"badge " <> if(p.active, do: "badge-success", else: "badge-ghost")}>
                  {if p.active, do: "Yes", else: "No"}
                </span>
              </td>
              <td class="text-right">
                <button class="btn btn-ghost btn-xs" phx-click="start_edit" phx-value-id={p.id}>
                  Edit
                </button>
                <button
                  id={"delete-#{p.id}"}
                  class="btn btn-ghost btn-xs text-error"
                  phx-click="delete"
                  phx-value-id={p.id}
                  data-confirm="Delete this persona? Customer tags will be removed."
                >
                  Delete
                </button>
              </td>
            </tr>
            <tr :if={@personas == []}>
              <td colspan="5" class="text-center text-base-content/60 py-8">
                No personas yet — create one to start segmenting customers.
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp persona_val(%Persona{} = p, field), do: Map.get(p, field)
  defp persona_val(_, _), do: nil
end
