defmodule MobileCarWash.Accounts do
  @moduledoc """
  The Accounts domain — customer authentication and profiles.
  """
  use Ash.Domain

  resources do
    resource MobileCarWash.Accounts.Customer
    resource MobileCarWash.Accounts.Token
  end
end
