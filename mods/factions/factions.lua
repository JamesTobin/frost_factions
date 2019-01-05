--read some basic information
local factions_worldid = minetest.get_worldpath()

--! @class factions
--! @brief main class for factions
factions = {}

--! @brief runtime data
factions.factions = {}
factions.parcels = {}
factions.players = {}

---------------------
--! @brief returns whether a faction can be created or not (allows for implementation of blacklists and the like)
--! @param name String containing the faction's name
factions.can_create_faction = function(name)
    if #name > factions_config.faction_name_max_length then
        return false
    elseif factions.factions[name] then
        return false
    else
        return true
    end
end


factions.Faction = {
}

util = {
    coords3D_string = function(coords)
        return coords.x..", "..coords.y..", "..coords.z
    end
}

factions.Faction.__index = factions.Faction

starting_ranks = {["leader"] = {"build","door","container","name","description","motd","invite","kick"
						,"player_title","spawn","with_draw","territory","claim","access","disband","flags","ranks","promote"},
                 ["moderator"] = {"claim","door","build","spawn","invite","kick","promote"},
                 ["member"] = {"build","container","door"}
                }

-- Faction permissions:
--
-- build: dig and place nodes
-- pain_build: dig and place nodes but take damage doing so
-- door: open/close or dig doors
-- container: be able to use containers like chest
-- name: set the faction's name
-- description: Set the faction description
-- motd: set the faction's message of the day
-- invite: (un)invite players to join the faction
-- kick: kick players off the faction
-- player_title: set player titles
-- spawn: set the faction's spawn
-- with_draw: withdraw money from the faction's bank
-- territory: claim or unclaim territory
-- claim: (un)claim parcels of land
-- access: manage access to territory and parcels of land to players or factions
-- disband: disband the faction
-- flags: manage faction's flags
-- ranks: create, edit, and delete ranks
-- promote: set a player's rank
-- diplomacy: be able to control the faction's diplomacy

factions.permissions = {"build","pain_build","door","container","name","description","motd","invite","kick"
						,"player_title","spawn","with_draw","territory","claim","access","disband","flags","ranks","promote"}
factions.permissions_desc = {"dig and place nodes","dig and place nodes but take damage doing so","open/close or dig","be able to use containers like chest","set the faction's name"
						,"Set the faction description","set the faction's message of the day","(un)invite players to join the faction","kick players off the faction","set player titles","set the faction's spawn"
						,"withdraw money from the faction's bank","claim or unclaim territory","(un)claim parcels of land","manage access to territory and parcels of land to players or factions"
						,"disband the faction","manage faction's flags","create, edit, and delete ranks"}
						
-- open: can the faction be joined without an invite?
-- monsters: can monsters spawn on your land?
-- tax_kick: will players be kicked for not paying tax?
-- animals: can animals spawn on your land?
factions.flags = {"open", "monsters", "tax_kick", "animals"}
factions.flags_desc = {"can the faction be joined without an invite?","can monsters spawn on your land?(unused)","will players be kicked for not paying tax?(unused)","can animals spawn on your land?(unused)"}

if factions_config.faction_diplomacy == true then
	table.insert(factions.permissions,"diplomacy")
	
	table.insert(factions.permissions_desc,"be able to control the faction's diplomacy")
	
	local lt = starting_ranks["leader"]
	table.insert(lt,"diplomacy")
	starting_ranks["leader"] = lt
end

function factions.Faction:new(faction) 
    faction = {
		name = "",
        --! @brief power of a faction (needed for parcel claiming)
        power = factions_config.power,
        --! @brief maximum power of a faction
        maxpower = factions_config.maxpower,
        --! @brief power currently in use
        usedpower = 0.,
        --! @brief list of player names
        players = {},
		--! @brief list of player names online
		onlineplayers = {},
		--! @brief list of player names offline
		offlineplayers = {},
        --! @brief table of ranks/permissions
        ranks = starting_ranks,
        --! @brief name of the leader
        leader = nil,
		--! @brief spawn of the faction
		spawn = {x=0, y=0, z=0},
        --! @brief default joining rank for new members
        default_rank = "member",
        --! @brief default rank assigned to the leader
        default_leader_rank = "leader",
        --! @brief faction's description string
        description = "Default faction description.",
		--! @brief faction's message of the day.
		message_of_the_day = "",
        --! @brief list of players currently invited (can join with /f join)
        invited_players = {},
        --! @brief table of claimed parcels (keys are parcelpos strings)
        land = {},
        --! @brief table of allies
        allies = {},
		--
		request_inbox = {},
        --! @brief table of enemies
        enemies = {},
		--!
		neutral = {},
        --! @brief table of parcels/factions that are under attack
        attacked_parcels = {},
        --! @brief whether faction is closed or open (boolean)
        join_free = false,
        --! @brief gives certain privileges
        is_admin = false,
		--! @brief if a player on the faction has a nil rank
		rankless = false,
        --! @brief last time anyone logged on
        last_logon = os.time(),
		--! @brief how long this has been without parcels
		no_parcel = os.time(),
    } or faction
    setmetatable(faction, self)
    return faction
