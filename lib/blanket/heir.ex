defmodule Blanket.Heir do
  use GenServer
  # require Logger

  defmacro __using__(_) do
    quote do

      @doc false
      def get_owner_pid(atom), do: Process.whereis(atom)

      defoverridable [get_owner_pid: 1]

    end
  end

  # x @todo seems we do not need the tab in the GenServer state. We could use it
  # to match on the table if someone (for one reason) decide to set a Heir
  # instance to be the heir of another table.

  # The table is created in the caller process creation errors are synchronous
  def new(module, owner, tab_def) do
    {tab_name, tab_opts} = tab_def
    tab = :ets.new(tab_name, tab_opts)
    start_heir(module, owner, tab)
  end

  def new(module, owner, tab_def, populate) do
    {tab_name, tab_opts} = tab_def
    tab = :ets.new(tab_name, tab_opts)
    case populate.(tab) do
      :ok -> start_heir(module, owner, tab)
      {:error, reason} -> {:error, reason}
      err -> {:error, err}
    end
  end

  defp start_heir(module, owner, tab) do
    heir_conf = [module, owner, tab]
    {:ok, heir_pid} = Supervisor.start_child(Blanket.Supervisor, heir_conf)
    # Now this is tricky. The client process is the current owner of the table.
    # Typically, the process calling Heir.new/3 is not the GenServer that will
    # own the table. It's the process that starts the gen_server.
    # So, we give the table to the heir, and the heir will give it to the
    # GenServer
    true = :ets.give_away(tab, heir_pid, :bootstrap)
    :ok #@todo should also return the tab ?
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

  def start_link(tab_name, tab_opts, get_pid) do
    GenServer.start_link(__MODULE__, [tab_name, tab_opts, get_pid])
  end

  # -- Server side -----------------------------------------------------------

  require Record
  Record.defrecordp :heir, tab: nil, module: nil, owner: nil

  def init([module, owner, tab]) do
    state = heir(tab: tab, module: module, owner: owner)
    {:ok, state}
    # Here we do nothing more. In Heir.new, the Heir process is given the table,
    # so we will receive a ETS-TRANSFER in handle_info, tagged with :bootstrap,
    # where the give_away to the real owner will happen
  end


  def handle_info({:'ETS-TRANSFER', tab, _starter_pid, :bootstrap}, state) do
    # We are receiving the table after its creation. We will fetch the owner
    # pid and give it the table ownership ; after setting ourselves as the heir
    # Logger.debug "Heir received tab #{tab} on boostrap sequence from #{inspect _starter_pid}"
    :ets.setopts(tab, {:heir, self, :blanket_heir})
    give_away_table(tab, state)
    {:noreply, state, :hibernate}
  end

  def handle_info({:'ETS-TRANSFER', tab, _dead_owner_pid, :blanket_heir}, state) do
    # Logger.debug "Heir #{inspect self} received the table back from #{inspect _dead_owner_pid}"
    give_away_table(tab, state)
    {:noreply, state, :hibernate}
  end

  defp give_away_table(tab, state) do
    owner_pid = get_owner_pid(state)
    :ets.give_away(tab, owner_pid, :blanket_giveaway)
  end

  # this will wait forever, so the client must be sure that the owner process
  # will be restarted (or call Heir.abandon_table)
  defp get_owner_pid(heir(module: module, owner: owner)=state) do
    case module.get_owner_pid(owner) do
      pid when is_pid(pid) -> pid
      _ ->
          :timer.sleep(1)
          get_owner_pid(state)
    end
  end

end
