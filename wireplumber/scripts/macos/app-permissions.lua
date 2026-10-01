-- App permissions for sound and camera (docs/os-plan.md, "App permissions").
--
-- Sandboxed apps (PipeWire access "flatpak": apps started by app-sandbox, and Flatpak
-- apps) only see and only get linked to microphones, outputs and cameras they may use.
-- The decisions are in the system's permission store, table "devices", entries
-- "microphone", "speakers", "camera": "yes" or "no". Without a decision a new stream
-- waits unlinked and the shell asks: a request "request:<app>:<entry>" in the metadata
-- "macos-permissions" (read by `app-permissions watch-sound` for Privacy.qml), removed
-- again once decided. Once allowed, waiting streams are linked right away.
--
-- Recording anything (also what the speakers play) needs the microphone permission.
-- Taking a permission away cuts the app's running streams at once.
--
-- What other apps play stays hidden – except for apps allowed to record the screen
-- (table "org.riptide.sandbox", entry "screen"), which on a Mac also covers system audio:
-- they see other apps' playback, so a shared screen or window carries its sound
-- (Discord). PipeWire only links two app streams when each app sees the other's, so a
-- recording of such an app is visible to the apps it records.

lutils = require ("linking-utils")
cutils = require ("common-utils")
log = Log.open_topic ("s-client")
pps = Plugin.find ("portal-permissionstore")

DEVICE_KINDS = { microphone = true, speakers = true, camera = true }
STREAM_KINDS = {
  ["Stream/Input/Audio"] = "microphone",
  ["Stream/Output/Audio"] = "speakers",
  ["Stream/Input/Video"] = "camera",
}

-- entry ("microphone" …) → { app → { values } }, kept up to date by the store's signal
cache = {}

function lookup (entry)
  if cache [entry] == nil then
    cache [entry] = (pps and pps:call ("lookup", "devices", entry)) or {}
  end
  return cache [entry]
end

-- The screen permission lives in our own table, not in "devices"
screen_cache = nil

function screen_allowed (app)
  if screen_cache == nil then
    screen_cache = (pps and pps:call ("lookup", "org.riptide.sandbox", "screen")) or {}
  end
  for _, v in pairs (screen_cache [app] or {}) do
    if v == "yes" then
      return true
    end
  end
  return false
end

function state (app, entry)
  local values = lookup (entry) [app]
  if values then
    for _, v in pairs (values) do
      if v == "yes" or v == "no" then
        return v
      end
    end
  end
  return "ask"
end

-- The app id of a sandboxed client, nil for everything else
function sandboxed_app (client)
  local props = client.properties
  local app = props ["pipewire.access.portal.app_id"]
  if props ["pipewire.access"] == "flatpak" and app ~= nil and app ~= "" then
    return app
  end
  return nil
end

-- What a sandboxed client sees: everything read-only as for Flatpak, devices only with
-- permission, our request channel not at all
pm = PermissionManager ()
pm:set_default_permissions (Perm.RX)

function device_rule (entry)
  return function (_, client, _)
    local app = sandboxed_app (client)
    if app ~= nil and state (app, entry) == "yes" then
      return Perm.RX
    end
    return Perm.NONE
  end
end

pm:add_interest_match (device_rule ("microphone"),
    Interest { type = "node", Constraint { "media.class", "#", "Audio/Source*" } })
pm:add_interest_match (device_rule ("speakers"),
    Interest { type = "node", Constraint { "media.class", "#", "Audio/Sink*" } })
pm:add_interest_match (device_rule ("camera"),
    Interest { type = "node", Constraint { "media.class", "#", "Video/Source*" } })
pm:add_interest_match (function () return Perm.NONE end,
    Interest { type = "metadata", Constraint { "metadata.name", "=", "macos-permissions" } })
-- The sandboxed app a node belongs to (nil: none, or not a sandboxed one)
function owner_app (node)
  local id = tonumber (node.properties ["client.id"])
  local owner = id and clients_om:lookup {
    Constraint { "bound-id", "=", id, type = "gobject" },
  }
  return owner and sandboxed_app (owner)
end