end


--! @brief create a new empty faction
function factions.new_faction(name,do_not_save)
    local faction = factions.Faction:new(nil)
    faction.name = name
    factions.factions[name] = faction
    faction:on_create()
	minetest.after(1, 
	function(f)
		f:on_no_parcel()
	end,faction)
	if not do_not_save then
		factions.bulk_save()
	end
    return faction
end

function factions.start_diplomacy(name,faction)
	for i,fac in pairs(factions.factions) do
		if i ~= name and not (faction.neutral[i] or faction.allies[i] or faction.enemies[i]) then
			if factions_config.faction_diplomacy == true then
				faction:new_neutral(i)
				fac:new_neutral(name)
			else
				faction:new_enemy(i)
				fac:new_enemy(name)
			end
		end
	end
end

function factions.Faction.set_name(self, name)
	local oldname = self.name
	local oldfaction = factions.factions[oldname]
	self.name = name
	for i,fac in pairs(factions.factions) do
		if i ~= oldname then
			if fac.neutral[oldname] then
				fac.neutral[oldname] = nil
				fac.neutral[name] = true
			end
			if fac.allies[oldname] then
				fac.allies[oldname] = nil
				fac.allies[name] = true
			end
			if fac.enemies[oldname] then
				fac.enemies[oldname] = nil
				fac.enemies[name] = true
			end
		end
	end
	for parcel in pairs(self.land) do
	factions.parcels[parcel] = self.name
	end
	for playername in pairs(self.players) do
	factions.players[playername] = self.name
	end
	factions.factions[oldname] = nil
	factions.factions[name] = oldfaction
	factions.factions[name].name = name
	for playername in pairs(self.onlineplayers) do
		updateFactionName(playername,name)
	end
	self:on_set_name(oldname)
	factions.bulk_save()
end

function factions.Faction.increase_power(self, power)
    self.power = self.power + power
    if self.power > self.maxpower  - self.usedpower then
        self.power = self.maxpower - self.usedpower
    end
	for i in pairs(self.onlineplayers) do
		updateHudPower(minetest.get_player_by_name(i),self)
	end
    factions.bulk_save()
end

function factions.Faction.decrease_power(self, power)
    self.power = self.power - power
	for i in pairs(self.onlineplayers) do
		updateHudPower(minetest.get_player_by_name(i),self)
	end
    factions.bulk_save()
end

function factions.Faction.increase_maxpower(self, power)
    self.maxpower = self.maxpower + power
	for i in pairs(self.onlineplayers) do
		updateHudPower(minetest.get_player_by_name(i),self)
	end
    factions.bulk_save()
end

function factions.Faction.decrease_maxpower(self, power)
    self.maxpower = self.maxpower - power
    if self.maxpower < 0. then -- should not happen
        self.maxpower = 0.
    end
	for i in pairs(self.onlineplayers) do
		updateHudPower(minetest.get_player_by_name(i),self)
	end
end

function factions.Faction.increase_usedpower(self, power)
    self.usedpower = self.usedpower + power
	for i in pairs(self.onlineplayers) do
		updateHudPower(minetest.get_player_by_name(i),self)
	end
end

function factions.Faction.decrease_usedpower(self, power)
    self.usedpower = self.usedpower - power
    if self.usedpower < 0. then
        self.usedpower = 0.
    end
	for i in pairs(self.onlineplayers) do
		updateHudPower(minetest.get_player_by_name(i),self)
	end
end
-- power-per-players only.
function factions.Faction.check_power(self)
	if factions_config.enable_power_per_player then
		for player,unused in pairs(self.players) do
			local ip = factions_ip.player_ips[player]
			local notsame = true
			for i,k in pairs(self.players) do
				local other_ip = factions_ip.player_ips[i]
				if other_ip == ip then
					notsame = false
					break
				end
			end
			if notsame then
				self:increase_maxpower(factions_config.powermax_per_player)
			end
		end
	end
end

function factions.Faction.count_land(self)
    local count = 0.
    for k, v in pairs(self.land) do
        count = count + 1
    end
    return count
end

minetest.register_on_prejoinplayer(function(name, ip)
	factions_ip.player_ips[name] = ip
end)

function factions.Faction.add_player(self, player, rank)
    self:on_player_join(player)
	if factions_config.enable_power_per_player then
		local ip = factions_ip.player_ips[player]
		local notsame = true
		for i,k in pairs(self.players) do
			local other_ip = factions_ip.player_ips[i]
			if other_ip == ip then
				notsame = false
				break
			end
		end
		if notsame then
			self:increase_maxpower(factions_config.powermax_per_player)
		end
	end
	self.players[player] = rank or self.default_rank
    factions.players[player] = self.name
    self.invited_players[player] = nil
	local pdata = minetest.get_player_by_name(player)
	local ipc = pdata:is_player_connected(player)
	if ipc then
		createHudFactionName(pdata,self.name)
		createHudPower(pdata,self)
		self.offlineplayers[player] = nil
		self.onlineplayers[player] = 1
	else
		self.offlineplayers[player] = 1
		self.onlineplayers[player] = nil
	end
    factions.bulk_save()
