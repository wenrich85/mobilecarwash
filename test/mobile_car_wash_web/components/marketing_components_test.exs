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

  describe "service_tier_card/1" do
    test "renders name, price, duration, features" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.service_tier_card
          name="Basic Wash"
          price="$50"
          duration="~45 min"
          features={["Exterior hand wash", "Wheels & tires"]}
        >
          <:cta><a href="/booking?tier=basic">Book Basic</a></:cta>
        </.service_tier_card>
        """)

      assert html =~ "Basic Wash"
      assert html =~ "$50"
      assert html =~ "~45 min"
      assert html =~ "Exterior hand wash"
      assert html =~ "Wheels &amp; tires"
      assert html =~ "Book Basic"
    end

    test "renders highlighted variant with MOST POPULAR badge" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.service_tier_card
          name="Premium"
          price="$199.99"
          duration="~3 hours"
          features={["Everything in Basic"]}
          highlighted={true}
        >
          <:cta><a>Book Premium</a></:cta>
        </.service_tier_card>
        """)

      assert html =~ "MOST POPULAR"
      assert html =~ "border-cyan-500"
    end

    test "non-highlighted card omits MOST POPULAR badge" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.service_tier_card name="Basic" price="$50" duration="~45 min" features={[]}>
          <:cta><a>Book</a></:cta>
        </.service_tier_card>
        """)

      refute html =~ "MOST POPULAR"
    end
  end
end
