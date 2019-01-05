local send_error = function(player, message)
    minetest.chat_send_player(player, message)
end

factions_chat = {}

factions.commands = {}

factions.register_command = function(cmd_name, cmd, ignore_param_count,or_perm)
    factions.commands[cmd_name] = { -- default command
        name = cmd_name,
        faction_permissions = {},
        global_privileges = {},
        format = {},
        infaction = true,
        description = "This command has no description.",
        run = function(self, player, argv)
            if self.global_privileges then
                local tmp = {}
                for i in ipairs(self.global_privileges) do
                    tmp[self.global_privileges[i]] = true
                end
                local bool, missing_privs = minetest.check_player_privs(player, tmp)
                if not bool then
                    send_error(player, "Unauthorized.")
                    return false
                end
            end
            -- checks argument formats
            local args = {
                factions = {},
                players = {},
                strings = {},
				unknowns = {},
                other = {}
            }
			if not ignore_param_count then
				if #argv < #(self.format) then
					send_error(player, "Not enough parameters.")
					return false
				end
				else
				if self.format[1] then
					local fm = self.format[1]
					for i in ipairs(argv) do
						if #argv > #(self.format) then
							table.insert(self.format, fm)
						else
							break
						end
					end
				end
			end
			
            for i in ipairs(self.format) do
                local argtype = self.format[i]
                local arg = argv[i]
                if argtype == "faction" then
                    local fac = factions.get_faction(arg)
                    if not fac then
                        send_error(player, "Specified faction "..arg.." does not exist")
                        return false
                    else
                        table.insert(args.factions, fac)
                    end
                elseif argtype == "player" then
                    local pl = minetest.get_player_by_name(arg)
                    if not pl and not factions.players[arg] then
                        send_error(player, "Player is not online.")
                        return false
                    else
                        table.insert(args.players, pl)
                    end
                elseif argtype == "string" then
                    table.insert(args.strings, arg)
                else
					table.insert(args.unknowns, arg)
                    --minetest.log("error", "Bad format definition for function "..self.name)
                    --send_error(player, "Internal server error")
                    --return false
                end
            end
            for i=2, #argv do
				if argv[i] then
					table.insert(args.other, argv[i])
				end
            end

            -- checks permissions
            local player_faction = factions.get_player_faction(player)
            if self.infaction and not player_faction then
                minetest.chat_send_player(player, "This command is only available within a faction.")
                return false
            end
			local one_p = false
            if self.faction_permissions then
                for i in ipairs(self.faction_permissions) do
					local perm = self.faction_permissions[i]
                    if not or_perm and not player_faction:has_permission(player, perm) then
                        send_error(player, "You do not have the faction permission "..perm)
                        return false
					elseif or_perm and player_faction:has_permission(player, perm) then
						one_p = true
						break
                    end
                end
            end
			if or_perm and one_p == false then
			    send_error(player, "You do not have any of faction permissions required.")
                return false
			end

            -- get some more data
            local pos = minetest.get_player_by_name(player):getpos()
            local parcelpos = factions.get_parcel_pos(pos)
            return self.on_success(player, player_faction, pos, parcelpos, args)
        end,
        on_success = function(player, faction, pos, parcelpos, args)
            minetest.chat_send_player(player, "Not implemented yet!")
        end
    }
    -- override defaults
    for k, v in pairs(cmd) do
        factions.commands[cmd_name][k] = v
    end
end


local init_commands
init_commands = function()
	
	if factions_config.faction_user_priv == true then
		minetest.register_privilege("faction_user",
			{
				description = "this user is allowed to interact with faction mod",
				give_to_singleplayer = true,
			}
		)
	end
	
	
	minetest.register_privilege("faction_admin",
		{
			description = "this user is allowed to create or delete factions",
			give_to_singleplayer = true,
		}
	)
	
	local def_privs = { interact=true}
	if factions_config.faction_user_priv == true then
		def_privs.faction_user = true
	end
	
	minetest.register_chatcommand("factions",
		{
			params = "<command> parameters",
			description = "Factions commands. Type /factions help for available commands.",
			privs = def_privs,
			func = factions_chat.cmdhandler,
		}
	)
	
	minetest.register_chatcommand("f",
		{
			params = "<command> parameters",
			description = "Factions commands. Type /f help for available commands.",
            privs = def_privs,
			func = factions_chat.cmdhandler,
		}
	)
end
	

-------------------------------------------
-- R E G I S T E R E D   C O M M A N D S  |
-------------------------------------------

local def_global_privileges = nil

if factions_config.faction_user_priv == true then
	minetest.register_on_newplayer(function(player)
		local name = player:get_player_name()
		local privs = minetest.get_player_privs(name)
		privs.faction_user = true
		minetest.set_player_privs(name, privs)
	end
	)
	def_global_privileges = {"faction_user"}
end

factions.register_command ("set_name", {
    faction_permissions = {"name"},
	format = {"string"},
    description = "Change the faction's name.",
	global_privileges = def_global_privileges,
    on_success = function(player, faction, pos, parcelpos, args)
        local factionname = args.strings[1]
        if factions.can_create_faction(factionname) then
			faction:set_name(factionname)
            return true
        else
            send_error(player, "Faction cannot be renamed.")
            return false
        end
    end
},false)

