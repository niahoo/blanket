defmodule Blanket.Heir do
  @moduledoc """
  This modules describes the generic server for the heirs. Use the `Blanket`
  module to create and interact with the heirs.
  """
  alias :ets, as: ETS

  use GenServer
  defmodule State do
    defstruct [tab: nil, owner_pid: nil, mref: nil]
  end

  defp via(tref) do
    {:via, Registry, {Blanket.Registry, tref}}
  end

  def pid_of(tref, opts) do
    case __MODULE__.boot(tref, opts) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
    end
  end

  def boot(tref, opts) do
    Supervisor.start_child(Blanket.Heir.Supervisor, [tref, opts])
  end

  @doc false
  def start_link(tref, opts) do
    GenServer.start_link(__MODULE__, [tref, opts], name: via(tref))
  end

  def claim(pid, owner_pid) when is_pid(pid) do
    GenServer.call(pid, {:claim, owner_pid})
    |> case do
      err={:error, _} -> err
      {:ok, tab} ->
        receive do
          {:'ETS-TRANSFER', ^tab, ^pid, :blanket_giveaway} -> :ok
        after
          1000 -> raise "Something went wrong"
        end
        {:ok, tab}
    end

  end


  # -- Server side -----------------------------------------------------------

  def init([tref, opts]) do
    IO.puts "heir initializing for #{inspect tref}"
    case find_or_create_table(tref, opts) do
      {:ok, tab} ->
        IO.puts "table #{inspect tref} found or created"
        {:ok, %State{tab: tab}}
      other ->
        IO.puts "table #{inspect tref} : could not create or find it : #{inspect other}"
        other
    end
  end

  def handle_call(:stop, _from, state) do
    {:stop, :normal, :ok, state}
  end

  def handle_call({:claim, new_owner_pid}, _from,
    state = %State{owner_pid: owner_pid})
    when is_pid(owner_pid) do
    {:reply, {:error, :already_owned}, state}
  end

  def handle_call({:claim, owner_pid}, _from, state = %State{owner_pid: nil, tab: tab})
    when is_pid(owner_pid) do
    mref = Process.monitor(owner_pid)
    ETS.give_away(tab, owner_pid, :blanket_giveaway)
    {:reply, {:ok, tab}, %State{state | mref: mref, owner_pid: owner_pid}}
  end

  # def handle_call(_msg, _from, state) do
  #   {:noreply, state, :hibernate}
  # end

  # def handle_info({:'ETS-TRANSFER', tab, _, :INIT}, state=st(tab: tab)) do
  #   # We are receiving the table after its creation. We will fetch the owner
  #   # pid and give it the table ownership ; after setting ourselves as the heir
  #   ETS.setopts(tab, {:heir, self, :blanket_heir})
  #   handle_transfer(state)
  # end

  def handle_info({:DOWN, mref, :process, owner_pid, _reason},
      state = %State{owner_pid: owner_pid, tab: tab, mref: mref}) do
    # We receive the 'DOWN' message first, so we wait for the ETS-TRANSFER
    receive do
      {:'ETS-TRANSFER', ^tab, ^owner_pid, :blanket_heir} ->
        {:noreply, reset_owner(state)}
    after
      5000 -> raise "Transfer not received"
    end
  end

  def handle_info({:'ETS-TRANSFER', tab, owner_pid, :blanket_heir},
      state = %State{owner_pid: owner_pid, tab: tab, mref: mref}) do
    # We receive the 'ETS-TRANSFER' message first, so we wait for the DOWN
    receive do
      {:DOWN, ^mref, :process, ^owner_pid, _reason} ->
        {:noreply, reset_owner(state)}
    after
      5000 -> raise "Transfer not received"
    end
  end

  # def handle_info({:'ETS-TRANSFER', tab, _, :blanket_heir},
  #     state=st(tab: tab)) do
  #   handle_transfer(state)
  # end

  def handle_info(_info, state) do
    IO.puts "heir (#{inspect self()}) got info : #{inspect _info}"
    {:noreply, state, :hibernate}
  end

  defp reset_owner(state),
    do: %State{state | owner_pid: nil, mref: nil}

  # defp handle_transfer(state=st(tab: tab)) do
  #   owner_pid = get_owner_pid(state)
  #   state = st(state, mref: Process.monitor(owner_pid))
  #   ETS.give_away(tab, owner_pid, :blanket_giveaway)
  #   {:noreply, state, :hibernate}
  # end

  # # this will wait forever, so the client must be sure that the owner process
  # # will be restarted (or call Heir.abandon_table)
  # defp get_owner_pid(st(module: module, owner: owner)=state) do
  #   case module.get_owner_pid(owner) do
  #     pid when is_pid(pid) ->
  #       pid
  #     _otherwise ->
  #       :timer.sleep(1)
  #       get_owner_pid(state)
  #   end
  # end

  defp find_or_create_table(tref, opts) do
    case find_table(tref) do
      {:ok, tab} ->
        IO.puts "table #{inspect tref} exists"
        {:ok, tab}
      :not_found ->
        IO.puts "table #{inspect tref} must be created"
        with {:ok, tab} <- create_table(tref, opts),
             :ok <- register_table(tref, tab),
           do: {:ok, tab}
    end
  end

  defp find_table(tref) do
    case Blanket.Metatable.lookup_by_tref(:my_test_table) do
      nil -> :not_found
      tab -> {:ok, tab}
    end
  end

  defp register_table(tref, tab) do
    Blanket.Metatable.register_by_tref(tref, tab)
  end

  defp create_table(tref, opts) do
    # We are creating a new heir, we must also create the table
    heir = {:heir, self(), :blanket_heir}
    create_table =
      case Keyword.get(opts, :create) do
        # If the user supplied a module, give back the opts, plus the heir opt
        module when is_atom(module) ->
          fn() -> apply(module, :create_table, [opts, heir]) end
        # If the user supplied options, create a table with those options and
        # the heir option.
        table_opts when is_list(table_opts) ->
          {table_name, table_opts} = Keyword.pop(opts, :name, :nameless_table)
          fn() -> {:ok, ETS.new(table_name, [heir|table_opts])} end
        fun when is_function(fun, 2) ->
          fn() -> fun.(opts, heir) end
        _other ->
          raise "Creation method invalid"
      end
    IO.puts "Heir creating table ref=#{inspect tref}"
    with {:ok, tab} <- create_table.(),
         populate <- Keyword.get(opts, :populate, fn(_tab) -> :ok end),
         :ok <- populate.(tab),
       do: {:ok, tab}
  end

end
