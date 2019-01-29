local storage = minetest.get_mod_storage()

if not minetest.deserialize(storage:get_string("spawn")) then
	storage:set_string("spawn", minetest.serialize({x = 1099, y = 11, z = 1818}))
end

local tip = {}

spawnpos = minetest.deserialize(storage:get_string("spawn"))

minetest.register_privilege("spawn_admin", {
	description = "Can use /setspawn",
	give_to_singleplayer = false
})

minetest.register_chatcommand("spawn", {
	description = "Teleport you to the server's spawn",
	func = function(name)
		if tip[name] then
			return false, "Your already being teleported!"
		end
		local player = minetest.get_player_by_name(name)
		minetest.after(5, function(player, name) 
			if player and tip[name] then
				player:set_pos(spawnpos) 
			end
			tip[name] = nil
		end, player, name)
		tip[name] = true
		return true, "You will be teleported in five seconds."
	end,
})

minetest.register_chatcommand("setspawn", {
	description = "Set the server's spawn point",
	privs = {spawn_admin = true},
	func = function(name)
		name = name or "" -- fallback to blank name if nil
		local player = minetest.get_player_by_name(name)
		local pos = player:get_pos()
		spawnpos = pos
		storage:set_string("spawn", minetest.serialize(pos))
		return true, "Spawn set!"
	end,
})

minetest.register_on_leaveplayer(
	function(player)
		local name = player:get_player_name()
		tip[name] = nil
	end
)

local function pvp_block(player, hitter, time_from_last_punch, tool_capabilities, dir, damage)
	if not player or not hitter or not player:is_player() or not hitter:is_player() then
		return
	end

	local pos = player:get_pos()
	
	local x = pos.x
	local z = pos.z
	local x2 = spawnpos.x
	local z2 = spawnpos.z
	
	if x < x2 + 30 and x > x2 - 30 and z < z2 + 30 and z > z2 - 30 then
		local name = hitter:get_player_name()
		hitter:set_hp(hitter:get_hp() - 0.5)
		minetest.chat_send_player(name, "You can not kill players on server spawn!")
		return true
	end

end

minetest.register_on_punchplayer(pvp_block)
