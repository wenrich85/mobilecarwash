defmodule MobileCarWashWeb.ChannelCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint MobileCarWashWeb.Endpoint

      use Phoenix.ChannelTest
      import MobileCarWashWeb.ChannelCase
    end
  end

  setup tags do
    MobileCarWash.DataCase.setup_sandbox(tags)
    :ok
  end
end
