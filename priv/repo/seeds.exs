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

# --- E-Myth: Org Positions ---

alias MobileCarWash.Operations.{OrgPosition, PositionContract, Procedure, ProcedureStep}

IO.puts("\nSeeding org positions...")

positions_data = [
  %{name: "Owner / CEO", slug: "owner", level: 0, sort_order: 1,
    description: "Strategic leadership, business development, financial oversight. Sets the vision and ensures all systems are working."},
  %{name: "Operations Manager", slug: "ops_manager", level: 1, sort_order: 2,
    description: "Manages day-to-day operations, scheduling, quality control, and technician training."},
  %{name: "Lead Technician", slug: "lead_tech", level: 2, sort_order: 3,
    description: "Senior wash technician. Trains new hires, handles complex details, ensures quality standards."},
  %{name: "Technician", slug: "technician", level: 2, sort_order: 4,
    description: "Performs car wash services following SOPs. Uses checklists for every appointment."},
  %{name: "Admin Assistant", slug: "admin_assistant", level: 1, sort_order: 5,
    description: "Handles scheduling, customer communication, invoicing, and compliance tracking."}
]

position_map =
  for attrs <- positions_data, into: %{} do
    existing = OrgPosition |> Ash.Query.filter(slug == ^attrs.slug) |> Ash.read!()

    pos = case existing do
      [] ->
        OrgPosition
        |> Ash.Changeset.for_create(:create, attrs)
        |> Ash.create!()
        |> tap(fn _ -> IO.puts("  ✓ #{attrs.name}") end)

      [p] ->
        IO.puts("  - #{attrs.name} (exists)")
        p
    end

    {attrs.slug, pos}
  end

# Set parent relationships
for {slug, parent_slug} <- [{"ops_manager", "owner"}, {"lead_tech", "ops_manager"}, {"technician", "ops_manager"}, {"admin_assistant", "owner"}] do
  child = position_map[slug]
  parent = position_map[parent_slug]
  if child && parent do
    child
    |> Ash.Changeset.for_update(:update, %{})
    |> Ash.Changeset.force_change_attribute(:parent_position_id, parent.id)
    |> Ash.update!()
  end
end

# --- E-Myth: Procedures (SOPs) ---

IO.puts("\nSeeding procedures...")

# Get service type IDs for linking
basic_wash_st = ServiceType |> Ash.Query.filter(slug == "basic_wash") |> Ash.read!() |> List.first()
deep_clean_st = ServiceType |> Ash.Query.filter(slug == "deep_clean") |> Ash.read!() |> List.first()

procedures_data = [
  %{
    name: "Basic Wash Procedure",
    slug: "basic_wash_sop",
    description: "Standard operating procedure for a basic exterior wash. Every step must be completed and checked off.",
    category: :wash,
    service_type_id: basic_wash_st && basic_wash_st.id,
    steps: [
      %{step_number: 1, title: "Vehicle Inspection", description: "Walk around vehicle. Note any existing damage, scratches, or dents. Take photos if needed. Alert customer of any pre-existing issues.", estimated_minutes: 3},
      %{step_number: 2, title: "Pre-Rinse", description: "Rinse entire vehicle with deionized water to remove loose dirt and debris. Start from top, work down.", estimated_minutes: 5},
      %{step_number: 3, title: "Apply Soap", description: "Apply car wash soap using foam cannon. Ensure full coverage on all panels, bumpers, and trim.", estimated_minutes: 3},
      %{step_number: 4, title: "Hand Wash / Scrub", description: "Using microfiber wash mitt, wash all panels in straight lines (not circles). Two-bucket method. Rinse mitt frequently.", estimated_minutes: 10},
      %{step_number: 5, title: "Rinse", description: "Thoroughly rinse all soap from vehicle with deionized water. Check for missed spots.", estimated_minutes: 5},
      %{step_number: 6, title: "Tire & Wheel Cleaning", description: "Clean wheels with wheel cleaner and brush. Clean tire sidewalls. Apply tire dressing.", estimated_minutes: 5},
      %{step_number: 7, title: "Dry", description: "Dry vehicle using clean microfiber drying towels. Use air blower for crevices and mirrors.", estimated_minutes: 8},
      %{step_number: 8, title: "Final Inspection", description: "Walk around vehicle for quality check. Ensure no water spots, streaks, or missed areas. Clean windows if needed.", estimated_minutes: 3}
    ]
  },
  %{
    name: "Deep Clean & Detail Procedure",
    slug: "deep_clean_sop",
    description: "Full interior and exterior detail procedure. Premium service with clay bar, wax, and full interior treatment.",
    category: :wash,
    service_type_id: deep_clean_st && deep_clean_st.id,
    steps: [
      %{step_number: 1, title: "Vehicle Inspection", description: "Comprehensive inspection inside and out. Document all existing damage. Photograph interior condition.", estimated_minutes: 5},
      %{step_number: 2, title: "Interior - Remove Trash & Personal Items", description: "Remove all trash. Set aside personal items carefully. Remove floor mats.", estimated_minutes: 5},
      %{step_number: 3, title: "Interior - Vacuum", description: "Vacuum all seats, carpets, floor mats, trunk, and crevices. Use detail brush for tight areas.", estimated_minutes: 15},
      %{step_number: 4, title: "Interior - Dashboard & Console", description: "Clean and condition dashboard, center console, door panels, and all plastic/vinyl surfaces.", estimated_minutes: 10},
      %{step_number: 5, title: "Interior - Leather/Upholstery", description: "Clean and condition leather seats (or shampoo fabric seats). Treat all seating surfaces.", estimated_minutes: 10},
      %{step_number: 6, title: "Interior - Carpet Shampoo", description: "Shampoo carpets and floor mats. Extract moisture. Allow to dry.", estimated_minutes: 10},
      %{step_number: 7, title: "Interior - Windows & Mirrors", description: "Clean all interior glass surfaces streak-free.", estimated_minutes: 5},
      %{step_number: 8, title: "Exterior - Pre-Rinse", description: "Rinse entire exterior with deionized water.", estimated_minutes: 5},
      %{step_number: 9, title: "Exterior - Foam & Hand Wash", description: "Foam cannon + two-bucket hand wash on all exterior panels.", estimated_minutes: 12},
      %{step_number: 10, title: "Exterior - Clay Bar Treatment", description: "Clay bar entire painted surface to remove bonded contaminants. Leaves paint glass-smooth.", estimated_minutes: 15},
      %{step_number: 11, title: "Exterior - Rinse & Dry", description: "Final rinse with deionized water. Hand dry with microfiber towels.", estimated_minutes: 8},
      %{step_number: 12, title: "Exterior - Wax / Sealant", description: "Apply carnauba wax or paint sealant to all painted surfaces. Buff to shine.", estimated_minutes: 15},
      %{step_number: 13, title: "Tires & Wheels", description: "Deep clean wheels, apply tire dressing.", estimated_minutes: 5},
      %{step_number: 14, title: "Engine Bay", description: "Carefully degrease and clean engine bay. Cover sensitive electronics. Rinse and dress.", estimated_minutes: 10, required: false},
      %{step_number: 15, title: "Final Inspection", description: "Complete walk-around inside and out. Check every surface. Ensure customer satisfaction standards met.", estimated_minutes: 5}
    ]
  }
]

