defmodule Blanket.Heir.Supervisor do
  @moduledoc """
  The supervisor for the `:blanket` application.
  """
  use Supervisor

  @doc "Starts the supervisor"
  def start_link do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc false
  def init([]) do
    children = [
      worker(Blanket.Heir, [], restart: :transient),
    ]

    supervise(children, strategy: :simple_one_for_one)
  end
end