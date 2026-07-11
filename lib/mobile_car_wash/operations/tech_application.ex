defmodule MobileCarWash.Operations.TechApplication do
  @moduledoc """
  Private technician application tied to an existing Customer account.
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Operations,
    data_layer: AshPostgres.DataLayer

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Operations.Technician

  require Ash.Query

  @applicant_fields [
    :preferred_name,
    :phone,
    :home_zip,
    :preferred_zone,
    :availability_weekdays,
    :availability_weekends,
    :availability_mornings,
    :availability_afternoons,
    :availability_evenings,
    :experience_level,
    :has_valid_driver_license,
    :has_reliable_transportation,
    :can_lift_supplies,
    :desired_hours_per_week,
    :earliest_start_date,
    :emergency_contact_name,
    :emergency_contact_phone,
    :why_work_with_us,
    :experience_notes,
    :schedule_notes
  ]

  @admin_invite_fields @applicant_fields ++
                         [
                           :review_notes,
                           :decision_note,
                           :accepted_pay_rate_cents,
                           :accepted_pay_rate_pct,
                           :assigned_zone,
                           :van_id,
                           :active
                         ]

  postgres do
    table("tech_applications")
    repo(MobileCarWash.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :status, :atom do
      constraints(one_of: [:draft, :pending_review, :reviewed, :accepted, :not_accepted])
      default(:draft)
      allow_nil?(false)
      public?(true)
    end

    attribute :source, :atom do
      constraints(one_of: [:applicant, :admin_invite])
      default(:applicant)
      allow_nil?(false)
      public?(true)
    end

    attribute :preferred_name, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :phone, :string do
      public?(true)
    end

    attribute :home_zip, :string do
      public?(true)
    end

    attribute :preferred_zone, :atom do
      constraints(one_of: [:nw, :ne, :sw, :se])
      public?(true)
    end

    attribute :availability_weekdays, :boolean do
      default(false)
      allow_nil?(false)
      public?(true)
    end

    attribute :availability_weekends, :boolean do
      default(false)
      allow_nil?(false)
      public?(true)
    end

    attribute :availability_mornings, :boolean do
      default(false)
      allow_nil?(false)
      public?(true)
    end

    attribute :availability_afternoons, :boolean do
      default(false)
      allow_nil?(false)
      public?(true)
    end

    attribute :availability_evenings, :boolean do
      default(false)
      allow_nil?(false)
      public?(true)
    end

    attribute :experience_level, :atom do
      constraints(one_of: [:none, :some, :professional])
      default(:none)
      allow_nil?(false)
      public?(true)
    end

    attribute :has_valid_driver_license, :boolean do
      default(false)
      allow_nil?(false)
      public?(true)
    end

    attribute :has_reliable_transportation, :boolean do
      default(false)
      allow_nil?(false)
      public?(true)
    end

    attribute :can_lift_supplies, :boolean do
      default(false)
      allow_nil?(false)
      public?(true)
    end

    attribute :desired_hours_per_week, :integer do
      public?(true)
    end

    attribute :earliest_start_date, :date do
      public?(true)
    end

    attribute :emergency_contact_name, :string do
      public?(true)
    end

    attribute :emergency_contact_phone, :string do
      public?(true)
    end

    attribute :why_work_with_us, :string do
      public?(true)
    end

    attribute :experience_notes, :string do
      public?(true)
    end

    attribute :schedule_notes, :string do
      public?(true)
    end

    attribute :review_notes, :string do
      public?(true)
    end

    attribute :decision_note, :string do
      public?(true)
    end

    attribute :accepted_pay_rate_cents, :integer do
      public?(true)
    end

    attribute :accepted_pay_rate_pct, :decimal do
      public?(true)
    end

    attribute :assigned_zone, :atom do
      constraints(one_of: [:nw, :ne, :sw, :se])
      public?(true)
    end

    attribute :active, :boolean do
      default(true)
      allow_nil?(false)
      public?(true)
    end

    attribute :submitted_at, :utc_datetime_usec do
      public?(true)
    end

    attribute :reviewed_at, :utc_datetime_usec do
      public?(true)
    end

    attribute :decided_at, :utc_datetime_usec do
      public?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :customer, Customer do
      allow_nil?(false)
      public?(true)
    end

    belongs_to :van, MobileCarWash.Operations.Van do
      allow_nil?(true)
      attribute_writable?(true)
      public?(true)
    end
  end

  identities do
    identity(:unique_customer_application, [:customer_id])
  end

  actions do
    defaults([:read])

    create :create do
      accept(@applicant_fields)
      change(set_attribute(:status, :draft))
      change(set_attribute(:source, :applicant))
    end

    create :create_admin_invite do
      accept(@admin_invite_fields)
      change(set_attribute(:status, :accepted))
      change(set_attribute(:source, :admin_invite))
      change(set_attribute(:decided_at, &DateTime.utc_now/0))
    end

    read :for_customer do
      argument(:customer_id, :uuid, allow_nil?: false)
      filter(expr(customer_id == ^arg(:customer_id)))
    end

    update :save_draft do
      require_atomic?(false)
      accept(@applicant_fields)

      validate(fn changeset, _context ->
        validate_current_status(changeset, :draft, "save draft")
      end)

      change(set_attribute(:status, :draft))
    end

    update :submit do
      require_atomic?(false)
      validate(present([:preferred_name, :home_zip, :desired_hours_per_week]))
      validate(fn changeset, _context -> validate_current_status(changeset, :draft, "submit") end)
      change(set_attribute(:status, :pending_review))
      change(set_attribute(:submitted_at, &DateTime.utc_now/0))
    end

    update :mark_reviewed do
      require_atomic?(false)
      accept([:review_notes])

      validate(fn changeset, _context ->
        validate_current_status(changeset, :pending_review, "mark reviewed")
      end)

      change(set_attribute(:status, :reviewed))
      change(set_attribute(:reviewed_at, &DateTime.utc_now/0))
    end

    update :not_accept do
      require_atomic?(false)
      accept([:review_notes, :decision_note])

      validate(fn changeset, _context ->
        validate_current_status(changeset, :reviewed, "mark not accepted")
      end)

      change(set_attribute(:status, :not_accepted))
      change(set_attribute(:decided_at, &DateTime.utc_now/0))
    end

    update :accept do
      require_atomic?(false)

      accept([
        :review_notes,
        :decision_note,
        :accepted_pay_rate_cents,
        :accepted_pay_rate_pct,
        :assigned_zone,
        :van_id,
        :active
      ])

      validate(fn changeset, _context ->
        validate_current_status(changeset, :reviewed, "accept")
      end)

      change(set_attribute(:status, :accepted))
      change(set_attribute(:decided_at, &DateTime.utc_now/0))
      change(after_action(&promote_customer_to_technician/3))
    end
  end

  def applicant_fields do
    @applicant_fields
  end

  defp validate_current_status(changeset, expected_status, action_name) do
    case changeset.data.status do
      ^expected_status ->
        :ok

      current_status ->
        {:error,
         field: :status,
         message:
           "cannot #{action_name} from #{current_status || "unknown"}; expected #{expected_status}"}
    end
  end

  defp promote_customer_to_technician(_changeset, application, _context) do
    customer = Ash.get!(Customer, application.customer_id, authorize?: false)

    customer
    |> Ash.Changeset.for_update(:update, %{role: :technician})
    |> Ash.update!(authorize?: false)

    technician =
      Technician
      |> Ash.Query.filter(user_account_id == ^customer.id)
      |> Ash.read_one!(authorize?: false)

    attrs = %{
      name: application.preferred_name,
      phone: application.phone || customer.phone,
      active: application.active,
      zone: application.assigned_zone || application.preferred_zone,
      pay_rate_cents: application.accepted_pay_rate_cents || 2500,
      pay_rate_pct: application.accepted_pay_rate_pct,
      van_id: application.van_id
    }

    if technician do
      technician
      |> Ash.Changeset.for_update(:update, attrs)
      |> Ash.Changeset.force_change_attribute(:user_account_id, customer.id)
      |> Ash.update!(authorize?: false)
    else
      Technician
      |> Ash.Changeset.for_create(:create, attrs)
      |> Ash.Changeset.force_change_attribute(:user_account_id, customer.id)
      |> Ash.create!(authorize?: false)
    end

    {:ok, application}
  end
end
