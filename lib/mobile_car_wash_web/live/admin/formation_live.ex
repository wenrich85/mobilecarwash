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
        filter_status: nil
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

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto py-8 px-4">
      <div class="flex justify-between items-center mb-8">
        <div>
          <h1 class="text-3xl font-bold">Business Formation</h1>
          <p class="text-base-content/60">TX State · Federal · Veteran Certs · Compliance</p>
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

      <!-- Tasks by Category -->
      <div :for={group <- @grouped_tasks} class="card bg-base-100 shadow-xl mb-6">
        <div class="card-body p-0">
          <div class="px-6 py-4 bg-base-200 rounded-t-2xl">
            <h2 class="font-bold text-lg">{group.category.name}</h2>
            <p :if={group.category.description} class="text-sm text-base-content/60">{group.category.description}</p>
          </div>

          <div :if={group.tasks == []} class="px-6 py-4 text-base-content/50 text-sm">
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
end
