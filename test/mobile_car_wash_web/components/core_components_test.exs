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

  describe "progress_bar/1" do
    test "renders cyan variant by default at given value" do
      assigns = %{}
      html = rendered_to_string(~H|<.progress_bar value={0.42} />|)
      assert html =~ "bg-cyan-500"
      assert html =~ "width: 42%"
    end

    test "renders amber variant" do
      assigns = %{}
      html = rendered_to_string(~H|<.progress_bar value={0.8} variant={:amber} />|)
      assert html =~ "bg-warning"
      assert html =~ "width: 80%"
    end

    test "renders green variant" do
      assigns = %{}
      html = rendered_to_string(~H|<.progress_bar value={1.0} variant={:green} />|)
      assert html =~ "bg-success"
      assert html =~ "width: 100%"
    end

    test "renders red variant" do
      assigns = %{}
      html = rendered_to_string(~H|<.progress_bar value={0.05} variant={:red} />|)
      assert html =~ "bg-error"
      assert html =~ "width: 5%"
    end

    test "clamps value above 1.0 to 100%" do
      assigns = %{}
      html = rendered_to_string(~H|<.progress_bar value={1.5} />|)
      assert html =~ "width: 100%"
    end

    test "clamps value below 0 to 0%" do
      assigns = %{}
      html = rendered_to_string(~H|<.progress_bar value={-0.2} />|)
      assert html =~ "width: 0%"
    end
  end

  describe "empty_state/1" do
    test "renders icon, title, body" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.empty_state icon="hero-inbox" title="Nothing here yet" body="Once you book, it'll show up here." />
        """)

      assert html =~ "hero-inbox"
      assert html =~ "Nothing here yet"
      assert html =~ "Once you book"
    end

    test "renders action slot" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.empty_state icon="hero-inbox" title="Empty" body="Add one.">
          <:action>
            <button>Add</button>
          </:action>
        </.empty_state>
        """)

      assert html =~ "<button>Add</button>"
    end
  end

  describe "kpi_card/1" do
    test "renders label and value" do
      assigns = %{}
      html = rendered_to_string(~H|<.kpi_card label="Cash on hand" value="$24,807" />|)
      assert html =~ "Cash on hand"
      assert html =~ "$24,807"
      assert html =~ "font-mono"
    end

    test "renders positive delta" do
      assigns = %{}
      html = rendered_to_string(~H|<.kpi_card label="Cash" value="$10" delta="+12.4%" delta_direction={:up} />|)
      assert html =~ "+12.4%"
      assert html =~ "text-success"
    end

    test "renders negative delta" do
      assigns = %{}
      html = rendered_to_string(~H|<.kpi_card label="Cash" value="$10" delta="-3.1%" delta_direction={:down} />|)
      assert html =~ "-3.1%"
      assert html =~ "text-error"
    end

    test "renders subtext" do
      assigns = %{}
      html = rendered_to_string(~H|<.kpi_card label="Cash" value="$10" subtext="vs last month" />|)
      assert html =~ "vs last month"
    end
  end

  describe "bucket_card/1" do
    test "renders label, amount, target percent, status pill" do
      assigns = %{}

      html =
        rendered_to_string(
          ~H|<.bucket_card label="Operating" amount="$8,420" target="of $10,000 goal" target_pct={0.84} status={:on_target} status_label="On target" />|
        )

      assert html =~ "Operating"
      assert html =~ "$8,420"
      assert html =~ "of $10,000 goal"
      assert html =~ "On target"
      assert html =~ "width: 84%"
    end

    test "renders underfunded status with amber bar" do
      assigns = %{}

      html =
        rendered_to_string(
          ~H|<.bucket_card label="Tax" amount="$3,150" target="of $5,000 goal" target_pct={0.63} status={:underfunded} status_label="Underfunded" />|
        )

      assert html =~ "bg-warning"
      assert html =~ "Underfunded"
    end

    test "renders empty progress bar when target_pct is nil" do
      assigns = %{}

      html =
        rendered_to_string(
          ~H|<.bucket_card label="Investment" amount="$0" target="no goal set" target_pct={nil} status={:long_term} status_label="Long-term" />|
        )

      refute html =~ "width: 0%"
      # Empty bar has no inner width div at all
      assert html =~ "Long-term"
    end
  end
end
