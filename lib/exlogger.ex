defmodule ExLogger do

  @type  object_key :: atom
  @type  object :: [{atom, term}]
  @type  message :: String.t

  defmodule Message do
    defstruct timestamp: nil,
             level: nil, message: nil, object: [],
             module: nil, file: nil, line: nil, pid: nil
  end

  defmodule MFA do
    defstruct module: nil, function: nil, arguments: [], properties: []

    def construct([head|_]) do
      construct(head)
    end
    def construct({m, f, a, properties}) do
      %__MODULE__{module: m, function: f, arguments: a, properties: properties}
    end

    def construct({m, f, a}) do
      %__MODULE__{module: m, function: f, arguments: a}
    end

    def construct(nil) do
      %__MODULE__{}
    end

  end

  @levels ~w(verbose debug info notice warning error critical alert emergency)a
  def levels, do: @levels

  def register_backend({backend, options}) when is_atom(backend) do
    ExLogger.BackendWatcher.start(Process.whereis(ExLogger.Event), backend, options)
  end

  def register_backend(backend) when is_atom(backend) do
    ExLogger.BackendWatcher.start(Process.whereis(ExLogger.Event), backend, [])
  end

  def set_log_level(backend, level) when level in @levels do
    :gen_event.call(Process.whereis(ExLogger.Event), backend, {:set_log_level, level}, :infinity)
  end

  def get_log_level(backend) do
    :gen_event.call(Process.whereis(ExLogger.Event), backend, :get_log_level, :infinity)
  end


  for level <- @levels do
    defmacro unquote(level)(msg \\ nil, object \\ []) do
      excluded_levels = unless nil?(__CALLER__.module) do
        Module.get_attribute __CALLER__.module, :exlogger_excluded_levels, nil
      else
        []
      end
      default_attributes = unless nil?(__CALLER__.module) do
        Module.get_attribute __CALLER__.module, :exlogger_default_attributes, nil
      else
        []
      end
      if unquote(level) in excluded_levels do
        nil
      else
        level = unquote(level)
        # If msg is omitted but object is not,
        # avoid a situation where the object is actually stored
        # in msg
        if is_list(msg) and object == [] do
          object = msg
          msg = nil
        end
        quote do
          object = unquote(object)
          object = Dict.merge([__MODULE__: __MODULE__, __FILE__: __ENV__.file,
                               __LINE__: __ENV__.line, __PID__: self], unquote(default_attributes)) |>
                   Dict.merge(object)
          stripped_object = Dict.delete(object, :__MODULE__) |>
                            Dict.delete(:__FILE__) |>
                            Dict.delete(:__LINE__) |>
                            Dict.delete(:__PID__)
          log_msg = %ExLogger.Message{timestamp: :os.timestamp,
                                      level: unquote(level), message: unquote(msg),
                                      object: stripped_object,
                                      module: object[:__MODULE__],
                                      file: object[:__FILE__], line: object[:__LINE__],
                                      pid: object[:__PID__]}
          event = case Process.get(ExLogger.Event) do
            nil ->
              event = Process.whereis(ExLogger.Event)
              Process.put(ExLogger.Event, event)
              event
            event ->
              event
          end
          :gen_event.notify(event, {:log, log_msg})
        end
      end
    end
  end


  defmacro __using__(options) do
    default_excluded_levels = quote do
      cond do
        Enum.any?(:application.which_applications, fn({a, _, _}) -> a == :mix end) and Mix.env == :prod ->
          ~w(debug verbose)a
        true -> []
      end
    end
    as = options[:as] || ExLogger
    excluded_levels = options[:excluded_levels] || default_excluded_levels
    default_attributes = Macro.escape(options[:default_attributes] || [])
    prolog = quote do
      require ExLogger
      alias ExLogger, as: unquote(as)
    end
    unless nil?(__CALLER__.module) do
      quote do
        unquote(prolog)
        @exlogger_excluded_levels unquote(excluded_levels)
        @exlogger_default_attributes (Module.get_attribute(__MODULE__, :exlogger_default_attributes, nil) || []) ++ unquote(default_attributes)
      end
    else
      prolog
    end
  end

  def inspect(thing) do
    ExLogger.Inspect.to_string(thing)
  end


end
