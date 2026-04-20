defmodule MobileCarWash.Marketing.PersonaTest do
  @moduledoc """
  Marketing Phase 2B / Slice 1: personas are named customer archetypes
  the owner uses to target marketing. Each has a name, a human-readable
  description (used later as the AI image prompt), and a criteria map
  that the rule engine evaluates against Customer data.

  Contract pinned here:
    * Persona has name (unique), slug, description, criteria (map),
      image_url, image_prompt, active, sort_order, timestamps
    * :create / :update / :destroy actions with admin-only mutate policy
    * :active read filters on active == true, sorted by sort_order
    * :by_slug read
  """
  use MobileCarWash.DataCase, async: false

  alias MobileCarWash.Marketing.Persona

  describe ":create action" do
    test "persists a persona with valid attributes" do
      {:ok, persona} =
        Persona
        |> Ash.Changeset.for_create(:create, %{
          slug: "busy_parent",
          name: "Busy Parent",
          description:
            "Harried parent in their 30s-40s, two kids, SUV or minivan, values convenience over price.",
          criteria: %{"device_type" => "mobile", "acquired_channel_slug" => "meta_paid"},
          image_prompt:
            "Friendly 35yo parent in casual clothes, standing next to an SUV in a suburban driveway"
        })
        |> Ash.create(authorize?: false)

      assert persona.slug == "busy_parent"
      assert persona.name == "Busy Parent"
      assert persona.criteria["device_type"] == "mobile"
      assert persona.active == true
    end

    test "rejects duplicate slug" do
      {:ok, _} =
        Persona
        |> Ash.Changeset.for_create(:create, %{
          slug: "dupe",
          name: "Dupe",
          description: "first"
        })
        |> Ash.create(authorize?: false)

      {:error, _} =
        Persona
        |> Ash.Changeset.for_create(:create, %{
          slug: "dupe",
          name: "Dupe 2",
          description: "second"
        })
        |> Ash.create(authorize?: false)
    end

    test "requires name + slug" do
      {:error, _} =
        Persona
        |> Ash.Changeset.for_create(:create, %{description: "missing name and slug"})
        |> Ash.create(authorize?: false)
    end
  end

  describe ":active read" do
    test "returns only active personas, sorted by sort_order" do
      {:ok, _} =
        Persona
        |> Ash.Changeset.for_create(:create, %{
          slug: "a",
          name: "A",
          description: "",
          sort_order: 20
        })
        |> Ash.create(authorize?: false)

      {:ok, _} =
        Persona
        |> Ash.Changeset.for_create(:create, %{
          slug: "b",
          name: "B",
          description: "",
          sort_order: 10
        })
        |> Ash.create(authorize?: false)

      {:ok, _} =
        Persona
        |> Ash.Changeset.for_create(:create, %{
          slug: "c",
          name: "C",
          description: "",
          active: false
        })
        |> Ash.create(authorize?: false)

      rows =
        Persona
        |> Ash.Query.for_read(:active)
        |> Ash.read!(authorize?: false)

      slugs = Enum.map(rows, & &1.slug)
      assert slugs == ["b", "a"]
    end
  end

  describe ":by_slug read" do
    test "returns the matching persona" do
      {:ok, _} =
        Persona
        |> Ash.Changeset.for_create(:create, %{
          slug: "weekend_enthusiast",
          name: "Weekend Enthusiast",
          description: "Detail-obsessed car lovers"
        })
        |> Ash.create(authorize?: false)

      {:ok, [found]} =
        Persona
        |> Ash.Query.for_read(:by_slug, %{slug: "weekend_enthusiast"})
        |> Ash.read(authorize?: false)

      assert found.name == "Weekend Enthusiast"
    end
  end
end
