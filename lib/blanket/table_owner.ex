defmodule Blanket.TableOwner do

  defmacro __using__(_) do
    quote do

      @doc false
      def get_owner_pid(atom), do: Process.whereis(atom)

      defoverridable [get_owner_pid: 1]

    end
  end

end
