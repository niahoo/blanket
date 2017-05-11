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

  def pid_or_create(tref, opts) do
    case __MODULE__.boot(:create, tref, opts) do
      {:ok, pid} ->
        IO.puts "(xx) heir was created"
        {:ok, pid}
      {:error, {:already_started, pid}} ->
        IO.puts "(xx) heir exists"
        {:ok, pid}
    end
  end

  def boot(create_or_recover, tref, opts) do
    Supervisor.start_child(Blanket.Heir.Supervisor, [create_or_recover, tref, opts])
  end

  @doc false
  def start_link(create_or_recover, tref, opts) do
    GenServer.start_link(__MODULE__, [create_or_recover, tref, opts], name: via(tref))
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

  def attach(pid, tab) do
    # the calling process must be the table owner
    true = :ets.setopts(tab, [heir_opt(pid)])
    GenServer.call(pid, {:attach, tab, self()})
  end

  def heir_opt(pid) when is_pid(pid) do
    {:heir, pid, :blanket_heir}
  end

  # -- Server side -----------------------------------------------------------

  def init([:create, tref, opts]) do
    IO.puts "heir initializing for #{inspect tref}"
    case create_table(tref, opts) do
      {:ok, tab} ->
        IO.puts "table #{inspect tref} found or created"
        {:ok, %State{tab: tab}}
      other ->
        IO.puts "table #{inspect tref} : could not create or find it : #{inspect other}"
        other
    end
  end

  def init([:recover, tref, :no_opts]) do
    IO.puts "heir recovering for #{inspect tref}"
    {:ok, %State{}}
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

  def handle_call({:attach, tab, owner_pid}, _from, state = %State{owner_pid: nil, tab: nil}) do
    mref = Process.monitor(owner_pid)
    {:reply, :ok, %State{state | mref: mref, owner_pid: owner_pid, tab: tab}}
  end

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
      5000 -> raise "Down message not received"
    end
  end

  def handle_info(_info, state) do
    IO.puts "heir (#{inspect self()}) got info : #{inspect _info}"
    {:noreply, state, :hibernate}
  end

  defp reset_owner(state),
    do: %State{state | owner_pid: nil, mref: nil}


  defp create_table(tref, opts) do
    # We are creating a new heir, we must also create the table
    heir = heir_opt(self())
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
         :ok <- Blanket.Metatable.register_table(tab, tref),
       do: {:ok, tab}
  end

end
