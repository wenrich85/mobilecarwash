defmodule MobileCarWashWeb.Admin.CampaignsLive do
  @moduledoc """
  Marketing Phase 3A / Slice 4: admin-side social-media composer.

  One page:
    * Form to draft a Post (title, body, image_url, channel checkboxes,
      persona targeting)
    * List of recent posts with status badges + per-row "Publish" action
    * Publish routes through Marketing.Publisher → SocialAdapter (today:
      LogAdapter; tomorrow: real Meta/X/Buffer adapters)
  """
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Marketing.{Persona, Post, Publisher}

  @default_channels ~w(meta x tiktok linkedin buffer log)

  @impl true
  def mount(_params, _session, socket) do
    personas =
      Persona
      |> Ash.Query.for_read(:active)
      |> Ash.read!(authorize?: false)

    {:ok,
     socket
     |> assign(page_title: "Campaigns")
     |> assign(personas: personas)
     |> assign(available_channels: @default_channels)
     |> assign(form_error: nil)
     |> load_posts()}
  end

  @impl true
  def handle_event("save_post", %{"post" => attrs}, socket) do
    channels = List.wrap(attrs["channels"])
    persona_ids = List.wrap(attrs["persona_ids"])

    result =
      Post
      |> Ash.Changeset.for_create(:create, %{
        title: attrs["title"] || "",
        body: attrs["body"] || "",
        image_url: blank_to_nil(attrs["image_url"]),
        channels: channels,
        persona_ids: persona_ids
      })
      |> Ash.create(authorize?: false)

    case result do
      {:ok, _post} ->
        {:noreply, socket |> assign(form_error: nil) |> load_posts()}

      {:error, changeset} ->
        {:noreply, assign(socket, form_error: friendly_error(changeset))}
    end
  end

  def handle_event("publish_post", %{"id" => id}, socket) do
    case Publisher.publish(id) do
      {:ok, _post} ->
        {:noreply, load_posts(socket)}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Publish failed: #{inspect(reason)}")
         |> load_posts()}
    end
  end

  def handle_event("delete_post", %{"id" => id}, socket) do
    with {:ok, post} <- Ash.get(Post, id, authorize?: false) do
      Ash.destroy!(post, authorize?: false)
    end

    {:noreply, load_posts(socket)}
  end

  defp load_posts(socket) do
    posts =
      Post
      |> Ash.Query.for_read(:recent)
      |> Ash.read!(authorize?: false)

    assign(socket, posts: posts)
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(s) when is_binary(s), do: s

  defp friendly_error(%Ash.Error.Invalid{errors: errors}) do
    errors
    |> Enum.map(fn
      %{message: msg} when is_binary(msg) -> msg
      err -> Exception.message(err)
    end)
    |> Enum.join(", ")
    |> case do
      "" -> "Unable to save — check your inputs"
      msg -> msg
    end
  end

  defp friendly_error(other), do: inspect(other)

  defp status_class(:draft), do: "badge-ghost"
  defp status_class(:scheduled), do: "badge-info"
  defp status_class(:published), do: "badge-success"
  defp status_class(:failed), do: "badge-error"
  defp status_class(_), do: "badge-ghost"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto py-8 px-4">
      <div class="mb-6">
        <h1 class="text-3xl font-bold">Campaigns</h1>
        <p class="text-base-content/80">
          Draft a post once, fan it out to every channel. Phase 3A ships the
          composer + audit log — real Meta/X/Buffer adapters drop in later.
        </p>
      </div>

      <div class="card bg-base-200 mb-6">
        <div class="card-body">
          <h2 class="card-title">New post</h2>

          <form id="post-form" phx-submit="save_post" class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <label class="form-control md:col-span-2">
              <span class="label-text">Title</span>
              <input type="text" name="post[title]" class="input input-bordered" required />
            </label>

            <label class="form-control md:col-span-2">
              <span class="label-text">Body</span>
              <textarea name="post[body]" rows="3" class="textarea textarea-bordered"></textarea>
            </label>

            <label class="form-control md:col-span-2">
              <span class="label-text">Image URL (optional)</span>
              <input type="url" name="post[image_url]" class="input input-bordered" placeholder="https://…" />
            </label>

            <fieldset class="form-control md:col-span-2">
              <legend class="label-text font-medium">Channels</legend>
              <div class="flex flex-wrap gap-3 mt-1">
                <label
                  :for={ch <- @available_channels}
                  class="cursor-pointer flex items-center gap-2 bg-base-100 px-3 py-1 rounded-lg border border-base-300"
                >
                  <input type="checkbox" name="post[channels][]" value={ch} class="checkbox checkbox-sm" />
                  <span class="text-sm">{ch}</span>
                </label>
              </div>
            </fieldset>

            <fieldset :if={@personas != []} class="form-control md:col-span-2">
              <legend class="label-text font-medium">Target personas (optional)</legend>
              <div class="flex flex-wrap gap-2 mt-1">
                <label
                  :for={p <- @personas}
                  class="cursor-pointer flex items-center gap-2 bg-base-100 px-3 py-1 rounded-lg border border-base-300"
                >
                  <input type="checkbox" name="post[persona_ids][]" value={p.id} class="checkbox checkbox-sm" />
                  <span class="text-sm">{p.name}</span>
                </label>
              </div>
            </fieldset>

            <div :if={@form_error} class="md:col-span-2 alert alert-error">
              <span>{@form_error}</span>
            </div>

            <div class="md:col-span-2 flex justify-end">
              <button type="submit" class="btn btn-primary btn-sm">Save draft</button>
            </div>
          </form>
        </div>
      </div>

      <div class="card bg-base-100 border border-base-300">
        <div class="card-body">
          <h2 class="card-title">Recent posts</h2>

          <div :if={@posts == []} class="text-center py-6 text-base-content/60">
            No posts yet. Draft one above.
          </div>

          <div :for={p <- @posts} class="border-t border-base-300 py-3 first:border-t-0">
            <div class="flex justify-between items-start gap-4 flex-wrap">
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2 mb-1">
                  <span class="font-semibold truncate">{p.title}</span>
                  <span class={"badge badge-sm " <> status_class(p.status)}>{p.status}</span>
                </div>
                <p :if={p.body != ""} class="text-sm text-base-content/70 truncate">{p.body}</p>
                <p class="text-xs text-base-content/60 mt-1">
                  Channels: {Enum.join(p.channels, ", ")}
                  <span :if={p.external_ids != %{}}>
                    · IDs: {Enum.map_join(p.external_ids, ", ", fn {k, v} -> "#{k}=#{v}" end)}
                  </span>
                </p>
                <p :if={p.error_message} class="text-xs text-error mt-1">{p.error_message}</p>
              </div>

              <div class="flex gap-2 shrink-0">
                <button
                  :if={p.status in [:draft, :scheduled, :failed]}
                  id={"publish-#{p.id}"}
                  phx-click="publish_post"
                  phx-value-id={p.id}
                  class="btn btn-primary btn-sm"
                >
                  Publish
                </button>
                <button
                  id={"delete-post-#{p.id}"}
                  phx-click="delete_post"
                  phx-value-id={p.id}
                  class="btn btn-ghost btn-sm text-error"
                  data-confirm="Delete this post?"
                >
                  Delete
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
