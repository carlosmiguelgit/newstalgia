dailyRewardWindow = nil
confirmRewardWindow = nil
selectRewardWindow = nil

local instantTokens
local jokerTokens
local rewardAmount = 0
local totalOz = 0
local freeCap = 0
local globalMessage
local gameFromShrine

local ResourceReward = ResourceTypes.DAILYREWARD_STREAK
local ResourceJokerReward = ResourceTypes.DAILYREWARD_JOKERS

local function freecap()
  local player = g_game.getLocalPlayer()
  if not player then
    return 0
  end
  return player:getFreeCapacity()
end

if not g_client.setInputLockWidget then
  g_client.setInputLockWidget = function() end
end

function toggle()
  if dailyRewardWindow and dailyRewardWindow:isVisible() then
    return closeDaily()
  end
  show()
end

function init()
  dailyRewardWindow = g_ui.displayUI('dailyreward')
  dailyRewardWindow:hide()

  g_ui.importStyle('selectreward')

  ButtonRewardWall = modules.game_mainpanel.addToggleButton("rewardWall", tr("Open rewardWall"), "/images/options/rewardwall", toggle, false, 21)

  connect(g_game, {
    onGameEnd = offline,
    onDailyReward = onDailyReward,
    onOpenRewardWall = onOpenRewardWall,
    onRewardHistory = onDailyRewardHistory,
    onResourcesBalanceChange = onResourceBalance,
  })

  connect(LocalPlayer, {
    onFreeCapacityChange = onFreeCapacityChange,
  })
end

function terminate()
  DailyReward:cancelConfiguration()

  disconnect(g_game, {
    onGameEnd = offline,
    onDailyReward = onDailyReward,
    onOpenRewardWall = onOpenRewardWall,
    onRewardHistory = onDailyRewardHistory,
    onResourcesBalanceChange = onResourceBalance,
  })

  disconnect(LocalPlayer, {
    onFreeCapacityChange = onFreeCapacityChange,
  })

  if ButtonRewardWall then
    ButtonRewardWall:destroy()
    ButtonRewardWall = nil
  end

  dailyRewardWindow:destroy()

  if dailyRewardHistory then
    dailyRewardHistory:destroy()
    dailyRewardHistory = nil
  end

  if selectRewardWindow then
    g_client.setInputLockWidget(nil)
    selectRewardWindow:destroy()
    selectRewardWindow = nil
  end
  if confirmRewardWindow then
    g_client.setInputLockWidget(nil)
    confirmRewardWindow:destroy()
    confirmRewardWindow = nil
  end
end

function closeSelectReward()
  if not selectRewardWindow then
    return
  end

  g_client.setInputLockWidget(nil)
  selectRewardWindow:destroy()
  selectRewardWindow = nil
  dailyRewardWindow:show(true)
  g_client.setInputLockWidget(dailyRewardWindow)
end

function closeDaily()
  dailyRewardWindow:hide()
  g_client.setInputLockWidget(nil)
  if ButtonRewardWall then
    ButtonRewardWall:setOn(false)
  end
  if selectRewardWindow then
    selectRewardWindow:hide()
    g_client.setInputLockWidget(nil)
  end
  if confirmRewardWindow then
    confirmRewardWindow:hide()
  end
  if dailyRewardHistory then
    dailyRewardHistory:destroy()
    dailyRewardHistory = nil
  end

  modules.game_console.getConsole():focus()
end

function show()
  g_game.sendOpenRewardWall()
  g_client.setInputLockWidget(dailyRewardWindow)
end

function requestHistory()
  closeDaily()
  g_game.requestOpenRewardHistory()

end

function offline()
  DailyReward:cancelConfiguration()
  dailyRewardWindow:hide()
  g_client.setInputLockWidget(nil)
  if confirmRewardWindow then
    confirmRewardWindow:destroy()
    confirmRewardWindow = nil
  end
  if selectRewardWindow then
    selectRewardWindow:destroy()
    selectRewardWindow = nil
  end
end