end

function factions.Faction.check_players_in_faction(self)
	for i,k in pairs(self.players) do
		return true
	end
	self:disband("Zero players on faction.")
	return false
end

function factions.Faction.remove_player(self, player)
    self.players[player] = nil
    factions.players[player] = nil
    self:on_player_leave(player)
	self:check_players_in_faction(self)
	if factions_config.enable_power_per_player then
		local ip = factions_ip.player_ips[player]
		local notsame = true
		for i,k in pairs(self.players) do
			local other_ip = factions_ip.player_ips[i]
			if other_ip == ip then
				notsame = false
				break
			end
		end
		if notsame then
			self:decrease_maxpower(factions_config.powermax_per_player)
		end
	end
	local pdata = minetest.get_player_by_name(player)
	local ipc = pdata:is_player_connected(player)
	if ipc then
		removeHud(pdata,"factionName")
		removeHud(pdata,"powerWatch")
	end
		self.offlineplayers[player] = nil
		self.onlineplayers[player] = nil
    factions.bulk_save()
end

--! @param parcelpos position of the wanted parcel
--! @return whether this faction can claim a parcelpos
function factions.Faction.can_claim_parcel(self, parcelpos)
    local fac = factions.parcels[parcelpos]
    if fac then
        if factions.factions[fac].power < 0. and self.power >= factions_config.power_per_parcel and not self.allies[factions.factions[fac].name] and not self.neutral[factions.factions[fac].name] then
            return true
        else
            return false
        end
    elseif self.power < factions_config.power_per_parcel then
        return false
    end
    return true
end

--! @brief claim a parcel, update power and update global parcels table
function factions.Faction.claim_parcel(self, parcelpos)
    -- check if claiming over other faction's territory
    local otherfac = factions.parcels[parcelpos]
    if otherfac then
        local faction = factions.factions[otherfac]
        faction:unclaim_parcel(parcelpos)
		faction:parcelless_check()
    end
    factions.parcels[parcelpos] = self.name
    self.land[parcelpos] = true
    self:decrease_power(factions_config.power_per_parcel)
    self:increase_usedpower(factions_config.power_per_parcel)
    self:on_claim_parcel(parcelpos)
	self:parcelless_check()
    factions.bulk_save()
end

--! @brief claim a parcel, update power and update global parcels table
function factions.Faction.unclaim_parcel(self, parcelpos)
    factions.parcels[parcelpos] = nil
    self.land[parcelpos] = nil
    self:increase_power(factions_config.power_per_parcel)
    self:decrease_usedpower(factions_config.power_per_parcel)
    self:on_unclaim_parcel(parcelpos)
	self:parcelless_check()
    factions.bulk_save()
end

function factions.Faction.parcelless_check(self)
	if self.land then
		local count = 0
		for index, value in pairs(self.land) do
			count = count + 1
			break
		end
		if count > 0 then
			if self.no_parcel ~= -1 then
				self:broadcast("Faction " .. self.name .. " will not be disbanded because it now has parcels.")
			end
			self.no_parcel = -1
		else
			self.no_parcel = os.time()
			self:on_no_parcel()
		end
	end
end

--! @brief disband faction, updates global players and parcels table
function factions.Faction.disband(self, reason)
	if not self.is_admin then
		for i,v in pairs(factions.factions) do
			if v.name ~= self.name then
				if v.enemies[self.name] then
					v:end_enemy(self.name)
				end
				if v.allies[self.name] then
					v:end_alliance(self.name)
				end
				if v.neutral[self.name] then
					v:end_neutral(self.name)
				end
			end
		end
		for k, _ in pairs(self.players) do -- remove players affiliation
			factions.players[k] = nil
		end
		for k, v in pairs(self.land) do -- remove parcel claims
			factions.parcels[k] = nil
		end
		self:on_disband(reason)
		for i,l in pairs(self.onlineplayers) do
			removeHud(i,"factionName")
			removeHud(i,"powerWatch")
		end
		factions.factions[self.name] = nil
		factions.bulk_save()
	end
end

--! @brief change the faction leader
function factions.Faction.set_leader(self, player)
    if self.leader then
        self.players[self.leader] = self.default_rank
    end
    self.leader = player
    self.players[player] = self.default_leader_rank
    self:on_new_leader()
    factions.bulk_save()
end

function factions.Faction.set_message_of_the_day(self,text)
    self.message_of_the_day = text
    factions.bulk_save()
end

--! @brief check permissions for a given player
--! @return boolean indicating permissions. Players not in faction always receive false
function factions.Faction.has_permission(self, player, permission)
    local p = self.players[player]
    if not p then
        return false
    end
    local perms = self.ranks[p]
	if perms then
		for i in ipairs(perms) do
			if perms[i] == permission then
				return true
			end
		end
	else
		if not self.rankless then
			self.rankless = true
			factions.bulk_save()
		end
	end
    return false
end

