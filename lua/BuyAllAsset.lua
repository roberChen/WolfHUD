if RequiredScript == "lib/managers/missionassetsmanager" then
	
	local _setup_mission_assets_original = MissionAssetsManager._setup_mission_assets
	local init_finalize_original = MissionAssetsManager.init_finalize
	local unlock_asset_original = MissionAssetsManager.unlock_asset
	local sync_unlock_asset_original = MissionAssetsManager.sync_unlock_asset
	local get_unlocked_asset_ids_original = MissionAssetsManager.get_unlocked_asset_ids
	local is_unlock_asset_allowed_original = MissionAssetsManager.is_unlock_asset_allowed
	local sync_save_original = MissionAssetsManager.sync_save
	local sync_load_original = MissionAssetsManager.sync_load
	
	function MissionAssetsManager:_setup_mission_assets(...)
		_setup_mission_assets_original(self, ...)
		if self:mission_has_assets() then
			self:create_buy_all_asset()
			self:update_buy_all_asset_cost()
		end
	end
	
	function MissionAssetsManager:sync_unlock_asset(...)
		sync_unlock_asset_original(self, ...)
		if self:mission_has_assets() then
			self:update_buy_all_asset_cost()
		end
	end

	function MissionAssetsManager:unlock_asset(asset_id, ...)
		if asset_id == "wolfhud_buy_all_assets" then
			for _, asset in ipairs(self._global.assets) do
				if self:asset_is_buyable(asset) then
					unlock_asset_original(self, asset.id)
				end
			end
			self:check_all_assets_bought()
		else
			unlock_asset_original(self, asset_id, ...)
			self:update_buy_all_asset_cost()
		end
	end
	
	function MissionAssetsManager:get_unlocked_asset_ids(...)
		local asset_ids = get_unlocked_asset_ids_original(self, ...)
		-- Remove Buy all id from unlocked table, so its state doesn't get restored after Profile switch.
		if table.contains(asset_ids, "wolfhud_buy_all_assets") then
			for i, id in ipairs(asset_ids) do
				if id == "wolfhud_buy_all_assets" then
					table.remove(asset_ids, i)
					break
				end
			end
		end
		
		return asset_ids
	end
	
	function MissionAssetsManager:is_unlock_asset_allowed(...)
		if game_state_machine then	-- original function can crash, if this doesn't exists (yet?) for some reason...
			return is_unlock_asset_allowed_original(self, ...)
		end
		return false
	end
	
	function MissionAssetsManager:sync_save(...)
		-- If we do not remove the buy all here it will be sent to clients and they may not know how to handle it.
		for i, asset in ipairs(self._global.assets) do
			if asset.id == "wolfhud_buy_all_assets" then
				table.remove(self._global.assets, i)
				break
			end
		end
		
		sync_save_original(self, ...)
	end
	
	function MissionAssetsManager:sync_load(data, ...)
		local has_assets = self:mission_has_assets()
		if has_assets then
			self:create_buy_all_asset(data.MissionAssetsManager.assets)
		end
		
		sync_load_original(self, data, ...)
		
		if has_assets then
			self:update_buy_all_asset_cost()
		end
	end

	-- Custom functions
	
	function MissionAssetsManager:create_buy_all_asset(insert_table)
		insert_table = insert_table or self._global.assets
		local asset_id = "wolfhud_buy_all_assets"
		local asset_tweak = self._tweak_data[asset_id]
		
		local asset = self:_get_asset_by_id(asset_id)

		if asset then
			table.sort(insert_table, function(a, b)
				if a.id == asset_id then
					return true
				end
				return false
			end)
		elseif asset_tweak then
			for i, tmp_asset in ipairs(insert_table) do
				if asset_id == tmp_asset.id then
					table.remove(insert_table, i)
				end
			end
			
			asset = {
				id = asset_id,
				unlocked = self:check_all_assets_bought(true),
				can_unlock = true,
				show = asset_tweak.visible_if_locked,
				no_mystery = asset_tweak.no_mystery,
				local_only = asset_tweak.local_only
			}
			
			table.insert(insert_table, 1, asset)
		end
	end

	function MissionAssetsManager:update_buy_all_asset_cost()
		if self._tweak_data.wolfhud_buy_all_assets then
			local value = 0
			for _, asset in ipairs(self._global.assets) do
				if self:asset_is_buyable(asset) then
					local asset_tweak = asset.id and self._tweak_data[asset.id]
					value = value + (asset_tweak and asset_tweak.money_lock or 0)
				end
			end
			
			self._tweak_data.wolfhud_buy_all_assets.money_lock = value
			self:check_all_assets_bought()
		end
	end

	function MissionAssetsManager:check_all_assets_bought(return_status)
		if game_state_machine then
			for _, asset in ipairs(self._global.assets) do
				if self:asset_is_buyable(asset) then
					return false
				end
			end
			if not return_status then
				self:unlock_buy_all_asset()
			else
				return true
			end
		end
	end
	
	function MissionAssetsManager:unlock_buy_all_asset()
		local asset = self:_get_asset_by_id("wolfhud_buy_all_assets")
		if asset and not asset.unlocked and self._tweak_data.wolfhud_buy_all_assets then
			self._tweak_data.wolfhud_buy_all_assets.money_lock = 0
			unlock_asset_original(self, "wolfhud_buy_all_assets")
		end
	end
	
	function MissionAssetsManager:mission_has_assets()
		local current_stage = managers.job:current_level_id() or ""
		local stages = self._tweak_data.wolfhud_buy_all_assets.stages
		local exclude_stages = self._tweak_data.wolfhud_buy_all_assets.exclude_stages
		return type(stages) == "table" and table.contains(stages, current_stage) or stages == "all" and not (exclude_stages and table.contains(exclude_stages, current_stage))
	end

	function MissionAssetsManager:asset_is_buyable(asset)
		return asset.id ~= "wolfhud_buy_all_assets" and asset.show and not asset.unlocked and self:get_asset_can_unlock_by_id(asset.id)
	end
elseif string.lower(RequiredScript) == "lib/tweak_data/assetstweakdata" then
	local _init_original = AssetsTweakData.init
	function AssetsTweakData:init(...)
		_init_original(self, ...)
		
		self.wolfhud_buy_all_assets = self.wolfhud_buy_all_assets or {
			name_id = "wolfhud_buy_all_assets",
			unlock_desc_id = "wolfhud_wolfhud_buy_all_assets_desc",
			texture = "guis/textures/pd2/feature_crimenet_heat",
			money_lock = 0,
			visible_if_locked = true,
			no_mystery = true,
			local_only = false,
			stages = "all",
			exclude_stages = {
				"safehouse",
				"alex_2",
				"escape_cafe",
				"escape_park",
				"escape_cafe_day",
				"escape_park_day",
				"escape_street",
				"escape_overpass",
				"escape_garage",
				"haunted",
				"hox_1",
				"hox_2",
				"pines",
				"crojob1",
				"short1_stage1",
				"short1_stage2",
				"short2_stage1",
				"short2_stage2b",
				"chill",
				"combat_chill",
			},
		}
	end
end