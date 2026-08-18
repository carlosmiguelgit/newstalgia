local imbuement = Action()

function imbuement.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	if configManager.getBoolean(configKeys.TOGGLE_IMBUEMENT_SHRINE_STORAGE) and player:getStorageValue(Storage.Quest.U11_02.ForgottenKnowledge.Tomes) ~= 1 then
		return player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You did not collect enough knowledge from the ancient Shapers. Visit the Shaper temple in Thais for help.")
	end

	if target and type(target) == "userdata" and target:isItem() then
		player:openImbuementWindow(target)
		return true
	end

	player:openImbuementWindow()
	return true
end

imbuement:id(25060, 25061, 25101, 25102, 25103, 25104, 25174, 25175, 25182, 25183, 25201, 25202, 24964)
imbuement:register()
