defmodule MobileCarWashWeb.Admin.FormationLive do
  @moduledoc """
  Business formation tracker — manage TX state, federal, veteran certification,
  and compliance tasks. Filter by category and status, complete tasks
  (with auto-creation of recurring tasks), and track progress toward launch.
  """
  use MobileCarWashWeb, :live_view

  import MobileCarWashWeb.Admin.FormationComponents

  alias MobileCarWash.Compliance.{FormationTask, TaskCategory}

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    categories = Ash.read!(TaskCategory) |> Enum.sort_by(& &1.sort_order)

    socket =
      socket
      |> assign(
        page_title: "Business Formation",
        categories: categories,
        filter_category: nil,
        filter_status: nil,
        show_add_form: false
      )
      |> load_tasks()

    {:ok, socket}
  end

  @impl true
  def handle_event("filter_category", %{"category" => ""}, socket) do
    {:noreply, socket |> assign(filter_category: nil) |> load_tasks()}
  end

  def handle_event("filter_category", %{"category" => cat_id}, socket) do
    {:noreply, socket |> assign(filter_category: cat_id) |> load_tasks()}
  end

  def handle_event("filter_status", %{"status" => ""}, socket) do
    {:noreply, socket |> assign(filter_status: nil) |> load_tasks()}
  end

  def handle_event("filter_status", %{"status" => status}, socket) do
    {:noreply, socket |> assign(filter_status: String.to_existing_atom(status)) |> load_tasks()}
  end

  def handle_event("update_status", %{"id" => id, "status" => status_str}, socket) do
    status = String.to_existing_atom(status_str)

    case Ash.get(FormationTask, id) do
      {:ok, task} ->
        if status == :completed do
          task |> Ash.Changeset.for_update(:complete, %{}) |> Ash.update()
        else
          task |> Ash.Changeset.for_update(:update_status, %{status: status}) |> Ash.update()
        end

        {:noreply, load_tasks(socket)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("complete_task", %{"id" => id}, socket) do
    case Ash.get(FormationTask, id) do
      {:ok, task} ->
        task |> Ash.Changeset.for_update(:complete, %{}) |> Ash.update()
        {:noreply, socket |> load_tasks() |> put_flash(:info, "Task completed: #{task.name}")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_add_form", _params, socket) do
    {:noreply, assign(socket, show_add_form: !socket.assigns.show_add_form)}
  end

  def handle_event("create_task", %{"task" => params}, socket) do
    attrs = %{
      name: params["name"],
      description: params["description"],
      priority: String.to_atom(params["priority"] || "medium"),
      due_date: parse_date(params["due_date"]),
      external_url: blank_to_nil(params["external_url"])
    }

    case FormationTask
         |> Ash.Changeset.for_create(:create, attrs)
         |> Ash.Changeset.force_change_attribute(:category_id, params["category_id"])
         |> Ash.create() do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(show_add_form: false)
         |> load_tasks()
         |> put_flash(:info, "Task created")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not create task")}
    end
  end

  def handle_event("add_category", %{"category" => params}, socket) do
    attrs = %{
      name: params["name"],
      description: params["description"],
      sort_order: parse_int(params["sort_order"])
    }

    case TaskCategory |> Ash.Changeset.for_create(:create, attrs) |> Ash.create() do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(categories: Ash.read!(TaskCategory) |> Enum.sort_by(& &1.sort_order))
         |> put_flash(:info, "Category created")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not create category")}
    end
  end

  def handle_event("delete_task", %{"id" => id}, socket) do
    case Ash.get(FormationTask, id) do
      {:ok, task} ->
        # Guard: reject if task is completed (historical record)
        if task.status == :completed do
          {:noreply, put_flash(socket, :error, "Cannot delete completed tasks")}
        else
          case Ash.destroy(task) do
            :ok ->
              {:noreply, socket |> load_tasks() |> put_flash(:info, "Task deleted")}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Could not delete task")}
          end
        end

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto py-8 px-4">
      <div class="flex justify-between items-center mb-8">
        <div>
          <h1 class="text-3xl font-bold">Business Formation</h1>
          <p class="text-base-content/80">TX State · Federal · Veteran Certs · Compliance</p>
        </div>
        <.link navigate={~p"/admin/metrics"} class="btn btn-outline btn-sm">
          ← Dashboard
        </.link>
      </div>

      <.progress_summary total={@total} completed={@completed} overdue={@overdue} />

      <!-- Filters -->
      <div class="flex gap-4 mb-6">
        <select class="select select-bordered select-sm" phx-change="filter_category" name="category">
          <option value="">All Categories</option>
          <option
            :for={cat <- @categories}
            value={cat.id}
            selected={@filter_category == cat.id}
          >
            {cat.name}
          </option>
        </select>

        <select class="select select-bordered select-sm" phx-change="filter_status" name="status">
          <option value="">All Statuses</option>
          <option value="not_started" selected={@filter_status == :not_started}>Not Started</option>
          <option value="in_progress" selected={@filter_status == :in_progress}>In Progress</option>
          <option value="completed" selected={@filter_status == :completed}>Completed</option>
          <option value="blocked" selected={@filter_status == :blocked}>Blocked</option>
        </select>
      </div>

      <!-- Add Task / Add Category -->
      <div class="mb-6">
        <button class="btn btn-primary btn-sm mb-4" phx-click="toggle_add_form">
          {if @show_add_form, do: "Cancel", else: "+ Add Task"}
        </button>

        <div :if={@show_add_form} class="card bg-base-100 shadow mb-4">
          <div class="card-body p-4">
            <h3 class="font-bold mb-4">Add Task</h3>
            <form phx-submit="create_task" class="space-y-3">
              <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
                <div class="form-control">
                  <label class="label label-text text-xs">Task Name</label>
                  <input type="text" name="task[name]" class="input input-bordered input-sm" required placeholder="Task name" />
                </div>
                <div class="form-control">
                  <label class="label label-text text-xs">Category</label>
                  <select name="task[category_id]" class="select select-bordered select-sm" required>
                    <option value="">Select Category</option>
                    <option :for={cat <- @categories} value={cat.id}>{cat.name}</option>
                  </select>
                </div>
              </div>
              <div class="grid grid-cols-1 md:grid-cols-3 gap-3">
                <div class="form-control">
                  <label class="label label-text text-xs">Priority</label>
                  <select name="task[priority]" class="select select-bordered select-sm">
                    <option value="low">Low</option>
                    <option value="medium" selected>Medium</option>
                    <option value="high">High</option>
                  </select>
                </div>
                <div class="form-control">
                  <label class="label label-text text-xs">Due Date</label>
                  <input type="date" name="task[due_date]" class="input input-bordered input-sm" />
                </div>
                <div class="form-control">
                  <label class="label label-text text-xs">External URL</label>
                  <input type="url" name="task[external_url]" class="input input-bordered input-sm" placeholder="https://..." />
                </div>
              </div>
              <div class="form-control">
                <label class="label label-text text-xs">Description</label>
                <textarea name="task[description]" class="textarea textarea-bordered textarea-sm" placeholder="Task details..."></textarea>
              </div>
              <button type="submit" class="btn btn-primary btn-sm">Create Task</button>
            </form>

            <!-- Add Category Form -->
            <div class="divider mt-6">Or Add Category</div>
            <form phx-submit="add_category" class="space-y-3">
              <div class="grid grid-cols-1 md:grid-cols-3 gap-3">
                <div class="form-control">
                  <label class="label label-text text-xs">Category Name</label>
                  <input type="text" name="category[name]" class="input input-bordered input-sm" required placeholder="e.g., Texas State" />
                </div>
                <div class="form-control">
                  <label class="label label-text text-xs">Sort Order</label>
                  <input type="number" name="category[sort_order]" class="input input-bordered input-sm" value="0" />
                </div>
              </div>
              <div class="form-control">
                <label class="label label-text text-xs">Description</label>
                <input type="text" name="category[description]" class="input input-bordered input-sm" placeholder="Category description" />
              </div>
              <button type="submit" class="btn btn-primary btn-sm">Add Category</button>
            </form>
          </div>
        </div>
      </div>

      <!-- Tasks by Category -->
      <div :for={group <- @grouped_tasks} class="card bg-base-100 shadow-xl mb-6">
        <div class="card-body p-0">
          <div class="px-6 py-4 bg-base-200 rounded-t-2xl">
            <h2 class="font-bold text-lg">{group.category.name}</h2>
            <p :if={group.category.description} class="text-sm text-base-content/80">{group.category.description}</p>
          </div>

          <div :if={group.tasks == []} class="px-6 py-4 text-base-content/70 text-sm">
            No tasks match your filters.
          </div>

          <table :if={group.tasks != []} class="table">
            <thead>
              <tr>
                <th>Task</th>
                <th>Status</th>
                <th>Priority</th>
                <th>Due Date</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              <.task_row :for={task <- group.tasks} task={task} />
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  defp load_tasks(socket) do
    query = FormationTask |> Ash.Query.sort([:priority, :due_date])

    query =
      case socket.assigns.filter_category do
        nil -> query
        cat_id -> Ash.Query.filter(query, category_id == ^cat_id)
      end

    query =
      case socket.assigns.filter_status do
        nil -> query
        status -> Ash.Query.filter(query, status == ^status)
      end

    tasks = Ash.read!(query)
    categories = socket.assigns.categories

    today = Date.utc_today()
    total = length(tasks)
    completed = Enum.count(tasks, &(&1.status == :completed))
    overdue = Enum.count(tasks, fn t ->
      t.due_date && Date.compare(t.due_date, today) == :lt && t.status != :completed
    end)

    # Group tasks by category
    grouped =
      categories
      |> Enum.map(fn cat ->
        cat_tasks = Enum.filter(tasks, &(&1.category_id == cat.id))
        %{category: cat, tasks: cat_tasks}
      end)
      |> Enum.reject(&(&1.tasks == [] and socket.assigns.filter_category != nil))

    assign(socket,
      tasks: tasks,
      grouped_tasks: grouped,
      total: total,
      completed: completed,
      overdue: overdue
    )
  end

  # === Helpers ===

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil
  defp parse_date(str) when is_binary(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      :error -> nil
    end
  end
  defp parse_date(d), do: d

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil
  defp parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> nil
    end
  end
  defp parse_int(n) when is_integer(n), do: n

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(str), do: str
end
