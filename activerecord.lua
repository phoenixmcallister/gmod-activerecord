
---
-- @module ActiveRecord

local library = {
  __buffer = {},
  queue = {
    push = {},
    pull = {}
  },
  search_methods = {},

  mysql = mysql,
  config = {
    prefix = 'ar_',
    suppress = false
  },

  meta = {
    schema = {},
    replication = {
      enabled = false,
      sync = false,
      sync_existing = false,
      allow_db_pull = false,
      condition = nil
    },
    model = {
      __schema = {},
      __replication = {}
    },
    object = {}
  },
  model = {}
}

--- Network message enumeration
-- @table MESSAGE
local MESSAGE = {
  COMMIT = 1, -- Client-to-server object commit
  SCHEMA = 2, -- Model schema update
  REQUEST = 3, -- Object fetch request
  UPDATE = 4, -- Object replication update
  SYNC = 5 -- Full sync of objects
}

local function print_log(text)
  if (!library.config.suppress) then
    print(string.format('[ActiveRecord] %s', text))
  end
end

local function search_method(name, require_key, single_result)
  library.search_methods[name] = {
    require_key = require_key,
    single_result = single_result
  }
end

local function to_snake_case(str)
	str = str[1]:lower()..str:sub(2, str:len())

	return str:gsub('([a-z])([A-Z])', function(lower, upper)
		return lower..'_'..string.lower(upper)
	end)
end

--- Helpers
-- @section helpers

--- pluralize a string.
-- @param string string to pluralize
-- @return pluralized string
function library:pluralize(string)
  return string .. 's' -- poor man's pluralization
end

--- Returns the first function arg from the given varargs. Currently kind of useless.
-- @return Callback function
function library:get_callback_arg(...)
  local args = {...}
  local callback = args[1]

  assert(callback and type(callback) == 'function', 'Expected function type for asynchronous request, got "' .. type(callback) .. '"')
  return callback
end

--- Sets the prefix used when creating tables. An underscore is appended to the end of the given prefix. Default is 'ar'.
-- @param prefix string to use as prefix
function library:set_prefix(prefix)
  self.config.prefix = string.lower(prefix) .. '_'
  self:on_prefix_set()
end

--- Returns the unique full name of the project. Mainly used for networking.
-- @return Name of project
function library:get_name()
  return 'ActiveRecord_' .. self.config.prefix
end

--- Serializes and compresses a table for networking.
-- @param table Table of data
-- @return Packed data string
-- @return Length of data
function library:pack_table(table)
  local data = util.Compress(util.TableToJSON(table))
  return data, string.len(data)
end

--- Decompresses and deserializes a string into a table.
-- @see pack_table
-- @param string Packed data string
-- @return Table of data
function library:unpack_table(string)
  return util.JSONToTable(util.Decompress(string))
end

--- Returns true if the given object is an ActiveRecord object.
-- @param var Any object
-- @return Whether or not var is an ActiveRecord object
function library:is_object(var)
  return getmetatable(var) == self.meta.object
end

--- Begins an ActiveRecord net message.
-- @see MESSAGE
-- @param type Message type 
function library:start_net_msg(type)
  net.Start(self:get_name() .. '.message')
  net.WriteUInt(type, 8)
end

--- Writes a table to the currently active net message.
-- @see read_net_table
-- @param data Table of data
function library:write_net_table(data)
  local data, length = self:pack_table(data)

  net.WriteUInt(length, 32)
  net.WriteData(data, length)
end

--- Reads a table from the currently active net message.
-- @see write_net_table
-- @return Table of data
function library:read_net_table()
  return self:unpack_table(net.ReadData(net.ReadUInt(32)))
end

