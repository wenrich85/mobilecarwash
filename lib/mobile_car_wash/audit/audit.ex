defmodule MobileCarWash.Audit do
  @moduledoc """
  The Audit domain — security audit trail for every state change.
  """
  use Ash.Domain

  resources do
    resource MobileCarWash.Audit.AuditLog
  end
end
