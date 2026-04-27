defmodule MobileCarWashWeb.MarketingComponentsTest do
  use ExUnit.Case, async: true
  import Phoenix.Component
  import Phoenix.LiveViewTest
  import MobileCarWashWeb.MarketingComponents

  describe "hero/1" do
    test "renders headline and subhead" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.hero headline="Big Promise" subhead="Small Detail">
          <:primary_cta>
            <a href="/booking">Book</a>
          </:primary_cta>
        </.hero>
        """)

      assert html =~ "Big Promise"
      assert html =~ "Small Detail"
      assert html =~ ~s(href="/booking")
    end

    test "renders trust badge when provided" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.hero headline="X" subhead="Y" trust_badge="LICENSED">
          <:primary_cta><a>Go</a></:primary_cta>
        </.hero>
        """)

      assert html =~ "LICENSED"
    end

    test "renders secondary_cta when provided" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.hero headline="X" subhead="Y">
          <:primary_cta><a href="/a">Primary</a></:primary_cta>
          <:secondary_cta><a href="/b">Secondary</a></:secondary_cta>
        </.hero>
        """)

      assert html =~ "Primary"
      assert html =~ "Secondary"
      assert html =~ ~s(href="/b")
    end
  end
end
