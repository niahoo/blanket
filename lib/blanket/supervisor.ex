defmodule Blanket.Supervisor do
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
      supervisor(Blanket.Heir.Supervisor, []),
      supervisor(Registry, [:unique, Blanket.Registry]),
      worker(Blanket.Metatable, []),
    ]
    supervise(children, strategy: :one_for_one)
  end
end