factions.register_command ("claim", {
    faction_permissions = {"claim"},
    description = "Claim the plot of land you're on.",
	global_privileges = def_global_privileges,
    on_success = function(player, faction, pos, parcelpos, args)
        local can_claim = faction:can_claim_parcel(parcelpos)
        if can_claim then
            minetest.chat_send_player(player, "Claming parcel "..parcelpos)
            faction:claim_parcel(parcelpos)
            return true
        else
            local parcel_faction = factions.get_parcel_faction(parcelpos)
			if parcel_faction and parcel_faction.name == faction.name then
			    send_error(player, "This parcel already belongs to your faction.")
                return false
            elseif parcel_faction and parcel_faction.name ~= faction.name then
                send_error(player, "This parcel belongs to another faction.")
                return false
            elseif faction.power <= factions_config.power_per_parcel then
                send_error(player, "Not enough power.")
                return false
            else
                send_error(player, "Your faction cannot claim any (more) parcel(s).")
                return false
            end
        end
    end
},false)

factions.register_command("unclaim", {
    faction_permissions = {"claim"},
    description = "Unclaim the plot of land you're on.",
	global_privileges = def_global_privileges,
    on_success = function(player, faction, pos, parcelpos, args)
        local parcel_faction = factions.get_parcel_faction(parcelpos)
		if not parcel_faction then
		    send_error(player, "This parcel does not exist.")
            return false
		end
        if parcel_faction.name ~= faction.name then
            send_error(player, "This parcel does not belong to you.")
            return false
        else
            faction:unclaim_parcel(parcelpos)
            return true
        end
    end
},false)

--list all known factions
factions.register_command("list", {
    description = "List all registered factions.",
    infaction = false,
	global_privileges = def_global_privileges,
    on_success = function(player, faction, pos, parcelpos, args)
        local list = factions.get_faction_list()
        local tosend = "Existing factions:"
        
        for i,v in ipairs(list) do
            if i ~= #list then
                tosend = tosend .. " " .. v .. ","
            else
                tosend = tosend .. " " .. v
            end
        end	
        minetest.chat_send_player(player, tosend, false)
        return true
    end
},false)

--show factions mod version
factions.register_command("version", {
    description = "Displays mod version.",
    on_success = function(player, faction, pos, parcelpos, args)
        minetest.chat_send_player(player, "factions: version " .. misc_mod_data.data.factions_version , false)
    end
},false)

--show description  of faction
factions.register_command("info", {
    format = {"faction"},
    description = "Shows a faction's description.",
	global_privileges = def_global_privileges,
    on_success = function(player, faction, pos, parcelpos, args)
        minetest.chat_send_player(player,
            "factions: " .. args.factions[1].name .. ": " ..
            args.factions[1].description, false)
        return true
    end
},false)

factions.register_command("leave", {
    description = "Leave your faction.",
	global_privileges = def_global_privileges,
    on_success = function(player, faction, pos, parcelpos, args)
        faction:remove_player(player)
        return true
    end
},false)

factions.register_command("kick", {
    faction_permissions = {"kick"},
    format = {"player"},
    description = "Kick a player from your faction.",
	global_privileges = def_global_privileges,
    on_success = function(player, faction, pos, parcelpos, args)
        local victim = args.players[1]
        local victim_faction = factions.get_player_faction(victim:get_player_name())
        if victim_faction and victim:get_player_name() ~= faction.leader then -- can't kick da king
            faction:remove_player(victim:get_player_name())
            return true
        elseif not victim_faction then
            send_error(player, victim:get_player_name().." is not in your faction.")
            return false
        else
            send_error(player, victim:get_player_name().." cannot be kicked from your faction.")
            return false
        end
    end
},false)

--create new faction
factions.register_command("create", {
    format = {"string"},
    infaction = false,
    description = "Create a new faction.",
	global_privileges = def_global_privileges,
    on_success = function(player, faction, pos, parcelpos, args)
        if faction then
            send_error(player, "You are already in a faction.")
            return false
        end
        local factionname = args.strings[1]
        if factions.can_create_faction(factionname) then
			new_faction = factions.new_faction(factionname, nil)
            new_faction:add_player(player, new_faction.default_leader_rank)
			factions.start_diplomacy(factionname,new_faction)
            return true
        else
            send_error(player, "Faction cannot be created.")
            return false
        end
    end
},false)

factions.register_command("join", {
    format = {"faction"},
    description = "Join a faction.",
    infaction = false,
	global_privileges = def_global_privileges,
    on_success = function(player, faction, pos, parcelpos, args)
        local new_faction = args.factions[1]
        if new_faction:can_join(player) then
            if faction then -- leave old faction
                faction:remove_player(player)
            end
            new_faction:add_player(player)
        else
            send_error(player, "You cannot join this faction.")
            return false
        end
        return true
    end
},false)

factions.register_command("disband", {
    faction_permissions = {"disband"},
    description = "Disband your faction.",
	global_privileges = def_global_privileges,
    on_success = function(player, faction, pos, parcelpos, args)
        faction:disband()
        return true
    end
},false)