function factions.Faction.set_description(self, new)
    self.description = new
    self:on_change_description()
    factions.bulk_save()
end

--! @brief places player in invite list
function factions.Faction.invite_player(self, player)
    self.invited_players[player] = true
    self:on_player_invited(player)
    factions.bulk_save()
end

--! @brief removes player from invite list (can no longer join via /f join)
function factions.Faction.revoke_invite(self, player)
    self.invited_players[player] = nil
    self:on_revoke_invite(player)
    factions.bulk_save()
end
--! @brief set faction openness
function factions.Faction.toggle_join_free(self, bool)
    self.join_free = bool
    self:on_toggle_join_free()
    factions.bulk_save()
end

--! @return true if a player can use /f join, false otherwise
function factions.Faction.can_join(self, player)
    return self.join_free or self.invited_players[player]
end

function factions.Faction.new_alliance(self, faction)
    self.allies[faction] = true
    self:on_new_alliance(faction)
    if self.enemies[faction] then
        self:end_enemy(faction)
    end
	if self.neutral[faction] then
        self:end_neutral(faction)
    end
    factions.bulk_save()
end

function factions.Faction.end_alliance(self, faction)
    self.allies[faction] = nil
    self:on_end_alliance(faction)
    factions.bulk_save()
end

function factions.Faction.new_neutral(self, faction)
    self.neutral[faction] = true
    self:on_new_neutral(faction)
    if self.allies[faction] then
        self:end_alliance(faction)
    end
    if self.enemies[faction] then
        self:end_enemy(faction)
    end
    factions.bulk_save()
end

function factions.Faction.end_neutral(self, faction)
    self.neutral[faction] = nil
    self:on_end_neutral(faction)
    factions.bulk_save()
end

function factions.Faction.new_enemy(self, faction)
    self.enemies[faction] = true
    self:on_new_enemy(faction)
    if self.allies[faction] then
        self:end_alliance(faction)
    end
	if self.neutral[faction] then
        self:end_neutral(faction)
    end
    factions.bulk_save()
end

function factions.Faction.end_enemy(self, faction)
    self.enemies[faction] = nil
    self:on_end_enemy(faction)
    factions.bulk_save()
end

--! @brief faction's member will now spawn in a new place
function factions.Faction.set_spawn(self, pos)
    self.spawn = {x=pos.x, y=pos.y, z=pos.z}
    self:on_set_spawn()
    factions.bulk_save()
end

function factions.Faction.tp_spawn(self, playername)
	player = minetest.get_player_by_name(playername)
	if player then
		player:moveto(self.spawn, false)
	end
end

--! @brief create a new rank with permissions
--! @param rank the name of the new rank
--! @param rank a list with the permissions of the new rank
function factions.Faction.add_rank(self, rank, perms)
    self.ranks[rank] = perms
    self:on_add_rank(rank)
    factions.bulk_save()
end

--! @brief replace an rank's permissions
--! @param rank the name of the rank to edit
--! @param add or remove permissions to the rank
function factions.Faction.replace_privs(self, rank, perms)
    self.ranks[rank] = perms
    self:on_replace_privs(rank)
    factions.bulk_save()
end

function factions.Faction.remove_privs(self, rank, perms)
	local revoked = false
	local p = self.ranks[rank]
	for index, perm in pairs(p) do
		if table_Contains(perms,perm) then
			revoked = true
			table.remove(p,index)
		end
	end
	self.ranks[rank] = p
	if revoked then
		self:on_remove_privs(rank,perms)
	else
		self:broadcast("No privilege was revoked from rank "..rank..".")
	end
    factions.bulk_save()
end

function factions.Faction.add_privs(self, rank, perms)
	local added = false
	local p = self.ranks[rank]
	for index, perm in pairs(perms) do
		if not table_Contains(p,perm) then
			added = true
			table.insert(p,perm)
		end
	end
	self.ranks[rank] = p
	if added then
		self:on_add_privs(rank,perms)
	else
		self:broadcast("The rank "..rank.." already has these privileges.")
	end
    factions.bulk_save()
end

function factions.Faction.set_rank_name(self, oldrank, newrank)
	local copyrank = self.ranks[oldrank]
	self.ranks[newrank] = copyrank
	self.ranks[oldrank] = nil
	for player, r in pairs(self.players) do
        if r == oldrank then
            self.players[player] = newrank
        end
    end
	if oldrank == self.default_leader_rank then
		self.default_leader_rank = newrank
		self:broadcast("The default leader rank has been set to "..newrank)
	end
	if oldrank == self.default_rank then
		self.default_rank = newrank
		self:broadcast("The default rank given to new players is set to "..newrank)
	end
    self:on_set_rank_name(oldrank, newrank)
    factions.bulk_save()
end

function factions.Faction.set_def_rank(self, rank)
    for player, r in pairs(self.players) do
        if r == rank or r == nil or not self.ranks[r] then
            self.players[player] = rank
        end
    end
	self.default_rank = rank
	self:on_set_def_rank(rank)
	self.rankless = false
    factions.bulk_save()
end

