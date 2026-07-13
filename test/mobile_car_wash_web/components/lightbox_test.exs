defmodule MobileCarWashWeb.LightboxTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias MobileCarWashWeb.Lightbox

  test "lightbox_root renders the hidden overlay skeleton with hook and a11y contract" do
    html = render_component(&Lightbox.lightbox_root/1, %{})

    assert html =~ ~s(id="lightbox-root")
    assert html =~ ~s(phx-hook="Lightbox")
    assert html =~ ~s(phx-update="ignore")
    assert html =~ ~s(role="dialog")
    assert html =~ ~s(aria-modal="true")
    assert html =~ ~s(aria-label="Photo viewer")

    # controls
    assert html =~ ~s(aria-label="Close photo viewer")
    assert html =~ ~s(aria-label="Previous photo")
    assert html =~ ~s(aria-label="Next photo")
    assert html =~ ~s(aria-live="polite")

    # stage parts the hook hydrates
    for role <-
          ~w(backdrop stage image slider-stage slider-before slider-after slider-divider load-error counter caption) do
      assert html =~ ~s(data-role="#{role}"), "missing data-role=#{role}"
    end
  end
end