factions.register_command("flag", {
    faction_permissions = {"flags"},
    description = "Manage the faction's flags.",
	global_privileges = def_global_privileges,
	format = {"string"},
    on_success = function(player, faction, pos, parcelpos, args)
		--"Make your faction invite-only."
		--"Allow any player to join your faction."
        --faction:toggle_join_free(false)
		local flag_name = args.strings[1]
		local bool = args.strings[2]
		if (flag_name == "help" or flag_name == "flags") or not bool then
			for i, k in pairs(factions.flags) do
				minetest.chat_send_player(player, k..": ".. factions.flags_desc[i] .. "\n")
			end
			return true
		end
		if flag_name and bool then
			local yes = false
			if bool == "yes" then
				yes = true
			elseif bool == "no" then
				yes = false
			else
				send_error(player, "Set the flags only to yes or no.")
				return false
			end
			if flag_name == "open" then
				faction:toggle_join_free(yes)
			elseif flag_name == "monsters" then
			elseif flag_name == "tax_kick" then
			elseif flag_name == "animals" then
			else
				send_error(player, flag_name.." is not an flag.")
			end
		end
        return true
    end
},true)

factions.register_command("description", {
	format = {"string"},
    faction_permissions = {"description"},
    description = "Set your faction's description",
	global_privileges = def_global_privileges,
    on_success = function(player, faction, pos, parcelpos, args)
        faction:set_description(table.concat(args.strings," "))
        return true
    end
},true)

factions.register_command("invite", {
    format = {"player"},
    faction_permissions = {"invite"},
    description = "Invite a player to your faction.",
	global_privileges = def_global_privileges,
    on_success = function(player, faction, pos, parcelpos, args)
        faction:invite_player(args.players[1]:get_player_name())
        return true
    end
},false)

factions.register_command("uninvite", {
    format = {"player"},
    faction_permissions = {"invite"},
    description = "Revoke a player's invite.",
	global_privileges = def_global_privileges,
    on_success = function(player, faction, pos, parcelpos, args)
        faction:revoke_invite(args.players[1]:get_player_name())
        return true
    end
},false)

factions.register_command("delete", {
    global_privileges = {"faction_admin"},
    format = {"faction"},
    infaction = false,
    description = "Delete a faction.",
    on_success = function(player, faction, pos, parcelpos, args)
        args.factions[1]:disband()
        return true
    end
},false)

factions.register_command("ranks", {
    description = "List ranks within your faction",
	global_privileges = def_global_privileges,
    on_success = function(player, faction, pos, parcelpos, args)
        for rank, permissions in pairs(faction.ranks) do
            minetest.chat_send_player(player, rank..": "..table.concat(permissions, " "))
        end
        return true
    end
},false)

factions.register_command("rank_privileges", {
    description = "List available rank privileges.",
	global_privileges = def_global_privileges,
    on_success = function(player, faction, pos, parcelpos, args)
		minetest.chat_send_player(player, "Privileges available:\n")
		for i, k in pairs(factions.permissions) do
            minetest.chat_send_player(player, k .. ": " .. factions.permissions_desc[i] .. "\n")
        end
        return true
    end
},false)

factions.register_command("set_message_of_the_day", {
    format = {"string"},
    faction_permissions = {"motd"},
    description = "Sets the message that shows up every time a faction member logs-in.",
	global_privileges = def_global_privileges,
    on_success = function(player, faction, pos, parcelpos, args)
		local s = ""
		for i,l in pairs(args.strings) do
			s = s .. l .. " "
		end
        faction:set_message_of_the_day("Message of the day: " .. s)
        return true
    end
},true)

