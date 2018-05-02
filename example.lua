
local ar = include('activerecord.lua')

--[[
  This should be set to something short and unique to your project.
  Default is 'ar'.
]]--
ar:set_prefix('test')

--[[
  Here we set up the model for our object. In this case, the object
  represents a generic user.

  Model name should be in PascalCase.
]]--
ar:setup_model('User',
  function(schema, replication)
    --[[
      Here we describe the properties of the model and how they're
      stored. You call various functions on the schema object that's
      passed as part of the setup function to build your object's
      representation. Valid types include:
        boolean
        integer
        string
        text

      Models are given an auto incremented ID by default, you can
      disable it by calling schema:id(false). You can chain property
      descriptions together to make them look nicer if you'd like.

      In this example, we're making a string property for a player's
      name and Steam ID, and an integer property for the amount of
      imaginary boxes they've received.

      Searching for objects differs depending on whether or not you
      decide to sync the database to the server. Syncing makes the
      server the 'owner' of the data in the sense that the database
      replicates what the server has. This behaviour is enabled by
      default and allows you to use the search functions without
      callbacks.

      Disabling syncing using schema:sync(false) makes it so that the
      server doesn't store its own copy of the data, which in turn makes
      the database the owner of the data where the server is only used
      to pull data from the database itself. Doing this requires you
      to specify an extra callback parameter on every search function.

      Leaving database syncing enabled suffices most of the time, but if
      you're concerned about performance/memory issues with tables
      containing a large number of rows (say, a ban list or something),
      you'll probably want to disable syncing and use callbacks instead.

      The preferred naming style of properties is snake_case. If you
      use anything but snake case, the system will automatically internally
      convert your name to snake case.

      Snake case is used so that the find_by_* methods look somewhat sane and
      consistent. It is a part of Luna's convention.
    ]]--
    schema
      :string('name')
      :string('steamid')
      :integer('boxes')

    --[[
      Objects can be replicated to clients if requested. To enable it,
      simply call replication:enable(true).

      Here, we call replication:Sync(true) to have newly-created objects
      sent to the client. We also call replication:sync_existing(true) to
      send all previous objects that exist to the client. You should
      only use sync_existing for small arrays of objects - otherwise
      you'll end up sending a TON of data to clients when you don't have
      to!

      replication:allow_pull(true) enables clients requesting
      object data to trigger a database query to find the object if it 
      doesn't reside in memory. Usually this should be left as false.

      replication:condition(function) decides what client is allowed to
      request data, and what clients the server should update the data
      for (if applicable). !!! NOTE: This always needs to be specified
      if replication for this model is enabled !!! If you want to send
      to all clients, simply return true.
    ]]--
    replication
      :enable(true)
      :sync_existing(true)
      :allow_pull(true)
      :condition(function(player)
        return player:IsAdmin()
      end)
  end
)

--[[
  Now that we've set up our model, we can start using it to save objects to
  the database. Any models that you have created will be stored in the
  library's model table. The properties you've described can be accessed
  as regular lua variables.

  To commit the object and/or its changes to the database, simply call the
  Save method on the object. Query queuing is done automatically.
]]--
do
  local user = ar.model.User:new()
    user.name = '`impulse'
    user.steamid = 'STEAM_1:2:3'
    user.boxes = 9001
  user:save()
end

--[[
  We can also find users quite easily. Here, we retrieve a list of all the
  users.
]]--
do
  local users = ar.model.User:all()

  for k, v in pairs(users) do
    print(string.format('User %i has name %s', v.id, v.name))
  end
end

--[[
  Using the model#first method returns the first created user (or user with the
  lowest ID if applicable).
]]--
do
  local user = ar.model.User:first()

  -- Always check to make sure you got a valid result!
  if (user) then
    print(string.format('User %i has name %s', user.id, user.name))
  end
end

--[[
  You can find a user by a specific condition. FindBy requires a property
  name and required value for that property. You can also set a different
  condition to match with by using the property name, followed by an
  operator with a question mark.

  You can have multiple conditions, simply by adding another property name/
  value pair. See the Where block below this one for an example.
]]--
do
  local user = ar.model.User:find_by_id(1)
  local user = ar.model.User:find_by('boxes > ?', 100)

  if (user) then
    print(string.format('User %i has name %s', user.id, user.name))
  end
end

--[[
  Where works like FindBy, except it returns a table of all objects that
  fit the criteria.
]]--
do
  local users = ar.model.User:where(
    'boxes > ?', 9000,
    'name', '`impulse'
  )

  for k, v in pairs(users) do
    print(string.format('User %i has name %s', v.id, v.name))
  end
end

--[[
  To delete an object from the database, simply call Destroy on the object.
  This means you can use any of the search methods to find the user you want
  to delete.
]]--
do
  local user = ar.model.User:find_by_id(1)
  user:Destroy()
end