function factions.Faction.reset_ranks(self)
	self.ranks = starting_ranks
	self.default_rank = "member"
	self.default_leader_rank_rank = "leader"
    for player, r in pairs(self.players) do
        if not player == leader and (r == nil or not self.ranks[r]) then
            self.players[player] = self.default_rank
		elseif player == leader then
			self.players[player] = self.default_leader_rank_rank
        end
    end
	self:on_reset_ranks()
	self.rankless = false
    factions.bulk_save()
end

--! @brief delete a rank and replace it
--! @param rank the name of the rank to be deleted
--! @param newrank the rank given to players who were previously "rank"
function factions.Faction.delete_rank(self, rank, newrank)
    for player, r in pairs(self.players) do
        if r == rank then
            self.players[player] = newrank
        end
    end
    self.ranks[rank] = nil
    self:on_delete_rank(rank, newrank)
	if rank == self.default_leader_rank then
		self.default_leader_rank = newrank
		self:broadcast("The default leader rank has been set to "..newrank)
	end
	if rank == self.default_rank then
		self.default_rank = newrank
		self:broadcast("The default rank given to new players is set to "..newrank)
	end
    factions.bulk_save()
end

--! @brief set a player's rank
function factions.Faction.promote(self, member, rank)
    self.players[member] = rank
    self:on_promote(member)
end

--! @brief send a message to all members
function factions.Faction.broadcast(self, msg, sender)
    local message = self.name.."> "..msg
    if sender then
        message = sender.."@"..message
    end
    message = "Faction<"..message
    for k, _ in pairs(self.onlineplayers) do
        minetest.chat_send_player(k, message)
    end
end

--! @brief checks whether a faction has at least one connected player
function factions.Faction.is_online(self)
    for playername, _ in pairs(self.onlineplayers) do
		return true
    end
    return false
end

function factions.Faction.attack_parcel(self, parcelpos)
	if factions_config.attack_parcel then
		local attacked_faction = factions.get_parcel_faction(parcelpos)
		if attacked_faction then
			if not self.allies[attacked_faction.name] then
				self.power = self.power - factions_config.power_per_attack
				if attacked_faction.attacked_parcels[parcelpos] then 
					attacked_faction.attacked_parcels[parcelpos][self.name] = true
				else
					attacked_faction.attacked_parcels[parcelpos] = {[self.name] = true}
				end
				attacked_faction:broadcast("Parcel ("..parcelpos..") is being attacked by "..self.name.."!!")
				if self.power < 0. then -- punish memers
					minetest.chat_send_all("Faction "..self.name.." has attacked too much and has now negative power!")
				end
				factions.bulk_save()
			else
				self:broadcast("You can not attack that parcel because it belongs to an ally.")
			end
		end    
	end
end

function factions.Faction.stop_attack(self, parcelpos)
    local attacked_faction = factions.parcels[parcelpos]
    if attacked_faction then
        attacked_faction = factions.factions[attacked_faction]
        if attacked_faction.attacked_parcels[parcelpos] then
            attacked_faction.attacked_parcels[parcelpos][self.name] = nil
            attacked_faction:broadcast("Parcel ("..parcelpos..") is no longer under attack from "..self.name..".")
            self:broadcast("Parcel ("..parcelpos..") has been reconquered by "..attacked_faction.name..".")
        end
        factions.bulk_save()
    end
end

function factions.Faction.parcel_is_attacked_by(self, parcelpos, faction)
    if self.attacked_parcels[parcelpos] then
        return self.attacked_parcels[parcelpos][faction.name]
    else
        return false
    end
end

--------------------------
-- callbacks for events --
function factions.Faction.on_create(self)  --! @brief called when the faction is added to the global faction list
    minetest.chat_send_all("Faction "..self.name.." has been created.")
end

function factions.Faction.on_set_name(self,oldname)
    minetest.chat_send_all("Faction "..oldname.." has been changed its name to "..self.name..".")
end

function factions.Faction.on_no_parcel(self)
	local now = os.time() - self.no_parcel
	local l = factions_config.maximum_parcelless_faction_time
    self:broadcast("This faction will disband in "..l-now.." seconds, because it has no parcels.")
end

function factions.Faction.on_player_leave(self, player)
    self:broadcast(player.." has left this faction.")
end

function factions.Faction.on_player_join(self, player)
    self:broadcast(player.." has joined this faction.")
end

function factions.Faction.on_claim_parcel(self, pos)
    self:broadcast("Parcel ("..pos..") has been claimed.")
end

function factions.Faction.on_unclaim_parcel(self, pos)
    self:broadcast("Parcel ("..pos..") has been unclaimed.")
end

function factions.Faction.on_disband(self, reason)
    local msg = "Faction "..self.name.." has been disbanded."
    if reason then
        msg = msg.." ("..reason..")"
    end
    minetest.chat_send_all(msg)
end

function factions.Faction.on_new_leader(self)
    self:broadcast(self.leader.." is now the leader of this faction.")
end

function factions.Faction.on_change_description(self)
    self:broadcast("Faction description has been modified to: "..self.description)
end

