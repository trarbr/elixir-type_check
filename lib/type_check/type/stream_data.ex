defmodule TypeCheck.Type.StreamData do
  @moduledoc """
  Transforms types into StreamData generators.

  With the exception of `wrap_with_gen/2`,
  methods in this module are
  only compiled when the optional dependency
  `:stream_data` is added to your project's dependencies.
  """

  defstruct [:type, :generator_function]

  @doc """
  Customizes a type with a _custom_ generator.

  `generator_function` can be a arity-zero function
  (in which case it should simply return a StreamData generator)

  or a arity-one function, in which case it is passed
  the value that would be generated by default and it can be altered
  by e.g. using `StreamData.map/2` or `StreamData.bind/2`.

  Note that these functions _must_ be of the form `&Module.function/arity`
  because this is the only form of function capture that can be stored at compile-time.

  ## Example:

      iex> defmodule IntString do
      ...>   use TypeCheck
      ...>   import TypeCheck.Type.StreamData
      ...>   @type! t() :: ((val :: binary()) when Integer.parse(val) != :error)
      ...>                 |> wrap_with_gen(&IntString.gen/0)
      ...>
      ...>   def gen() do
      ...>     StreamData.integer()
      ...>     |> StreamData.map(&to_string/1)
      ...>   end
      ...> end
      ...>
      ...> IntString.t() |> TypeCheck.Type.StreamData.to_gen() |> StreamData.seeded(42) |> Enum.take(10)
      ["0", "2", "1", "-3", "-5", "-4", "-3", "-4", "3", "-6"]
  """
  def wrap_with_gen(type, generator_function) when is_function(generator_function, 0) or is_function(generator_function, 1) do
    %__MODULE__{type: type, generator_function: generator_function}
  end

  defimpl TypeCheck.Protocols.ToCheck do
    def to_check(s, param) do
      TypeCheck.Protocols.ToCheck.to_check(s.type, param)
    end
  end

  defimpl TypeCheck.Protocols.Inspect do
    def inspect(s, opts) do
      TypeCheck.Protocols.Inspect.inspect(s.type, opts)
    end
  end

  if Code.ensure_loaded?(StreamData) do

    defimpl TypeCheck.Protocols.ToStreamData do
      def to_gen(s) do
        if is_function(s.generator_function, 0) do
          s.generator_function.()
        else
          s.type
          |> TypeCheck.Protocols.ToStreamData.to_gen()
          |> s.generator_function.()
        end
      end
    end

    @doc """
    When given a type, it is transformed to a StreamData generator
    that can be used in a property test.

        iex> import TypeCheck.Type.StreamData
        iex> generator = TypeCheck.Type.build({:ok | :error, integer()}) |> to_gen()
        iex> StreamData.seeded(generator, 42) |> Enum.take(10)
        [
        {:ok, -1},
        {:ok, 2},
        {:ok, -2},
        {:ok, -4},
        {:ok, 1},
        {:ok, 1},
        {:ok, 2},
        {:ok, 4},
        {:ok, -7},
        {:ok, 5}
        ]
    """
    def to_gen(type) do
      TypeCheck.Protocols.ToStreamData.to_gen(type)
    end

    def arbitrary_primitive_type_gen do
      choices = primitive_types_list()
      Elixir.StreamData.one_of(choices)
    end

    defp primitive_types_list() do
      import TypeCheck.Builtin

      simple =
        [
          any(),
          atom(),
          binary(),
          bitstring(),
          boolean(),
          float(),
          function(),
          integer(),
          number()
        ]
        |> Enum.map(&Elixir.StreamData.constant/1)

      lit = Elixir.StreamData.term() |> Elixir.StreamData.map(&literal/1)

      [lit | simple]
    end

    def arbitrary_type_gen() do
      # TODO WIP
      StreamData.one_of(
        primitive_types_list() ++ [list_gen(), map_gen(), fixed_list_gen(), fixed_tuple_gen()]
      )
    end

    defp list_gen() do
      lazy_type_gen()
      |> StreamData.map(&TypeCheck.Builtin.list/1)
    end

    defp map_gen() do
      {lazy_type_gen(), lazy_type_gen()}
      |> StreamData.map(fn {key_type, value_type} ->
        TypeCheck.Builtin.map(key_type, value_type)
      end)
    end

    def fixed_list_gen() do
      lazy_type_gen()
      |> StreamData.list_of()
      |> StreamData.map(&TypeCheck.Builtin.fixed_list/1)
    end

    defp fixed_tuple_gen() do
      lazy_type_gen()
      |> StreamData.list_of(max_length: 255)
      |> StreamData.map(&TypeCheck.Builtin.fixed_tuple/1)
    end

    defp lazy_type_gen() do
      # Lazily call content generator
      # To prevent infinite expansion recursion
      StreamData.constant({})
      |> StreamData.bind(fn _ ->
        arbitrary_type_gen()
        |> StreamData.scale(fn size -> div(size, 2) end)
      end)
    end

  else

    def arbitrary_type_gen() do
      raise ArgumentError, """
      `arbitrary_type_gen/0` depends on the optional library `:stream_data`.
      To use this functionality, add `:stream_data` to your application's deps.
      """
    end
  end
end
