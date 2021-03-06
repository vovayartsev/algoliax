if Code.ensure_loaded?(Ecto) do
  defmodule Algoliax.Resources.ObjectEcto do
    @moduledoc false

    import Ecto.Query

    alias Algoliax.Requests
    alias Algoliax.Resources.{Index, Object}

    def reindex(module, settings, %Ecto.Query{} = query, opts) do
      repo = Algoliax.UtilsEcto.repo(settings)

      Algoliax.UtilsEcto.find_in_batches(repo, query, 0, settings, fn batch ->
        Object.save_objects(module, settings, batch, opts)
      end)
    end

    def reindex(module, settings, nil, opts) do
      reindex(module, settings, %{}, opts)
    end

    def reindex(module, settings, query_filters, opts) when is_map(query_filters) do
      repo = Algoliax.UtilsEcto.repo(settings)

      modules =
        case Algoliax.Utils.schemas(settings) do
          [_ | _] = schemas ->
            schemas

          _ ->
            [module]
        end

      modules
      |> Enum.each(fn mod ->
        where_filters = Map.get(query_filters, :where, [])

        query =
          from(m in mod)
          |> where(^where_filters)

        Algoliax.UtilsEcto.find_in_batches(repo, query, 0, settings, fn batch ->
          Object.save_objects(module, settings, batch, opts)
        end)
      end)

      {:ok, :completed}
    end

    def reindex(_, _, _, _) do
      {:error, :invalid_query}
    end

    def reindex_atomic(module, settings) do
      Algoliax.UtilsEcto.repo(settings)

      Index.ensure_settings(module, settings)

      index_name = Algoliax.Utils.index_name(module, settings)
      tmp_index_name = :"#{index_name}.tmp"
      tmp_settings = Keyword.put(settings, :index_name, tmp_index_name)

      Algoliax.SettingsStore.start_reindexing(index_name)

      reindex(module, tmp_settings, nil, [])

      Requests.move_index(tmp_index_name, %{
        operation: "move",
        destination: "#{index_name}"
      })

      Algoliax.SettingsStore.delete_settings(tmp_index_name)
      Algoliax.SettingsStore.stop_reindexing(index_name)

      {:ok, :completed}
    end
  end
end
