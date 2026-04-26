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

  describe "input/1" do
    test "renders text input with label" do
      assigns = %{}
      html = rendered_to_string(~H|<.input name="email" label="Email" value="" />|)
      assert html =~ ~s(name="email")
      assert html =~ "Email"
      assert html =~ "input"
      assert html =~ "input-bordered"
    end

    test "renders textarea variant" do
      assigns = %{}
      html = rendered_to_string(~H|<.input type="textarea" name="msg" label="Message" value="" />|)
      assert html =~ "<textarea"
      assert html =~ "textarea-bordered"
    end

    test "renders select variant" do
      assigns = %{}
      html = rendered_to_string(~H|<.input type="select" name="tier" label="Tier" value="basic" options={[{"Basic", "basic"}, {"Premium", "premium"}]} />|)
      assert html =~ "<select"
      assert html =~ "select-bordered"
      assert html =~ "Basic"
      assert html =~ "Premium"
    end

    test "renders checkbox variant" do
      assigns = %{}
      html = rendered_to_string(~H|<.input type="checkbox" name="agree" label="I agree" checked={false} />|)
      assert html =~ ~s(type="checkbox")
      assert html =~ "checkbox"
    end

    test "shows error messages when errors present" do
      assigns = %{}
      html = rendered_to_string(~H|<.input name="email" label="Email" value="" errors={["can't be blank"]} />|)
      assert html =~ "can&#39;t be blank"
    end
  end

  describe "flash/1" do
    test "renders info kind" do
      assigns = %{}
      html = rendered_to_string(~H|<.flash kind={:info}>Saved.</.flash>|)
      assert html =~ "alert-info"
      assert html =~ "Saved."
    end

    test "renders error kind" do
      assigns = %{}
      html = rendered_to_string(~H|<.flash kind={:error}>Bad.</.flash>|)
      assert html =~ "alert-error"
      assert html =~ "Bad."
    end

    test "renders success kind" do
      assigns = %{}
      html = rendered_to_string(~H|<.flash kind={:success}>Ok.</.flash>|)
      assert html =~ "alert-success"
      assert html =~ "Ok."
    end

    test "renders warning kind" do
      assigns = %{}
      html = rendered_to_string(~H|<.flash kind={:warning}>Heads up.</.flash>|)
      assert html =~ "alert-warning"
      assert html =~ "Heads up."
    end
  end

  describe "table/1" do
    test "renders rows and headers" do
      rows = [%{name: "Alice", role: "Admin"}, %{name: "Bob", role: "Tech"}]
      assigns = %{rows: rows}

      html =
        rendered_to_string(~H"""
        <.table id="users" rows={@rows}>
          <:col :let={u} label="Name">{u.name}</:col>
          <:col :let={u} label="Role">{u.role}</:col>
        </.table>
        """)

      assert html =~ "Name"
      assert html =~ "Role"
      assert html =~ "Alice"
      assert html =~ "Bob"
      assert html =~ "Admin"
      assert html =~ "Tech"
    end
  end

  describe "header/1" do
    test "renders title and subtitle" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.header>
          Page title
          <:subtitle>Helpful description</:subtitle>
        </.header>
        """)

      assert html =~ "Page title"
      assert html =~ "Helpful description"
    end

    test "renders actions slot" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.header>
          Stuff
          <:actions>
            <button>New</button>
          </:actions>
        </.header>
        """)

      assert html =~ "Stuff"
      assert html =~ "<button>New</button>"
    end
  end

  describe "modal/1" do
    test "renders with title and body" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.modal id="test-modal">
          <:title>Confirm</:title>
          Are you sure?
        </.modal>
        """)

      assert html =~ ~s(id="test-modal")
      assert html =~ "Confirm"
      assert html =~ "Are you sure?"
    end

    test "renders footer slot" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.modal id="m">
          <:title>Hi</:title>
          Body
          <:footer>
            <button>OK</button>
          </:footer>
        </.modal>
        """)

      assert html =~ "<button>OK</button>"
    end
  end

  describe "status_pill/1" do
    test "renders on_target as success" do
      assigns = %{}
      html = rendered_to_string(~H|<.status_pill status={:on_target}>On target</.status_pill>|)
      assert html =~ "bg-success/15"
      assert html =~ "text-success"
      assert html =~ "On target"
    end

    test "renders underfunded as warning" do
      assigns = %{}
      html = rendered_to_string(~H|<.status_pill status={:underfunded}>Underfunded</.status_pill>|)
      assert html =~ "bg-warning/15"
      assert html =~ "text-warning"
    end

    test "renders paid as success" do
      assigns = %{}
      html = rendered_to_string(~H|<.status_pill status={:paid}>Paid</.status_pill>|)
      assert html =~ "bg-success/15"
    end

    test "renders over as error" do
      assigns = %{}
      html = rendered_to_string(~H|<.status_pill status={:over}>Over</.status_pill>|)
      assert html =~ "bg-error/15"
    end

    test "renders long_term as neutral" do
      assigns = %{}
      html = rendered_to_string(~H|<.status_pill status={:long_term}>Long-term</.status_pill>|)
      assert html =~ "bg-base-200"
    end
  end
end
