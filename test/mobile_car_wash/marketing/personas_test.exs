defmodule MobileCarWash.Marketing.PersonasTest do
  @moduledoc """
  Marketing Phase 2B / Slice 2: the rule engine that matches customers
  to personas based on `criteria` predicates.

  Supported predicates (all under top-level keys in the criteria map):
    * "acquired_channel_slug"       — exact match (string)
    * "device_type"                 — exact match on Customer's latest
                                       event's device_type
    * "lifetime_revenue_cents"      — %{"gte" => n} or %{"lte" => n} or both
    * "has_subscription"            — boolean; matches when the customer
                                       has an :active subscription

  Empty criteria match every customer — useful for an "All Customers"
  catch-all persona.
  """
  use MobileCarWash.DataCase, async: false

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Billing.Payment
  alias MobileCarWash.Marketing
  alias MobileCarWash.Marketing.{AcquisitionChannel, Persona, PersonaMembership, Personas}

  require Ash.Query

  setup do
    :ok = Marketing.seed_channels!()

    {:ok, [meta]} =
      AcquisitionChannel
      |> Ash.Query.for_read(:by_slug, %{slug: "meta_paid"})
      |> Ash.read(authorize?: false)

    {:ok, [referral]} =
      AcquisitionChannel
      |> Ash.Query.for_read(:by_slug, %{slug: "referral"})
      |> Ash.read(authorize?: false)

    %{meta: meta, referral: referral}
  end

  defp register!(channel_id \\ nil) do
    attrs = %{
      email: "persona-#{System.unique_integer([:positive])}@test.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      name: "Persona Test",
      phone: "+15125558#{:rand.uniform(999) |> Integer.to_string() |> String.pad_leading(3, "0")}"
    }

    attrs = if channel_id, do: Map.put(attrs, :acquired_channel_id, channel_id), else: attrs

    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, attrs)
      |> Ash.create()

    customer
  end

  defp create_persona!(slug, criteria) do
    {:ok, persona} =
      Persona
      |> Ash.Changeset.for_create(:create, %{
        slug: slug <> "_#{System.unique_integer([:positive])}",
        name: slug,
        description: "",
        criteria: criteria
      })
      |> Ash.create(authorize?: false)

    persona
  end

  defp pay!(customer, cents) do
    Payment
    |> Ash.Changeset.for_create(:create, %{
      amount_cents: cents,
      stripe_payment_intent_id: "pi_persona_#{System.unique_integer([:positive])}"
    })
    |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
    |> Ash.Changeset.force_change_attribute(:status, :succeeded)
    |> Ash.create!(authorize?: false)
  end

  describe "matches?/2 — acquired_channel_slug" do
    test "true when customer's channel slug matches", %{meta: meta} do
      customer = register!(meta.id)
      persona = create_persona!("meta_buyers", %{"acquired_channel_slug" => "meta_paid"})

      assert Personas.matches?(persona, customer) == true
    end

    test "false when channel slug differs", %{meta: meta} do
      customer = register!(meta.id)
      persona = create_persona!("referred", %{"acquired_channel_slug" => "referral"})

      assert Personas.matches?(persona, customer) == false
    end
  end

  describe "matches?/2 — lifetime_revenue_cents" do
    test "matches when gte threshold is crossed", %{meta: meta} do
      customer = register!(meta.id)
      pay!(customer, 5_000)
      pay!(customer, 3_000)

      persona = create_persona!("big_spenders", %{"lifetime_revenue_cents" => %{"gte" => 7_000}})

      assert Personas.matches?(persona, customer) == true
    end

    test "does not match when below gte threshold", %{meta: meta} do
      customer = register!(meta.id)
      pay!(customer, 1_000)

      persona = create_persona!("big_spenders", %{"lifetime_revenue_cents" => %{"gte" => 10_000}})

      assert Personas.matches?(persona, customer) == false
    end

    test "respects lte upper bound", %{meta: meta} do
      customer = register!(meta.id)
      pay!(customer, 99_999)

      persona = create_persona!("thrifty", %{"lifetime_revenue_cents" => %{"lte" => 5_000}})

      assert Personas.matches?(persona, customer) == false
    end
  end

  describe "matches?/2 — combined predicates" do
    test "all predicates must match (AND semantics)", %{meta: meta} do
      customer = register!(meta.id)
      pay!(customer, 10_000)

      matching =
        create_persona!("meta_big", %{
          "acquired_channel_slug" => "meta_paid",
          "lifetime_revenue_cents" => %{"gte" => 5_000}
        })

      non_matching =
        create_persona!("referral_big", %{
          "acquired_channel_slug" => "referral",
          "lifetime_revenue_cents" => %{"gte" => 5_000}
        })

      assert Personas.matches?(matching, customer) == true
      assert Personas.matches?(non_matching, customer) == false
    end
  end

  describe "matches?/2 — empty criteria" do
    test "empty criteria map matches any customer", %{meta: meta} do
      customer = register!(meta.id)
      persona = create_persona!("all_customers", %{})

      assert Personas.matches?(persona, customer) == true
    end
  end

  describe "assign_matching!/1" do
    test "creates memberships for every matching persona", %{meta: meta, referral: referral} do
      customer = register!(meta.id)

      matching = create_persona!("meta_a", %{"acquired_channel_slug" => "meta_paid"})
      also_matching = create_persona!("everyone", %{})

      _skipped = create_persona!("referral_only", %{"acquired_channel_slug" => "referral"})

      # Pre-existing persona but inactive — should be skipped
      {:ok, inactive} =
        Persona
        |> Ash.Changeset.for_create(:create, %{
          slug: "inactive_#{System.unique_integer([:positive])}",
          name: "Inactive",
          description: "",
          criteria: %{},
          active: false
        })
        |> Ash.create(authorize?: false)

      :ok = Personas.assign_matching!(customer)

      persona_ids =
        PersonaMembership
        |> Ash.Query.for_read(:for_customer, %{customer_id: customer.id})
        |> Ash.read!(authorize?: false)
        |> Enum.map(& &1.persona_id)

      assert matching.id in persona_ids
      assert also_matching.id in persona_ids
      refute inactive.id in persona_ids
      # Don't use referral in this test — make sure it was set up
      _ = referral
    end

    test "is idempotent — running twice produces no duplicate rows",
         %{meta: meta} do
      customer = register!(meta.id)
      _ = create_persona!("every", %{})

      :ok = Personas.assign_matching!(customer)
      :ok = Personas.assign_matching!(customer)

      count =
        PersonaMembership
        |> Ash.Query.for_read(:for_customer, %{customer_id: customer.id})
        |> Ash.read!(authorize?: false)
        |> length()

      assert count == 1
    end

    test "preserves manually_assigned memberships even if rules no longer match",
         %{meta: meta, referral: referral} do
      customer = register!(meta.id)

      # Customer is a meta_paid acquisition, but admin manually tagged
      # them as "referral".
      referral_persona = create_persona!("referral", %{"acquired_channel_slug" => "referral"})

      {:ok, _} =
        PersonaMembership
        |> Ash.Changeset.for_create(:assign, %{
          customer_id: customer.id,
          persona_id: referral_persona.id,
          manually_assigned: true
        })
        |> Ash.create(authorize?: false)

      :ok = Personas.assign_matching!(customer)

      # Admin tag survives — rule engine never revokes manual assignments
      still_there =
        PersonaMembership
        |> Ash.Query.for_read(:for_customer, %{customer_id: customer.id})
        |> Ash.read!(authorize?: false)
        |> Enum.any?(&(&1.persona_id == referral_persona.id))

      assert still_there == true
      _ = referral
    end
  end
end
