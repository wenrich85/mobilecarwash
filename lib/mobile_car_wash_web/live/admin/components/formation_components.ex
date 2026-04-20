defmodule MobileCarWashWeb.Admin.FormationComponents do
  @moduledoc """
  Function components for the business formation tracker.
  """
  use Phoenix.Component

  attr :status, :atom, required: true

  def status_badge(assigns) do
    ~H"""
    <span class={["badge badge-sm", status_class(@status)]}>
      {format_status(@status)}
    </span>
    """
  end

  attr :priority, :atom, required: true

  def priority_badge(assigns) do
    ~H"""
    <span class={["badge badge-sm badge-outline", priority_class(@priority)]}>
      {to_string(@priority)}
    </span>
    """
  end

  attr :total, :integer, required: true
  attr :completed, :integer, required: true
  attr :overdue, :integer, required: true

  def progress_summary(assigns) do
    pct =
      if assigns.total > 0, do: Float.round(assigns.completed / assigns.total * 100, 0), else: 0

    assigns = assign(assigns, pct: pct)

    ~H"""
    <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-8">
      <div class="stat bg-base-100 shadow rounded-box p-4">
        <div class="stat-title text-sm">Total Tasks</div>
        <div class="stat-value text-lg">{@total}</div>
      </div>
      <div class="stat bg-base-100 shadow rounded-box p-4">
        <div class="stat-title text-sm">Completed</div>
        <div class="stat-value text-lg text-success">{@completed}</div>
      </div>
      <div class="stat bg-base-100 shadow rounded-box p-4">
        <div class="stat-title text-sm">Progress</div>
        <div class="stat-value text-lg">{@pct}%</div>
        <progress class="progress progress-success w-full" value={@pct} max="100"></progress>
      </div>
      <div class="stat bg-base-100 shadow rounded-box p-4">
        <div class="stat-title text-sm">Overdue</div>
        <div class={"stat-value text-lg #{if @overdue > 0, do: "text-error", else: "text-success"}"}>
          {@overdue}
        </div>
      </div>
    </div>
    """
  end

  attr :task, :map, required: true
  attr :editing, :boolean, default: false

  def task_row(assigns) do
    overdue? =
      assigns.task.due_date && Date.compare(assigns.task.due_date, Date.utc_today()) == :lt &&
        assigns.task.status != :completed

    assigns = assign(assigns, overdue: overdue?)

    ~H"""
    <tr class={[@overdue && "bg-error/5"]}>
      <td class="max-w-xs">
        <div class="font-semibold">{@task.name}</div>
        <div :if={@task.description} class="text-xs text-base-content/70 line-clamp-2">
          {@task.description}
        </div>
        <a
          :if={@task.external_url}
          href={@task.external_url}
          target="_blank"
          class="text-xs link link-primary"
        >
          Gov website →
        </a>
      </td>
      <td><.status_badge status={@task.status} /></td>
      <td><.priority_badge priority={@task.priority} /></td>
      <td class={["text-sm", @overdue && "text-error font-bold"]}>
        {if @task.due_date, do: Calendar.strftime(@task.due_date, "%b %d, %Y"), else: "-"}
        <span :if={@task.recurring} class="badge badge-ghost badge-xs ml-1">recurring</span>
      </td>
      <td>
        <div class="flex gap-1">
          <select
            class="select select-bordered select-xs"
            phx-change="update_status"
            phx-value-id={@task.id}
            name="status"
          >
            <option value="not_started" selected={@task.status == :not_started}>Not Started</option>
            <option value="in_progress" selected={@task.status == :in_progress}>In Progress</option>
            <option value="completed" selected={@task.status == :completed}>Completed</option>
            <option value="blocked" selected={@task.status == :blocked}>Blocked</option>
          </select>
          <button
            :if={@task.status != :completed}
            class="btn btn-success btn-xs"
            phx-click="complete_task"
            phx-value-id={@task.id}
          >
            ✓
          </button>
          <button
            :if={@task.status != :completed}
            class="btn btn-ghost btn-xs text-error"
            phx-click="delete_task"
            phx-value-id={@task.id}
          >
            ×
          </button>
        </div>
      </td>
    </tr>
    """
  end

  defp status_class(:not_started), do: "badge-ghost"
  defp status_class(:in_progress), do: "badge-info"
  defp status_class(:completed), do: "badge-success"
  defp status_class(:blocked), do: "badge-error"

  defp priority_class(:high), do: "border-error text-error"
  defp priority_class(:medium), do: "border-warning text-warning"
  defp priority_class(:low), do: "border-base-300"

  defp format_status(:not_started), do: "Not Started"
  defp format_status(:in_progress), do: "In Progress"
  defp format_status(:completed), do: "Completed"
  defp format_status(:blocked), do: "Blocked"
end
