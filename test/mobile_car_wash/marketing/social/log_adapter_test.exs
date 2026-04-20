defmodule MobileCarWash.Marketing.Social.LogAdapterTest do
  @moduledoc """
  Marketing Phase 3A / Slice 2: the default SocialAdapter is a
  no-op adapter that just logs what it would publish and returns a
  fake external id. Lets us build the end-to-end composer + publish
  flow without any API approvals / credentials.

  Real adapters (Meta, X, Buffer) in later phases implement the same
  SocialAdapter behaviour and slot in by config.
  """
  use ExUnit.Case, async: true

  alias MobileCarWash.Marketing.Post
  alias MobileCarWash.Marketing.Social.LogAdapter

  test "publish/2 returns {:ok, external_id} on any channel" do
    post = %Post{title: "test", body: "b", channels: ["meta"]}

    assert {:ok, id} = LogAdapter.publish(post, "meta")
    assert is_binary(id)
    assert String.starts_with?(id, "log_")
  end

  test "external ids are distinct per call" do
    post = %Post{title: "test", body: "b", channels: ["x"]}

    {:ok, id1} = LogAdapter.publish(post, "x")
    {:ok, id2} = LogAdapter.publish(post, "x")
    assert id1 != id2
  end

  test "supported_channels/0 returns the list of slugs this adapter handles" do
    channels = LogAdapter.supported_channels()
    assert is_list(channels)
    assert "log" in channels
  end
end
