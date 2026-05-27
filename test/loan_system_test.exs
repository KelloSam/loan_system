defmodule LoanSystemTest do
  use ExUnit.Case
  doctest LoanSystem

  test "greets the world" do
    assert LoanSystem.hello() == :world
  end
end
