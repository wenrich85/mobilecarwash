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

  alias MobileCarWash.Marketing.{AcquisitionChannel, Persona, PersonaImageWorker, Personas}

  @impl true
  def mount(_params, _session, socket) do
    channels =
      AcquisitionChannel
      |> Ash.Query.for_read(:active)
      |> Ash.read!(authorize?: false)

    socket =
      socket
      |> assign(page_title: "Personas")
      |> assign(form_error: nil)
      |> assign(editing: nil)
      |> assign(draft_criteria: %{})
      |> assign(match_count: 0)
      |> assign(match_sample: [])
      |> assign(channels: channels)
      |> load_personas()

    # Subscribe to every listed persona's image-ready topic so we can
    # swap placeholders in place when the Oban worker finishes.
    if connected?(socket) do
      Enum.each(socket.assigns.personas, fn p ->
        Phoenix.PubSub.subscribe(MobileCarWash.PubSub, "persona:#{p.id}")
      end)
    end

    {:ok, socket}
  end

  @impl true
  def handle_info({:persona_image_ready, persona_id, url}, socket) do
    personas =
      Enum.map(socket.assigns.personas, fn p ->
        if p.id == persona_id, do: %{p | image_url: url}, else: p
      end)

    {:noreply, assign(socket, personas: personas)}
  end

  @impl true
  def handle_event("start_create", _params, socket) do
    {:noreply,
     socket
     |> assign(editing: :new, form_error: nil, draft_criteria: %{})
     |> recompute_preview()}
  end

  def handle_event("start_edit", %{"id" => id}, socket) do
    persona = Enum.find(socket.assigns.personas, &(&1.id == id))

    {:noreply,
     socket
     |> assign(editing: persona, form_error: nil, draft_criteria: persona.criteria || %{})
     |> recompute_preview()}
  end

  def handle_event("validate_persona", %{"persona" => params}, socket) do
    criteria = extract_criteria(params)

    {:noreply,
     socket
     |> assign(draft_criteria: criteria)
     |> recompute_preview()}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing: nil, form_error: nil)}
  end

  def handle_event("save_persona", %{"persona" => attrs}, socket) do
    attrs =
      attrs
      |> normalize()
      |> Map.put(:criteria, extract_criteria(attrs))

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

  def handle_event("regen_image", %{"id" => id}, socket) do
    # Enqueue + subscribe — the worker broadcasts on this topic.
    Phoenix.PubSub.subscribe(MobileCarWash.PubSub, "persona:#{id}")

    %{"persona_id" => id}
    |> PersonaImageWorker.new()
    |> Oban.insert!()

    {:noreply, socket}
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

  # Map the form's prefixed criteria_* fields into the canonical
  # criteria map the rule engine understands. Empty strings / nil /
  # "any" are treated as "unset" and dropped.
  defp extract_criteria(params) do
    %{}
    |> maybe_put_str("acquired_channel_slug", params["criteria_channel_slug"])
    |> maybe_put_str("device_type", params["criteria_device_type"])
    |> maybe_put_revenue_bounds(params["criteria_revenue_min"], params["criteria_revenue_max"])
    |> maybe_put_bool("has_subscription", params["criteria_has_subscription"])
  end

  defp maybe_put_str(map, _key, nil), do: map
  defp maybe_put_str(map, _key, ""), do: map
  defp maybe_put_str(map, _key, "any"), do: map
  defp maybe_put_str(map, key, value) when is_binary(value), do: Map.put(map, key, value)

  defp maybe_put_revenue_bounds(map, min_str, max_str) do
    min_int = parse_int(min_str)
    max_int = parse_int(max_str)

    bounds =
      %{}
      |> put_if(min_int, fn acc -> Map.put(acc, "gte", min_int * 100) end)
      |> put_if(max_int, fn acc -> Map.put(acc, "lte", max_int * 100) end)

    if bounds == %{}, do: map, else: Map.put(map, "lifetime_revenue_cents", bounds)
  end

  defp put_if(acc, nil, _fun), do: acc
  defp put_if(acc, _val, fun), do: fun.(acc)

  defp maybe_put_bool(map, _key, nil), do: map
  defp maybe_put_bool(map, _key, ""), do: map
  defp maybe_put_bool(map, _key, "any"), do: map
  defp maybe_put_bool(map, key, "true"), do: Map.put(map, key, true)
  defp maybe_put_bool(map, key, "false"), do: Map.put(map, key, false)
  defp maybe_put_bool(map, _key, _), do: map

  defp recompute_preview(socket) do
    criteria = socket.assigns.draft_criteria

    socket
    |> assign(match_count: Personas.count_matching(criteria))
    |> assign(match_sample: Personas.sample_matching(criteria, 5))
  end

  defp friendly_error(%Ash.Error.Invalid{errors: errors}) do
    cond do
      Enum.any?(
        errors,
        &(&1.__struct__ == Ash.Error.Changes.InvalidAttribute && &1.field == :slug)
      ) ->
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

      <div :if={@editing} class="grid grid-cols-1 lg:grid-cols-3 gap-6 mb-6">
        <div class="card bg-base-200 lg:col-span-2">
          <div class="card-body">
            <h2 class="card-title">
              <%= if match?(%Persona{}, @editing) do %>
                Edit Persona
              <% else %>
                New Persona
              <% end %>
            </h2>

            <form
              id="persona-form"
              phx-submit="save_persona"
              phx-change="validate_persona"
              phx-debounce="300"
              class="grid grid-cols-1 md:grid-cols-2 gap-4"
            >
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
              
    <!-- Criteria — any empty / "Any" field is ignored at save time -->
              <div class="md:col-span-2 divider text-xs text-base-content/60">
                Criteria (who matches)
              </div>

              <label class="form-control">
                <span class="label-text">Acquisition channel</span>
                <select name="persona[criteria_channel_slug]" class="select select-bordered">
                  <option value="">Any</option>
                  <option
                    :for={chan <- @channels}
                    value={chan.slug}
                    selected={@draft_criteria["acquired_channel_slug"] == chan.slug}
                  >
                    {chan.display_name}
                  </option>
                </select>
              </label>

              <label class="form-control">
                <span class="label-text">Device type (latest event)</span>
                <select name="persona[criteria_device_type]" class="select select-bordered">
                  <option value="">Any</option>
                  <option
                    :for={dt <- ~w(mobile tablet desktop bot)}
                    value={dt}
                    selected={@draft_criteria["device_type"] == dt}
                  >
                    {dt}
                  </option>
                </select>
              </label>

              <label class="form-control">
                <span class="label-text">Lifetime revenue min ($)</span>
                <input
                  type="number"
                  min="0"
                  name="persona[criteria_revenue_min]"
                  value={bound_display(@draft_criteria, "gte")}
                  class="input input-bordered"
                />
              </label>

              <label class="form-control">
                <span class="label-text">Lifetime revenue max ($)</span>
                <input
                  type="number"
                  min="0"
                  name="persona[criteria_revenue_max]"
                  value={bound_display(@draft_criteria, "lte")}
                  class="input input-bordered"
                />
              </label>

              <label class="form-control md:col-span-2">
                <span class="label-text">Active subscription</span>
                <select name="persona[criteria_has_subscription]" class="select select-bordered">
                  <option value="">Any</option>
                  <option value="true" selected={@draft_criteria["has_subscription"] == true}>
                    Only subscribers
                  </option>
                  <option value="false" selected={@draft_criteria["has_subscription"] == false}>
                    Only non-subscribers
                  </option>
                </select>
              </label>

              <div :if={@form_error} class="md:col-span-2 alert alert-error">
                <span>{@form_error}</span>
              </div>

              <div class="md:col-span-2 flex justify-end gap-2">
                <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel_edit">
                  Cancel
                </button>
                <button type="submit" class="btn btn-primary btn-sm">Save</button>
              </div>
            </form>
          </div>
        </div>
        
    <!-- Live preview (right column of the editor grid) -->
        <aside class="card bg-base-100 border border-base-300 lg:col-span-1">
          <div class="card-body">
            <h3 class="card-title text-base">Live preview</h3>
            <div class="stat px-0">
              <div class="stat-title">Customers matching</div>
              <div class="stat-value text-primary">{@match_count}</div>
              <div class="stat-desc">Updates as you tweak criteria.</div>
            </div>

            <div :if={@match_sample != []} class="mt-2">
              <div class="text-sm font-medium mb-2">Sample</div>
              <ul class="text-sm space-y-1">
                <li :for={c <- @match_sample} class="truncate">
                  <span class="font-medium">{c.name}</span>
                  <span class="text-base-content/60">· {c.email}</span>
                </li>
              </ul>
            </div>

            <div :if={match?(%Persona{}, @editing)} class="mt-4">
              <div class="text-sm font-medium mb-2">AI image</div>
              <img
                :if={@editing.image_url}
                src={@editing.image_url}
                alt={"#{@editing.name} image"}
                class="rounded-lg w-full aspect-square object-cover border border-base-300"
              />
              <div
                :if={is_nil(@editing.image_url)}
                class="rounded-lg aspect-square border border-dashed border-base-300 flex items-center justify-center text-6xl"
              >
                🎭
              </div>
              <button
                class="btn btn-ghost btn-sm mt-2 w-full"
                phx-click="regen_image"
                phx-value-id={@editing.id}
              >
                {if @editing.image_url, do: "Regenerate image", else: "Generate image"}
              </button>
            </div>
          </div>
        </aside>
      </div>

      <div class="overflow-x-auto bg-base-100 rounded-lg border border-base-300">
        <table class="table">
          <thead>
            <tr>
              <th>Image</th>
              <th>Name</th>
              <th>Slug</th>
              <th>Description</th>
              <th>Active</th>
              <th class="text-right">Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={p <- @personas} class="hover">
              <td class="w-20">
                <img
                  :if={p.image_url}
                  src={p.image_url}
                  alt={"#{p.name} image"}
                  class="w-16 h-16 object-cover rounded-lg border border-base-300"
                />
                <div
                  :if={is_nil(p.image_url)}
                  class="w-16 h-16 rounded-lg border border-dashed border-base-300 flex items-center justify-center text-2xl"
                >
                  🎭
                </div>
              </td>
              <td class="font-medium">{p.name}</td>
              <td><code>{p.slug}</code></td>
              <td class="max-w-sm truncate">{p.description}</td>
              <td>
                <span class={"badge " <> if(p.active, do: "badge-success", else: "badge-ghost")}>
                  {if p.active, do: "Yes", else: "No"}
                </span>
              </td>
              <td class="text-right">
                <button
                  id={"regen-#{p.id}"}
                  class="btn btn-ghost btn-xs"
                  phx-click="regen_image"
                  phx-value-id={p.id}
                  title="Generate a new AI image from the description"
                >
                  Regenerate
                </button>
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
              <td colspan="6" class="text-center text-base-content/60 py-8">
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

  # The criteria stores cents; the form input is dollars.
  defp bound_display(criteria, key) do
    case criteria do
      %{"lifetime_revenue_cents" => %{^key => cents}} when is_integer(cents) ->
        div(cents, 100)

      _ ->
        ""
    end
  end
end
