-- @docvars @{
-- root widget
rootWidget = g_ui.getRootWidget()
modules = package.loaded

-- G is used as a global table to save variables in memory between reloads
G = G or {}

-- @}

-- @docfuncs @{

local function getEventName(callback)
	local ok, info = pcall(debug.getinfo, callback, "S")
	if ok and info then
		local src = info.short_src or "lua"
		local line = info.linedefined or 0
		return src .. ":" .. line
	end
	return "lua"
end

function scheduleEvent(callback, delay)
	local name = getEventName(callback)
	local event
	if g_dispatcher.scheduleEventEx then
		event = g_dispatcher.scheduleEventEx(name, callback, delay)
	else
		event = g_dispatcher.scheduleEvent(callback, delay)
	end
	-- must hold a reference to the callback, otherwise it would be collected
	event._callback = callback
	return event
end

function addEvent(callback, front)
	local name = getEventName(callback)
	local event
	if g_dispatcher.addEventEx then
		event = g_dispatcher.addEventEx(name, callback)
	else
		event = g_dispatcher.addEvent(callback, front)
	end
	-- must hold a reference to the callback, otherwise it would be collected
	event._callback = callback
	return event
end

function cycleEvent(callback, interval)
	local name = getEventName(callback)
	local event
	if g_dispatcher.cycleEventEx then
		event = g_dispatcher.cycleEventEx(name, callback, interval)
	else
		event = g_dispatcher.cycleEvent(callback, interval)
	end
	-- must hold a reference to the callback, otherwise it would be collected
	event._callback = callback
	return event
end

function periodicalEvent(eventFunc, conditionFunc, delay, autoRepeatDelay)
	delay = delay or 30
	autoRepeatDelay = autoRepeatDelay or delay

	local func
	func = function()
		if conditionFunc and not conditionFunc() then
			func = nil
			return
		end
		eventFunc()
		scheduleEvent(func, delay)
	end

	scheduleEvent(function()
		func()
	end, autoRepeatDelay)
end

function removeEvent(event)
	if event then
		event:cancel()
		event._callback = nil
	end
end

UIWidget.setColorText = UIWidget.setColorText or function(self, text)
	text = tostring(text or '')
	if self.setColoredText then
		local colored = {}
		local defaultColor = '#ffffff'
		local current = 1
		while true do
			local tagStart, tagEnd, color = text:find('%[color=([^%]]+)%]', current)
			if not tagStart then
				local rest = text:sub(current):gsub('%[/color%]', '')
				if rest ~= '' then setStringColor(colored, rest, defaultColor) end
				break
			end

			local before = text:sub(current, tagStart - 1)
			if before ~= '' then setStringColor(colored, before, defaultColor) end

			local closeStart, closeEnd = text:find('%[/color%]', tagEnd + 1)
			local value = color:gsub('^[\'"]', ''):gsub('[\'"]$', '')
			if closeStart then
				setStringColor(colored, text:sub(tagEnd + 1, closeStart - 1), value)
				current = closeEnd + 1
			else
				setStringColor(colored, text:sub(tagEnd + 1), value)
				current = #text + 1
			end
		end

		self.coloredText = colored
		self:setColoredText(colored)
	elseif self.setText then
		self:setText(text:gsub('%[color=[^%]]+%]', ''):gsub('%[/color%]', ''))
	end
	return self
end

UIWidget.getColoredText = UIWidget.getColoredText or function(self)
	return self.coloredText
end

-- @}
