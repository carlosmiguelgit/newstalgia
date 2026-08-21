-- @docclass
UILabel = extends(UIWidget, 'UILabel')

function UILabel.create()
    local label = UILabel.internalCreate()
    label:setPhantom(true)
    label:setFocusable(false)
    label:setTextAlign(AlignLeft)
    return label
end

function UILabel:setValue(value)
    local scrollBar = self:recursiveGetChildById('valueBar')
    if scrollBar then
        scrollBar:setValue(value)
    end
end

function UILabel:setFormatedText(textVec)
    for i, child in pairs(self:getChildren()) do
        if string.find(child:getId(), "labelHtml_") then
            child:destroy()
        end
    end

    local width = self:getWidth()
    local sumWidth = 0
    local line = 1

    local results = string.parseHTML(textVec)
    local font = "Verdana Bold-11px"
    self:setTextAutoResize(true)

    for i = 1, #results do
        local result = results[i]
        local label = g_ui.createWidget("UILabel", self)
        label:setId('labelHtml_' .. i)
        label:setFont(font)
        local tabStyle = {}
        tabStyle["text-auto-resize"] = true

        if i == 1 then
            tabStyle['anchors.top'] = "parent.top"
            tabStyle['anchors.left'] = "parent.left"
        elseif sumWidth >= width or result[1] == "list" or result[1] == "break" then
            tabStyle['anchors.top'] = "prev.bottom"
            tabStyle['anchors.left'] = "parent.left"
            line = line + 1
            sumWidth = 0
        else
            tabStyle['anchors.top'] = 'labelHtml_' .. i - 1 ..".top"
            tabStyle['anchors.left'] = 'labelHtml_' .. i - 1 ..".right"
        end

        if result[1] == "" then
            label:setText(result[2])
        elseif result[1] == "color" then
            local t = {}
            setStringColor(t, result[2], result[3])
            label:setColoredText(t)
        elseif result[1] == "bold" then
            label:setFont("Verdana Bold-11px")
            label:setText(result[2])
        elseif result[1] == "list" then
            label:setFont("pVerdana Bold-11px")
            label:setText("* " .. result[2])
        end

        label:mergeStyle(tabStyle)
        sumWidth = sumWidth + label:getWidth()
    end
end