defmodule MobileCarWash.Marketing.PersonaMembershipTest do
  @moduledoc """
  Marketing Phase 2B / Slice 1: PersonaMembership is the join table
  between Customer and Persona. One customer can belong to many
  personas simultaneously (overlapping archetypes).

  Contract pinned here:
    * Membership has customer_id, persona_id, matched_at,
      manually_assigned (bool)
    * Unique on (customer_id, persona_id) — no duplicate rows
    * :assign action creates a membership
    * :unassign deletes one
    * :for_customer read
    * :for_persona read
  """
  use MobileCarWash.DataCase, async: false

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Marketing.{Persona, PersonaMembership}

  defp register_customer! do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "pm-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "PM Test",
        phone: "+15125559#{:rand.uniform(999) |> Integer.to_string() |> String.pad_leading(3, "0")}"
      })
      |> Ash.create()

    customer
  end

  defp create_persona!(slug, overrides \\ %{}) do
    {:ok, p} =
      Persona
      |> Ash.Changeset.for_create(
        :create,
        Map.merge(
          %{slug: slug, name: String.capitalize(slug), description: ""},
          overrides
        )
      )
      |> Ash.create(authorize?: false)

    p
  end

  describe ":assign action" do
    test "creates a membership row" do
      customer = register_customer!()
      persona = create_persona!("busy_parent_#{System.unique_integer([:positive])}")

      {:ok, m} =
        PersonaMembership
        |> Ash.Changeset.for_create(:assign, %{
          customer_id: customer.id,
          persona_id: persona.id,
          manually_assigned: true
        })
        |> Ash.create(authorize?: false)

      assert m.customer_id == customer.id
      assert m.persona_id == persona.id
      assert m.manually_assigned == true
      assert m.matched_at != nil
    end

    test "prevents duplicate memberships for the same pair" do
      customer = register_customer!()
      persona = create_persona!("dup_#{System.unique_integer([:positive])}")

      {:ok, _} =
        PersonaMembership
        |> Ash.Changeset.for_create(:assign, %{
          customer_id: customer.id,
          persona_id: persona.id
        })
        |> Ash.create(authorize?: false)

      {:error, _} =
        PersonaMembership
        |> Ash.Changeset.for_create(:assign, %{
          customer_id: customer.id,
          persona_id: persona.id
        })
        |> Ash.create(authorize?: false)
    end
  end

  describe ":for_customer read" do
    test "returns all memberships for a given customer" do
      customer = register_customer!()
      p1 = create_persona!("p1_#{System.unique_integer([:positive])}")
      p2 = create_persona!("p2_#{System.unique_integer([:positive])}")

      for p <- [p1, p2] do
        PersonaMembership
        |> Ash.Changeset.for_create(:assign, %{
          customer_id: customer.id,
          persona_id: p.id
        })
        |> Ash.create!(authorize?: false)
      end

      {:ok, rows} =
        PersonaMembership
        |> Ash.Query.for_read(:for_customer, %{customer_id: customer.id})
        |> Ash.read(authorize?: false)

      assert length(rows) == 2
      persona_ids = Enum.map(rows, & &1.persona_id)
      assert p1.id in persona_ids
      assert p2.id in persona_ids
    end
  end

  describe ":for_persona read" do
    test "returns all memberships for a given persona" do
      persona = create_persona!("fp_#{System.unique_integer([:positive])}")
      c1 = register_customer!()
      c2 = register_customer!()

      for c <- [c1, c2] do
        PersonaMembership
        |> Ash.Changeset.for_create(:assign, %{
          customer_id: c.id,
          persona_id: persona.id
        })
        |> Ash.create!(authorize?: false)
      end

      {:ok, rows} =
        PersonaMembership
        |> Ash.Query.for_read(:for_persona, %{persona_id: persona.id})
        |> Ash.read(authorize?: false)

      assert length(rows) == 2
    end
  end
end
