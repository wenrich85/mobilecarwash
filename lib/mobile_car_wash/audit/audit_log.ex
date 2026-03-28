defmodule MobileCarWash.Audit.AuditLog do
  @moduledoc """
  Immutable audit trail. Records every meaningful state change
  for security forensics and compliance.

  Examples:
  - appointment.created, appointment.status_changed
  - subscription.started, subscription.cancelled
  - customer.updated (with before/after diff)
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Audit,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "audit_logs"
    repo MobileCarWash.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :actor_id, :uuid do
      public? true
      description "The user or system that performed the action"
    end

    attribute :actor_type, :string do
      default "system"
      public? true
      description "customer, system, admin"
    end

    attribute :action, :string do
      allow_nil? false
      public? true
      description "e.g. appointment.created, subscription.cancelled"
    end

    attribute :resource_type, :string do
      allow_nil? false
      public? true
    end

    attribute :resource_id, :uuid do
      public? true
    end

    attribute :metadata, :map do
      default %{}
      public? true
      description "IP address, user agent, UTM params, etc."
    end

    attribute :changes, :map do
      default %{}
      public? true
      description "Before/after diff of changed fields"
    end

    create_timestamp :inserted_at
  end

  actions do
    defaults [:read]

    create :log do
      accept [
        :actor_id,
        :actor_type,
        :action,
        :resource_type,
        :resource_id,
        :metadata,
        :changes
      ]
    end
  end
end
