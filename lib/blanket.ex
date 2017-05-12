defmodule Blanket do
  @moduledoc """
  This is the facade of the Blanket application. Handles starting/stopping the
  application and defines the client API.
  """
  alias Blanket.Heir

  # -- Application API --------------------------------------------------------

  use Application

  @doc false
  def start(_type, _args) do
    Blanket.Supervisor.start_link
  end

  # User API ------------------------------------------------------------------

  def claim_table(tref, opts) do
    # boots a table heir, or get the pid of an existing one, and attempt to set
    # the owner. Returns error if the table is already owned.
    # The table is created in the heir process so we can then use the same code
    # asking foir the table when the heir is owner
    {:ok, heir_pid} = Heir.pid_or_create(tref, opts)
    # Maybe we want to set a monitor if we expect the heir to crash. This should
    # never happen because the heir does nothing, but we offer this safety
    monitor = Keyword.get(opts, :monitor, false)
    return_monitor_ref = Keyword.get(opts, :monitor_ref, false)
    case Heir.claim(heir_pid, self()) do
      {:ok, tab} ->
        mref = if monitor,
          do: Process.monitor(heir_pid)
        if monitor and return_monitor_ref do
          {:ok, tab, mref}
        else
          {:ok, tab}
        end
      other -> other
    end
  end

  # Creates a new heir for the table. The calling process must be the table
  # owner. We set a monitor (because to be there, you must have asked for a
  # monitor beforehand) and return the new process monitor ref
  def recover_heir(tab) do
    with {:ok, tref} <- Blanket.Metatable.get_tab_tref(tab),
         {:ok, heir_pid} <- Blanket.Heir.boot(:recover, tref, :no_opts),
         :ok <- Heir.attach(heir_pid, tab) do
         {:ok, Process.monitor(heir_pid)}
    end
  end

end