if factions_config.faction_diplomacy == true then
	factions.register_command("send_alliance", {
		description = "Send an alliance request to another faction.",
		global_privileges = def_global_privileges,
		format = {"string"},
		faction_permissions = {"diplomacy"},
		on_success = function(player, faction, pos, parcelpos, args)
			if factions.factions[args.strings[1]] then
				if not factions.factions[args.strings[1]].request_inbox[faction.name] then
					if faction.allies[args.strings[1]] then
						send_error(player, "You are already allys.")
						return false
					end
					if faction.enemies[args.strings[1]] then
						send_error(player, "You need to be neutral in-order to send an alliance request.")
						return false
					end
					if args.strings[1] == faction.name then
						send_error(player, "You can not send an alliance to your own faction.")
						return false
					end
					if faction.request_inbox[args.strings[1]] then
						send_error(player, "Faction " .. args.strings[1] .. "has already sent a request to you.")
						return false
					end
					factions.factions[args.strings[1]].request_inbox[faction.name] = "alliance"
					factions.factions[args.strings[1]]:broadcast("An alliance request from faction " .. faction.name .. " has been sent to you.")
					faction:broadcast("An alliance request was sent to faction " .. args.strings[1])
					factions.bulk_save()
				else
					send_error(player, "You have already sent a request.")
				end
			else
				send_error(player, args.strings[1] .. " is not a name of a faction.")
			end
		end
	},false)
	
	factions.register_command("send_neutral", {
		description = "Send neutral to another faction.",
		global_privileges = def_global_privileges,
		format = {"string"},
		faction_permissions = {"diplomacy"},
		on_success = function(player, faction, pos, parcelpos, args)
			if factions.factions[args.strings[1]] then
				if not factions.factions[args.strings[1]].request_inbox[faction.name] then
					if faction.allies[args.strings[1]] then
						send_error(player, "You are allys.")
						return false
					end
					if faction.neutral[args.strings[1]] then
						send_error(player, "You are already neutral with this faction.")
						return false
					end
					if args.strings[1] == faction.name then
						send_error(player, "You can not send a neutral request to your own faction.")
						return false
					end
					if faction.request_inbox[args.strings[1]] then
						send_error(player, "Faction " .. args.strings[1] .. "has already sent a request to you.")
						return false
					end
					factions.factions[args.strings[1]].request_inbox[faction.name] = "neutral"
					factions.factions[args.strings[1]]:broadcast("A neutral request from faction " .. faction.name .. " has been sent to you.")
					faction:broadcast("A neutral request was sent to faction " .. args.strings[1])
					factions.bulk_save()
				else
					send_error(player, "You have already sent a request.")
				end
			else
				send_error(player, args.strings[1] .. " is not a name of a faction.")
			end
		end
	},false)
	
	factions.register_command("accept", {
		description = "accept an request from another faction.",
		global_privileges = def_global_privileges,
		format = {"string"},
		faction_permissions = {"diplomacy"},
		on_success = function(player, faction, pos, parcelpos, args)
			if faction.request_inbox[args.strings[1]] then
				if args.strings[1] == faction.name then
					send_error(player, "You can not accept an request from own faction.")
					return false
				end
				if faction.request_inbox[args.strings[1]] == "alliance" then
					faction:new_alliance(args.strings[1])
					factions.factions[args.strings[1]]:new_alliance(faction.name)
				else
				if faction.request_inbox[args.strings[1]] == "neutral" then
					faction:new_neutral(args.strings[1])
					factions.factions[args.strings[1]]:new_neutral(faction.name)
				end
				end
				faction.request_inbox[args.strings[1]] = nil
				factions.bulk_save()
			else
				send_error(player, "No request was sent to you.")
			end
		end
	},false)
	
	factions.register_command("refuse", {
		description = "refuse an request from another faction.",
		global_privileges = def_global_privileges,
		format = {"string"},
		faction_permissions = {"diplomacy"},
		on_success = function(player, faction, pos, parcelpos, args)
			if faction.request_inbox[args.strings[1]] then
				if args.strings[1] == faction.name then
					send_error(player, "You can not refuse an request from your own faction.")
					return false
				end
				faction.request_inbox[args.strings[1]] = nil
				factions.factions[args.strings[1]]:broadcast("Faction " .. faction.name .. " refuse to be your ally.")
				faction:broadcast("Refused an request from faction " .. args.strings[1])
				factions.bulk_save()
			else
				send_error(player, "No request was sent to you.")
			end
		end
	},false)
	
	factions.register_command("delcare_war", {
		description = "Delcare war on a faction.",
		global_privileges = def_global_privileges,
		format = {"string"},
		faction_permissions = {"diplomacy"},
		on_success = function(player, faction, pos, parcelpos, args)
			if not faction.enemies[args.strings[1]] then
				if args.strings[1] == faction.name then
					send_error(player, "You can not delcare war on your own faction.")
					return false
				end
				if faction.allies[args.strings[1]] then
					faction:end_alliance(args.strings[1])
					factions.factions[args.strings[1]]:end_alliance(faction.name)
				end
				if faction.neutral[args.strings[1]] then
					faction:end_neutral(args.strings[1])
					factions.factions[args.strings[1]]:end_neutral(faction.name)
				end
				faction:new_neutral(args.strings[1])
				factions.factions[args.strings[1]]:new_neutral(faction.name)
				factions.bulk_save()
			else
				send_error(player, "You are already at war.")
			end
		end
	},false)
	
	factions.register_command("break", {
		description = "Break an alliance.",
		global_privileges = def_global_privileges,
		format = {"string"},
		faction_permissions = {"diplomacy"},
		on_success = function(player, faction, pos, parcelpos, args)
			if faction.allies[args.strings[1]] then
				if args.strings[1] == faction.name then
					send_error(player, "You can not break an alliance from your own faction.")
					return false
				end
				faction:end_alliance(args.strings[1])
				factions.factions[args.strings[1]]:end_alliance(faction.name)
				faction:new_neutral(args.strings[1])
				factions.factions[args.strings[1]]:new_neutral(faction.name)
				factions.bulk_save()
			else
				send_error(player, "You where not allies to begin with.")
			end
		end
	},false)
	
	factions.register_command("inbox", {
		description = "Check your diplomacy request inbox.",
		global_privileges = def_global_privileges,
		faction_permissions = {"diplomacy"},
		on_success = function(player, faction, pos, parcelpos, args)
			local empty = true
			for i,k in pairs(faction.request_inbox) do
				if k == "alliance" then
					minetest.chat_send_player(player,"Alliance request from faction " .. i .. "\n")
				else 
				if k == "neutral" then
					minetest.chat_send_player(player,"neutral request from faction " .. i .. "\n")
				end
				end
				empty = false
			end
			if empty then
				minetest.chat_send_player(player,"none:")
			end
		end
	},false,true)
	
	factions.register_command("allies", {
		description = "Shows the factions that are allied to you.",
		global_privileges = def_global_privileges,
		on_success = function(player, faction, pos, parcelpos, args)
			local empty = true
			for i,k in pairs(faction.allies) do
				minetest.chat_send_player(player,i .. "\n")
				empty = false
			end
			if empty then
				minetest.chat_send_player(player,"none:")
			end
		end
	},false)
	
	factions.register_command("neutral", {
		description = "Shows the factions that are neutral with you.",
		global_privileges = def_global_privileges,
		on_success = function(player, faction, pos, parcelpos, args)
			local empty = true
			for i,k in pairs(faction.neutral) do
				minetest.chat_send_player(player,i .. "\n")
				empty = false
			end
			if empty then
				minetest.chat_send_player(player,"none:")
			end
		end
	},false)
	
	factions.register_command("enemies", {
		description = "Shows enemies of your faction.",
		global_privileges = def_global_privileges,
		on_success = function(player, faction, pos, parcelpos, args)
			local empty = true
			for i,k in pairs(faction.enemies) do
				minetest.chat_send_player(player,i .. "\n")
				empty = false
			end
			if empty then
				minetest.chat_send_player(player,"none:")
			end
		end
	},false)