function factions.Faction.on_player_invited(self, player)
    minetest.chat_send_player(player, "You have been invited to faction "..self.name)
end

function factions.Faction.on_toggle_join_free(self, player)
    if self.join_free then
        self:broadcast("This faction is now invite-free.")
    else
        self:broadcast("This faction is no longer invite-free.")
    end
end

function factions.Faction.on_new_alliance(self, faction)
    self:broadcast("This faction is now allied with "..faction)
end

function factions.Faction.on_end_alliance(self, faction)
    self:broadcast("This faction is no longer allied with "..faction.."!")
end

function factions.Faction.on_new_neutral(self, faction)
    self:broadcast("This faction is now neutral with "..faction)
end

function factions.Faction.on_end_neutral(self, faction)
    self:broadcast("This faction is no longer neutral with "..faction.."!")
end

function factions.Faction.on_new_enemy(self, faction)
    self:broadcast("This faction is now at war with "..faction)
end

function factions.Faction.on_end_enemy(self, faction)
    self:broadcast("This faction is no longer at war with "..faction.."!")
end

function factions.Faction.on_set_spawn(self)
    self:broadcast("The faction spawn has been set to ("..util.coords3D_string(self.spawn)..").")
end

function factions.Faction.on_add_rank(self, rank)
    self:broadcast("The rank "..rank.." has been created with privileges: "..table.concat(self.ranks[rank], ", "))
end

function factions.Faction.on_replace_privs(self, rank)
    self:broadcast("The privileges in rank "..rank.." have been delete and changed to: "..table.concat(self.ranks[rank], ", "))
end

function factions.Faction.on_remove_privs(self, rank,privs)
    self:broadcast("The privileges in rank "..rank.." have been revoked: "..table.concat(privs, ", "))
end

function factions.Faction.on_add_privs(self, rank,privs)
    self:broadcast("The privileges in rank "..rank.." have been added: "..table.concat(privs, ", "))
end

function factions.Faction.on_set_rank_name(self, rank,newrank)
    self:broadcast("The name of rank "..rank.." has been changed to "..newrank)
end

function factions.Faction.on_delete_rank(self, rank, newrank)
    self:broadcast("The rank "..rank.." has been deleted and replaced by "..newrank)
end

function factions.Faction.on_set_def_rank(self, rank)
    self:broadcast("The default rank given to new players has been changed to "..rank)
end

function factions.Faction.on_reset_ranks(self)
    self:broadcast("All of the faction's ranks have been reset to the default ones.")
end

function factions.Faction.on_promote(self, member)
    minetest.chat_send_player(member, "You have been promoted to "..self.players[member])
end

function factions.Faction.on_revoke_invite(self, player)
    minetest.chat_send_player(player, "You are no longer invited to faction "..self.name)
end

local parcel_size = factions_config.parcel_size
function factions.get_parcel_pos(pos)
	if factions_config.protection_style == "2d" then
		return math.floor(pos.x / parcel_size) * parcel_size .. "," .. math.floor(pos.z / parcel_size) * parcel_size
	elseif factions_config.protection_style == "3d" then
		return math.floor(pos.x / parcel_size) * parcel_size .. "," .. math.floor(pos.y / parcel_size) * parcel_size .. "," .. math.floor(pos.z / parcel_size) * parcel_size
	end
end

function factions.get_player_faction(playername)
    local facname = factions.players[playername]
    if facname then
        local faction = factions.factions[facname]
        return faction
    end
    return nil
end

function factions.get_parcel_faction(parcelpos)
    local facname = factions.parcels[parcelpos]
    if facname then
        local faction = factions.factions[facname]
        return faction
    end
    return nil
end

function factions.get_faction(facname)
    return factions.factions[facname]
end

function factions.get_faction_at(pos)
	local y = pos.y
    if factions_config.protection_depth_height_limit and (pos.y < factions_config.protection_max_depth or pos.y > factions_config.protection_max_height) then
        return nil
    end
    local parcelpos = factions.get_parcel_pos(pos)
    return factions.get_parcel_faction(parcelpos)
end


-------------------------------------------------------------------------------
-- name: add_faction(name)
--
--! @brief add a faction
--! @memberof factions
--! @public
--
--! @param name of faction to add
--!
--! @return faction object/false (succesfully added faction or not)
-------------------------------------------------------------------------------
function factions.add_faction(name)
    if factions.can_create_faction(name) then
        local fac = factions.new_faction(name)
        fac:on_create()
        return fac
    else
        return nil
    end
end

-------------------------------------------------------------------------------
-- name: get_faction_list()
--
--! @brief get list of factions
--! @memberof factions
--! @public
--!
--! @return list of factions
-------------------------------------------------------------------------------
function factions.get_faction_list()

    local retval = {}

    for key,value in pairs(factions.factions) do
        table.insert(retval,key)
    end

    return retval
end

local saving = false

