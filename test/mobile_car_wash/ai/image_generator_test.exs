defmodule MobileCarWash.AI.ImageGeneratorTest do
  @moduledoc """
  Marketing Phase 2C / Slice 1: OpenAI DALL-E 3 client.

  Pinned contract:
    * generate/1 takes a prompt string, returns {:ok, url} or
      {:error, reason}
    * returns {:error, :openai_not_configured} when no API key set
    * goes through the mock in test env — we NEVER hit OpenAI in CI
  """
  use ExUnit.Case, async: false

  alias MobileCarWash.AI.{ImageGenerator, ImageGeneratorMock}

  setup do
    ImageGeneratorMock.reset()

    original = Application.get_env(:mobile_car_wash, :image_generator)
    Application.put_env(:mobile_car_wash, :image_generator, ImageGeneratorMock)
    on_exit(fn -> Application.put_env(:mobile_car_wash, :image_generator, original) end)

    :ok
  end

  describe "generate/1" do
    test "returns the url the mock is configured to return" do
      ImageGeneratorMock.stub(:generate, fn _prompt ->
        {:ok, "https://example.com/fake-persona.png"}
      end)

      assert {:ok, "https://example.com/fake-persona.png"} =
               ImageGenerator.generate("a friendly customer")
    end

    test "bubbles up errors" do
      ImageGeneratorMock.stub(:generate, fn _prompt -> {:error, :rate_limited} end)

      assert {:error, :rate_limited} = ImageGenerator.generate("x")
    end

    test "records the prompt so tests can assert on it" do
      ImageGeneratorMock.stub(:generate, fn _prompt -> {:ok, "https://x/y.png"} end)
      _ = ImageGenerator.generate("Busy parent in a suburban driveway")

      assert ImageGeneratorMock.prompts() == ["Busy parent in a suburban driveway"]
    end
  end

  describe "real client (config-gated)" do
    test "returns :openai_not_configured when key absent" do
      # Route around the mock — test the real module's guard clause directly.
      Application.put_env(:mobile_car_wash, :image_generator, ImageGenerator)
      original_key = Application.get_env(:mobile_car_wash, :openai_api_key)
      Application.put_env(:mobile_car_wash, :openai_api_key, nil)

      on_exit(fn ->
        Application.put_env(:mobile_car_wash, :openai_api_key, original_key)
      end)

      assert {:error, :openai_not_configured} = ImageGenerator.generate("anything")
    end
  end
end
