defmodule MobileCarWash.Operations do
  @moduledoc """
  The Operations domain — technicians and vans.
  Minimal scaffold for MVP (single operator), full implementation in Phase 2.
  """
  use Ash.Domain

  resources do
    resource MobileCarWash.Operations.Technician
    resource MobileCarWash.Operations.Van
  end
end
