defmodule MobileCarWash.Accounts.Token do
  @moduledoc """
  Token resource for authentication (JWT storage for revocation).
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAuthentication.TokenResource]

  postgres do
    table("tokens")
    repo(MobileCarWash.Repo)
  end

  actions do
    defaults([:read, :destroy])
  end
end