-------------------------------------------------------------------------------
-- name: save()
--
--! @brief save data to file
--! @memberof factions
--! @private
-------------------------------------------------------------------------------
function factions.save()

    --saving is done much more often than reading data to avoid delay
    --due to figuring out which data to save and which is temporary only
    --all data is saved here
    --this implies data needs to be cleant up on load

    local file,error = io.open(factions_worldid .. "/" .. "factions.conf","w")

    if file ~= nil then
        file:write(minetest.serialize(factions.factions))
        file:close()
    else
        minetest.log("error","MOD factions: unable to save factions world specific data!: " .. error)
    end
	factions_ip.save()
	saving = false
end

function factions.bulk_save()
    if saving == false then
		saving = true
		minetest.after(5,function() factions.save() end)
	end
end

-------------------------------------------------------------------------------
-- name: load()
--
--! @brief load data from file
--! @memberof factions
--! @private
--
--! @return true/false
-------------------------------------------------------------------------------
function factions.load()
    local filename = "factions.conf"
    local file,error = io.open(factions_worldid .. "/" .. filename,"r")

    if file ~= nil then
        local raw_data = file:read("*a")
		local current_version = misc_mod_data.data.factions_version
		misc_mod_data.load()
		local old_version = misc_mod_data.data.factions_version 
        local tabledata = minetest.deserialize(raw_data)
		file:close()
		if tabledata then
			factions.factions = tabledata
			if current_version ~= old_version or factions.is_old_file(tabledata) then
				if factions.convert(filename) then
					minetest.after(5, 
					function()
						minetest.chat_send_all("Factions successfully converted.")
					end)
				end
			end
			for facname, faction in pairs(factions.factions) do
				minetest.log("action", facname..","..faction.name)
				for player, rank in pairs(faction.players) do
					minetest.log("action", player..","..rank)
					factions.players[player] = facname
				end
				for parcelpos, val in pairs(faction.land) do
					factions.parcels[parcelpos] = facname
				end
				setmetatable(faction, factions.Faction)
				if not faction.maxpower or faction.maxpower <= 0. then
					faction.maxpower = faction.power
					if faction.power < 0. then
						faction.maxpower = 0.
					end
				end
				if not faction.attacked_parcels then
					faction.attacked_parcels = {}
				end
				if not faction.usedpower then
					faction.usedpower = faction:count_land() * factions_config.power_per_parcel
				end
				if #faction.name > factions_config.faction_name_max_length then
					faction:disband()
				end
				if not faction.last_logon then
					faction.last_logon = os.time()
				end
				if faction.no_parcel ~= -1 then
					faction.no_parcel = os.time()
				end
				if faction:count_land() > 0 then
					faction.no_parcel = -1
				end
				faction.onlineplayers = {}
				faction.offlineplayers = {}
				if faction.players then
					for i, _ in pairs(faction.players) do
						faction.offlineplayers[i] = _
					end
				end
			end
			misc_mod_data.data.factions_version = current_version
			misc_mod_data.save()
			factions.save()
		else
			minetest.after(5, 
			function()
				minetest.chat_send_all("Failed to deserialize saved file.")
			end)
		end
    end
	factions_ip.load()
end

function factions.is_old_file(oldfactions)
	local tempfaction = factions.Faction:new(nil)
	local pass = false
	for facname, faction in pairs(oldfactions) do
		for ni, nl in pairs(tempfaction) do
			pass = false
			for key, value in pairs(faction) do
				if key == ni then
					pass = true
					break
				end
			end
			if not pass then
				tempfaction = nil
				return true
			end
		end
		-- Only check one faction to save time.
		if not pass then
			tempfaction = nil
			return true
		else
			tempfaction = nil
			return false
		end
	end
	tempfaction = nil
	return false
end

function factions.convert(filename)
    local file, error = io.open(factions_worldid .. "/" .. filename, "r")
    if not file then
        minetest.chat_send_all("Cannot load file "..filename..". "..error)
        return false
    end
    local raw_data = file:read("*a")
	file:close()
	
    local data = minetest.deserialize(raw_data)
	
    for facname,faction in pairs(data) do
        local newfac = factions.new_faction(facname,true)
		for oi, ol in pairs(faction) do
			if newfac[oi] then
				newfac[oi] = ol
			end
		end
		if faction.players then
			newfac.players = faction.players
		end
		if faction.land then
		newfac.land = faction.land
		end
		if faction.ranks then
		newfac.ranks = faction.ranks
		end
		if faction.rankless then
			newfac.rankless = faction.rankless
		else
			newfac.rankless = false
		end
		factions.start_diplomacy(facname,newfac)
		newfac:check_power()
    end
	-- Create runtime data.
	for facname,faction in pairs(factions.factions) do
		if faction.players then
			for player, unused in pairs(faction.players) do
				factions.players[player] = faction.name
			end
		end
		if faction.land then
			for l, unused in pairs(faction.land) do
				factions.parcels[l] = facname
			end
		end
	end
    return true
end

minetest.register_on_dieplayer(
function(player)
    local faction = factions.get_player_faction(player:get_player_name())
    if not faction then
        return true
    end
    faction:decrease_power(factions_config.power_per_death)
    return true
end
)

