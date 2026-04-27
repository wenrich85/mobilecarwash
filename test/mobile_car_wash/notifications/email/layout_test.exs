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

  describe "wrap_text/1" do
    test "produces header with brand name and separator" do
      text = Layout.wrap_text("Hello.")
      assert text =~ "Driveway Detail Co"
      assert text =~ "================="
    end

    test "includes the body content" do
      text = Layout.wrap_text("UNIQUE_TEXT_BODY")
      assert text =~ "UNIQUE_TEXT_BODY"
    end

    test "footer mentions the legal name" do
      text = Layout.wrap_text("body")
      assert text =~ "Driveway Detail Co. LLC"
      assert text =~ "San Antonio"
    end
  end
end