if (SERVER) then
  AddCSLuaFile()

  function library:get_table_name(name)
    return self.config.prefix .. string.lower(self:pluralize(name))
  end

  function library:set_sql_adapter(table)
    self.mysql = table
  end

  --- Class: Schema
  -- @section schema
  library.meta.schema.__index = library.meta.schema

  function library.meta.schema:id(use)
    if (!use) then
      self.id = nil
    end

    return self
  end

  --- Adds a string to the model schema.
  -- @param name Name of field
  function library.meta.schema:string(name)
    self[to_snake_case(name)] = 'VARCHAR(255)'
    return self
  end

  --- Adds a text field to the model schema.
  -- @param name Name of field
  function library.meta.schema:text(name)
    self[to_snake_case(name)] = 'TEXT'
    return self
  end

  --- Adds an integer to the model schema.
  -- @param name Name of field
  function library.meta.schema:integer(name)
    self[to_snake_case(name)] = 'INTEGER'
    return self
  end

  --- Adds a boolean to the model schema.
  -- @param name Name of field
  function library.meta.schema:boolean(name)
    self[to_snake_case(name)] = 'TINYINT(1)'
    return self
  end

  --- Sets whether or not the model will sync all in-memory objects with the database.
  -- @param value true/false
  function library.meta.schema:sync(value)
    self.__sync = tobool(value)
    return self
  end

  --- Sets callback executed when syncing is completed. Only called if `schema:sync(true)` has been set.
  -- @param callback Function to execute
  function library.meta.schema:on_sync(callback)
    self.__onsync = callback
    return self
  end

  --- Class: Replication
  -- @section replication
  library.meta.replication.__index = library.meta.replication

  --- enables replication for the model.
  -- @param value Whether or not to enable/disable
  function library.meta.replication:enable(value)
    self.enabled = value
    return self
  end

  --- Sets the replication condition function. Note that this is REQUIRED when you're using replication.
  -- A boolean return type is expected from the filter function.
  -- @param callback Function to use as the filter
  function library.meta.replication:condition(callback)
    self.condition = callback
    return self
  end

  --- Helpers
  -- @section helpers

  --- Returns true if the player is able to request object data from the given model.
  -- @param model_name Name of the model
  -- @param player Player to check with
  -- @return Whether or not the player is allowed to request object data
  function library:check_request_condition(model_name, player)
    return (self.model[model_name] and
      self.model[model_name].__replication.enabled and
      self.model[model_name].__replication.condition(player))
  end

  --- Class: Object
  -- @section object
  library.meta.object.__index = library.meta.object

  --- Commits the object to the database and networks it to clients if applicable.
  function library.meta.object:save()
    library:queue_push('object', self)

    if (self.__model.__schema.__sync and self.__model.__replication.enabled) then
      library:network_object(self)
    end
  end

  --- Returns a string representation of the object. This will include its model and properties.
  -- @return string representation of object
  function library.meta.object:__tostring()
    local result = string.format('<ActiveRecord object of model %s>:', self.__model.__name)

    for k, v in pairs(self) do
      if (string.sub(k, 1, 2) == '__') then
        continue
      end

      result = result .. string.format('\n\t%s\t= %s', k, v)
    end

    return result
  end

  --- Helpers
  -- @section helpers

  --- Networks an object to clients. This does not check if replication is applicable for the object's model, so you'll have to do it yourself!
  -- @param object Object to network
  function library:network_object(object)
    local model = object.__model
    local players = self:filter_players(model.__replication.condition)

    if (#players < 1) then
      return
    end

    self:start_net_msg(MESSAGE.UPDATE)
      net.Writestring(model.__name)
      self:write_net_table(self:get_object_table(object))
    net.Send(players[1]) -- TODO: why only the first player?
  end

  --- Class: Model
  -- @section model
  library.meta.model.__index = library.meta.model

  --- Creates a new object.
  -- @return An object defined by the given model class.
  function library.meta.model:New()
    local object = setmetatable({
      __model = self,
      __bsaved = false,
    }, library.meta.object)

    if (object.__model.__schema.id) then
      object.id = #library.__buffer[self.__name] + 1
    end

    table.insert(library.__buffer[self.__name], object)
    return object
  end

  search_method('all')
  --- Returns all objects with this model.
  -- @param ...
  -- @return Table of objects
  function library.meta.model:all(...)
    if (self.__schema.__sync) then
      return library.__buffer[self.__name]
    else
      local args = {...}
      local query = library.mysql:Select(library:get_table_name(self.__name))
        query:Callback(function(result)
          local callback = library:get_callback_arg(unpack(args))
          callback(library:build_objects_from_sql(self, result))
        end)
      query:Execute()
    end
  end

  search_method('first', false, true)
  --- Returns the first object with this model
  -- @param ...
  -- @return An object
  function library.meta.model:first(...)
    if (self.__schema.__sync) then
      return library.__buffer[self.__name][1]
    else
      local args = {...}
      local query = library.mysql:Select(library:get_table_name(self.__name))
        query:OrderByAsc('id') -- TODO: account for no id
        query:Limit(1)
        query:Callback(function(result)
          local callback = library:get_callback_arg(unpack(args))
          callback(library:build_objects_from_sql(self, result, true))
        end)
      query:Execute()
    end
  end

  search_method('find_by', true, true)
  --- Returns an object with a matching key/value pair.
  -- @param key Name of the property to match
  -- @param value Value of the property to match
  -- @param ...
  -- @return An object
  function library.meta.model:find_by(key, value, ...)
		key = to_snake_case(key)

    if (self.__schema.__sync) then
      local result

      for k, v in pairs(library.__buffer[self.__name]) do
        if (v[key] and tostring(v[key]) == tostring(value)) then -- TODO: unhack this
          result = v
          break
        end
      end

      return result
    else
      local args = {...}
      local query = library.mysql:Select(library:get_table_name(self.__name))
        query:Where(key, value)
        query:Limit(1)
        query:Callback(function(result)
          local callback = library:get_callback_arg(unpack(args))
          callback(library:build_objects_from_sql(self, result, true))
        end)
      query:Execute()
    end
  end

  --- Helpers
  -- @section helpers

  --- Creates objects from the given SQL result.
  -- @param model Model to build object from
  -- @param result SQL result set
  -- @param[opt] single_result Whether or not this should return a single object
  -- @return Table of objects, or a single object as specified by single_result
  function library:build_objects_from_sql(model, result, single_result)
    if (!result or type(result) != 'table' or #result < 1) then
      return {}
    end

    local objects = {}

    for id, row in pairs(result) do
      local object = model:New()

      for k, v in pairs(row) do
        if (!model.__schema[k] or v == 'NULL') then
          continue
        end

        object[k] = v
      end

      object.__bsaved = true
      table.insert(objects, object)
    end

    if (single_result) then -- TODO: should avoid building the results table here
      return objects[1]
    end

    return objects
  end

  --- Returns a table of an object's properties. Useful for iterating over properties.
  -- @param object Object to get properties from
  -- @return Table of key/values for the given object
  function library:get_object_table(object)
    local result = {}

    for k, v in pairs(object) do
      if (string.sub(k, 1, 2) == '__' or !object.__model.__schema[k]) then
        continue
      end

      result[k] = v
    end

    return result
  end

  --- Creates a model and does the appropriate database/networking setup for it.
  -- @param name Name of the model.
  -- @param setup Function to execute when setting up the model.
  function library:setup_model(name, setup)
    local schema = setmetatable({
      __sync = true,
      id = -1
    }, self.meta.schema)
    local replication = setmetatable({}, self.meta.replication)
    local model = setmetatable({}, self.meta.model)

    setup(schema, replication) -- TODO: use pcall here

		-- Setup find_by_* helpers.
		-- Example: my_obj:find_by_name('foo')
		for k, v in pairs(schema) do
			if isstring(k) and isstring(v) then
				model['find_by_'..k] = function(object, ...)
					return object:find_by(k, ...)
				end
			end
		end
    
    model.__name = name
    model.__schema = schema
    model.__replication = replication

    self.model[name] = model
    self.__buffer[name] = self.__buffer[name] or {}

    if (replication.enabled) then
      assert(replication.condition and type(replication.condition) == 'function', 'Replicated models need to have a condition!')
      self:network_model(model)
    end

    self:queue_push('schema', name)
  end

  --- Returns a table of players that passed the given filter function.
  -- @param func The filter function to run players through
  -- @return A table of players
  function library:filter_players(func)
    local filter = {}

    for k, v in pairs(player.GetAll()) do
      if (func(v)) then
        table.insert(filter, v)
      end
    end

    return filter
  end

  --- Networks a model to clients. This does not check if replication is applicable for the object's model, so you'll have to do it yourself!
  -- @param model Model to network
  function library:network_model(model)
    local players = self:filter_players(model.__replication.condition)

    if (#players < 1) then
      return
    end

    local data = {}

    for k, v in pairs(model.__schema) do
      if (string.sub(k, 1, 2) == '__') then
        continue
      end

      data[k] = true
    end

    self:start_net_msg(MESSAGE.SCHEMA)
      net.Writestring(model.__name)
      self:write_net_table(data)
    net.Send(players[1]) -- TODO: why only the first player?
  end

  --[[
    Database-specific
  --]]

  --- Queues a database push with the given type.
  -- @param type The type of data push
  -- @param data The data to push
  function library:queue_push(type, data)
    table.insert(self.queue.push, {
      type = type,
      data = data
    })
  end

  --- Pulls all of a model's objects from the database and stores it in memory.
  -- @param model The model to sync
  function library:perform_model_sync(model)
    local query = self.mysql:Select(self:get_table_name(model.__name))
      query:Callback(function(result)
        local objects = self:build_objects_from_sql(model, result)

        for k, v in pairs(objects) do -- TODO: don't send a message for each object
          self:network_object(v)
        end

        if (model.__schema.__onsync) then
          model.__schema.__onsync() -- TODO: pcall this
        end
      end)
    query:Execute()
  end

  --- Builds an SQL query given the type.
  -- @param type The type of query
  -- @param data Any extra data
  -- @return An SQL query object
  function library:build_query(type, data)
    if (type == 'schema') then
      local model = self.model[data]
      local query = self.mysql:Create(self:get_table_name(data))

      for k, v in pairs(model.__schema) do
        if (string.sub(k, 1, 2) == '__') then
          continue
        end

        if (k == 'id') then
          query:Create('id', 'INTEGER NOT NULL AUTO_INCREMENT')
          query:PrimaryKey('id')
        else
          query:Create(k, v)
        end
      end

      if (model.__schema.__sync) then
        query:Callback(function()
          self:perform_model_sync(model)
        end)
      end

      return query
    elseif (type == 'object') then
      local model = data.__model
      local query
      local update_func = 'Update'

      if (data.__bsaved) then
        query = self.mysql:Update(self:get_table_name(model.__name))
        query:Where('id', data.id) -- TODO: account for models without ids
      else
        query = self.mysql:Insert(self:get_table_name(model.__name))
        query:Callback(function(result, status, lastid)
          data.__bsaved = true
        end)

        update_func = 'Insert'
      end

      for k, v in pairs(data) do
        if (string.sub(k, 1, 2) == '__' or k == 'id') then
          continue
        end

        query[update_func](query, k, v)
      end

      return query
    end
  end

  --- Handles some database stuff. Should be called constantly - about every second is enough.
  -- This is already done automatically.
  function library:think()
    if (!self.mysql:IsConnected()) then
      return
    end

    if (#self.queue.push > 0) then
      local item = self.queue.push[1]

      if (item) then
        local query = self:build_query(item.type, item.data)
        query:Execute()

        table.remove(self.queue.push, 1)
      end
    end
  end

  do
    timer.Create('ActiveRecord.think', 1, 0, function()
      library:think()
    end)
  end

  --- Called when the prefix for the project has been set.
  -- Currently used for setting up networking events.
  -- This should NOT be overridden, otherwise things will break BADLY!
  function library:on_prefix_set()
    util.AddNetworkstring(self:get_name() .. '.message')

    if (!self.mysql) then
      print_log('SQL wrapper not loaded trying to include now...')
      self.mysql = include('dependencies/sqlwrapper/mysql.lua')
    end

    --[[
      Network events
    --]]
    hook.Add('PlayerInitialSpawn', self:get_name() .. ':PlayerInitialSpawn', function(player)
      for model_name, model in pairs(library.model) do
        if (model.__replication.enabled) then
          self:network_model(model)

          if (model.__schema.__sync) then
            for k, v in pairs(library.__buffer[model_name]) do
              self:network_object(v)
            end
          end
        end
      end
    end)

    net.Receive(self:get_name() .. '.message', function(length, player)
      local message = net.ReadUInt(8)

      if (message == MESSAGE.REQUEST) then
        local model_name = net.Readstring()

        if (self:check_request_condition(model_name, player)) then
          local model = self.model[model_name]
          local schema = model.__schema

          local req_id = net.Readstring()
          local criteria = self:read_net_table()

          local method = criteria[1]
          local key = tostring(criteria[2]) -- TODO: check for different operators (e.g > ?)
          local value = criteria[3]

          -- TODO: check if replication config is allowed to pull from database
          local search_method = self.search_methods[method]

          if (search_method and
            (search_method.require_key and string.sub(key, 1, 2) != '__' and schema[key]) or
            (!search_method.require_key)) then
            if (schema.__sync) then
              local result = model[method](model, key, value)

              self:start_net_msg(MESSAGE.REQUEST)
                net.Writestring(req_id)
                net.Writestring(model_name)

                net.WriteBool(search_method.single_result)

                local objects = {}

                if (search_method.single_result) then
                  table.insert(objects, self:get_object_table(result))
                else
                  for k, v in pairs(result) do
                    table.insert(objects, self:get_object_table(v))
                  end
                end

                self:write_net_table(objects)
              net.Send(player)
            else
              local args = {model}

              if (search_method.require_key) then
                table.insert(args, key)
                table.insert(args, value)
              end

              table.insert(args, function(result) -- TODO: WHAT
                if (!IsValid(player) or !player:IsPlayer()) then
                  return
                end

                self:start_net_msg(MESSAGE.REQUEST)
                  net.Writestring(req_id)
                  net.Writestring(model_name)

                  net.WriteBool(search_method.single_result)

                  local objects = {}

                  if (search_method.single_result) then
                    table.insert(objects, self:get_object_table(result[1]))
                  else
                    for k, v in pairs(result) do
                      table.insert(objects, self:get_object_table(v))
                    end
                  end

                  self:write_net_table(objects)
                net.Send(player)
              end)

              model[method](unpack(args))
            end
          else
            print_log('Invalid search method or key!')
          end
        end
      end
    end)
  end
end

if (CLIENT) then
  function library:set_prefix(prefix)
    self.config.prefix = string.lower(prefix) .. '_'
    self:on_prefix_set()
  end

  function library:get_name()
    return 'ActiveRecord_' .. self.config.prefix
  end

  function library:request_object(name, criteria, callback)
    local id = self.config.prefix .. CurTime() .. '-' .. math.random(100000, 999999)

    self:start_net_msg(MESSAGE.REQUEST)
      net.Writestring(name)
      net.Writestring(id)
      
      self:write_net_table(criteria)
    net.SendToServer()

    self.queue.pull[id] = callback

    return id
  end

  --[[
    Object
  --]]
  function library:commit_object(object)
    --
  end

  library.meta.object.__index = library.meta.object

  function library.meta.object:save()
    library:commit_object(self)
  end

  --[[
    Model
  --]]
  library.meta.model.__index = library.meta.model

  function library.meta.model:New(add_to_buffer)
    local object = setmetatable({
      __model = self
    }, library.meta.object)

    if (add_to_buffer) then
      table.insert(library.__buffer[self.__name], object)
    end

    return object
  end

  function library.meta.model:all(...)
    library:request_object(self.__name, {
      'all'
    }, library:get_callback_arg(...))
  end

  function library.meta.model:first(...)
    library:request_object(self.__name, {
      'first'
    }, library:get_callback_arg(...))
  end

  function library.meta.model:find_by(key, value, ...)
    library:request_object(self.__name, {
      'find_by', key, value
    }, library:get_callback_arg(...))
  end

  function library:build_objects_from_message(model, result)
    local objects = {}

    for id, data in pairs(result) do
      local object = model:New()

      for k, v in pairs(data) do
        object[k] = v
      end

      table.insert(objects, object)
    end

    return objects
  end

  function library:setup_model(name, schema)
    local model = setmetatable({
      __schema = schema,
      __name = name
    }, self.meta.model)

    self.model[name] = model
    self.__buffer[name] = {}
  end

  --[[
    Networking events
  --]]
  function library:on_prefix_set()
    net.Receive(self:get_name() .. '.message', function(length)
      local message = net.ReadUInt(8)

      if (message == MESSAGE.REQUEST) then
        local id = net.Readstring()
        local model_name = net.Readstring()
        local single_result = net.ReadBool()
        local model = self.model[model_name]

        if (!model) then
          ErrorNoHalt('Received request networking message for invalid model "' .. model_name .. '"!\n')
          return
        end

        if (self.queue.pull[id] and type(self.queue.pull[id]) == 'function') then
          local result = self:read_net_table()
          result = self:build_objects_from_message(model, result)

          if (single_result) then
            result = result[1]
          end

          self.queue.pull[id](result) -- TODO: pcall this
          self.queue.pull[id] = nil
        end
      elseif (message == MESSAGE.SCHEMA) then
        local name = net.Readstring()
        local schema = self:read_net_table()

        self:setup_model(name, schema)
      elseif (message == MESSAGE.UPDATE) then
        local model_name = net.Readstring()
        local model = self.model[model_name]

        if (!model) then
          ErrorNoHalt('Received update networking message for invalid model "' .. model_name .. '"!\n')
          return
        end

        local data = self:read_net_table(data)
        local found = false

        for id, object in pairs(self.__buffer[model_name]) do
          if (object.id == data.id) then
            for k, v in pairs(data) do
              object[k] = v
            end

            print('found object')
            found = true
            break
          end
        end

        if (!found) then
          print('not found, creating new object')
          local object = model:New(true)

          for k, v in pairs(data) do
            object[k] = v
          end
        end
      end
    end)
  end
end

return library
