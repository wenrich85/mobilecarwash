defmodule MobileCarWash.Scheduling.ServiceTypeBlockFieldsTest do
  @moduledoc """
  ServiceType carries `window_minutes` (how long a block for this service lasts)
  and `block_capacity` (max appointments per block). These drive block generation
  and scheduling throughout the system.
  """
  use MobileCarWash.DataCase, async: false

  alias MobileCarWash.Scheduling.ServiceType

  defp create_service(attrs \\ %{}) do
    ServiceType
    |> Ash.Changeset.for_create(
      :create,
      Map.merge(
        %{
          name: "Basic Wash",
          slug: "basic_wash_#{:rand.uniform(100_000)}",
          base_price_cents: 5000,
          duration_minutes: 45
        },
        attrs
      )
    )
    |> Ash.create!()
  end

  describe "block_capacity default" do
    test "defaults to 3 when not provided" do
      service = create_service()
      assert service.block_capacity == 3
    end

    test "can be overridden at creation" do
      service = create_service(%{block_capacity: 5})
      assert service.block_capacity == 5
    end
  end

  describe "window_minutes default" do
    test "defaults to duration_minutes * 3 + 60 when not provided (basic wash: 45*3+60 = 195)" do
      service = create_service(%{duration_minutes: 45})
      assert service.window_minutes == 195
    end

    test "defaults scale for a deep clean (120*3+60 = 420)" do
      service =
        create_service(%{
          name: "Deep Clean",
          slug: "deep_clean_#{:rand.uniform(100_000)}",
          duration_minutes: 120
        })

      assert service.window_minutes == 420
    end

    test "can be overridden at creation" do
      service = create_service(%{window_minutes: 240})
      assert service.window_minutes == 240
    end
  end
end
