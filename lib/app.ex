defmodule ExLogger.App do
  use Application

  def start(_type, _args) do
    case ExLogger.Sup.start_link do
      {:ok, pid} ->
        {:ok, backends} = :application.get_env(:exlogger, :backends)
        for backend <- backends, do: ExLogger.register_backend(backend)

        case :application.get_env(:exlogger, :error_logger_redirect) do
          {:ok, true} ->
            ExLogger.BackendWatcher.start(:error_logger, ExLogger.ErrorLoggerHandler, [])
            for error_handler <- (:gen_event.which_handlers(:error_logger) --
                                     [ExLogger.ErrorLoggerHandler]) do
              :error_logger.delete_report_handler(error_handler)
            end
          _ ->
           :ok
        end

        {:ok, pid}
      other ->
        other
     end
  end

end