function factions.faction_tick()
    local now = os.time()
    for facname, faction in pairs(factions.factions) do
        if faction:is_online() then
			if factions_config.enable_power_per_player then
				local t = faction.onlineplayers
				local count = 0
				for _ in pairs(t) do count = count + 1 end
				faction:increase_power(factions_config.power_per_player*count)
			else
				faction:increase_power(factions_config.power_per_tick)
			end
        end
        if now - faction.last_logon > factions_config.maximum_faction_inactivity or (faction.no_parcel ~= -1 and now - faction.no_parcel > factions_config.maximum_parcelless_faction_time)  then
            faction:disband()
        end
    end
end

local player_count = 0

minetest.register_on_joinplayer(
function(player)
	player_count = player_count + 1
	local name = player:get_player_name()
	minetest.after(5,createHudfactionLand,player)
    local faction = factions.get_player_faction(name)
    if faction then
        faction.last_logon = os.time()
		minetest.after(5,createHudFactionName,player,faction.name)
		minetest.after(5,createHudPower,player,faction)
		faction.offlineplayers[name] = nil
		faction.onlineplayers[name] = 1
		if faction.no_parcel ~= -1 then
			local now = os.time() - faction.no_parcel
			local l = factions_config.maximum_parcelless_faction_time
			minetest.chat_send_player(name,"This faction will disband in "..l-now.." seconds, because it has no parcels.")
		end
		if faction:has_permission(name, "accept_treaty") or faction:has_permission(name, "refuse_treaty") then
			for _ in pairs(faction.request_inbox) do minetest.chat_send_player(name,"You have diplomatic requests in the inbox.") break end
		end
		if faction.rankless then
			local p1 = faction:has_permission(name, "reset_ranks")
			local p2 = faction:has_permission(name, "set_def_ranks")
			if p1 and p2 then
				minetest.chat_send_player(name,"You need to reset the default rank because there are rankless players in this faction. reset all the ranks back to default using /f reset_ranks (You will lose all of your custom ranks) or use /f set_def_rank")
			elseif p1 then
				minetest.chat_send_player(name,"You need to reset the default rank because there are rankless players in this faction. reset all the ranks back to default using /f reset_ranks (You will lose all of your custom ranks)")
			elseif p2 then
				minetest.chat_send_player(name,"You need to reset the default rank because there are rankless players in this faction. reset all the ranks back to default using /f set_def_rank")
			end
		end
		if faction.message_of_the_day and (faction.message_of_the_day ~= "" or faction.message_of_the_day ~= " ") then
		minetest.chat_send_player(name,faction.message_of_the_day)
		end
    end
	factions.bulk_save()
end
)

minetest.register_on_leaveplayer(
	function(player)
		player_count = player_count - 1
		local name = player:get_player_name()
		local faction = factions.get_player_faction(name)
		local id_name1 = name .. "factionLand"
		if hud_ids[id_name1] then
			hud_ids[id_name1] = nil
		end
		if faction then
			local id_name2 = name .. "factionName"
			local id_name3 = name .. "powerWatch"
			if hud_ids[id_name2] then
				hud_ids[id_name2] = nil
			end
			if hud_ids[id_name3] then
				hud_ids[id_name3] = nil
			end
			faction.offlineplayers[name] = 1
			faction.onlineplayers[name] = nil
		end
		if player_count > 0 then
			factions.bulk_save()
		else
			factions.save()
		end
	end
)

minetest.register_on_respawnplayer(
    function(player)
        local faction = factions.get_player_faction(player:get_player_name())
        if not faction then
            return false
        else
            if not faction.spawn then
                return false
            else
                player:setpos(faction.spawn)
                return true
            end
        end
    end
)



local default_is_protected = minetest.is_protected
minetest.is_protected = function(pos, player)
    local y = pos.y
    if factions_config.protection_depth_height_limit and (pos.y < factions_config.protection_max_depth or pos.y > factions_config.protection_max_height) then
        return false
    end

    local parcelpos = factions.get_parcel_pos(pos)
    local parcel_faction = factions.get_parcel_faction(parcelpos)
    local player_faction = factions.get_player_faction(player)
    -- no faction
    if not parcel_faction then
        return default_is_protected(pos, player)
    elseif player_faction then
        if parcel_faction.name == player_faction.name then
			if parcel_faction:has_permission(player, "pain_build") then
				local p = minetest.get_player_by_name(player)
				p:set_hp(p:get_hp() - 0.5)
			end
            return not (parcel_faction:has_permission(player, "build") or parcel_faction:has_permission(player, "pain_build"))
        elseif parcel_faction.allies[player_faction.name] then
			if player_faction:has_permission(player, "pain_build") then
				local p = minetest.get_player_by_name(player)
				p:set_hp(p:get_hp() - 0.5)
			end
			return not (player_faction:has_permission(player, "build") or player_faction:has_permission(player, "pain_build"))
		else
			return not parcel_faction:parcel_is_attacked_by(parcelpos, player_faction)
        end
    else
        return true
    end
end

function factionUpdate()
	factions.faction_tick()
	minetest.after(factions_config.tick_time,factionUpdate)
end