end

factions.register_command("who", {
    description = "List players in your faction, and their ranks.",
	global_privileges = def_global_privileges,
    on_success = function(player, faction, pos, parcelpos, args)
        if not faction.players then
            minetest.chat_send_player(player, "There is nobody in this faction ("..faction.name..")")
            return true
        end
        minetest.chat_send_player(player, "Players in faction "..faction.name..": ")
        for p, rank in pairs(faction.players) do
            minetest.chat_send_player(player, p.." ("..rank..")")
        end
        return true
    end
},false)

local parcel_size_center = factions_config.parcel_size / 2

factions.register_command("show_parcel", {
    description = "Shows parcel for six seconds.",
	global_privileges = def_global_privileges,
    on_success = function(player, faction, pos, parcelpos, args)
		local parcel_faction = factions.get_parcel_faction(parcelpos)
		if not parcel_faction then
			send_error(player, "There is no claim here")
			return false
		end
		local psc = parcel_size_center
		local fps = factions_config.parcel_size

		local ppos = {x = (math.floor(pos.x / fps)*fps)+psc,y = (math.floor(pos.y / fps)*fps)+psc,z = (math.floor(pos.z / fps)*fps)+psc}
		minetest.add_entity(ppos, "factions:display")
        return true
    end
},false)

factions.register_command("new_rank", {
    description = "Add a new rank.",
    format = {"string"},
    faction_permissions = {"ranks"},
	global_privileges = def_global_privileges,
    on_success = function(player, faction, pos, parcelpos, args)
		if args.strings[1] then
			local rank = args.strings[1]
			if faction.ranks[rank] then
				send_error(player, "Rank already exists")
				return false
			end
			local success = false
			local failindex = -1
			for _, f in pairs(args.strings) do
				if f then
					for q, r in pairs(factions.permissions) do
						if f == r then
							success = true
							break
						else
							success = false
						end
					end
					if not success and _ ~= 1 then
						failindex = _
						break
					end
				end
			end
			if not success then
				if args.strings[failindex] then
					send_error(player, "Permission " .. args.strings[failindex] .. " is invalid.")
				else
					send_error(player, "No permission was given.")
				end
				return false
			end
			faction:add_rank(rank, args.other)
			return true
		end
		send_error(player, "No rank was given.")
		return false
    end
},true)

factions.register_command("replace_privs", {
    description = "Deletes current permissions and replaces them with the ones given.",
    format = {"string"},
    faction_permissions = {"ranks"},
	global_privileges = def_global_privileges,
    on_success = function(player, faction, pos, parcelpos, args)
		if args.strings[1] then
			local rank = args.strings[1]
			if not faction.ranks[rank] then
				send_error(player, "Rank does not exist")
				return false
			end
			local success = false
			local failindex = -1
			for _, f in pairs(args.strings) do
				if f then
					for q, r in pairs(factions.permissions) do
						if f == r then
							success = true
							break
						else
							success = false
						end
					end
					if not success and _ ~= 1 then
						failindex = _
						break
					end
				end
			end
			if not success then
				if args.strings[failindex] then
					send_error(player, "Permission " .. args.strings[failindex] .. " is invalid.")
				else
					send_error(player, "No permission was given.")
				end
				return false
			end
			faction:replace_privs(rank, args.other)
			return true
		end
		send_error(player, "No rank was given.")
		return false
    end
},true)

