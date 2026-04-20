defmodule MobileCarWashWeb.Admin.TagsLive do
  @moduledoc """
  Admin CRUD for customer tags. Lists every tag (active or archived),
  lets admins create new ones, archive (active=false) or delete
  non-protected ones. Seeded tags (VIP, At Risk, Do Not Service, etc.)
  are flagged `protected` and can be archived but not deleted.
  """
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Marketing.Tag

  require Ash.Query

  @colors ~w(neutral primary success warning error info)a

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Tags")
     |> assign(colors: @colors)
     |> assign(create_error: nil)
     |> load_tags()}
  end

  @impl true
  def handle_event("create_tag", %{"tag" => params}, socket) do
    attrs = %{
      slug: params |> Map.get("slug", "") |> String.trim() |> String.downcase(),
      name: params |> Map.get("name", "") |> String.trim(),
      description: params |> Map.get("description", ""),
      color: parse_color(params["color"]),
      affects_booking: params |> Map.get("affects_booking") |> truthy?()
    }

    case Tag
         |> Ash.Changeset.for_create(:create, attrs)
         |> Ash.create(authorize?: false) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(create_error: nil)
         |> put_flash(:info, "Tag created")
         |> load_tags()}

      {:error, %Ash.Error.Invalid{} = e} ->
        {:noreply, assign(socket, create_error: Exception.message(e))}

      {:error, _} ->
        {:noreply, assign(socket, create_error: "Could not create tag")}
    end
  end

  def handle_event("delete_tag", %{"id" => id}, socket) do
    case Ash.get(Tag, id, authorize?: false) do
      {:ok, %{protected: true}} ->
        {:noreply, put_flash(socket, :error, "Protected tags cannot be deleted")}

      {:ok, tag} ->
        Ash.destroy!(tag, authorize?: false)
        {:noreply, socket |> put_flash(:info, "Tag deleted") |> load_tags()}

      _ ->
        {:noreply, put_flash(socket, :error, "Tag not found")}
    end
  end

  def handle_event("toggle_active", %{"id" => id}, socket) do
    with {:ok, tag} <- Ash.get(Tag, id, authorize?: false),
         {:ok, _} <-
           tag
           |> Ash.Changeset.for_update(:update, %{active: !tag.active})
           |> Ash.update(authorize?: false) do
      {:noreply, load_tags(socket)}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not toggle")}
    end
  end

  # --- Private ---

  defp load_tags(socket) do
    tags =
      Tag
      |> Ash.read!(authorize?: false)
      |> Enum.sort_by(&{!&1.active, &1.name})

    assign(socket, tags: tags)
  end

  defp parse_color(value) when is_binary(value) do
    case Enum.find(@colors, &(Atom.to_string(&1) == value)) do
      nil -> :neutral
      c -> c
    end
  end

  defp parse_color(_), do: :neutral

  defp truthy?(v) when v in [true, "true", "on", "1"], do: true
  defp truthy?(_), do: false

  defp badge_class_for(%{color: :primary}), do: "badge-primary"
  defp badge_class_for(%{color: :success}), do: "badge-success"
  defp badge_class_for(%{color: :warning}), do: "badge-warning"
  defp badge_class_for(%{color: :error}), do: "badge-error"
  defp badge_class_for(%{color: :info}), do: "badge-info"
  defp badge_class_for(_), do: "badge-neutral"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto py-8 px-4">
      <div class="mb-6">
        <h1 class="text-3xl font-bold">Tags</h1>
        <p class="text-base-content/80">
          Manually-applied customer flags. Personas are rule-based archetypes; tags are decisions.
        </p>
      </div>

      <div class="card bg-base-100 border border-base-300 mb-6">
        <div class="card-body">
          <h2 class="card-title">New tag</h2>

          <p :if={@create_error} class="text-sm text-error">{@create_error}</p>

          <form
            id="new-tag"
            phx-submit="create_tag"
            class="grid grid-cols-1 md:grid-cols-6 gap-2"
          >
            <input
              name="tag[slug]"
              placeholder="slug_snake_case"
              class="input input-bordered input-sm md:col-span-2"
            />
            <input
              name="tag[name]"
              placeholder="Display name"
              class="input input-bordered input-sm md:col-span-2"
            />
            <select name="tag[color]" class="select select-bordered select-sm">
              <option :for={c <- @colors} value={c}>{c}</option>
            </select>
            <button type="submit" class="btn btn-primary btn-sm">Create</button>

            <input
              name="tag[description]"
              placeholder="Optional description"
              class="input input-bordered input-sm md:col-span-5"
            />
            <label class="label cursor-pointer gap-2">
              <input
                type="checkbox"
                name="tag[affects_booking]"
                value="true"
                class="checkbox checkbox-sm"
              />
              <span class="label-text text-xs">Booking flag</span>
            </label>
          </form>
        </div>
      </div>

      <div class="overflow-x-auto bg-base-100 rounded-lg border border-base-300">
        <table class="table">
          <thead>
            <tr>
              <th>Tag</th>
              <th>Slug</th>
              <th>Description</th>
              <th class="text-center">Booking flag</th>
              <th class="text-center">Active</th>
              <th class="text-right">Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={t <- @tags} class="hover">
              <td>
                <span class={"badge " <> badge_class_for(t)}>{t.name}</span>
                <span :if={t.protected} class="badge badge-xs badge-ghost ml-1">protected</span>
              </td>
              <td class="text-sm"><code>{t.slug}</code></td>
              <td class="text-sm text-base-content/70 max-w-md">{t.description}</td>
              <td class="text-center">
                <span :if={t.affects_booking} class="badge badge-xs badge-error">yes</span>
              </td>
              <td class="text-center">
                <button
                  id={"toggle-active-#{t.id}"}
                  phx-click="toggle_active"
                  phx-value-id={t.id}
                  class={"badge badge-sm " <> if(t.active, do: "badge-success", else: "badge-ghost")}
                >
                  {if t.active, do: "Active", else: "Archived"}
                </button>
              </td>
              <td class="text-right">
                <button
                  :if={not t.protected}
                  id={"delete-tag-#{t.id}"}
                  phx-click="delete_tag"
                  phx-value-id={t.id}
                  data-confirm="Delete this tag? Customer memberships will be removed."
                  class="btn btn-ghost btn-xs text-error"
                >
                  Delete
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end
end
