defmodule MobileCarWashWeb.CoreComponentsTest do
  use ExUnit.Case, async: true
  import Phoenix.Component
  import Phoenix.LiveViewTest
  import MobileCarWashWeb.CoreComponents

  describe "button/1" do
    test "renders primary variant by default" do
      assigns = %{}
      html = rendered_to_string(~H|<.button>Click</.button>|)
      assert html =~ ~s(class=)
      assert html =~ "btn-primary"
      assert html =~ "Click"
    end

    test "renders secondary variant" do
      assigns = %{}
      html = rendered_to_string(~H|<.button variant="secondary">Save</.button>|)
      assert html =~ "btn-secondary"
    end

    test "renders ghost variant" do
      assigns = %{}
      html = rendered_to_string(~H|<.button variant="ghost">Cancel</.button>|)
      assert html =~ "btn-ghost"
    end

    test "renders destructive variant" do
      assigns = %{}
      html = rendered_to_string(~H|<.button variant="destructive">Delete</.button>|)
      assert html =~ "btn-error"
    end

    test "renders size sm" do
      assigns = %{}
      html = rendered_to_string(~H|<.button size="sm">Small</.button>|)
      assert html =~ "btn-sm"
    end

    test "renders size lg" do
      assigns = %{}
      html = rendered_to_string(~H|<.button size="lg">Large</.button>|)
      assert html =~ "btn-lg"
    end

    test "renders link when navigate set" do
      assigns = %{}
      html = rendered_to_string(~H|<.button navigate="/foo">Go</.button>|)
      assert html =~ ~s(href="/foo")
    end
  end
end