factions.register_command("remove_privs", {
    description = "Remove permissions from a rank.",
    format = {"string"},
    faction_permissions = {"ranks"},
	global_privileges = def_global_privileges,
    on_success = function(player, faction, pos, parcelpos, args)
		if args.strings[1] then
			local rank = args.strings[1]
			if not faction.ranks[rank] then
				send_error(player, "Rank does not exist")
				return false
			end
			local success = false
			local failindex = -1
			for _, f in pairs(args.strings) do
				if f then
					for q, r in pairs(factions.permissions) do
						if f == r then
							success = true
							break
						else
							success = false
						end
					end
					if not success and _ ~= 1 then
						failindex = _
						break
					end
				end
			end
			if not success then
				if args.strings[failindex] then
					send_error(player, "Permission " .. args.strings[failindex] .. " is invalid.")
				else
					send_error(player, "No permission was given.")
				end
				return false
			end
			faction:remove_privs(rank, args.other)
			return true
		end
		send_error(player, "No rank was given.")
		return false
    end
},true)

factions.register_command("add_privs", {
    description = "add permissions to a rank.",
    format = {"string"},
    faction_permissions = {"ranks"},
	global_privileges = def_global_privileges,
    on_success = function(player, faction, pos, parcelpos, args)
		if args.strings[1] then
			local rank = args.strings[1]
			if not faction.ranks[rank] then
				send_error(player, "Rank does not exist")
				return false
			end
			local success = false
			local failindex = -1
			for _, f in pairs(args.strings) do
				if f then
					for q, r in pairs(factions.permissions) do
						if f == r then
							success = true
							break
						else
							success = false
						end
					end
					if not success and _ ~= 1 then
						failindex = _
						break
					end
				end
			end
			if not success then
				if args.strings[failindex] then
					send_error(player, "Permission " .. args.strings[failindex] .. " is invalid.")
				else
					send_error(player, "No permission was given.")
				end
				return false
			end
			faction:add_privs(rank, args.other)
			return true
		end
		send_error(player, "No rank was given.")
		return false
    end
},true)

factions.register_command("set_rank_name", {
    description = "Change the name of given rank.",
    format = {"string","string"},
    faction_permissions = {"ranks"},
	global_privileges = def_global_privileges,
    on_success = function(player, faction, pos, parcelpos, args)
        local rank = args.strings[1]
        local newrank = args.strings[2]
        if not faction.ranks[rank] then
            send_error(player, "The rank does not exist.")
            return false
        end
		if faction.ranks[newrank] then
            send_error(player, "This rank name was already taken.")
            return false
        end
        faction:set_rank_name(rank, newrank)
        return true
    end
},false)

factions.register_command("del_rank", {
    description = "Replace and delete a rank.",
    format = {"string", "string"},
    faction_permissions = {"ranks"},
	global_privileges = def_global_privileges,
    on_success = function(player, faction, pos, parcelpos, args)
        local rank = args.strings[1]
        local newrank = args.strings[2]
        if not faction.ranks[rank] or not faction.ranks[newrank] then
            send_error(player, "One of the specified ranks does not exist.")
            return false
        end
        faction:delete_rank(rank, newrank)
        return true
    end
},false)

factions.register_command("set_def_rank", {
    description = "Change the default rank given to new players and also replace rankless players in this faction.",
    format = {"string"},
    faction_permissions = {"ranks"},
	global_privileges = def_global_privileges,
    on_success = function(player, faction, pos, parcelpos, args)
        local rank = args.strings[1]
        if not faction.ranks[rank] then
            send_error(player, "This rank does not exist.")
            return false
        end
        faction:set_def_rank(rank)
        return true
    end
},false)

factions.register_command("reset_ranks", {
    description = "Reset's all of the factions rankings back to the default ones.",
    format = {},
    faction_permissions = {"ranks"},
	global_privileges = def_global_privileges,
    on_success = function(player, faction, pos, parcelpos, args)
        faction:reset_ranks()
        return true
    end
},false)

factions.register_command("set_spawn", {
    description = "Set the faction's spawn",
    faction_permissions = {"spawn"},
	global_privileges = def_global_privileges,
    on_success = function(player, faction, pos, parcelpos, args)
        faction:set_spawn(pos)
        return true
    end
},false)

factions.register_command("del_spawn", {
    description = "Set the faction's spawn to zero",
    faction_permissions = {"spawn"},
	global_privileges = def_global_privileges,
    on_success = function(player, faction, pos, parcelpos, args)
        faction:set_spawn({x=0,y=0,z=0})
        return true
    end
},false)

if factions_config.spawn_teleport == true then
	factions.register_command("tp_spawn", {
		description = "Teleport to the faction's spawn",
		faction_permissions = {"spawn"},
		global_privileges = def_global_privileges,
		on_success = function(player, faction, pos, parcelpos, args)
			if player then
				minetest.chat_send_player(player, "Teleporting in five seconds.")
				minetest.after(5, 
					function(faction,player)
						faction:tp_spawn(player)
					end,faction,player)
				return true
			end
			return false
		end
	},false)
end

factions.register_command("where", {
    description = "See whose parcel you stand on.",
    infaction = false,
	global_privileges = def_global_privileges,
    on_success = function(player, faction, pos, parcelpos, args)
        local parcel_faction = factions.get_parcel_faction(parcelpos)
        local place_name = (parcel_faction and parcel_faction.name) or "Wilderness"
        minetest.chat_send_player(player, "You are standing on parcel "..parcelpos..", part of "..place_name)
        return true
    end
},false)

factions.register_command("help", {
    description = "Shows help for commands.",
    infaction = false,
	global_privileges = def_global_privileges,
    on_success = function(player, faction, pos, parcelpos, args)
        factions_chat.show_help(player)
        return true
    end
},false)