for proc_data <- procedures_data do
  {steps_data, proc_attrs} = Map.pop(proc_data, :steps)

  existing = Procedure |> Ash.Query.filter(slug == ^proc_attrs.slug) |> Ash.read!()

  case existing do
    [] ->
      # Create procedure
      changeset = Procedure |> Ash.Changeset.for_create(:create, Map.drop(proc_attrs, [:service_type_id]))

      changeset = if proc_attrs[:service_type_id] do
        Ash.Changeset.force_change_attribute(changeset, :service_type_id, proc_attrs.service_type_id)
      else
        changeset
      end

      proc = Ash.create!(changeset)
      IO.puts("  ✓ #{proc_attrs.name}")

      # Create steps
      for step_attrs <- steps_data do
        ProcedureStep
        |> Ash.Changeset.for_create(:create, step_attrs)
        |> Ash.Changeset.force_change_attribute(:procedure_id, proc.id)
        |> Ash.create!()
      end

      IO.puts("    → #{length(steps_data)} steps created")

    [_] ->
      IO.puts("  - #{proc_attrs.name} (exists)")
  end
end

# --- Technicians ---

alias MobileCarWash.Operations.Technician

IO.puts("\nSeeding technicians...")

for attrs <- [
      %{name: "Owner", phone: "512-555-0001", active: true}
    ] do
  existing = Technician |> Ash.Query.filter(name == ^attrs.name) |> Ash.read!()

  case existing do
    [] ->
      Technician |> Ash.Changeset.for_create(:create, attrs) |> Ash.create!()
      IO.puts("  ✓ #{attrs.name}")

    [_] ->
      IO.puts("  - #{attrs.name} (exists)")
  end
end

# --- Demo Accounts ---

alias MobileCarWash.Accounts.Customer

IO.puts("\nSeeding demo accounts...")

demo_accounts = [
  %{email: "customer@demo.com", name: "Jane Customer", phone: "512-555-1001", role: :customer},
  %{email: "tech@demo.com", name: "Owner", phone: "512-555-0001", role: :technician},
  %{email: "admin@mobilecarwash.com", name: "Admin Owner", phone: "512-555-0000", role: :admin}
]

for attrs <- demo_accounts do
  existing = Customer |> Ash.Query.filter(email == ^attrs.email) |> Ash.read!()

  case existing do
    [] ->
      {:ok, user} =
        Customer
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: attrs.email,
          password: "Password123!",
          password_confirmation: "Password123!",
          name: attrs.name,
          phone: attrs.phone
        })
        |> Ash.create()

      # Set role via direct Ecto update (role not in register action)
      if attrs.role != :customer do
        import Ecto.Query
        MobileCarWash.Repo.update_all(
          from(c in "customers", where: c.id == type(^user.id, :binary_id)),
          set: [role: to_string(attrs.role)]
        )
      end

      IO.puts("  ✓ #{attrs.email} (#{attrs.role})")

    [existing_user] ->
      # Update role if needed
      if existing_user.role != attrs.role do
        import Ecto.Query
        MobileCarWash.Repo.update_all(
          from(c in "customers", where: c.id == type(^existing_user.id, :binary_id)),
          set: [role: to_string(attrs.role)]
        )
        IO.puts("  ↻ #{attrs.email} role updated to #{attrs.role}")
      else
        IO.puts("  - #{attrs.email} (exists)")
      end
  end
end

IO.puts("\nDemo login credentials:")
IO.puts("  Customer:   customer@demo.com / Password123!")
IO.puts("  Technician: tech@demo.com / Password123!")
IO.puts("  Admin:      admin@mobilecarwash.com / Password123!")

IO.puts("\n✅ Seeding complete!")
