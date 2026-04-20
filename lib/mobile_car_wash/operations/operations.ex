defmodule MobileCarWash.Operations do
  @moduledoc """
  The Operations domain — E-Myth franchise prototype systems.

  Includes: org chart, position contracts, SOPs (procedures),
  live appointment checklists, technicians, and vans.
  """
  use Ash.Domain

  resources do
    resource(MobileCarWash.Operations.Technician)
    resource(MobileCarWash.Operations.Van)
    resource(MobileCarWash.Operations.OrgPosition)
    resource(MobileCarWash.Operations.PositionContract)
    resource(MobileCarWash.Operations.Procedure)
    resource(MobileCarWash.Operations.ProcedureStep)
    resource(MobileCarWash.Operations.AppointmentChecklist)
    resource(MobileCarWash.Operations.ChecklistItem)
    resource(MobileCarWash.Operations.Photo)
  end
end
