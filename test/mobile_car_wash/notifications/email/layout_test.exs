defmodule MobileCarWash.Notifications.Email.LayoutTest do
  use ExUnit.Case, async: true
  alias MobileCarWash.Notifications.Email.Layout

  describe "wrap_html/1" do
    test "produces a doctype html document" do
      html = Layout.wrap_html("<p>Hello</p>")
      assert html =~ "<!doctype html>"
      assert html =~ "<html"
      assert html =~ "</html>"
    end

    test "includes meta charset and viewport" do
      html = Layout.wrap_html("<p>Hi</p>")
      assert html =~ ~s(charset="utf-8")
      assert html =~ ~s(name="viewport")
    end

    test "includes the inline SVG logo in the header" do
      html = Layout.wrap_html("<p>Body</p>")
      assert html =~ "<svg"
      assert html =~ "Driveway Detail Co"
    end

    test "wraps the content_html in the body slot" do
      html = Layout.wrap_html(~s(<p class="signal">UNIQUE_BODY_CONTENT</p>))
      assert html =~ "UNIQUE_BODY_CONTENT"
    end

    test "footer contains the legal name" do
      html = Layout.wrap_html("<p>x</p>")
      assert html =~ "Driveway Detail Co. LLC"
      assert html =~ "San Antonio"
    end
  end
end
