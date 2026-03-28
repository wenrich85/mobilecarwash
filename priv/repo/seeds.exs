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

# --- Business Formation Categories ---

alias MobileCarWash.Compliance.TaskCategory
alias MobileCarWash.Compliance.FormationTask

IO.puts("\nSeeding business formation categories...")

categories =
  for attrs <- [
        %{name: "Texas State Formation", slug: "tx_state", sort_order: 1, description: "State-level business formation requirements for Texas"},
        %{name: "Federal Requirements", slug: "federal", sort_order: 2, description: "Federal tax, banking, and insurance requirements"},
        %{name: "Disabled Veteran Certifications", slug: "veteran_certs", sort_order: 3, description: "VA and SBA certifications for 100% disabled veteran-owned business"},
        %{name: "Compliance & Renewals", slug: "compliance_renewals", sort_order: 4, description: "Recurring filings, renewals, and ongoing compliance"}
      ] do
    existing =
      TaskCategory
      |> Ash.Query.filter(slug == ^attrs.slug)
      |> Ash.read!()

    case existing do
      [] ->
        cat =
          TaskCategory
          |> Ash.Changeset.for_create(:create, attrs)
          |> Ash.create!()

        IO.puts("  ✓ Created category: #{attrs.name}")
        cat

      [cat] ->
        IO.puts("  - #{attrs.name} already exists, skipping")
        cat
    end
  end

cat_map = Map.new(categories, &{&1.slug, &1.id})

# --- Business Formation Tasks ---

IO.puts("\nSeeding formation tasks...")

formation_tasks = [
  # Texas State Formation
  %{name: "LLC Filing with TX Secretary of State", category_slug: "tx_state", priority: :high,
    description: "File Certificate of Formation (Form 205) with the Texas Secretary of State. Filing fee ~$300.",
    external_url: "https://www.sos.state.tx.us/corp/forms_702.shtml"},
  %{name: "Registered Agent Designation", category_slug: "tx_state", priority: :high,
    description: "Designate a registered agent in Texas to receive legal documents on behalf of the LLC."},
  %{name: "TX Sales Tax Permit", category_slug: "tx_state", priority: :high,
    description: "Apply for a Texas Sales and Use Tax Permit from the Comptroller. Required before collecting sales tax.",
    external_url: "https://comptroller.texas.gov/taxes/permit/"},
  %{name: "TX Franchise Tax Registration", category_slug: "tx_state", priority: :high,
    description: "Register for Texas franchise tax. All LLCs must file an annual franchise tax report."},
  %{name: "Business License / DBA Filing", category_slug: "tx_state", priority: :medium,
    description: "File assumed name certificate (DBA) with the county clerk if operating under a trade name."},
  %{name: "TX Workers Compensation Coverage", category_slug: "tx_state", priority: :low,
    description: "Texas does not require workers comp for most employers, but consider it when hiring employees."},

  # Federal Requirements
  %{name: "EIN from IRS", category_slug: "federal", priority: :high,
    description: "Apply for an Employer Identification Number online. Required for tax filing, banking, and hiring.",
    external_url: "https://www.irs.gov/businesses/small-businesses-self-employed/apply-for-an-employer-identification-number-ein-online"},
  %{name: "Federal Tax Obligations Setup", category_slug: "federal", priority: :high,
    description: "Determine federal tax obligations: self-employment tax, estimated quarterly taxes, income tax."},
  %{name: "Business Bank Account", category_slug: "federal", priority: :high,
    description: "Open a dedicated business checking account. Keep personal and business finances separate."},
  %{name: "General Liability Insurance", category_slug: "federal", priority: :high,
    description: "Obtain general liability insurance to protect against property damage and injury claims."},
  %{name: "Commercial Auto Insurance", category_slug: "federal", priority: :high,
    description: "Insure the service van with commercial auto insurance. Personal auto policies don't cover business use."},

  # Disabled Veteran Certifications
  %{name: "VA Disability Rating Verification (100%)", category_slug: "veteran_certs", priority: :high,
    description: "Obtain and keep current your VA disability rating letter showing 100% service-connected disability."},
  %{name: "SBA VOSB Certification", category_slug: "veteran_certs", priority: :high,
    description: "Apply for Veteran-Owned Small Business (VOSB) certification through SBA's VetCert program.",
    external_url: "https://veteransbusiness.sba.gov/"},
  %{name: "SBA SDVOSB Certification", category_slug: "veteran_certs", priority: :high,
    description: "Apply for Service-Disabled Veteran-Owned Small Business (SDVOSB) certification. Opens federal contracting opportunities.",
    external_url: "https://veteransbusiness.sba.gov/"},
  %{name: "TX HUB Certification", category_slug: "veteran_certs", priority: :high,
    description: "Apply for Historically Underutilized Business (HUB) certification with the TX Comptroller. Qualifies for state contracting preferences.",
    external_url: "https://comptroller.texas.gov/purchasing/vendor/hub/"},
  %{name: "Property Tax Exemption - TX Disabled Veteran", category_slug: "veteran_certs", priority: :medium,
    description: "Apply for property tax exemption available to 100% disabled veterans in Texas. File with county appraisal district."},
  %{name: "TX Franchise Tax Exemption (Disabled Veteran)", category_slug: "veteran_certs", priority: :medium,
    description: "100% disabled veterans may qualify for a total franchise tax exemption in Texas. File exemption request with Comptroller."},

  # Compliance & Renewals
  %{name: "Annual TX Franchise Tax Report", category_slug: "compliance_renewals", priority: :high,
    recurring: true, recurrence_months: 12, due_date: ~D[2027-05-15],
    description: "File annual franchise tax report by May 15. Even exempt businesses must file a No Tax Due report."},
  %{name: "Registered Agent Renewal", category_slug: "compliance_renewals", priority: :medium,
    recurring: true, recurrence_months: 12,
    description: "Renew or confirm registered agent designation annually."},
  %{name: "Business Insurance Renewal", category_slug: "compliance_renewals", priority: :high,
    recurring: true, recurrence_months: 12,
    description: "Renew general liability and commercial auto insurance policies before expiration."},
  %{name: "Quarterly Sales Tax Filing", category_slug: "compliance_renewals", priority: :high,
    recurring: true, recurrence_months: 3, due_date: ~D[2026-07-20],
    description: "File quarterly sales tax report with TX Comptroller. Due 20th of month following quarter end."},
  %{name: "Environmental Compliance - Water Disposal", category_slug: "compliance_renewals", priority: :medium,
    description: "Ensure compliance with TX water disposal regulations for mobile car wash operations. Collect and properly dispose of wash water."}
]

for attrs <- formation_tasks do
  {category_slug, task_attrs} = Map.pop(attrs, :category_slug)
  category_id = Map.fetch!(cat_map, category_slug)
  task_attrs = Map.put(task_attrs, :category_id, category_id)

  existing =
    FormationTask
    |> Ash.Query.filter(name == ^task_attrs.name)
    |> Ash.read!()

  case existing do
    [] ->
      {cat_id, create_attrs} = Map.pop(task_attrs, :category_id)

      FormationTask
      |> Ash.Changeset.for_create(:create, create_attrs)
      |> Ash.Changeset.force_change_attribute(:category_id, cat_id)
      |> Ash.create!()

      IO.puts("  ✓ #{task_attrs.name}")

    [_] ->
      IO.puts("  - #{task_attrs.name} (exists)")
  end
end

IO.puts("\n✅ Seeding complete!")
