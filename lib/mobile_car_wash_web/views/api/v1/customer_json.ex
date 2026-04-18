defmodule MobileCarWashWeb.Api.V1.CustomerJSON do
  @moduledoc "Serializes Customer records for the API — never exposes credentials."

  def render(customer) do
    %{
      id: customer.id,
      email: to_string(customer.email),
      name: customer.name,
      phone: customer.phone,
      sms_opt_in: customer.sms_opt_in,
      role: customer.role
    }
  end
end
