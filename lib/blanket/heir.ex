defmodule Blanket.Heir do
  @moduledoc """
  This modules describes the generic server for the table heirs. Use the
  `Blanket` module to create and interact with a heir.
  """
  alias :ets, as: ETS

  use GenServer
  defmodule State do
    @moduledoc false
    defstruct [tab: nil, owner: nil, mref: nil]
  end

  defp via(tref) do
    {:via, Registry, {Blanket.Registry, tref}}
  end

  def whereis(tref) do
    case Registry.lookup(Blanket.Registry, tref) do
      [{pid, _}] -> {:ok, pid}
      other -> {:error, {:heir_not_found, other}}
    end
  end

  def pid_or_create(tref, opts) do
    case __MODULE__.boot(:create, tref, opts) do
      {:ok, pid} ->
        {:ok, pid}
      {:error, {:already_started, pid}} ->
        {:ok, pid}
    end
  end

  def boot(mode, tref, opts) do
    Supervisor.start_child(Blanket.Heir.Supervisor, [mode, tref, opts])
  end

  @doc false
  # The :via option is just used so we cannot create two processes with the same
  # tref. But we use the pid to send messages to the gen_server.
  def start_link(mode, tref, opts) do
    GenServer.start_link(__MODULE__, [mode, tref, opts], name: via(tref))
  end

  def claim(pid, owner) when is_pid(pid) do
    pid
    |> GenServer.call({:claim, owner})
    |> case do
      err = {:error, _} -> err
      {:ok, tab} ->
        receive do
          {:'ETS-TRANSFER', ^tab, ^pid, :blanket_giveaway} -> :ok
        after
          1000 -> raise "Something went wrong"
        end
        {:ok, tab}
    end
  end

  def attach(pid, tab) do
    :ok = set_heir(pid, tab)
    GenServer.call(pid, {:attach, tab, self()})
  end

  # the calling process must own the table.
  def detach(pid, tab) do
    :ok = remove_heir(tab)
    GenServer.call(pid, {:stop, :detach})
  end

  # the calling process must be the table owner
  defp set_heir(pid, tab) do
    true = :ets.setopts(tab, [heir_opt(pid)])
    :ok
  end

  defp remove_heir(tab) do
    true = :ets.setopts(tab, [{:heir, :none}])
    :ok
  end

  defp heir_opt(pid) when is_pid(pid) do
    {:heir, pid, :blanket_heir}
  end

  # -- Server side -----------------------------------------------------------

  def init([:create, tref, opts]) do
    case create_table(tref, opts) do
      {:ok, tab} ->
        {:ok, %State{tab: tab}}
      other ->
        other
    end
  end

  def init([:recover, _tref, :no_opts]) do
    {:ok, %State{}}
  end

  def handle_call(:stop, _from, state) do
    {:stop, :normal, :ok, state}
  end


  def handle_call({:claim, _new_owner}, _from,
    state = %State{owner: owner})
    when is_pid(owner) do
    {:reply, {:error, :already_owned}, state}
  end

  def handle_call({:claim, owner}, _from, state = %State{owner: nil, tab: tab})
    when is_pid(owner) do
    if ETS.info(tab, :owner) === self() do
      mref = Process.monitor(owner)
      ETS.give_away(tab, owner, :blanket_giveaway)
      {:reply, {:ok, tab}, %State{state | mref: mref, owner: owner}}
    else
      {:reply, {:error, :cannot_giveaway}, state}
    end
  end

  def handle_call({:attach, tab, owner}, _from,
    state = %State{owner: nil, tab: nil}) do
    mref = Process.monitor(owner)
    {:reply, :ok, %State{state | mref: mref, owner: owner, tab: tab}}
  end

  def handle_call({:stop, :detach}, _from, state) do
    {:stop, :normal, :ok, state}
  end

  def handle_info({:DOWN, mref, :process, owner, _reason},
      state = %State{owner: owner, tab: tab, mref: mref}) do
    # We receive the 'DOWN' message first, so we wait for the ETS-TRANSFER
    receive do
      {:'ETS-TRANSFER', ^tab, ^owner, :blanket_heir} ->
        {:noreply, reset_owner(state)}
    after
      5000 -> raise "Transfer not received"
    end
  end

  def handle_info({:'ETS-TRANSFER', tab, owner, :blanket_heir},
      state = %State{owner: owner, tab: tab, mref: mref}) do
    # We receive the 'ETS-TRANSFER' message first, so we wait for the DOWN
    receive do
      {:DOWN, ^mref, :process, ^owner, _reason} ->
        {:noreply, reset_owner(state)}
    after
      5000 -> raise "Down message not received"
    end
  end

  def handle_info(_info, state) do
    {:noreply, state, :hibernate}
  end

  defp reset_owner(state),
    do: %State{state | owner: nil, mref: nil}


  defp create_table(tref, opts) do
    # We are creating a new heir, we must also create the table
    create_table =
      case Keyword.get(opts, :create_table) do
        # If the user supplied a module, give back the opts, plus the heir opt
        module when is_atom(module) ->
          fn() -> apply(module, :create_table, [opts]) end
        # If the user supplied options, create a table with those options and
        # the heir option.
        {tname, table_opts} when is_atom(tname) and is_list(table_opts) ->
          fn() -> {:ok, ETS.new(tname, table_opts)} end
        fun when is_function(fun, 0) ->
          fun
        _other ->
          raise "Creation method invalid"
      end
    with {:ok, tab} <- create_table.(),
          :ok <- set_heir(self(), tab),
          :ok <- Blanket.Metatable.register_table(tab, tref),
      do: {:ok, tab}
  end

end
