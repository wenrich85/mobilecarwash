defmodule MobileCarWash.Compliance.FormationTaskTest do
  use MobileCarWash.DataCase, async: true

  alias MobileCarWash.Compliance.{FormationTask, TaskCategory}

  require Ash.Query

  setup do
    {:ok, category} =
      TaskCategory
      |> Ash.Changeset.for_create(:create, %{
        name: "Test Category",
        slug: "test_cat_#{:rand.uniform(100_000)}",
        sort_order: 1
      })
      |> Ash.create()

    %{category: category}
  end

  defp create_task(category, attrs \\ %{}) do
    defaults = %{
      name: "Test Task #{:rand.uniform(100_000)}",
      status: :not_started,
      priority: :medium
    }

    FormationTask
    |> Ash.Changeset.for_create(:create, Map.merge(defaults, attrs))
    |> Ash.Changeset.force_change_attribute(:category_id, category.id)
    |> Ash.create!()
  end

  describe "CRUD" do
    test "creates a formation task", %{category: category} do
      task = create_task(category, %{name: "LLC Filing", priority: :high})

      assert task.name == "LLC Filing"
      assert task.status == :not_started
      assert task.priority == :high
    end

    test "reads all tasks", %{category: category} do
      create_task(category, %{name: "Task 1"})
      create_task(category, %{name: "Task 2"})

      tasks = Ash.read!(FormationTask)
      assert length(tasks) >= 2
    end
  end

  describe "complete action" do
    test "marks task as completed with timestamp", %{category: category} do
      task = create_task(category)

      {:ok, completed} =
        task
        |> Ash.Changeset.for_update(:complete, %{})
        |> Ash.update()

      assert completed.status == :completed
      assert completed.completed_at != nil
    end

    test "creates next recurring task when recurring is true", %{category: category} do
      task =
        create_task(category, %{
          name: "Annual Report",
          recurring: true,
          recurrence_months: 12,
          due_date: ~D[2026-05-15]
        })

      {:ok, _completed} =
        task
        |> Ash.Changeset.for_update(:complete, %{})
        |> Ash.update()

      # Should have created a new task
      all_tasks =
        FormationTask
        |> Ash.Query.filter(name == "Annual Report")
        |> Ash.read!()

      assert length(all_tasks) == 2

      new_task = Enum.find(all_tasks, &(&1.status == :not_started))
      assert new_task != nil
      assert new_task.parent_task_id == task.id
      assert new_task.recurring == true
      # Due date should be ~12 months later
      assert Date.compare(new_task.due_date, task.due_date) == :gt
    end

    test "does NOT create recurring task for non-recurring tasks", %{category: category} do
      task = create_task(category, %{name: "One-Time Task", recurring: false})

      {:ok, _completed} =
        task
        |> Ash.Changeset.for_update(:complete, %{})
        |> Ash.update()

      all =
        FormationTask
        |> Ash.Query.filter(name == "One-Time Task")
        |> Ash.read!()

      assert length(all) == 1
    end
  end

  describe "status transitions" do
    test "updates status via update_status action", %{category: category} do
      task = create_task(category)

      {:ok, updated} =
        task
        |> Ash.Changeset.for_update(:update_status, %{status: :in_progress})
        |> Ash.update()

      assert updated.status == :in_progress
    end
  end

  describe "category identity" do
    test "enforces unique slug on TaskCategory" do
      slug = "unique_slug_#{:rand.uniform(100_000)}"

      {:ok, _} =
        TaskCategory
        |> Ash.Changeset.for_create(:create, %{name: "Cat 1", slug: slug})
        |> Ash.create()

      assert {:error, _} =
               TaskCategory
               |> Ash.Changeset.for_create(:create, %{name: "Cat 2", slug: slug})
               |> Ash.create()
    end
  end
end
