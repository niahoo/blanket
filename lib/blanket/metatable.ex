
defmodule Blanket.Metatable do
  use GenServer

  @metatable __MODULE__

  @doc "Starts the supervisor"
  def start_link do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def register_table(tab, tref) do
    case :ets.insert_new(@metatable, {tab, tref}) do
      true -> :ok
      false -> {:error, {:already_registered, tab, tref}}
    end
  end

  def get_tab_tref(tab) do
    case :ets.lookup(@metatable, tab) do
      [] -> {:error, {:table_not_found, tab}}
      [{^tab, tref}] -> {:ok, tref}
    end
  end

  @doc false
  def init([]) do
    # The funny thing is that we do not use a heir here :)
    tab = :ets.new(@metatable, [:public, :named_table])
    {:ok, tab, :hibernate}
  end
end
