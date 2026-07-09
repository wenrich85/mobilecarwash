defmodule MobileCarWash.Scheduling.ServiceTypeLandingDisplayTest do
  use MobileCarWash.DataCase, async: true

  alias MobileCarWash.Scheduling.ServiceType

  test "service types can be created hidden from the landing page" do
    service =
      ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Fleet Wash",
        slug: "fleet_wash_#{System.unique_integer([:positive])}",
        description: "Bookable service that should not be marketed.",
        base_price_cents: 7500,
        duration_minutes: 60,
        show_on_landing: false
      })
      |> Ash.create!()

    assert service.active == true
    assert service.show_on_landing == false
  end

  test "service types can update landing page display independently of active state" do
    service =
      ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Visible Wash",
        slug: "visible_wash_#{System.unique_integer([:positive])}",
        description: "Starts visible.",
        base_price_cents: 6500,
        duration_minutes: 50
      })
      |> Ash.create!()

    updated =
      service
      |> Ash.Changeset.for_update(:update, %{show_on_landing: false})
      |> Ash.update!()

    assert updated.active == true
    assert updated.show_on_landing == false
  end
end
