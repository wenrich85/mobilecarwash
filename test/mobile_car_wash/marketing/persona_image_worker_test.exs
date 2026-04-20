defmodule MobileCarWash.Marketing.PersonaImageWorkerTest do
  @moduledoc """
  Marketing Phase 2C / Slice 2: the Oban worker that generates a
  DALL-E image for a persona, stamps the URL onto the record, and
  broadcasts `{:persona_image_ready, id}` over PubSub.
  """
  use MobileCarWash.DataCase, async: false
  use Oban.Testing, repo: MobileCarWash.Repo

  alias MobileCarWash.AI.ImageGeneratorMock
  alias MobileCarWash.Marketing.{Persona, PersonaImageWorker}

  setup do
    ImageGeneratorMock.reset()
    :ok
  end

  defp create_persona!(attrs \\ %{}) do
    defaults = %{
      slug: "img_#{System.unique_integer([:positive])}",
      name: "Image Test",
      description: "An exuberant weekend detailer in their driveway",
      image_prompt: nil
    }

    {:ok, persona} =
      Persona
      |> Ash.Changeset.for_create(:create, Map.merge(defaults, attrs))
      |> Ash.create(authorize?: false)

    persona
  end

  describe "perform/1" do
    test "stamps image_url onto the persona on success" do
      persona = create_persona!()

      ImageGeneratorMock.stub(:generate, fn _prompt ->
        {:ok, "https://example.com/generated.png"}
      end)

      assert :ok =
               perform_job(PersonaImageWorker, %{"persona_id" => persona.id})

      {:ok, reloaded} = Ash.get(Persona, persona.id, authorize?: false)
      assert reloaded.image_url == "https://example.com/generated.png"
    end

    test "passes the image_prompt when set, else falls back to description" do
      persona =
        create_persona!(%{
          description: "ignored if prompt is set",
          image_prompt: "explicit visual prompt"
        })

      ImageGeneratorMock.stub(:generate, fn _prompt -> {:ok, "https://x/y.png"} end)
      assert :ok = perform_job(PersonaImageWorker, %{"persona_id" => persona.id})

      assert "explicit visual prompt" in ImageGeneratorMock.prompts()
    end

    test "falls back to description when image_prompt is nil" do
      persona = create_persona!(%{description: "friendly 35yo in suburban driveway"})

      ImageGeneratorMock.stub(:generate, fn _prompt -> {:ok, "https://x/y.png"} end)
      assert :ok = perform_job(PersonaImageWorker, %{"persona_id" => persona.id})

      assert "friendly 35yo in suburban driveway" in ImageGeneratorMock.prompts()
    end

    test "returns {:error, reason} to let Oban retry on generator failure" do
      persona = create_persona!()
      ImageGeneratorMock.stub(:generate, fn _ -> {:error, :rate_limited} end)

      assert {:error, :rate_limited} =
               perform_job(PersonaImageWorker, %{"persona_id" => persona.id})
    end

    test "no-ops gracefully on missing persona" do
      assert :ok =
               perform_job(PersonaImageWorker, %{
                 "persona_id" => Ecto.UUID.generate()
               })
    end

    test "broadcasts :persona_image_ready after successful save" do
      persona = create_persona!()
      Phoenix.PubSub.subscribe(MobileCarWash.PubSub, "persona:#{persona.id}")

      ImageGeneratorMock.stub(:generate, fn _ -> {:ok, "https://x/ready.png"} end)
      :ok = perform_job(PersonaImageWorker, %{"persona_id" => persona.id})

      assert_receive {:persona_image_ready, persona_id, "https://x/ready.png"}, 500
      assert persona_id == persona.id
    end
  end
end
