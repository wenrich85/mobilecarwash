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

  describe "tech_section/1" do
    test "renders eyebrow, headline, subhead" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.tech_section
          eyebrow="[ DIFF ]"
          headline="On-time arrival"
          subhead="15-min windows."
        >
          <:preview>SMS_PREVIEW_HERE</:preview>
        </.tech_section>
        """)

      assert html =~ "[ DIFF ]"
      assert html =~ "On-time arrival"
      assert html =~ "15-min windows."
      assert html =~ "SMS_PREVIEW_HERE"
    end

    test "renders bullets with arrow prefixes" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.tech_section
          headline="X"
          subhead="Y"
          bullets={["First point", "Second point"]}
        >
          <:preview>P</:preview>
        </.tech_section>
        """)

      assert html =~ "First point"
      assert html =~ "Second point"
    end
  end

  describe "testimonial/1" do
    test "renders quote and name" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.testimonial quote="Great service" name="Maria G." />
        """)

      assert html =~ "Great service"
      assert html =~ "Maria G."
    end

    test "renders vehicle when provided" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.testimonial quote="X" name="Y" vehicle="2023 Tesla" />
        """)

      assert html =~ "2023 Tesla"
    end

    test "omits vehicle row when not provided" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.testimonial quote="X" name="Y" />
        """)

      refute html =~ "Tesla"
    end
  end

  describe "cta_band/1" do
    test "renders headline, subhead, cta" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.cta_band headline="Ready?" subhead="No commitment.">
          <:cta><a href="/booking">Book</a></:cta>
        </.cta_band>
        """)

      assert html =~ "Ready?"
      assert html =~ "No commitment."
      assert html =~ ~s(href="/booking")
      assert html =~ ">Book<"
    end
  end
end
