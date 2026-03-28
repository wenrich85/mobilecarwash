# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Or as part of:
#
#     mix ash.setup

alias MobileCarWash.Scheduling.ServiceType
alias MobileCarWash.Billing.SubscriptionPlan

require Ash.Query

# --- Service Types ---

IO.puts("Seeding service types...")

for attrs <- [
      %{
        name: "Basic Wash",
        slug: "basic_wash",
        description:
          "Exterior hand wash, tire cleaning, window cleaning, and towel dry. Perfect for regular maintenance.",
        base_price_cents: 5_000,
        duration_minutes: 45
      },
      %{
        name: "Deep Clean & Detail",
        slug: "deep_clean",
        description:
          "Full interior and exterior detail including clay bar, wax, carpet shampoo, leather conditioning, and engine bay cleaning.",
        base_price_cents: 20_000,
        duration_minutes: 120
      }
    ] do
  existing =
    ServiceType
    |> Ash.Query.filter(slug == ^attrs.slug)
    |> Ash.read!()

  case existing do
    [] ->
      ServiceType
      |> Ash.Changeset.for_create(:create, attrs)
      |> Ash.create!()

      IO.puts("  ✓ Created #{attrs.name}")

    [_] ->
      IO.puts("  - #{attrs.name} already exists, skipping")
  end
end

# --- Subscription Plans ---

IO.puts("\nSeeding subscription plans...")

for attrs <- [
      %{
        name: "Basic",
        slug: "basic",
        price_cents: 9_000,
        basic_washes_per_month: 2,
        deep_cleans_per_month: 0,
        deep_clean_discount_percent: 25,
        description: "2 basic washes per month + 25% off any deep clean"
      },
      %{
        name: "Standard",
        slug: "standard",
        price_cents: 12_500,
        basic_washes_per_month: 4,
        deep_cleans_per_month: 0,
        deep_clean_discount_percent: 30,
        description: "4 basic washes per month + 30% off any deep clean"
      },
      %{
        name: "Premium",
        slug: "premium",
        price_cents: 20_000,
        basic_washes_per_month: 3,
        deep_cleans_per_month: 1,
        deep_clean_discount_percent: 50,
        description: "3 basic washes + 1 deep clean per month + 50% off additional deep cleans"
      }
    ] do
  existing =
    SubscriptionPlan
    |> Ash.Query.filter(slug == ^attrs.slug)
    |> Ash.read!()

  case existing do
    [] ->
      SubscriptionPlan
      |> Ash.Changeset.for_create(:create, attrs)
      |> Ash.create!()

      IO.puts("  ✓ Created #{attrs.name} plan")

    [_] ->
      IO.puts("  - #{attrs.name} plan already exists, skipping")
  end
end

IO.puts("\n✅ Seeding complete!")
