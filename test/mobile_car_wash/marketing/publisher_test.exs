defmodule MobileCarWash.Marketing.PublisherTest do
  @moduledoc """
  Marketing Phase 3A / Slice 3: `Publisher.publish/1` fans out a Post
  across every channel in its `channels` list, invoking each
  channel's configured SocialAdapter, and stamps the results onto
  the Post row (external_ids merged, status flipped to :published
  or :failed).
  """
  use MobileCarWash.DataCase, async: false

  alias MobileCarWash.Marketing.{Post, Publisher}

  defp draft!(channels) do
    {:ok, post} =
      Post
      |> Ash.Changeset.for_create(:create, %{
        title: "Draft #{System.unique_integer([:positive])}",
        body: "",
        channels: channels
      })
      |> Ash.create(authorize?: false)

    post
  end

  describe "publish/1" do
    test "fans out to every configured channel and stamps external_ids" do
      post = draft!(["log"])

      assert {:ok, published} = Publisher.publish(post.id)
      assert published.status == :published
      assert Map.has_key?(published.external_ids, "log")
      assert published.external_ids["log"] |> String.starts_with?("log_")
      assert published.published_at != nil
    end

    test "records results per channel on multi-channel posts" do
      post = draft!(["log", "meta", "x"])

      {:ok, published} = Publisher.publish(post.id)

      # LogAdapter handles all three in 3A
      assert Map.keys(published.external_ids) |> Enum.sort() == ["log", "meta", "x"]
    end

    test "returns {:error, :not_found} for a missing post id" do
      assert {:error, :not_found} = Publisher.publish(Ecto.UUID.generate())
    end

    test "refuses to re-publish an already-published post" do
      post = draft!(["log"])
      {:ok, _} = Publisher.publish(post.id)

      assert {:error, :already_published} = Publisher.publish(post.id)
    end
  end
end
