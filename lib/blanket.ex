defmodule Blanket do
  @moduledoc """
  This is the facade of the Blanket application. Handles starting/stopping the
  application and defines the client API.
  """
  alias Blanket.Heir

  @typedoc """
  Blanket heir options are a proplist.
  """
  @type opts :: [{atom, function | boolean} | atom]

  @typedoc """
  An owner is a value used to retrieve a process. Typically it's an atom
  manipulated with `Process.register` and `Process.whereis`. But it can be any
  value used with a custom pid-store.
  """
  @type owner :: atom | any

  # -- Application API --------------------------------------------------------

  use Application

  @doc false
  def start(_type, _args) do
    Blanket.Supervisor.start_link
  end

  # User API ------------------------------------------------------------------

  def claim_table(tref, opts \\ [])

  def claim_table(tref, opts) do
    # boots a table heir, or get the pid of an existing one, and attempt to set
    # the owner. Returns error if the table is already owned.
    {:ok, heir_pid} = Heir.pid_of(tref, opts)
    Heir.claim(heir_pid, self())
  end

end
