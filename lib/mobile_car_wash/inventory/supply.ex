defmodule MobileCarWash.Inventory.Supply do
  @moduledoc """
  A supply item used during car washes (chemicals, equipment, disposables, etc.).
  Quantity is tracked on-hand; restocking triggers an automatic cash flow expense.
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Inventory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "supplies"
    repo MobileCarWash.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :category, :atom do
      constraints one_of: [:chemicals, :equipment, :disposables, :safety, :other]
      default :other
      allow_nil? false
      public? true
    end

    attribute :unit, :string do
      default "units"
      allow_nil? false
      public? true
      description "Unit of measure: gallons, oz, bottles, boxes, etc."
    end

    attribute :quantity_on_hand, :decimal do
      default 0
      allow_nil? false
      public? true
    end

    attribute :low_stock_threshold, :decimal do
      allow_nil? true
      public? true
      description "Alert when quantity drops at or below this level. Nil = no alert."
    end

    attribute :unit_cost_cents, :integer do
      allow_nil? true
      public? true
      description "Default cost per unit in cents. Used as a starting point for restock forms."
    end

    attribute :supplier, :string do
      allow_nil? true
      public? true
    end

    attribute :notes, :string do
      allow_nil? true
      public? true
    end

    attribute :active, :boolean do
      default true
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  actions do
    defaults [:read]

    create :create do
      accept [:name, :category, :unit, :quantity_on_hand, :low_stock_threshold,
              :unit_cost_cents, :supplier, :notes, :active]
    end

    update :update do
      accept [:name, :category, :unit, :low_stock_threshold,
              :unit_cost_cents, :supplier, :notes, :active]
    end

    # Adds stock; caller is responsible for recording the cash flow expense.
    update :restock do
      accept []
      argument :quantity, :decimal, allow_nil?: false
      require_atomic? false

      change fn changeset, _ ->
        qty = Ash.Changeset.get_argument(changeset, :quantity)
        current = Ash.Changeset.get_data(changeset, :quantity_on_hand) || Decimal.new(0)
        Ash.Changeset.change_attribute(changeset, :quantity_on_hand, Decimal.add(current, qty))
      end
    end

    # Reduces stock; does not record cash flow (consumption is a normal opex covered by the expense account).
    update :use_quantity do
      accept []
      argument :quantity, :decimal, allow_nil?: false
      require_atomic? false

      change fn changeset, _ ->
        qty = Ash.Changeset.get_argument(changeset, :quantity)
        current = Ash.Changeset.get_data(changeset, :quantity_on_hand) || Decimal.new(0)
        new_qty = Decimal.sub(current, qty)
        Ash.Changeset.change_attribute(changeset, :quantity_on_hand, new_qty)
      end
    end
  end
end
