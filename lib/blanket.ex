defmodule Blanket do
  @moduledoc """
  This is the top module of the Blanket application.
  """

  # -- Application API --------------------------------------------------------

  use Application

  def start(_type, _args) do
    _x = Blanket.Supervisor.start_link
  end

  # Table Owner API -----------------------------------------------------------

  defmacro __using__(_) do
    Blanket.TableOwner.default_owner_defs
  end

  # Heir API ------------------------------------------------------------------


  # The table is created in the caller process creation errors are synchronous
  def new(module, owner, tab_def) do
    {tab_name, tab_opts} = tab_def
    tab = :ets.new(tab_name, tab_opts)
    start_heir(module, owner, tab)
  end

  def new(module, owner, tab_def, populate) do
    {tab_name, tab_opts} = tab_def
    tab = :ets.new(tab_name, tab_opts)
    wrap_err = fn ({:error, reason}) -> {:error, reason}
              (err)              -> {:error, err}
           end
    case populate.(tab) do
      :ok -> start_heir(module, owner, tab)
      err ->
          :ets.delete(tab)
          wrap_err.(err)
    end
  end

  def receive_table(timeout \\ 5000) do
    receive do
      {:'ETS-TRANSFER', tab, _heir_pid, :blanket_giveaway} ->
        # Logger.debug("Process #{inspect self} received table #{tab} from heir #{inspect _heir_pid}")
        {:ok, tab}
    after
      timeout -> {:error, :ets_transfer_timeout}
    end
  end

  defp start_heir(module, owner, tab) do
    heir_conf = [module, owner, tab]
    {:ok, heir_pid} = Blanket.Supervisor.start_heir(heir_conf)
    # Now this is tricky. The client process is the current owner of the table.
    # Typically, the process calling Heir.new/3 is not the GenServer that will
    # own the table. It's the process that starts the gen_server.
    # So, we give the table to the heir, and the heir will give it to the
    # GenServer
    true = :ets.give_away(tab, heir_pid, :bootstrap)
    {:ok, heir_pid}
  end

end