-- Other apps' streams stay invisible (what they play, their titles); their own are theirs.
-- Screen recording (with system audio): see what others play; its recordings are seen
pm:add_interest_match (function (_, client, node)
      if tonumber (node.properties ["client.id"]) == client ["bound-id"] then
        return Perm.ALL
      end
      local class = node.properties ["media.class"]
      if class == "Stream/Output/Audio" then
        local app = sandboxed_app (client)
        if app ~= nil and screen_allowed (app) then
          return Perm.RX
        end
      elseif class == "Stream/Input/Audio" then
        local recorder = owner_app (node)
        if recorder ~= nil and screen_allowed (recorder) then
          return Perm.RX
        end
      end
      return Perm.NONE
    end,
    Interest { type = "node", Constraint { "media.class", "#", "Stream/*" } })

SimpleEventHook {
  name = "client/macos-app-permissions",
  after = "client/find-config-access",
  before = "client/find-flatpak-access",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "select-access" },
    },
  },
  execute = function (event)
    local client = event:get_subject ()
    if event:get_data ("permission-manager") == nil and sandboxed_app (client) ~= nil then
      log:info (client, "sandboxed app " .. sandboxed_app (client) .. ": devices by permission")
      event:set_data ("permission-manager", pm)
    end
  end
}:register ()

-- Requests to the shell
requests = ImplMetadata ("macos-permissions")
requests:activate (Features.ALL, function (_, e)
  if e then
    log:warning ("metadata macos-permissions: " .. tostring (e))
  end
end)

asked = {}   -- metadata key → { app, entry } while the question is open

function ask (app, entry)
  local key = "request:" .. app .. ":" .. entry
  if asked [key] then
    return
  end
  asked [key] = { app = app, entry = entry }
  requests:set (0, key, "Spa:String:JSON",
      Json.Object { app = app, kind = entry, time = os.time () }:to_string ())
end

clients_om = ObjectManager { Interest { type = "client" } }
clients_om:activate ()

-- Remove the links of a stream (permission taken away while it runs)
function unlink (si)
  local om = cutils.get_object_manager ("session-item")
  for link in om:iterate { type = "SiLink" } do
    local out_id = tonumber (link.properties ["out.item.id"])
    local in_id = tonumber (link.properties ["in.item.id"])
    if out_id == si.id or in_id == si.id then
      lutils:get_flags (out_id).peer_id = nil
      lutils:get_flags (in_id).peer_id = nil
      link:remove ()
      log:info (si, "... link removed: permission taken away")
    end
  end
end

-- Before any target is picked: no link for a stream the app may not use
SimpleEventHook {
  name = "linking/macos-app-permissions",
  before = "linking/find-defined-target",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "select-target" },
    },
  },
  execute = function (event)
    local si = event:get_subject ()
    local entry = STREAM_KINDS [si.properties ["media.class"]]
    if entry == nil then
      return
    end
    local node = si:get_associated_proxy ("node")
    local client_id = node and node.properties ["client.id"]
    if client_id == nil then
      return
    end
    local client = clients_om:lookup {
      Constraint { "bound-id", "=", tonumber (client_id), type = "gobject" },
    }
    if client == nil then
      -- not known here yet: no link now (never let it through unchecked), look again soon
      log:info (si, "client " .. client_id .. " not known yet: linking later")
      event:stop_processing ()
      Core.timeout_add (300, function ()
        local source = Plugin.find ("standard-event-source")
        if source then
          source:call ("schedule-rescan", "linking")
        end
        return false
      end)
      return
    end
    local app = sandboxed_app (client)
    if app == nil then
      return
    end
    local now = state (app, entry)
    if now == "yes" then
      return
    end
    log:info (si, string.format ("%s may not use the %s (%s): not linked", app, entry, now))
    if now == "ask" then
      ask (app, entry)
    end
    unlink (si)
    event:stop_processing ()
  end
}:register ()

-- A decision changed: new permissions for every sandboxed client, link what now may be
if pps then
  pps:connect ("changed", function (_, table, entry, deleted, permissions)
    if table == "org.riptide.sandbox" and entry == "screen" then
      screen_cache = (not deleted and permissions) or {}
      pm:update_permissions ()
      return
    end
    if table ~= "devices" or not DEVICE_KINDS [entry] then
      return
    end
    cache [entry] = (not deleted and permissions) or {}
    for key, request in pairs (asked) do
      if request.entry == entry and state (request.app, entry) ~= "ask" then
        asked [key] = nil
        requests:set (0, key, nil, nil)
      end
    end
    pm:update_permissions ()
    local source = Plugin.find ("standard-event-source")
    if source then
      source:call ("schedule-rescan", "linking")
    end
  end)
end