factions.register_command("get_spawn", {
    description = "Shows your faction's spawn",
	global_privileges = def_global_privileges,
    on_success = function(player, faction, pos, parcelpos, args)
        local spawn = faction.spawn
        if spawn then
            local spawn = {spawn.x, spawn.y, spawn.z}
            minetest.chat_send_player(player, "Spawn is at ("..table.concat(spawn, ", ")..")")
            return true
        else
            minetest.chat_send_player(player, "Your faction has no spawn set.")
            return false
        end
    end
},false)

factions.register_command("promote", {
    description = "Promotes a player to a rank",
    format = {"player", "string"},
    faction_permissions = {"promote"},
	global_privileges = def_global_privileges,
    on_success = function(player, faction, pos, parcelpos, args)
        local rank = args.strings[1]
        if faction.ranks[rank] then
            faction:promote(args.players[1]:get_player_name(), rank)
            return true
        else
            send_error(player, "The specified rank does not exist.")
            return false
        end
    end
},false)

factions.register_command("power", {
    description = "Display your faction's power",
	global_privileges = def_global_privileges,
    on_success = function(player, faction, pos, parcelpos, args)
		local pps = 0
		if factions_config.enable_power_per_player then
			local t = faction.onlineplayers
			local count = 0
			for _ in pairs(t) do count = count + 1 end
			pps = factions_config.power_per_player * count
		else
			fpps = factions_config.power_per_tick
		end
        minetest.chat_send_player(player, "Power: "..faction.power.." / "..faction.maxpower - faction.usedpower.."\nPower per "..factions_config.tick_time.." seconds: "..pps.."\nPower per death: -"..factions_config.power_per_death)
        return true
    end
},false)

factions.register_command("convert", {
    description = "Load factions in the old format",
    infaction = false,
    global_privileges = {"faction_admin"},
    format = {"string"},
    on_success = function(player, faction, pos, parcelpos, args)
        if factions.convert(args.strings[1]) then
            minetest.chat_send_player(player, "Factions successfully converted.")
        else
            minetest.chat_send_player(player, "Error.")
        end
        return true
    end
},false)

factions.register_command("free", {
    description = "Forcefully frees a parcel",
    infaction = false,
    global_privileges = {"faction_admin"},
    on_success = function(player, faction, pos, parcelpos, args)
        local parcel_faction = factions.get_parcel_faction(parcelpos)
        if not parcel_faction then
            send_error(player, "No claim at this position")
            return false
        else
            parcel_faction:unclaim_parcel(parcelpos)
            return true
        end
    end
},false)

factions.register_command("chat", {
    description = "Send a message to your faction's members",
	format = {"string"},
	global_privileges = def_global_privileges,
    on_success = function(player, faction, pos, parcelpos, args)
        local msg = table.concat(args.strings, " ")
        faction:broadcast(msg, player)
    end
},true)

factions.register_command("forceupdate", {
    description = "Forces an update tick.",
    global_privileges = {"faction_admin"},
    on_success = function(player, faction, pos, parcelpos, args)
        factions.faction_tick()
    end
},false)

factions.register_command("which", {
    description = "Gets a player's faction",
    infaction = false,
    format = {"string"},
	global_privileges = def_global_privileges,
    on_success = function(player, faction, pos, parcelpos, args)
        local playername = args.strings[1]
        local faction = factions.get_player_faction(playername)
        if not faction then
            send_error(player, "Player "..playername.." does not belong to any faction")
            return false
        else
            minetest.chat_send_player(player, "player "..playername.." belongs to faction "..faction.name)
            return true
        end
    end
},false)

factions.register_command("set_leader", {
    description = "Set a player as a faction's leader",
    infaction = false,
    global_privileges = {"faction_admin"},
    format = {"faction", "player"},
    on_success = function(player, faction, pos, parcelpos, args)
        local playername = args.players[1]:get_player_name()
        local playerfaction = factions.get_player_faction(playername)
        local targetfaction = args.factions[1]
        if playerfaction.name ~= targetfaction.name then
            send_error(player, "Player "..playername.." is not in faction "..targetfaction.name..".")
            return false
        end
        targetfaction:set_leader(playername)
        return true
    end
},false)

factions.register_command("set_admin", {
    description = "Make a faction an admin faction",
    infaction = false,
    global_privileges = {"faction_admin"},
    format = {"faction"},
    on_success = function(player, faction, pos, parcelpos, args)
		if not args.factions[1].is_admin then
			minetest.chat_send_player(player,"faction " .. args.factions[1].name .. " is now an admin faction it can not be disband.")
		else
			minetest.chat_send_player(player,"faction " .. args.factions[1].name .. " is already an admin faction.")
		end
        args.factions[1].is_admin = true
		factions.bulk_save()
        return true
    end
},false)

factions.register_command("remove_admin", {
    description = "Make a faction not an admin faction",
    infaction = false,
    global_privileges = {"faction_admin"},
    format = {"faction"},
    on_success = function(player, faction, pos, parcelpos, args)
		if args.factions[1].is_admin then
			minetest.chat_send_player(player,"faction " .. args.factions[1].name .. " is not an admin faction any more.")
		else
			minetest.chat_send_player(player,"faction " .. args.factions[1].name .. " is not an admin faction to begin with.")
		end
        args.factions[1].is_admin = false
		factions.bulk_save()
        return true
    end
},false)

