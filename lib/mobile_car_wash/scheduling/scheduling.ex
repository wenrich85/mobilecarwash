defmodule MobileCarWash.Scheduling do
  @moduledoc """
  The Scheduling domain — service types, appointments, and availability.
  """
  use Ash.Domain

  resources do
    resource MobileCarWash.Scheduling.ServiceType
    resource MobileCarWash.Scheduling.Appointment
  end
end
