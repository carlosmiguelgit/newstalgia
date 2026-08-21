local bottomMenu
local calendarWindow
local activeScheduleEvent
local upcomingScheduleEvent
local eventSchedulerYears
local calendarCurrentMonth
local calendarPrevButton
local calendarNextButton
local calendarCurrentDate
local showOffWindow

local eventSchedulerTimestamp
local eventSchedulerCalendar
local eventSchedulerCalendarYearIndex
local eventSchedulerCalendarMonth

local boostedWindow
local monsterOutfit
local monsterImage
local bossOutfit
local bossImage

local CREATURE_BONUS_TEXT = "Today's boosted creature: %s\n\n\tBoosted creatures yield more experience\n points, carry more loot than usual\n and respawn at a faster rate."
local BOSS_BONUS_TEXT = "Today's boosted boss: %s\n\n\tBoosted boss contain more loot and\n count more kills for your bosstiary."

local applyToBoostedSlot
local resolveBoostedSlot
local retryBoostedSlot
local queueBoostedApply
local handleBoostedMessage
local onBoostedExtOpcode

local BOOSTED_EXT_OPCODE = 220

local default_info = {
    -- hint 1
    {
        image = "images/randomhint",
        Title = "Enabling Boosted Creature Panel",
        description = "Boosted creatures panel requires configuring a webservice (init.lua) and preloading a client version by either setting one server in Servers_init (init.lua) or by altering entergame.lua.\n\nFor more hints, visit:\t\t https://github.com/mehah/otclient/wiki"
    },

    -- hint 2
    -- {image = "image of label", Title = "title", description = "your hint here"},
}

function init()
    g_ui.importStyle('calendar')
    bottomMenu = g_ui.displayUI('bottommenu')

    calendarWindow = g_ui.createWidget('CalendarGrid', rootWidget)
    calendarCurrentMonth = calendarWindow:recursiveGetChildById('calendarCurrentMonth')
    calendarCurrentDate = calendarWindow:recursiveGetChildById('calendarCurrentDate')
    calendarPrevButton = calendarWindow:recursiveGetChildById('calendarPrevButton')
    calendarNextButton = calendarWindow:recursiveGetChildById('calendarNextButton')
    calendarWindow:hide()

    showOffWindow = bottomMenu:recursiveGetChildById('showOffWindow')
    showOffWindow.title = showOffWindow:recursiveGetChildById('showOffWindowText')
    activeScheduleEvent = bottomMenu:recursiveGetChildById('activeScheduleEvent')
    upcomingScheduleEvent = bottomMenu:recursiveGetChildById('upcomingScheduleEvent')
    upcomingScheduleEvent:recursiveGetChildById('fill'):setOn(false)
    eventSchedulerCalendarYearIndex = 1
    eventSchedulerCalendarMonth = tonumber(os.date("%m"))

    boostedWindow = bottomMenu:recursiveGetChildById('boostedWindow')
    monsterOutfit = boostedWindow:recursiveGetChildById('creature')
    bossOutfit = boostedWindow:recursiveGetChildById('boss')

