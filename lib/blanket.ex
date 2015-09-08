defmodule Blanket do
  @moduledoc """
  This is the facade of the Blanket application. Handles starting/stopping the
  application and defines the client API.
  """

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

  # Table Owner API -----------------------------------------------------------

  defmacro __using__(_) do
    Blanket.TableOwner.default_owner_defs
  end

  # Heir API ------------------------------------------------------------------


  @doc """
  Creates a new ETS table and a new heir attached to it.

  `opts` is either a function for populating the ets table (or any other
  operation), or a list containing zero or more options from :
   - `:transient` (`true` | `false`) : wether the heir will stop if the table
     process exits with `:normal`.
   - `:populate` : the same function as above.

  The table is created in the current process, as is called the populate
  function.
  """

  @spec new(atom, owner, {atom, Keyword.t}, opts) :: {:ok, pid} | {:error, any}

  def new(module, owner, tab_def, opts \\ [])

  def new(module, owner, tab_def, opts) when is_list(opts) do
    {tab_name, tab_opts} = tab_def
    tab = :ets.new(tab_name, tab_opts)
    {populate, opts} =
      opts
      |> proplist_to_keywords
      |> Keyword.pop(:populate, fn(_) -> :ok end)
    case populate.(tab) do
      :ok -> start_heir(module, owner, tab, opts)
      err ->
          :ets.delete(tab)
          wrap_error(err)
    end
  end

  def new(module, owner, tab_def, populate) when is_function(populate, 1) do
    new(module, owner, tab_def, [populate: populate])
  end

  @doc """
  Awaits for an `:'ETS-TRANSFER'` message from the heir. The heir must find the
  calling process by calling `module.get_owner_pid(name)` with the `module` and
  `owner` values provided in `Blanket.new/4`.
  """

  @spec receive_table(timeout) :: {:ok, :ets.tid} | {:error,:transfer_timeout}

  def receive_table(timeout \\ 5000) do
    receive do
      {:'ETS-TRANSFER', tab, _heir_pid, :blanket_giveaway} ->
        {:ok, tab}
    after
      timeout -> {:error, :transfer_timeout}
    end
  end

  @doc """
  Removes the `:heir` option from the table, stops the heir process.
  """
  @spec abandon_table(:ets.tid, pid) :: :ok
  def abandon_table(tab, heir) do
    # The owner must be the process which set options
    true = :ets.setopts(tab, [{:heir, :none}])
    GenServer.call(heir, :stop)
  end

  defp start_heir(module, owner, tab, opts) do
    Blanket.Heir.new(module, owner, tab, opts)
  end

  defp wrap_error({:error, reason}), do: {:error, reason}
  defp wrap_error(err), do: {:error, err}

  defp proplist_to_keywords(opts) do
    opts |> Enum.map(
      fn({k, v}) -> {k, v}
        (k) -> {k, true}
      end
    )
  end

end
