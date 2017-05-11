defmodule Blanket.Heir.Supervisor do
  @moduledoc """
  The supervisor for the `:blanket` application.

  It's a simple_one_for_one/temporary : the children are never restared. Table
  owner processes must claim a new heir when they receive the 'DOWN' message for
  their heir. (If they ask so).
  """

  use Supervisor

  @doc "Starts the supervisor"
  def start_link do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc false
  def init([]) do
    children = [
      worker(Blanket.Heir, [], restart: :temporary),
    ]

    supervise(children, strategy: :simple_one_for_one)
  end
end