--  if not Services.status and default_info then
    if default_info then
        local scrollable = showOffWindow:recursiveGetChildById('contentsPanel')
        local widget = g_ui.createWidget('ShowOffWidget', scrollable)
        local description = widget:recursiveGetChildById('description')
        local image = widget:recursiveGetChildById('image')

        math.randomseed(os.time())
        local randomIndex = math.random(1, #default_info)
        local randomItem = default_info[randomIndex]
        showOffWindow.title:setText(tr(randomItem.Title))
        image:setImageSource(randomItem.image)
        description:setText(tr(randomItem.description))
        monsterOutfit:setVisible(false)
        bossOutfit:setVisible(false)
        widget:resize(widget:getWidth(), description:getHeight())

        monsterImage = boostedWindow:recursiveGetChildById('monsterImage')
        bossImage = boostedWindow:recursiveGetChildById('bossImage')

        monsterImage:setImageSource("images/icon-questionmark")
        monsterImage:setVisible(true)
        bossImage:setImageSource("images/icon-questionmark")
        bossImage:setVisible(true)
    end
    if g_game.isOnline() then
        hide()
    end

    registerMessageMode(MessageModes.BoostedCreature, handleBoostedMessage)
    registerMessageMode(MessageModes.Status, handleBoostedMessage)
    registerMessageMode(MessageModes.Login, handleBoostedMessage)
    ProtocolGame.registerExtendedOpcode(BOOSTED_EXT_OPCODE, onBoostedExtOpcode)

    -- restore the boosted creature/boss cached from a previous session (same day)
    local cached = g_settings.getString('boosted-cache')
    if cached and #cached > 0 then
        local success, data = pcall(json.decode, cached)
        if success and type(data) == "table" and data.date == os.date("%Y-%m-%d") then
            -- make sure the client assets are loaded so the boosted creature/boss
            -- can be rendered right away at the login screen
            local savedVersion = g_settings.getInteger('client-version')
            if savedVersion and savedVersion ~= 0 and g_game.getClientVersion() ~= savedVersion then
                local version = savedVersion
                local function ensureBoostedThingsLoaded()
                    if not modules.game_things then
                        scheduleEvent(ensureBoostedThingsLoaded, 100)
                        return
                    end
                    pcall(g_game.setClientVersion, version)
                    pcall(g_game.setProtocolVersion, g_game.getClientProtocolVersion(version))
                end
                scheduleEvent(ensureBoostedThingsLoaded, 100)
            end
            if data.creatureId and data.creatureId ~= 0 then
                queueBoostedApply({ raceId = data.creatureId, name = data.creatureName, isBoss = false })
            end
            if data.bossId and data.bossId ~= 0 then
                queueBoostedApply({ raceId = data.bossId, name = data.bossName, isBoss = true })
            end
        end
    end
end

function terminate()
    unregisterMessageMode(MessageModes.BoostedCreature, handleBoostedMessage)
    unregisterMessageMode(MessageModes.Status, handleBoostedMessage)
    unregisterMessageMode(MessageModes.Login, handleBoostedMessage)
    ProtocolGame.unregisterExtendedOpcode(BOOSTED_EXT_OPCODE)
    bottomMenu:destroy()
    calendarWindow:destroy()
end

function hide()
    bottomMenu:hide()
    bottomMenu:lower()

    if not calendarWindow:isHidden() then
        onClickCloseCalendar()
    end
end

function show()
    bottomMenu:show()
    bottomMenu:raise()
    bottomMenu:focus()
end

-- @ Store showoff
function setShowOffData(data)
    local widget = g_ui.createWidget('ShowOffWidget', showOffWindow)
    local image = widget:recursiveGetChildById('image')

    if data.image and data.image:sub(1, 4):lower() == "http" then
        HTTP.downloadImage(data.image, function(path, err)
            if err then
                g_logger.warning("HTTP error: " .. err .. " - " .. data.image)
                return
            end
            image:setImageSource(path)
        end)
    else
        image:setImage(data.image)
    end

    local description = widget:recursiveGetChildById('description')

    showOffWindow.title:setText(tr(data.title))
    description:setText(tr(data.description))
end

-- @ Calendar/Events scheduler
function onClickOnCalendar()
    if eventSchedulerYears == nil or #eventSchedulerYears == 0 then
        return
    end

    calendarWindow:show()
    calendarWindow:raise()
    calendarWindow:centerIn('parent')
    calendarWindow:removeAnchor(AnchorHorizontalCenter)
    calendarWindow:removeAnchor(AnchorVerticalCenter)
    reloadEventsSchedulerCurrentPage()

    g_keyboard.bindKeyPress('Escape', onClickCloseCalendar)
end

function onClickCloseCalendar()
    calendarWindow:hide()
    calendarWindow:lower()

    g_keyboard.unbindKeyPress('Escape', onClickCloseCalendar)
end

function setEventsSchedulerTimestamp(time)
    eventSchedulerTimestamp = time
    calendarCurrentDate:setText(os.date("%Y-%m-%d, %H:%M CET", eventSchedulerTimestamp))
end

function getCalendarEventWidgetByDay(day, month, year, weekOffset, forceLine)
    local weekIndex = getDayOfWeek(day, month, year)
    local row = calendarWindow:recursiveGetChildById('row' .. weekIndex)
    if not row then
        return nil
    end

    local lineIndex = nil
    if forceLine ~= nil then
        lineIndex = forceLine
    else
        lineIndex = (math.floor(((weekOffset + day) - 1) / 7))
    end
    local line = row:recursiveGetChildById('line' .. lineIndex)
    if not line then
        return nil
    end

    return line
end

function reloadEventsSchedulerCurrentPage()
    local firstDayOffset = getDayOfWeek(1)
    if firstDayOffset == 0 then
        firstDayOffset = 7
    end
    local weekOffset = firstDayOffset - 1

    -- Days before the day 1 of this month
    if weekOffset > 0 then
        local previousYearIndex = eventSchedulerCalendarYearIndex
        local previousMonth = eventSchedulerCalendarMonth
        if previousMonth == 1 then
            previousYearIndex = previousYearIndex - 1
            previousMonth = 12
        else
            previousMonth = previousMonth - 1
        end
        if previousYearIndex >= 0 then
            local previousDays = eventSchedulerYears[previousYearIndex][previousMonth]
            local amountsLeft = weekOffset
            local i = #previousDays
            while (amountsLeft > 0) do
                local widget = getCalendarEventWidgetByDay(i, previousMonth, tonumber(os.date("%Y", os.time())) +
                    (previousYearIndex - 1), weekOffset, 0)
                if widget then
                    widget:clearEvents()
                    widget.dayOfTheWeek = i
                    widget:recursiveGetChildById('dayAndSeason'):setOn(true)
                    widget:recursiveGetChildById('day'):setText(i)
                    widget:recursiveGetChildById('day'):setWidth(string.len(
                        widget:recursiveGetChildById('day'):getText()) * 10)
                    widget:recursiveGetChildById('fill'):setOn(false)
                    for _, event in ipairs(previousDays[i]) do
                        widget:addScheduleEvent(event, false, nil)
                    end
                end
                amountsLeft = amountsLeft - 1
                i = i - 1
            end
        end
    end

    -- Days after the last day of this month
    local days = eventSchedulerYears[eventSchedulerCalendarYearIndex][eventSchedulerCalendarMonth]
    local lastDayOffset = getDayOfWeek(#days)
    if lastDayOffset == 0 then
        lastDayOffset = 7
    end
    local nextWeekOffset = 7 - lastDayOffset
    local nextYearIndex = eventSchedulerCalendarYearIndex
    local nextMonth = eventSchedulerCalendarMonth
    if nextMonth == 12 then
        nextYearIndex = nextYearIndex + 1
        nextMonth = 1
    else
        nextMonth = nextMonth + 1
    end
    if nextYearIndex <= 2 then
        local nextDays = eventSchedulerYears[nextYearIndex][nextMonth]
        local amountsLeft = nextWeekOffset
        local i = 1
        local forceLine = 4
        if firstDayOffset >= 5 then
            forceLine = 5
        end
        if firstDayOffset <= 5 then
            amountsLeft = amountsLeft + 7
        end
        while (amountsLeft > 0) do
            if forceLine == 4 and amountsLeft == 7 then
                forceLine = 5
            end
            local widget = getCalendarEventWidgetByDay(i, nextMonth,
                tonumber(os.date("%Y", os.time())) + (nextYearIndex - 1), nextWeekOffset, forceLine)
            if widget then
                widget:clearEvents()
                widget.dayOfTheWeek = i
                widget:recursiveGetChildById('dayAndSeason'):setOn(true)
                widget:recursiveGetChildById('day'):setText(i)
                widget:recursiveGetChildById('day'):setWidth(
                    string.len(widget:recursiveGetChildById('day'):getText()) * 10)
                widget:recursiveGetChildById('fill'):setOn(false)
                for _, event in ipairs(nextDays[i]) do
                    widget:addScheduleEvent(event, false, nil)
                end
            end
            amountsLeft = amountsLeft - 1
            i = i + 1
        end
    end

    for day, events in ipairs(days) do
        local widget = getCalendarEventWidgetByDay(day, nil, nil, weekOffset, nil)
        if widget then
            widget:clearEvents()
            widget.dayOfTheWeek = day
            widget:recursiveGetChildById('dayAndSeason'):setOn(true)
            widget:recursiveGetChildById('day'):setText(tr(day))
            widget:recursiveGetChildById('day'):setWidth(string.len(widget:recursiveGetChildById('day'):getText()) * 10)
            widget:recursiveGetChildById('fill'):setOn(true)
            for _, event in ipairs(events) do
                widget:addScheduleEvent(event, true, nil)
            end
        end
    end

    calendarCurrentMonth:setText(os.date("%B", os.time {
        year = 2023,
        month = eventSchedulerCalendarMonth,
        day = 1
    }) .. " " .. (tonumber(os.date("%Y", os.time())) + (eventSchedulerCalendarYearIndex - 1)))
end

function reloadEventsSchedulerCalender()
    eventSchedulerYears = {}
    table.insert(eventSchedulerYears, createCalendar(tonumber(os.date("%Y", os.time()))))
    table.insert(eventSchedulerYears, createCalendar(tonumber(os.date("%Y", os.time())) + 1))

    if eventSchedulerCalendar == nil or #eventSchedulerCalendar == 0 then
        return
    end

    for _, info in ipairs(eventSchedulerCalendar) do
        local days = getCalendarDays(info.startdate, info.enddate)
        for index, day in ipairs(days) do
            table.insert(day, {
                active = (info.colorlight .. "ff"),
                inactive = (info.colordark .. "ff"),
                description = info.description,
                priority = info.displaypriority,
                season = info.isseasonal,
                name = info.name,
                special = info.specialevent,
                firstDay = index == 1,
                lastDay = index == #days
            })
        end
    end

    activeScheduleEvent:clearEvents()
    local currentDay = getCalendarDays(os.time(), os.time())
    if #currentDay > 0 then
        for _, event in ipairs(currentDay[1]) do
            activeScheduleEvent:addScheduleEvent(event, true, onClickOnCalendar)
        end
    end

    upcomingScheduleEvent:clearEvents()
    local nextDay = getCalendarDays(os.time() + 86400, os.time() + 86400)
    if #nextDay > 0 then
        for _, event in ipairs(nextDay[1]) do
            upcomingScheduleEvent:addScheduleEvent(event, false, onClickOnCalendar)
        end
    end
end

function setEventsSchedulerCalender(calender)
    eventSchedulerCalendar = calender
    reloadEventsSchedulerCalender()
end

function createCalendar(year)
    local calendar = {}

    for month = 1, 12 do
        calendar[month] = {}
        local daysInMonth = 31
        if month == 2 then
            if (year % 4 == 0 and year % 100 ~= 0) or (year % 400 == 0) then
                daysInMonth = 29
            else
                daysInMonth = 28
            end
        elseif month == 4 or month == 6 or month == 9 or month == 11 then
            daysInMonth = 30
        end

        for day = 1, daysInMonth do
            calendar[month][day] = {}
        end
    end

    return calendar
end

function getCalendarDays(startTimestamp, endTimestamp)
    local currentYear = tonumber(os.date("%Y", os.time()))
    local startYear = tonumber(os.date("%Y", startTimestamp))
    local endYear = tonumber(os.date("%Y", endTimestamp))
    local daysInRange = {}

    if startYear ~= currentYear and startYear ~= (currentYear + 1) then
        return daysInRange
    end

    if endYear ~= currentYear and endYear ~= (currentYear + 1) then
        return daysInRange
    end

    local startMonth = tonumber(os.date("%m", startTimestamp))
    local startDay = tonumber(os.date("%d", startTimestamp))
    local endMonth = tonumber(os.date("%m", endTimestamp))
    local endDay = tonumber(os.date("%d", endTimestamp))

    if startYear == currentYear then
        for month = startMonth, endMonth do
            local startLoop = 1
            local endLoop = 31

            if month == startMonth then
                startLoop = startDay
            end

            if month == endMonth then
                endLoop = endDay
            end

            if eventSchedulerYears[1][month] then
                for day = startLoop, endLoop do
                    if eventSchedulerYears[1][month][day] then
                        table.insert(daysInRange, eventSchedulerYears[1][month][day])
                    end
                end
            end
        end
    else
        for month = startMonth, 12 do
            local startLoop = 1
            local endLoop = 31

            if month == startMonth then
                startLoop = startDay
            end

            if month == endMonth then
                endLoop = endDay
            end

            if eventSchedulerYears[1][month] then
                for day = startLoop, endLoop do
                    if eventSchedulerYears[1][month][day] then
                        table.insert(daysInRange, eventSchedulerYears[1][month][day])
                    end
                end
            end
        end
        for month = 1, endMonth do
            local startLoop = 1
            local endLoop = 31

            if month == startMonth then
                startLoop = startDay
            end

            if month == endMonth then
                endLoop = endDay
            end

            if eventSchedulerYears[2][month] then
                for day = startLoop, endLoop do
                    if eventSchedulerYears[2][month][day] then
                        table.insert(daysInRange, eventSchedulerYears[2][month][day])
                    end
                end
            end
        end
    end

    return daysInRange
end

function getDayOfWeek(day, month, year)
    if not year then
        year = tonumber(os.date("%Y", os.time())) + (eventSchedulerCalendarYearIndex - 1)
    end
    if not month then
        month = eventSchedulerCalendarMonth
    end
    local timestamp = os.time {
        year = year,
        month = month,
        day = day
    }
    local weekday = tonumber(os.date("%w", timestamp))
    -- 0: Sunday
    -- 6: Saturday
    return weekday
end

function onClickOnPreviousCalendar()
    if eventSchedulerCalendarMonth == 1 then
        if eventSchedulerCalendarYearIndex == 1 then
            return
        end
        eventSchedulerCalendarMonth = 12
        eventSchedulerCalendarYearIndex = eventSchedulerCalendarYearIndex - 1
    else
        eventSchedulerCalendarMonth = eventSchedulerCalendarMonth - 1
    end

    calendarNextButton:setEnabled(true)
    if eventSchedulerCalendarYearIndex == 1 and eventSchedulerCalendarMonth == (tonumber(os.date("%m", os.time())) - 1) then
        calendarPrevButton:setEnabled(false)
    else
        calendarPrevButton:setEnabled(true)
    end

    reloadEventsSchedulerCurrentPage()
end

function onClickOnNextCalendar()
    if eventSchedulerCalendarMonth == 12 then
        if eventSchedulerCalendarYearIndex == 2 then
            return
        end
        eventSchedulerCalendarMonth = 1
        eventSchedulerCalendarYearIndex = eventSchedulerCalendarYearIndex + 1
    else
        eventSchedulerCalendarMonth = eventSchedulerCalendarMonth + 1
    end

    calendarPrevButton:setEnabled(true)
    if eventSchedulerCalendarYearIndex == 2 and eventSchedulerCalendarMonth == (tonumber(os.date("%m", os.time())) - 1) then
        calendarNextButton:setEnabled(false)
    else
        calendarNextButton:setEnabled(true)
    end

    reloadEventsSchedulerCurrentPage()
end

-- (internal)
-- set creature/boss to boosted slot
function applyToBoostedSlot(raceId, outfitWidget, imageWidget, fileName, tooltipText)
    -- check if raceId was provided in the JSON response
    if not raceId then
        return
    end

    -- fetch race data
    local raceData = g_things.getRaceData(raceId)

    -- check if race id is present in the staticdata
    if raceData.raceId == 0 then
        local msg = string.format("[%s] Creature with race id %s was not found.", fileName,tostring(raceId))
        g_logger.warning(msg)
        return
    end

    -- apply to selected widget
    outfitWidget:setOutfit(raceData.outfit)
    outfitWidget:getCreature():setStaticWalking(1000)
    outfitWidget:setVisible(true)
    imageWidget:setVisible(false)
    outfitWidget:setTooltip(tr(tooltipText, raceData.name or "Unknown"))
end

function setBoostedCreatureAndBoss(data)
    if not modules.game_things.isLoaded() then
        return
    end

    -- file name for error reporting
    local fileName = debug.getinfo(1, "S").source -- current file name - bottommenu.lua

    -- boosted creature
    -- before bosstiary was introduced, the webservice was sending creature race in 'raceid' field
    -- after bosstiary was added, it was changed to 'creatureraceid'
    -- this 'or' statement ensures backwards compatibility
    applyToBoostedSlot(data.creatureraceid or data.raceid, monsterOutfit, monsterImage, fileName, CREATURE_BONUS_TEXT)

    -- boosted boss
    applyToBoostedSlot(data.bossraceid, bossOutfit, bossImage, fileName, BOSS_BONUS_TEXT)
end

-- (internal)
-- find race data for the creature/boss announced by the game server
function resolveBoostedSlot(entry)
    if not modules.game_things or not modules.game_things.isLoaded() then
        return false
    end

    local raceData
    if entry.raceId and entry.raceId ~= 0 then
        raceData = g_things.getRaceData(entry.raceId)
        if raceData.raceId == 0 then
            raceData = nil
        end
    end

    if not raceData and entry.name and #entry.name > 0 then
        local races = g_things.getRacesByName(entry.name)
        local race
        for _, candidate in ipairs(races) do
            if candidate.name:lower() == entry.name:lower() then
                race = candidate
                break
            end
        end
        race = race or races[1]
        if race and race.raceId ~= 0 then
            raceData = race
        end
    end

    if not raceData then
        return true
    end

    local outfitWidget = entry.isBoss and bossOutfit or monsterOutfit
    local imageWidget = entry.isBoss and bossImage or monsterImage
    local tooltipText = entry.isBoss and BOSS_BONUS_TEXT or CREATURE_BONUS_TEXT
    applyToBoostedSlot(raceData.raceId, outfitWidget, imageWidget, "bottommenu.lua", tooltipText)
    return true
end

local boostedPending = {}
local boostedApplied = {}
local boostedRetryCount = 0

function retryBoostedSlot()
    local remaining = {}
    for _, entry in ipairs(boostedPending) do
        if not resolveBoostedSlot(entry) then
            remaining[#remaining + 1] = entry
        end
    end
    boostedPending = remaining
    if #remaining > 0 then
        boostedRetryCount = boostedRetryCount + 1
        if boostedRetryCount < 300 then
            scheduleEvent(retryBoostedSlot, 500)
        end
    end
end

-- (internal)
-- queue an apply by race id and/or name; skipped if already applied for this session
function queueBoostedApply(entry)
    local key = (entry.raceId and entry.raceId ~= 0) and ("id:" .. entry.raceId) or ("name:" .. tostring(entry.name))
    key = key .. (entry.isBoss and ":boss" or ":creature")
    if boostedApplied[key] then
        return
    end
    boostedApplied[key] = true
    boostedPending[#boostedPending + 1] = entry
    retryBoostedSlot()
end

-- (internal)
-- the game server announces the boosted creature/boss on login, e.g.:
--   "Today's boosted creature: Juggernaut.\nBoosted creatures yield..."
--   "Today's boosted boss: Tropical Desolator.\nBoosted bosses contain..."
function handleBoostedMessage(messageMode, message)
    local trimmed = message:gsub("%s+$", "")

    local creatureName = trimmed:match("Today's boosted creature:%s*([^\n%.]+)")
    if creatureName then
        queueBoostedApply({ name = creatureName, isBoss = false })
        return
    end

    local bossName = trimmed:match("Today's boosted boss:%s*([^\n%.]+)")
    if bossName then
        queueBoostedApply({ name = bossName, isBoss = true })
    end
end

-- (internal)
-- the server sends the boosted creature/boss right at game login via extended
-- opcode, JSON payload: {"creatureId","bossId","creatureName","bossName"}
function onBoostedExtOpcode(protocol, opcode, buffer)
    local success, data = pcall(json.decode, buffer)
    if success and type(data) == "table" then
        if data.creatureId and data.creatureId ~= 0 then
            queueBoostedApply({ raceId = data.creatureId, name = data.creatureName, isBoss = false })
        elseif data.creatureName and #data.creatureName > 0 then
            queueBoostedApply({ name = data.creatureName, isBoss = false })
        end

        if data.bossId and data.bossId ~= 0 then
            queueBoostedApply({ raceId = data.bossId, name = data.bossName, isBoss = true })
        elseif data.bossName and #data.bossName > 0 then
            queueBoostedApply({ name = data.bossName, isBoss = true })
        end

        -- cache for the next client open (only valid on the same day)
        local ok, encoded = pcall(json.encode, {
            creatureId = data.creatureId,
            creatureName = data.creatureName,
            bossId = data.bossId,
            bossName = data.bossName,
            date = os.date("%Y-%m-%d")
        })
        if ok and encoded then
            g_settings.set('boosted-cache', encoded)
            g_settings.save()
        end
    else
        -- fallback: legacy "<creature>|||<boss>" payload
        local creatureName, bossName = buffer:match("^([^|]*)|||([^|]*)$")
        if creatureName and #creatureName > 0 then
            queueBoostedApply({ name = creatureName, isBoss = false })
        end
        if bossName and #bossName > 0 then
            queueBoostedApply({ name = bossName, isBoss = true })
        end
    end
end
