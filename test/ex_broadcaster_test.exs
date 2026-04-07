defmodule ExBroadcasterTest do
  use ExUnit.Case
  doctest ExBroadcaster

  test "greets the world" do
    assert ExBroadcaster.hello() == :world
  end
end
