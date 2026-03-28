defmodule MobileCarWash.Compliance.FormationTask do
  @moduledoc """
  A business formation or compliance task — tracks status, deadlines,
  and auto-creates recurring tasks (e.g., annual TX franchise tax report).

  Statuses: not_started → in_progress → completed (or blocked)
  Priorities: high, medium, low
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Compliance,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "formation_tasks"
    repo MobileCarWash.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
    end

    attribute :status, :atom do
      constraints one_of: [:not_started, :in_progress, :completed, :blocked]
      default :not_started
      allow_nil? false
      public? true
    end

    attribute :priority, :atom do
      constraints one_of: [:high, :medium, :low]
      default :medium
      public? true
    end

    attribute :due_date, :date do
      public? true
    end

    attribute :completed_at, :utc_datetime do
      public? true
    end

    attribute :notes, :string do
      public? true
    end

    attribute :external_url, :string do
      public? true
    end

    attribute :recurring, :boolean do
      default false
      public? true
    end

    attribute :recurrence_months, :integer do
      default 12
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :category, MobileCarWash.Compliance.TaskCategory do
      allow_nil? false
    end

    belongs_to :parent_task, MobileCarWash.Compliance.FormationTask do
      allow_nil? true
    end
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]

    update :complete do
      require_atomic? false
      change set_attribute(:status, :completed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)

      change after_action(fn changeset, record, _context ->
        if record.recurring do
          create_next_recurring_task(record)
        end

        {:ok, record}
      end)
    end

    update :update_status do
      accept [:status, :notes]
    end

    read :by_category do
      argument :category_id, :uuid, allow_nil?: false
      filter expr(category_id == ^arg(:category_id))
    end

    read :by_status do
      argument :status, :atom do
        constraints one_of: [:not_started, :in_progress, :completed, :blocked]
      end

      filter expr(status == ^arg(:status))
    end

    read :upcoming_deadlines do
      argument :days_ahead, :integer, default: 7

      prepare fn query, _context ->
        days = Ash.Query.get_argument(query, :days_ahead) || 7
        today = Date.utc_today()
        deadline = Date.add(today, days)

        require Ash.Query
        Ash.Query.filter(query, expr(not is_nil(due_date) and status != :completed and due_date <= ^deadline and due_date >= ^today))
      end
    end
  end

  defp create_next_recurring_task(completed_task) do
    new_due_date =
      if completed_task.due_date do
        Date.add(completed_task.due_date, completed_task.recurrence_months * 30)
      else
        Date.add(Date.utc_today(), completed_task.recurrence_months * 30)
      end

    __MODULE__
    |> Ash.Changeset.for_create(:create, %{
      name: completed_task.name,
      description: completed_task.description,
      status: :not_started,
      priority: completed_task.priority,
      due_date: new_due_date,
      external_url: completed_task.external_url,
      recurring: true,
      recurrence_months: completed_task.recurrence_months
    })
    |> Ash.Changeset.force_change_attribute(:category_id, completed_task.category_id)
    |> Ash.Changeset.force_change_attribute(:parent_task_id, completed_task.id)
    |> Ash.create!()
  end
end
