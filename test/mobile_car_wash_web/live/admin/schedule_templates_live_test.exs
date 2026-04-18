defmodule MobileCarWashWeb.Admin.ScheduleTemplatesLiveTest do
  @moduledoc """
  Tests for the admin Schedule Templates LiveView. Follows the admin-page
  pattern of verifying auth guard + resource-level CRUD.
  """
  use MobileCarWashWeb.ConnCase, async: true

  alias MobileCarWash.Scheduling.{BlockTemplate, ServiceType}

  describe "auth guard" do
    test "non-authenticated user is redirected to sign-in", %{conn: conn} do
      conn = get(conn, ~p"/admin/schedule-templates")
      assert redirected_to(conn) == "/sign-in"
    end
  end

  describe "template resource" do
    test "unique identity prevents duplicate (service, day, hour) rows" do
      {:ok, service} =
        ServiceType
        |> Ash.Changeset.for_create(:create, %{
          name: "Basic",
          slug: "basic_unique_#{:rand.uniform(100_000)}",
          base_price_cents: 5000,
          duration_minutes: 45
        })
        |> Ash.create()

      {:ok, _} =
        BlockTemplate
        |> Ash.Changeset.for_create(:create, %{
          service_type_id: service.id,
          day_of_week: 2,
          start_hour: 9,
          active: true
        })
        |> Ash.create()

      assert {:error, _} =
               BlockTemplate
               |> Ash.Changeset.for_create(:create, %{
                 service_type_id: service.id,
                 day_of_week: 2,
                 start_hour: 9,
                 active: true
               })
               |> Ash.create()
    end

    test "can destroy a template" do
      {:ok, service} =
        ServiceType
        |> Ash.Changeset.for_create(:create, %{
          name: "Basic",
          slug: "basic_destroy_#{:rand.uniform(100_000)}",
          base_price_cents: 5000,
          duration_minutes: 45
        })
        |> Ash.create()

      {:ok, t} =
        BlockTemplate
        |> Ash.Changeset.for_create(:create, %{
          service_type_id: service.id,
          day_of_week: 3,
          start_hour: 14,
          active: true
        })
        |> Ash.create()

      assert :ok = Ash.destroy!(t)
    end
  end
end
