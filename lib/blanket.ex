defmodule Blanket do
  @moduledoc """
  This is the facade of the Blanket application. Handles starting/stopping the
  application and defines the client API.
  """
  alias Blanket.Heir
  alias Blanket.Metatable

  # -- Application API --------------------------------------------------------

  use Application

  @doc false
  def start(_type, _args) do
    Blanket.Supervisor.start_link
  end

  # User API ------------------------------------------------------------------

  @doc """
  Create an ETS table associated to a table reference, or claims the ownership
  of the table, after a restart.

  The table reference is used in Blanket and is not the ETS table id. A table
  reference can actually be any term but must be unique.

  This function must be called by the process that will own the table, best is
  to put it in your `c:GenServer.init/1` or `c:Agent.start_link/2` function.

  If your process crashes, it must be restarted with the same table reference in
  order to retrieve its ETS table. The table reference argument should be in the
  supervisor child spec or in the `Supervisor.start_child/2` for instance.

  ### Available Options

  **`:create_table`**, **required**. Determines how to create the ETS table
    the first time the heir is created. One of the following :

  - A `fn` returning `{:ok, tab}` where `tab` is the identifier of the
     created ETS table.
  - A tuple `{table_name, table_opts}` which will be used to call
     `:ets.new(table_name, table_opts)`.
  - A module name, e.g. `MyTableServer` or `__MODULE__`. The module must
    export a `create_table/1` function which will be passed the whole
    `claim_table` options list and must return `{:ok, tab}` where `tab` is
    the identifier of the created ETS table.

  Any `{:heir, _, _}` set on the table will be overriden by the Blanket heir.

  **`:monitor`**, optional, defaults to false. If true, the calling process will
  set a monitor the heir process and receive a `:'DOWN'` message if the latter
  crashes. Mostly useless because heir have an extremely rare chance to crash,
  as they do basically nothing.

  **`:monitor_ref`**, optional, defaults to false. If true, the return of
  `claim_table/2` also includ a monitor reference as the third element.

  """
  @spec claim_table(term(), Keyword.t()) :: {:ok, :ets.tid()}
                                          | {:ok, :ets.tid(), reference()}
                                          | {:error, term()}
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

  @doc """
  Creates a new heir for the table.

  The calling process must be the table owner. Sets a monitor and return the new
  process monitor ref.

  This function should not be called if the heir is not dead because the current
  heir will not be turned down while booting a new one.
  """
  @spec recover_heir(:ets.tid()) :: {:ok, reference()} | {:error, any()}
  def recover_heir(tab) do
    with {:ok, tref} <- Metatable.get_tab_tref(tab),
         {:ok, heir_pid} <- Heir.boot(:recover, tref, :no_opts),
         :ok <- Heir.attach(heir_pid, tab) do
         {:ok, Process.monitor(heir_pid)}
    end
  end

  @doc """
  Finds the heir associated with the table, and stops it.

  The calling process must own the table.
  """
  @spec abandon_table(:ets.tid()) :: :ok | {:error, any()}
  def abandon_table(tab) do
    with {:ok, tref} <- Metatable.get_tab_tref(tab),
         {:ok, heir_pid} <- Heir.whereis(tref),
         :ok <- Heir.detach(heir_pid, tab) do
         :ok
    end
  end

end