local function convertRewardDay(day)
  local reward = { type = day.redeemMode, amount = 0, items = {}, preyCount = 0, xpboost = 0 }
  if day.redeemMode == 1 then
    reward.amount = day.itemsToSelect
    for _, item in pairs(day.selectableItems) do
      reward.items[#reward.items + 1] = { item = item.itemId, name = item.name, oz = item.weight }
    end
  elseif day.redeemMode == 2 then
    for _, bundle in pairs(day.bundleItems) do
      if bundle.bundleType == 1 then
        reward.items[#reward.items + 1] = { item = bundle.itemId, name = bundle.name, oz = bundle.count }
      elseif bundle.bundleType == 2 then
        reward.preyCount = bundle.count
      elseif bundle.bundleType == 3 then
        reward.xpboost = bundle.itemId
      end
    end
  end
  return reward
end

function onDailyReward(data)
  if not data then
    return
  end

  local freeRewards = {}
  local premiumRewards = {}
  for i = 1, #data.freeRewards do
    freeRewards[i] = convertRewardDay(data.freeRewards[i])
    premiumRewards[i] = convertRewardDay(data.premiumRewards[i])
  end

  local descriptions = {}
  for i, bonus in pairs(data.bonuses) do
    descriptions[i] = bonus.name
  end

  DailyReward:onDailyReward(freeRewards, premiumRewards, descriptions)
end

function onOpenRewardWall(bonusShrine, nextRewardTime, dayStreakDay, wasDailyRewardTaken, errorMessage, tokens, timeLeft, dayStreakLevel)
  local player = g_game.getLocalPlayer()
  if not player then
    return
  end

  local fromShrine = bonusShrine
  local currentIndex = dayStreakDay
  local message = errorMessage
  local dailyState = wasDailyRewardTaken ~= 0 and 0 or 2
  local jokerToken = tokens
  local serverSave = timeLeft

  dailyRewardWindow:focus()
  g_client.setInputLockWidget(dailyRewardWindow)
  dailyRewardWindow.miniWindowBonuses.jokerInfo.streakWidget:setText(dayStreakLevel)
  dailyRewardWindow.miniWindowBonuses.jokerInfo.timerStreakPanel.timerStreakProgress:setVisible(false)
  dailyRewardWindow.miniWindowBonuses.jokerInfo.timerStreakPanel.timerStreakLabel:setText("")
  dailyRewardWindow.miniWindowBonuses.jokerInfo.timerStreakPanel.timerStreakCheck:setVisible(true)

  local storedJokerBalance = player:getResourceBalance(ResourceJokerReward) or 0
  local jokerBalance = math.max(storedJokerBalance, jokerToken or 0)
  jokerTokens = jokerBalance
  instantTokens = player:getResourceBalance(ResourceReward) or instantTokens or 0

  dailyRewardWindow.instantAcess.instantLabel:setText(instantTokens)
  local text = jokerToken > 3 and ">3" or jokerToken
  dailyRewardWindow.miniWindowBonuses.jokerInfo.jokers.jokerInfoLabel:setText(text)

  local textColor = jokerToken > jokerBalance and "#d33c3c" or "#c0c0c0"
  dailyRewardWindow.miniWindowBonuses.jokerInfo.jokers.jokerInfoLabel:setColor(textColor)

  dailyRewardWindow.jokers.jokersLabel:setText(math.min(3, jokerBalance))

  if dailyState == 0 then
    dailyRewardWindow.miniWindowBonuses.bonusLabel:setText("You already claimed your daily reward.")
  elseif dailyState == 1 then
    dailyRewardWindow.miniWindowBonuses.bonusLabel:setText("You did not claim your daily reward in time.\nToo bad, you do not have enough Daily Reward Jokers.")
  elseif dailyState == 2 then
    dailyRewardWindow.miniWindowBonuses.bonusLabel:setColorText("Claim your daily reward before server save.\n If you don't claim your reward now, your [color=#d33c3c]streak will be reset[/color].")
  end

  globalMessage = message
  dailyRewardWindow.miniWindowBonuses.bonusLabel.onHoverChange = function(_, hovered) setupBonusLabelDesc(hovered, dailyState, jokerToken) end

  for i = 0, 6 do
    local widget = dailyRewardWindow.miniWindowDailyReward.dailyReward:recursiveGetChildById("dailyButton_".. i)
    if widget and i ~= currentIndex then
      widget:setImageSource("/images/dailyreward/nextbg")
      widget.blocked:setImageSource("/images/ui/ditherpattern64")
      widget.blocked:setMargin(1)
      local style = {}
      style["$pressed"] = {
        ["image-clip"] = "0 0 66 66"
      }
      widget:mergeStyle(style)
      widget.onClick = function() end
    elseif widget and dailyState ~= 0 then
      widget:setImageSource("/images/dailyreward/buttonbg")
      local style = {}
      style["$pressed"] = {
        ["icon-offset"] = "1 1",
        ["image-clip"] = "0 66 66 66"
      }
      widget:mergeStyle(style)
      widget.onClick = onClaimReward
      widget.blocked:setImageSource("")
    elseif widget then
      widget.blocked:setImageSource("")
      widget:setImageSource("/images/dailyreward/nextbg")
      local style = {}
      style["$pressed"] = {
        ["image-clip"] = "0 0 66 66"
      }
      widget:mergeStyle(style)
      widget.onClick = function() end
    end

    gameFromShrine = fromShrine

    local widget = dailyRewardWindow.miniWindowDailyReward.dailyReward:recursiveGetChildById("dailyPanel_".. i)
    widget.dailyPanelProgress:setVisible(false)
    if widget and i < currentIndex then
      widget.dailyBlocked:setVisible(false)
      widget.dailyPanelLabel:setVisible(true)
      widget.dailyPanelLabel:setText(" ")
      widget.dailyPanelLabel:setIcon("/images/dailyreward/icon-checkmark")
      widget.dailyIconLabel:setVisible(false)
    elseif widget and i > currentIndex then
      widget.dailyBlocked:setVisible(true)
      widget.dailyPanelLabel:setVisible(false)
      widget.dailyIconLabel:setVisible(false)
    elseif widget and dailyState == 0 then
      widget.dailyBlocked:setVisible(false)
      widget.dailyPanelLabel:setIcon("")
      widget.dailyPanelLabel:setText("")
      widget.dailyPanelLabel:setVisible(true)
      widget.dailyIconLabel:setVisible(false)
      widget.dailyPanelProgress:setVisible(true)

      local time = nextRewardTime - os.time()
      local hours = math.floor(time / 3600)
      local minutes = math.floor((time % 3600) / 60)
      local formattedTime = string.format("%02d:%02d", hours, minutes)

      widget.dailyPanelProgress:setText(formattedTime)
      local minimus = nextRewardTime - (24*60*60)
      widget.dailyPanelProgress:setValue(os.time(), 0, nextRewardTime)
      widget.dailyPanelProgress:setMinimum(minimus)
      widget.dailyPanelProgress:updateBackground()

    elseif widget and dailyState == 1 then
      widget.dailyBlocked:setVisible(false)
      widget.dailyPanelLabel:setIcon("")
      widget.dailyPanelLabel:setText(gameFromShrine and "0" or "1")
      widget.dailyIconLabel:setVisible(true)
      widget.dailyPanelProgress:setVisible(false)
      dailyRewardWindow.miniWindowBonuses.jokerInfo.timerStreakPanel.timerStreakLabel:setText("expired")
      dailyRewardWindow.miniWindowBonuses.jokerInfo.timerStreakPanel.timerStreakCheck:setVisible(false)
    elseif widget and dailyState == 2 then
      widget.dailyBlocked:setVisible(false)
      widget.dailyPanelLabel:setIcon("")
      widget.dailyPanelLabel:setVisible(true)
      widget.dailyPanelLabel:setText(gameFromShrine and "0" or "1")
      widget.dailyIconLabel:setVisible(true)
      widget.dailyPanelProgress:setVisible(false)

      local time = serverSave - os.time()
      local hours = math.floor(time / 3600)
      local minutes = math.floor((time % 3600) / 60)
      local formattedTime = string.format("%02d:%02d", hours, minutes)

      widget.dailyPanelProgress:setText(formattedTime)
      local minimus = serverSave - (24*60*60)
      widget.dailyPanelProgress:setValue(os.time(), 0, serverSave)
      widget.dailyPanelProgress:setMinimum(minimus)
      widget.dailyPanelProgress:updateBackground()

      dailyRewardWindow.miniWindowBonuses.jokerInfo.timerStreakPanel.timerStreakProgress:setVisible(true)
      dailyRewardWindow.miniWindowBonuses.jokerInfo.timerStreakPanel.timerStreakProgress:setText(formattedTime)
      dailyRewardWindow.miniWindowBonuses.jokerInfo.timerStreakPanel.timerStreakProgress:setValue(os.time(), 0, serverSave)
      dailyRewardWindow.miniWindowBonuses.jokerInfo.timerStreakPanel.timerStreakProgress:setMinimum(minimus)
      dailyRewardWindow.miniWindowBonuses.jokerInfo.timerStreakPanel.timerStreakProgress:updateBackground()
      dailyRewardWindow.miniWindowBonuses.jokerInfo.timerStreakPanel.timerStreakLabel:setText("")
      dailyRewardWindow.miniWindowBonuses.jokerInfo.timerStreakPanel.timerStreakLabel:setVisible(false)
      dailyRewardWindow.miniWindowBonuses.jokerInfo.timerStreakPanel.timerStreakCheck:setVisible(false)
    end

    local widget = dailyRewardWindow.miniWindowDailyReward.dailyReward:recursiveGetChildById("processArrow_".. i)
    if widget and i < currentIndex then
      widget:setText(" ")
      widget:setIcon("/images/dailyreward/icon-rewardarrow-active")
    end
  end

  if ButtonRewardWall then
    ButtonRewardWall:setOn(true)
  end

  dailyRewardWindow:show(true)
end

function setupBonusLabelDesc(hovered, dailyState, jokerToken)
  if not hovered then
    dailyRewardWindow.Description.tooltipTodo:setText("")
    return
  end

  local text = ""
  if dailyState == 0 then
    text = "Congratulations! You claimed your daily reward in time. Come back after\nthe next regular server save for more rewards.\nRaise your reward streak to benefit from bonuses in resting areas."
  elseif dailyState == 1 then
    text = string.format("Oh no! You are too late! You did not claim your daily reward before server\nsave. Your reward streak will be reset to 1 as you do not have at least %s\nDaily Reward Jokers to keep the streak going.\nRaise your reward streak to benefit from bonuses in resting areas.", jokerToken)
  elseif dailyState == 2 then
    if jokerToken > 0 then
      text = string.format("Hurry! Claim your daily reward before the next regular server save to raise\nyour reward streak by one.\nTo prevent a reset of your reward streak, %d Daily Reward Jokers will be used.\nRaise your reward streak to benefit from bonuses in resting areas.", jokerToken)
    else
      text = "Hurry! Claim your daily reward before the next regular server save to raise\nyour reward streak by one.\nTo prevent a reset of your reward streak.\nRaise your reward streak to benefit from bonuses in resting areas."
    end
  end
  dailyRewardWindow.Description.tooltipTodo:setText(text)
end

function onClaimReward(widget)
  local player = g_game.getLocalPlayer()
  if not player then
    return
  end

  if selectRewardWindow then
    selectRewardWindow:destroy()
    selectRewardWindow = nil
  end

  selectedAmount = 0
  selectItems = {}
  local reward = g_game.getLocalPlayer():isPremium() and widget.premiumRewards or widget.freeRewards
  if reward.type == 1 then
    dailyRewardWindow:hide()
    g_client.setInputLockWidget(nil)
    selectRewardWindow = g_ui.createWidget('MainWindowSelect', modules.game_interface.getRootPanel())
    g_client.setInputLockWidget(selectRewardWindow)

    for c, i in pairs(reward.items) do
      local w = g_ui.createWidget("RewardSelectLabel", selectRewardWindow.itemPanel)
      if w then
        w.item:setItemId(i.item)
        w.name:setText(i.name)
        w.oz:setText("0.00 oz")
        w.ozNumber = i.oz
        --w.oz:setText(string.format("%.2f oz", (i.oz)/100))
        w.leftSkipPlus.onClick = onClickAmount
        w.leftSkip.onClick = onClickAmount
        w.rightSkip.onClick = onClickAmount
        w.rightSkipPlus.onClick = onClickAmount
        w.leftSkipPlus.window = w
        w.leftSkip.window = w
        w.rightSkip.window = w
        w.rightSkipPlus.window = w
        w:setBackgroundColor((c % 2 ~= 0 and "#484848" or "#414141"))
      end
    end

    selectRewardWindow.freeCapacityLabel:setText(string.format("Free Capacity: %d oz", tonumber(freeCap) or 0))
    local m = {}
    setStringColor(m, "You have selected ", "#C0C0C0")
    setStringColor(m, "0", "#F75F5F")
    totalOz = 0
    rewardAmount = reward.amount
    setStringColor(m, string.format(" of %d reward items.", reward.amount), "#C0C0C0")
    selectRewardWindow.selectLabel:setColoredText(m)

    selectRewardWindow.closeButton.onClick = closeSelectReward
  else
    onClickConfirm(widget)
  end
end

function onFreeCapacityChange(player, freeCapacity)
  freeCap = freeCapacity
end

function onClickAmount(widget)
  local id = widget:getId()
  local row = widget.window

  local current = tonumber(row.countEdit:getText()) or 0
  if current < 0 then
    current = 0
  end

  local function getTotalSelected()
    local total = 0
    if selectRewardWindow and selectRewardWindow.itemPanel then
      for _, child in pairs(selectRewardWindow.itemPanel:getChildren()) do
        local v = tonumber(child.countEdit:getText()) or 0
        if v > 0 then
          total = total + v
        end
      end
    end
    return total
  end

  local remaining = math.max(0, rewardAmount - getTotalSelected())

  if id == "leftSkipPlus" then
    current = 0
  elseif id == "leftSkip" then
    current = math.max(0, current - 1)
  elseif id == "rightSkip" then
    if remaining > 0 then
      current = current + 1
    end
  elseif id == "rightSkipPlus" then
    if remaining > 0 then
      current = current + remaining
    end
  end

  row.countEdit:setText(tostring(current))

  selectedAmount = getTotalSelected()

  totalOz = 0
  for _, child in pairs(selectRewardWindow.itemPanel:getChildren()) do
    local v = tonumber(child.countEdit:getText()) or 0
    if v > 0 then
      totalOz = totalOz + (v * (child.ozNumber or 0))
    end
  end
  selectRewardWindow.totalWeightLabel:setText(string.format('Total Weight:        %.2f oz', totalOz/100))
  row.oz:setText(string.format("%.2f oz", (row.ozNumber * current)/100))

  -- arrumando as coisas
  if selectedAmount < rewardAmount then
    for i, child in pairs(selectRewardWindow.itemPanel:getChildren()) do
      child.rightSkipPlus:setIcon("/images/dailyreward/icon-arrowskipright")
      child.rightSkip:setIcon("/images/dailyreward/icon-arrowright")
    end
  else
    for i, child in pairs(selectRewardWindow.itemPanel:getChildren()) do
      child.rightSkipPlus:setIcon("/images/dailyreward/icon-arrowskipright-disabled")
      child.rightSkip:setIcon("/images/dailyreward/icon-arrowright-disabled")
    end
  end

  for i, child in pairs(selectRewardWindow.itemPanel:getChildren()) do
    if tonumber(child.countEdit:getText()) > 0 then
      child.leftSkipPlus:setIcon("/images/dailyreward/icon-arrowskip")
      child.leftSkip:setIcon("/images/dailyreward/icon-arrow")
    else
      child.leftSkipPlus:setIcon("/images/dailyreward/icon-arrowskip-disabled")
      child.leftSkip:setIcon("/images/dailyreward/icon-arrow-disabled")
    end
  end

  local m = {}
  setStringColor(m, "You have selected ", "#C0C0C0")
  if selectedAmount < rewardAmount then
    setStringColor(m, string.format("%d", selectedAmount), "#F75F5F")
  else
    setStringColor(m, string.format("%d", selectedAmount), "#0B8A0A")
  end
  setStringColor(m, string.format(" of %d reward items.", rewardAmount), "#C0C0C0")
  selectRewardWindow.selectLabel:setColoredText(m)

  if selectedAmount == rewardAmount then
    selectRewardWindow.ok:setEnabled(true)
    selectRewardWindow.ok.onClick = onClickConfirm
  else
    selectRewardWindow.ok:setEnabled(false)
  end

end

function onClickConfirm(widget)
  if confirmRewardWindow then
    return
  end

  if selectRewardWindow then
    selectRewardWindow:hide()
    g_client.setInputLockWidget(nil)
  end

  dailyRewardWindow:hide()
  g_client.setInputLockWidget(nil)

  local yesCallback = function()
    if confirmRewardWindow then
      confirmRewardWindow:destroy()
      confirmRewardWindow=nil
      dailyRewardWindow:show()
      g_client.setInputLockWidget(dailyRewardWindow)
    end

    local items = {}
    local totalOz = 0
    if selectRewardWindow then
      local childrens = selectRewardWindow.itemPanel:getChildren()
      for i, child in pairs(childrens) do
        if child and child.item and tonumber(child.countEdit:getText()) and tonumber(child.countEdit:getText()) > 0 then
          local count = tonumber(child.countEdit:getText())
          items[child.item:getItemId()] = count
          totalOz = totalOz + (count * child.ozNumber)
        end
      end
    end

    if (totalOz/ 100) > freecap() then
      return
    end
    g_game.requestGetRewardDaily(not gameFromShrine and 1 or 0, items)
  end

  local noCallback = function()
    if selectRewardWindow then
      selectRewardWindow:show(true)
      g_client.setInputLockWidget(selectRewardWindow)
    end
    confirmRewardWindow:destroy()
    confirmRewardWindow=nil
    dailyRewardWindow:show()
    g_client.setInputLockWidget(dailyRewardWindow)
  end

  if string.empty(globalMessage) then
    globalMessage = "Are you sure you want to claim this reward?"
  end

  confirmRewardWindow = displayGeneralBox(tr('Warning'), tr(globalMessage), {
      { text=tr('Yes'), callback=yesCallback },
      { text=tr('No'), callback=noCallback },
    }, yesCallback, noCallback)


  g_keyboard.bindKeyPress("Y", yesCallback, confirmRewardWindow)
  g_keyboard.bindKeyPress("N", noCallback, confirmRewardWindow)
end

function onTextChange(widget)
  local text = widget:getText()
  if not tonumber(text) then
    widget:setText('0')
    return false
  end

  return true
end

function onResourceBalance(value, oldBalance, type)
  local player = g_game.getLocalPlayer()
  if not player then
    return
  end
  player:setResourceBalance(type, value)
  if type == ResourceReward then
    instantTokens = value
    dailyRewardWindow.instantAcess.instantLabel:setText(value)
  elseif type == ResourceJokerReward then
    jokerTokens = value
    dailyRewardWindow.jokers.jokersLabel:setText(math.min(3, value))
  end
end

function closeHistory()
  closeDaily()
end
function backHistory()
  closeDaily()
  dailyRewardWindow:show(true)
  g_client.setInputLockWidget(dailyRewardWindow)
end

function onDailyRewardHistory(dailyRewardHistories)
  dailyRewardHistory = g_ui.displayUI('history')
  dailyRewardHistory:focus()
  g_client.setInputLockWidget(dailyRewardHistory)

  dailyRewardHistory.instantAcess.instantLabel:setText(instantTokens)
  dailyRewardHistory.jokers.jokersLabel:setText(jokerTokens)
  for i, info in pairs(dailyRewardHistories) do
    local widget = g_ui.createWidget('HistoryDescription', dailyRewardHistory.historyPanel.historyListPanel)
    widget.date:setText(os.date("%Y.%m.%d, %X", info[1]))
    widget.streak:setText(info[4])
    widget.description:setText(info[3])
    widget:setBackgroundColor(i % 2 == 0 and "#414141" or "#484848")
  end
end