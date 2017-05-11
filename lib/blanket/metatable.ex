
defmodule Blanket.Metatable do
  @moduledoc """
  The supervisor for the `:blanket` application.
  """
  use GenServer

  @metatable __MODULE__

  @doc "Starts the supervisor"
  def start_link do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  # returns a tab id by tref
  def lookup_by_tref(tref) do
    case :ets.lookup(@metatable, tref) do
      [] -> nil
      [{^tref, tab}] -> tab
    end
  end


  def register_by_tref(tref, tab) do
    case :ets.insert_new(@metatable, {tref, tab}) do
      true -> :ok
      false -> {:error, {:already_registered, tref, tab}}
    end
  end

  @doc false
  def init([]) do
    # The funny thing is that we do not use a heir here :)
    tab = :ets.new(@metatable, [:public, :named_table])
    {:ok, tab, :hibernate}
  end
end