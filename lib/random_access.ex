defmodule Eflatbuffers.RandomAccess do

  def get([key | keys], {:table, %{ name: table_name }}, table_pointer_pointer, data, {tables, _} = schema) when is_atom(key) do
    {:table, table_options} = Map.get(tables, table_name)
    table_fields = table_options.fields
    {index, type} = index_and_type(table_fields, key)
    {type_concrete, index_concrete} =
    case type do
      {:union, %{name: union_name}} ->
        # we are getting the field type from the field
        # and the data is actually in the next field
        # since the schema does not contain the *_type field
        type_pointer     = data_pointer(index, table_pointer_pointer, data)
        union_type_index = Eflatbuffers.Reader.read({:byte, %{ default: 0 }}, type_pointer, data, schema) - 1
        {:union, union_definition} = Map.get(tables, union_name)
        union_type = Map.get(union_definition.members, union_type_index)
        type = {:table, %{ name: union_type }}
        {type, index + 1}
      _ ->
        {type, index}
    end
    data_pointer  = data_pointer(index_concrete, table_pointer_pointer, data)
    case keys do
      [] ->
        # this is the terminus where we switch to eager reading
        Eflatbuffers.Reader.read(type_concrete, data_pointer, data, schema)
      _ ->
        get(keys, type_concrete, data_pointer, data, schema)
    end
  end

  def data_pointer(index, table_pointer_pointer, data) do
    << _ :: binary-size(table_pointer_pointer), table_offset :: little-size(32), _ :: binary >> = data
    table_pointer     = table_pointer_pointer + table_offset
    << _ :: binary-size(table_pointer), vtable_offset :: little-signed-size(32), _ :: binary >> = data
    vtable_pointer = table_pointer - vtable_offset + 4 + index * 2
    << _ :: binary-size(vtable_pointer),  data_offset :: little-size(16), _ :: binary >> = data
    table_pointer + data_offset
  end

  def get([index | keys], {:vector, %{ type: type }}, vector_pointer, data, schema) when is_integer(index) do
    << _ :: binary-size(vector_pointer), vector_offset :: unsigned-little-size(32), _ :: binary >> = data
    vector_length_pointer = vector_pointer + vector_offset
    << _ :: binary-size(vector_length_pointer), vector_length :: unsigned-little-size(32), _ :: binary >> = data
    data_offset =  vector_length_pointer + 4 + index * 4
    case vector_length < index + 1 do
      true ->  throw(:index_out_of_range)
      false ->
        case keys do
          [] ->
            Eflatbuffers.Reader.read(type, data_offset, data, schema)
          _ ->
            get(keys, type, data_offset, data, schema)
        end
    end
  end

  def index_and_type(fields, key) do
    {{^key, type}, index} = Enum.find(Enum.with_index(fields), fn({{name, _}, _}) -> name == key end)
    {index, type}
  end

end