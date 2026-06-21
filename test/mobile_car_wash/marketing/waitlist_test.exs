defmodule MobileCarWash.Marketing.WaitlistTest do
  use MobileCarWash.DataCase, async: true

  alias MobileCarWash.Marketing.Waitlist

  test "join/1 captures a lead with the entered address" do
    {:ok, entry} =
      Waitlist
      |> Ash.Changeset.for_create(:join, %{
        email: "lead@example.com",
        name: "Lead Person",
        phone: "5125551234",
        address_text: "1 Far Away Rd, Elsewhere, TX",
        zip: "00000",
        latitude: 30.1,
        longitude: -98.5,
        requested_service_slug: "basic_wash"
      })
      |> Ash.create(authorize?: false)

    assert entry.email == "lead@example.com"
    assert entry.zip == "00000"
    assert entry.requested_service_slug == "basic_wash"
  end

  test "join/1 requires an email" do
    assert {:error, _} =
             Waitlist
             |> Ash.Changeset.for_create(:join, %{address_text: "x", zip: "00000"})
             |> Ash.create(authorize?: false)
  end
end
