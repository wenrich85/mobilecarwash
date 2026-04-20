defmodule MobileCarWash.Marketing.PersonaImageWorker do
  @moduledoc """
  Oban worker that generates a DALL-E image for a Persona and stamps
  the resulting URL onto the record.

  Runs off the `:ai` queue (separate from :notifications so a
  run-away image-gen loop can't block customer-facing notifications).

  Prompt precedence: `persona.image_prompt` (if set) > `persona.description`.
  On success, broadcasts `{:persona_image_ready, persona_id, url}`
  over PubSub topic `persona:<persona_id>` so the admin LiveView can
  swap the placeholder in place.
  """
  use Oban.Worker, queue: :ai, max_attempts: 3

  alias MobileCarWash.AI.ImageGenerator
  alias MobileCarWash.Marketing.Persona

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"persona_id" => persona_id}}) do
    case Ash.get(Persona, persona_id, authorize?: false) do
      {:ok, persona} -> generate_and_stamp(persona)
      _ -> :ok
    end
  end

  defp generate_and_stamp(persona) do
    prompt = prompt_for(persona)

    case ImageGenerator.generate(prompt) do
      {:ok, url} ->
        {:ok, updated} =
          persona
          |> Ash.Changeset.for_update(:update, %{image_url: url})
          |> Ash.update(authorize?: false)

        Phoenix.PubSub.broadcast(
          MobileCarWash.PubSub,
          "persona:#{updated.id}",
          {:persona_image_ready, updated.id, url}
        )

        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp prompt_for(%{image_prompt: prompt}) when is_binary(prompt) and prompt != "", do: prompt
  defp prompt_for(%{description: d}) when is_binary(d) and d != "", do: d
  defp prompt_for(_), do: "Realistic portrait of a typical customer for a mobile car wash service"
end
