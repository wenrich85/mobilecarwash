defmodule MobileCarWash.Scheduling.AddOnTest do
  use MobileCarWash.DataCase, async: true

  alias MobileCarWash.Scheduling.AddOn

  test "creates an add-on with the expected fields" do
    addon =
      AddOn
      |> Ash.Changeset.for_create(:create, %{
        name: "Wax & Shine",
        slug: "wax_shine",
        description: "Hand wax",
        price_cents: 1_500,
        icon: "sparkles"
      })
      |> Ash.create!()

    assert addon.name == "Wax & Shine"
    assert addon.price_cents == 1_500
    assert addon.active == true
    assert addon.sort_order == 0
  end

  test "slug is unique" do
    attrs = %{name: "A", slug: "dup_addon", price_cents: 100}
    AddOn |> Ash.Changeset.for_create(:create, attrs) |> Ash.create!()

    assert {:error, _} =
             AddOn
             |> Ash.Changeset.for_create(:create, %{attrs | name: "B"})
             |> Ash.create()
  end
end
