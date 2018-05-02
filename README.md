# gmod-activerecord
A **work-in-progress** library for Garry's Mod that implements persistent objects via an active record pattern.

## Documentation
If you need a quick reference, check out the [documentation](https://impulsh.github.io/gmod-activerecord). The documentation is automatically built and updated from the source.

## Prerequisites
This library requires you to have https://github.com/alexgrist/GLua-MySQL-Wrapper included somewhere on your server. If it's nowhere to be found, activerecord will try to include the one bundled with this repo (make sure you pull this repository recursively so you also grab the submodule).

## Getting started
If all you need is a way to store objects in a database, the following guide will set you up in less than five minutes. :muscle:

#### Including the library
Activerecord was designed to run alongside other copies of itself so that multiple addons could use it together without running into conflicts. As such, including it into your project takes a few extra lines. Note that this section is all **serverside**.

first off, you'll need to include the library and store it somewhere so you can reference it. At this point the library won't do anything until you set a *prefix* for your project. This prefix should be unique to your project to prevent some potentially nasty conflicts with the database. Once the prefix is set and the database is connected, you'll be ready to roll.
```Lua
local ar = include('activerecord.lua')
ar:set_prefix('example')
ar.mysql:Connect(); -- Connect to SQLite
```

#### Creating models
Now you'll want to define a model serverside so you can start saving objects.
```Lua
ar:setup_model('user', function(t)
  t:string('steam_id')
  t:string('community_id')
  t:string('name')
end)
```

#### Creating and editing objects
Once you've created a model or two, you can start creating and storing objects.
```Lua
local user = ar.model.user:new()
  user.steam_id = 'STEAM_0:1:23456789'
  user.community_id = '1234567890'
  user.name = 'John Doe'
user:save()
```
Objects are edited by simply modifying the fields as you would with a regular table. To commit these changes to the database, call `save()` on the object.

#### Finding objects
There are various ways you can fetch some objects. You can fetch all of them,
```Lua
local users = ar.model.user:all()
```
maybe fetch the first one,
```Lua
local user = ar.model.user:first()
```
or perhaps find a user by their name.
```Lua
local user = ar.model.user:find_by_name('John Doe')
```

Since these search functions return objects, you can modify and save them as usual.
```Lua
local user = ar.model.user:find_by_name('John Doe')
  user.name = 'Bob Doe'
user:save()
```

You can also do it directly:
```lua
local user = ar.model.user:find_by('name', 'John Doe')
```

## Replication
If you want clients to be able to fetch and read objects, you'll need to set up your model to use replication. first off, you'll need to include the library clientside if you want it to work (duh). If you don't need replication, then you don't need to include activerecord clientside. Then, modify your model to include a replication definition.
```Lua
ar:setup_model('user', function(schema, replication)
  schema
    :string('steam_id')
    :string('community_id')
    :string('name')
    
  replication
    :enable(true)
    :condition(function(player)
      return player:IsAdmin()
    end)
end)
```
Note that we specified a condition function - this is **required** to be defined! Activerecord will yell at you if you don't. Guess what? That's all you need. You can use the same functions on the client to search for objects. You can't save objects - but that's being worked on. :ok_hand:

## License
This library is available the MIT license. Check out the [LICENSE](../master/LICENSE) file.

## Convention over Configuration
This fork of ActiveRecord is a part of the Luna project. It uses the same coding convention in order to make sure the code looks consistent and that everyone has easier time reading the code written by others.
To learn more about the convention, please scroll to the bottom of [Luna's Readme file](https://github.com/MrMe0w/Luna/blob/master/README.md).
