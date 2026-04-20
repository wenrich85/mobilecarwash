defmodule MobileCarWash.Fleet do
  @moduledoc """
  The Fleet domain — customer vehicles and service addresses.
  """
  use Ash.Domain

  resources do
    resource(MobileCarWash.Fleet.Vehicle)
    resource(MobileCarWash.Fleet.Address)
  end
end