factions.register_command("reset_power", {
    description = "Reset a faction's power",
    infaction = false,
    global_privileges = {"faction_admin"},
    format = {"faction"},
    on_success = function(player, faction, pos, parcelpos, args)
        args.factions[1].power = 0
        return true
    end
},false)


factions.register_command("obliterate", {
    description = "Remove all factions",
    infaction = false,
    global_privileges = {"faction_admin"},
    on_success = function(player, faction, pos, parcelpos, args)
        for _, f in pairs(factions.factions) do
            f:disband("obliterated")
        end
        return true
    end
},false)

factions.register_command("get_factions_spawn", {
    description = "Get a faction's spawn",
    infaction = false,
    global_privileges = {"faction_admin"},
    format = {"faction"},
    on_success = function(player, faction, pos, parcelpos, args)
        local spawn = args.factions[1].spawn
        if spawn then
            minetest.chat_send_player(player, spawn.x..","..spawn.y..","..spawn.z)
            return true
        else
            send_error(player, "Faction has no spawn set.")
            return false
        end
    end
},false)

factions.register_command("whoin", {
    description = "Get all members of a faction.",
    infaction = false,
    global_privileges = def_global_privileges,
    format = {"faction"},
    on_success = function(player, faction, pos, parcelpos, args)
        local msg = {}
        for player, _ in pairs(args.factions[1].players) do
            table.insert(msg, player)
        end
        minetest.chat_send_player(player, table.concat(msg, ", "))
        return true
    end
},false)

factions.register_command("stats", {
    description = "Get stats of a faction.",
    infaction = false,
    global_privileges = def_global_privileges,
    format = {"faction"},
    on_success = function(player, faction, pos, parcelpos, args)
        local f = args.factions[1]
		local pps = 0
		if factions_config.enable_power_per_player then
			local t = f.onlineplayers
			local count = 0
			for _ in pairs(t) do count = count + 1 end
			pps = factions_config.power_per_player * count
		else
			fpps = factions_config.power_per_tick
		end
        minetest.chat_send_player(player, "Power: "..f.power.." / "..f.maxpower - f.usedpower.."\nPower per "..factions_config.tick_time.." seconds: "..pps.."\nPower per death: -"..factions_config.power_per_death)
        return true
    end
},false)

factions.register_command("seen", {
    description = "Check the last time a faction had a member logged in",
    infaction = false,
    global_privileges = def_global_privileges,
    format = {"faction"},
    on_success = function(player, faction, pos, parcelpos, args)
        local lastseen = args.factions[1].last_logon
        local now = os.time()
        local time = now - lastseen
        local minutes = math.floor(time / 60)
        local hours = math.floor(minutes / 60)
        local days = math.floor(hours / 24)
        minetest.chat_send_player(player, "Last seen "..days.." day(s), "..
            hours % 24 .." hour(s), "..minutes % 60 .." minutes, "..time % 60 .." second(s) ago.")
        return true
    end
},false)

-------------------------------------------------------------------------------
-- name: cmdhandler(playername,parameter)
--
--! @brief chat command handler
--! @memberof factions_chat
--! @private
--
--! @param playername name
--! @param parameter data supplied to command
-------------------------------------------------------------------------------
factions_chat.cmdhandler = function (playername,parameter)

	local player = minetest.env:get_player_by_name(playername)
	local params = parameter:split(" ")
    local player_faction = factions.get_player_faction(playername)

	if parameter == nil or
		parameter == "" then
        if player_faction then
            minetest.chat_send_player(playername, "You are in faction "..player_faction.name..". Type /f help for a list of commands.")
        else
            minetest.chat_send_player(playername, "You are part of no faction")
        end
		return
	end

	local cmd = factions.commands[params[1]]
    if not cmd then
        send_error(playername, "Unknown command.")
        return false
    end

    local argv = {}
    for i=2, #params, 1 do
        table.insert(argv, params[i])
    end
	
    cmd:run(playername, argv)

end

function table_Contains(t,v)
	for k, a in pairs(t) do
		if a == v then
			return true
		end		
	end
	return false
end

-------------------------------------------------------------------------------
-- name: show_help(playername,parameter)
--
--! @brief send help message to player
--! @memberof factions_chat
--! @private
--
--! @param playername name
-------------------------------------------------------------------------------
function factions_chat.show_help(playername)

	local MSG = function(text)
		minetest.chat_send_player(playername,text,false)
	end
	
	MSG("factions mod")
	MSG("Usage:")
	local has, missing = minetest.check_player_privs(playername,  {
    faction_admin = true})
	
    for k, v in pairs(factions.commands) do
        local args = {}
		if has or not table_Contains(v.global_privileges,"faction_admin") then
			for i in ipairs(v.format) do
				table.insert(args, v.format[i])
			end
			MSG("\t/factions "..k.." <"..table.concat(args, "> <").."> : "..v.description)
		end
    end
end

init_commands()

