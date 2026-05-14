local AI_COPILOT_OPCODE = ExtendedIds.ElderaCopilot
local MAX_INPUT_LENGTH = 240
local DEFAULT_DUMMY_TEXT = 'dummy ping'
local REQUEST_TYPE = 'chat'
local TOGGLE_SHORTCUT = 'Ctrl+J'
local MAX_RENDERED_CARDS = 3
local ROUTE_PANEL_HEIGHT = 24

local copilotWindow = nil
local copilotButton = nil
local requestSequence = 0
local routeOverlay = {}

local activeRouteMarkers = {}
local activeRouteWidgets = {}
local activeRoute = nil

local ROUTE_START_ICON = 18
local ROUTE_STEP_ICON = 14
local ROUTE_DESTINATION_ICON = 9
local ROUTE_START_COLOR = '#30d158ee'
local ROUTE_STEP_COLOR = '#ffd60aee'
local ROUTE_DESTINATION_COLOR = '#ff453aee'
local ROUTE_MARKER_BORDER_COLOR = '#111111ff'
local ROUTE_MARKER_SIZE = '17 17'

local function getMinimapWidget()
    if modules.game_minimap and modules.game_minimap.getMiniMapUi then
        return modules.game_minimap.getMiniMapUi()
    end
    return nil
end

local function buildRoutePosition(point)
    if type(point) ~= 'table' then
        return nil
    end

    local positionX = tonumber(point.x)
    local positionY = tonumber(point.y)
    local positionZ = tonumber(point.z)
    if not positionX or not positionY or not positionZ then
        return nil
    end

    return {
        x = positionX,
        y = positionY,
        z = positionZ
    }
end

local function getRouteWaypoints(route)
    if type(route) ~= 'table' then
        return {}
    end

    if type(route.waypoints) == 'table' and #route.waypoints > 0 then
        return route.waypoints
    end

    if type(route.destination) == 'table' then
        return { route.destination }
    end

    return {}
end

local function getRouteMarkerIcon(index, waypointCount, waypoint)
    if type(waypoint) == 'table' and waypoint.icon then
        return waypoint.icon
    end
    if index == 1 then
        return ROUTE_START_ICON
    end
    if index == waypointCount then
        return ROUTE_DESTINATION_ICON
    end
    return ROUTE_STEP_ICON
end

local function getRouteMarkerColor(index, waypointCount)
    if index == 1 then
        return ROUTE_START_COLOR
    end
    if index == waypointCount then
        return ROUTE_DESTINATION_COLOR
    end
    return ROUTE_STEP_COLOR
end

local function buildRouteDescription(route, waypoint, index, waypointCount)
    local routeTitle = route.title or route.id or 'Copilot route'
    local waypointLabel = waypoint.label or waypoint.title or 'Waypoint'
    return string.format('Eldera Copilot: %s (%d/%d) - %s', routeTitle, index, waypointCount, waypointLabel)
end

local function destroyRouteWidgets()
    for _, widget in ipairs(activeRouteWidgets) do
        if widget and not widget:isDestroyed() then
            widget:destroy()
        end
    end
    activeRouteWidgets = {}
end

local function findRouteFocusPosition(minimapWidget, waypoints)
    local cameraPosition = minimapWidget:getCameraPosition()
    if cameraPosition then
        for _, waypoint in ipairs(waypoints) do
            local position = buildRoutePosition(waypoint)
            if position and position.z == cameraPosition.z then
                return position
            end
        end
    end

    for _, waypoint in ipairs(waypoints) do
        local position = buildRoutePosition(waypoint)
        if position then
            return position
        end
    end

    return nil
end

local function createVisibleRouteMarker(minimapWidget, position, description, color)
    local marker = g_ui.createWidget('UIWidget', minimapWidget)
    marker:setSize(ROUTE_MARKER_SIZE)
    marker:setBackgroundColor(color)
    marker:setBorderWidth(2)
    marker:setBorderColor(ROUTE_MARKER_BORDER_COLOR)
    marker:setOpacity(0.95)
    marker:setPhantom(true)
    marker:setTooltip(description)
    minimapWidget:centerInPosition(marker, position)
    marker:raise()
    table.insert(activeRouteWidgets, marker)
end

local function addVisibleRouteMarkers(minimapWidget, route, waypoints)
    destroyRouteWidgets()

    local cameraPosition = minimapWidget:getCameraPosition()
    if not cameraPosition then
        return 0
    end

    local visibleCount = 0
    for index, waypoint in ipairs(waypoints) do
        local position = buildRoutePosition(waypoint)
        if position and position.z == cameraPosition.z then
            local description = buildRouteDescription(route, waypoint, index, #waypoints)
            createVisibleRouteMarker(minimapWidget, position, description, getRouteMarkerColor(index, #waypoints))
            visibleCount = visibleCount + 1
        end
    end

    return visibleCount
end

function routeOverlay.clear()
    local minimapWidget = getMinimapWidget()
    if minimapWidget then
        for _, marker in ipairs(activeRouteMarkers) do
            minimapWidget:removeFlag(marker.position, marker.icon, marker.description)
        end
    end

    destroyRouteWidgets()
    activeRouteMarkers = {}
    activeRoute = nil
end

function routeOverlay.show(route)
    routeOverlay.clear()

    local minimapWidget = getMinimapWidget()
    if not minimapWidget then
        return false, 'Minimap is not ready yet.', 0
    end

    local waypoints = getRouteWaypoints(route)
    if #waypoints == 0 then
        return false, 'This route has no waypoints yet.', 0
    end

    local focusPosition = findRouteFocusPosition(minimapWidget, waypoints)
    if focusPosition then
        minimapWidget:setCameraPosition(focusPosition)
    end

    for index, waypoint in ipairs(waypoints) do
        local position = buildRoutePosition(waypoint)
        if position then
            local existingFlag = minimapWidget:getFlag(position)
            if not existingFlag then
                local icon = getRouteMarkerIcon(index, #waypoints, waypoint)
                local description = buildRouteDescription(route, waypoint, index, #waypoints)
                minimapWidget:addFlag(position, icon, description, true)
                table.insert(activeRouteMarkers, {
                    position = position,
                    icon = icon,
                    description = description
                })
            end
        end
    end

    local visibleMarkerCount = addVisibleRouteMarkers(minimapWidget, route, waypoints)
    scheduleEvent(function()
        if activeRoute == route then
            addVisibleRouteMarkers(minimapWidget, route, waypoints)
        end
    end, 50)

    if #activeRouteMarkers == 0 and visibleMarkerCount == 0 then
        return false, 'The route was found, but no waypoint is visible on the current minimap floor.', 0
    end

    activeRoute = route
    return true, nil, math.max(visibleMarkerCount, #activeRouteMarkers)
end

function routeOverlay.hasActiveRoute()
    return activeRoute ~= nil and (#activeRouteMarkers > 0 or #activeRouteWidgets > 0)
end

function routeOverlay.getActiveTitle()
    if not activeRoute then
        return nil
    end
    return activeRoute.title or activeRoute.id or 'Copilot route'
end

function routeOverlay.getMarkerCount()
    return math.max(#activeRouteWidgets, #activeRouteMarkers)
end

local function getInputWidget()
    return copilotWindow and copilotWindow:recursiveGetChildById('inputText')
end

local function getSendButton()
    return copilotWindow and copilotWindow:recursiveGetChildById('sendButton')
end

local function getHistoryPanel()
    return copilotWindow and copilotWindow:recursiveGetChildById('historyPanel')
end

local function getRoutePanel()
    return copilotWindow and copilotWindow:recursiveGetChildById('routePanel')
end

local function getRouteText()
    return copilotWindow and copilotWindow:recursiveGetChildById('routeText')
end

local function getClearRouteButton()
    return copilotWindow and copilotWindow:recursiveGetChildById('clearRouteButton')
end

local function grabInputKeyboard()
    local inputWidget = getInputWidget()
    if inputWidget then
        inputWidget:grabKeyboard()
    end
end

local function releaseInputKeyboard()
    local inputWidget = getInputWidget()
    if inputWidget then
        inputWidget:ungrabKeyboard()
    end
end

local function hideMiniWindowScrollBar()
    local miniWindowScrollBar = copilotWindow and copilotWindow:recursiveGetChildById('miniwindowScrollBar')
    if miniWindowScrollBar then
        miniWindowScrollBar:hide()
        miniWindowScrollBar:setWidth(0)
    end
end

local function addMessage(source, text, color)
    local historyPanel = getHistoryPanel()
    if not historyPanel then
        return
    end

    local messageLabel = g_ui.createWidget('CopilotMessageLabel', historyPanel)
    messageLabel:setText(string.format('%s: %s', source, text))
    if color then
        messageLabel:setColor(color)
    end
    historyPanel:ensureChildVisible(messageLabel)
end

local function estimateLabelHeight(text, charsPerLine, lineHeight, maxLines)
    text = tostring(text or '')
    if text == '' then
        return 0
    end

    local lines = math.ceil(#text / charsPerLine)
    lines = math.max(1, lines)
    if maxLines then
        lines = math.min(lines, maxLines)
    end
    return lines * lineHeight
end

local function isArray(value)
    if type(value) ~= 'table' then
        return false
    end

    local count = 0
    for key, _ in pairs(value) do
        if type(key) ~= 'number' then
            return false
        end
        count = math.max(count, key)
    end

    return count > 0
end

local function joinList(values, maxItems)
    if not isArray(values) then
        return nil
    end

    local parts = {}
    for index, value in ipairs(values) do
        if index > maxItems then
            break
        end
        if value and tostring(value) ~= '' then
            table.insert(parts, tostring(value))
        end
    end

    if #parts == 0 then
        return nil
    end

    return table.concat(parts, ' | ')
end

local function formatCardKind(kind)
    if kind == 'recommendation' then
        return 'Recommendation'
    elseif kind == 'hunt' then
        return 'Hunt'
    elseif kind == 'npc' then
        return 'NPC'
    elseif kind == 'location' then
        return 'Location'
    elseif kind == 'route' then
        return 'Route info'
    end

    return 'Info'
end

local function setLabelText(label, text, height, color)
    if not label then
        return 0
    end

    if not text or text == '' then
        label:hide()
        label:setHeight(0)
        return 0
    end

    label:setText(text)
    label:setHeight(height)
    if color then
        label:setColor(color)
    end
    label:show()
    return height
end

local function addCard(card)
    local historyPanel = getHistoryPanel()
    if not historyPanel or type(card) ~= 'table' then
        return
    end

    local cardPanel = g_ui.createWidget('CopilotCardPanel', historyPanel)
    local titleLabel = cardPanel:recursiveGetChildById('cardTitle')
    local summaryLabel = cardPanel:recursiveGetChildById('cardSummary')
    local reasonsLabel = cardPanel:recursiveGetChildById('cardReasons')
    local cautionsLabel = cardPanel:recursiveGetChildById('cardCautions')
    local metaLabel = cardPanel:recursiveGetChildById('cardMeta')

    local title = string.format('%s: %s', formatCardKind(card.type), card.title or card.id or 'Untitled')
    local summary = card.summary or ''
    local reasons = joinList(card.reasons, 2)
    local cautions = joinList(card.cautions, 2)
    local related = joinList(card.related, 3)
    local meta = related and ('Related: ' .. related) or (card.id and ('Source: ' .. card.id) or nil)

    local height = 12
    height = height + setLabelText(titleLabel, title, 14, '#f0df9fff')
    height = height + setLabelText(summaryLabel, summary, estimateLabelHeight(summary, 38, 13, 4), '#d7d7d7ff')
    height = height + setLabelText(reasonsLabel, reasons and ('Why: ' .. reasons) or nil, estimateLabelHeight(reasons, 38, 13, 3), '#9ee493ff')
    height = height + setLabelText(cautionsLabel, cautions and ('Careful: ' .. cautions) or nil, estimateLabelHeight(cautions, 38, 13, 3), '#ffb86cff')
    height = height + setLabelText(metaLabel, meta, estimateLabelHeight(meta, 42, 12, 2), '#8ab4f8ff')

    cardPanel:setHeight(math.max(54, height))
    historyPanel:ensureChildVisible(cardPanel)
end

local function addCards(cards)
    if not isArray(cards) then
        return
    end

    if #cards > MAX_RENDERED_CARDS then
        addMessage('Cards', string.format('%d more available in the response.', #cards - MAX_RENDERED_CARDS), '#8ab4f8')
    end

    local rendered = 0
    for _, card in ipairs(cards) do
        if type(card) == 'table' then
            addCard(card)
            rendered = rendered + 1
            if rendered >= MAX_RENDERED_CARDS then
                break
            end
        end
    end
end

local function getClientPosition()
    local localPlayer = g_game.getLocalPlayer()
    if not localPlayer then
        return nil
    end

    local position = localPlayer:getPosition()
    if not position then
        return nil
    end

    return {
        x = position.x,
        y = position.y,
        z = position.z
    }
end

local function updateRoutePanel()
    local routePanel = getRoutePanel()
    if not routePanel then
        return
    end

    if routeOverlay and routeOverlay.hasActiveRoute and routeOverlay.hasActiveRoute() then
        local routeTitle = routeOverlay.getActiveTitle and routeOverlay.getActiveTitle() or 'Copilot route'
        local markerCount = routeOverlay.getMarkerCount and routeOverlay.getMarkerCount() or 0
        local routeText = getRouteText()
        if routeText then
            routeText:setText(string.format('Route preview: %s (%d)', routeTitle, markerCount))
        end
        routePanel:setHeight(ROUTE_PANEL_HEIGHT)
        routePanel:show()
        return
    end

    routePanel:setHeight(0)
    routePanel:hide()
end

local function clearRoutePreview(showFeedback)
    if routeOverlay and routeOverlay.clear then
        routeOverlay.clear()
    end
    updateRoutePanel()
    if showFeedback then
        addMessage('Route', 'Route preview cleared.', '#8ab4f8')
    end
end

local function applyRoutePreview(route)
    if type(route) ~= 'table' then
        return
    end

    if not route.previewOnly then
        addMessage('Route', 'Copilot ignored a non-preview route response.', '#ffb86c')
        return
    end

    if not routeOverlay or not routeOverlay.show then
        addMessage('Route', 'Route overlay module is not ready.', '#ffb86c')
        return
    end

    local ok, errorMessage, markerCount = routeOverlay.show(route)
    updateRoutePanel()
    if ok then
        addMessage('Route', string.format('Previewing %d minimap waypoints. This will not move your character.', markerCount), '#8ab4f8')
    else
        addMessage('Route', errorMessage or 'Route preview is unavailable.', '#ffb86c')
    end
end

local function createWindow()
    if copilotWindow then
        return
    end

    copilotWindow = g_ui.loadUI('ai_copilot', modules.game_interface.getLeftPanel())
    copilotWindow:setup()
    hideMiniWindowScrollBar()
    copilotWindow:hide()

    local inputWidget = getInputWidget()
    if inputWidget then
        inputWidget.onFocusChange = function(widget, focused)
            if focused then
                widget:grabKeyboard()
            else
                widget:ungrabKeyboard()
            end
        end

        inputWidget.onMousePress = function(widget)
            widget:grabKeyboard()
            return false
        end

        inputWidget.onKeyDown = function(widget, keyCode)
            if keyCode == KeyReturn or keyCode == KeyEnter then
                sendDummy()
                return true
            end
            return false
        end
    end

    local sendButton = getSendButton()
    if sendButton then
        sendButton.onClick = function()
            sendDummy()
        end
    end

    local clearRouteButton = getClearRouteButton()
    if clearRouteButton then
        clearRouteButton.onClick = function()
            clearRoutePreview(true)
        end
    end

    updateRoutePanel()

    addMessage('System', 'Phase 4 route preview ready. Ask for a route to validate read-only minimap markers.', '#8ab4f8')
end

local function destroyWindow()
    clearRoutePreview(false)
    releaseInputKeyboard()
    if copilotWindow then
        copilotWindow:destroy()
        copilotWindow = nil
    end
end

local function setButtonState(enabled)
    if copilotButton then
        copilotButton:setOn(enabled)
    end
end

local function formatContext(context)
    if not context or not context.player then
        return nil
    end

    local player = context.player
    local position = player.position or {}
    return string.format(
        '%s level %s %s at %s,%s,%s - HP %s%%, Mana %s%%',
        player.name or 'unknown',
        player.level or '?',
        player.vocation or 'vocation',
        position.x or '?',
        position.y or '?',
        position.z or '?',
        player.healthPercent or '?',
        player.manaPercent or '?'
    )
end

function init()
    connect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })

    ProtocolGame.registerExtendedJSONOpcode(AI_COPILOT_OPCODE, onExtendedOpcode)
    copilotButton = modules.game_mainpanel.addToggleButton(
        'elderaCopilotButton',
        tr('Eldera Copilot') .. ' (' .. TOGGLE_SHORTCUT .. ')',
        '/images/options/analyzers',
        toggle,
        false,
        6
    )
    copilotButton:setOn(false)

    g_keyboard.bindKeyDown(TOGGLE_SHORTCUT, toggle)

    createWindow()
end

function terminate()
    disconnect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })

    ProtocolGame.unregisterExtendedJSONOpcode(AI_COPILOT_OPCODE)

    if copilotButton then
        copilotButton:destroy()
        copilotButton = nil
    end

    g_keyboard.unbindKeyDown(TOGGLE_SHORTCUT)

    destroyWindow()
end

function onGameStart()
    createWindow()
    if copilotWindow then
        copilotWindow:setupOnStart()
    end
end

function onGameEnd()
    clearRoutePreview(false)
    releaseInputKeyboard()
    if copilotWindow then
        copilotWindow:hide()
    end
    setButtonState(false)
end

function toggle()
    createWindow()
    if not copilotWindow then
        return
    end

    if copilotWindow:isVisible() then
        hide()
        return
    end

    show()
end

function show()
    createWindow()
    if not copilotWindow then
        return
    end

    if not copilotWindow:getParent() then
        local panel = modules.game_interface.findContentPanelAvailable(copilotWindow, copilotWindow:getMinimumHeight())
        if panel then
            panel:addChild(copilotWindow)
        end
    end

    copilotWindow:open()
    hideMiniWindowScrollBar()
    copilotWindow:focus()
    setButtonState(true)

    local inputWidget = getInputWidget()
    if inputWidget then
        inputWidget:focus()
        grabInputKeyboard()
    end
end

function hide()
    clearRoutePreview(false)
    releaseInputKeyboard()
    if copilotWindow then
        copilotWindow:close()
    end
    setButtonState(false)
end

function onOpen()
    setButtonState(true)
end

function sendDummy()
    createWindow()

    if not g_game.isOnline() then
        addMessage('System', 'You need to be online before sending a Copilot ping.', '#ffb86c')
        return
    end

    local protocolGame = g_game.getProtocolGame()
    if not protocolGame then
        addMessage('System', 'Game protocol is not ready yet.', '#ffb86c')
        return
    end

    local inputWidget = getInputWidget()
    local text = inputWidget and inputWidget:getText():trim() or ''
    if text == '' then
        text = DEFAULT_DUMMY_TEXT
    end
    if #text > MAX_INPUT_LENGTH then
        text = text:sub(1, MAX_INPUT_LENGTH)
    end

    requestSequence = requestSequence + 1
    local requestId = string.format('copilot-%d-%d', g_clock.millis(), requestSequence)
    local requestPayload = {
        v = 1,
        requestId = requestId,
        type = REQUEST_TYPE,
        text = text,
        clientState = {
            uiContext = 'game_ai_copilot',
            position = getClientPosition()
        }
    }

    protocolGame:sendExtendedJSONOpcode(AI_COPILOT_OPCODE, requestPayload)
    addMessage('You', text, '#dfdfdfff')

    if inputWidget then
        inputWidget:setText('')
        inputWidget:focus()
        grabInputKeyboard()
    end
end

function onExtendedOpcode(protocol, opcode, data)
    createWindow()

    data = data or {}

    if data.type == 'error' or data.error then
        addMessage('Canary', data.error or 'Copilot request failed.', '#ff8f8f')
        return
    end

    local message = data.message or 'Dummy response received from Canary.'
    addMessage('Canary', message, '#9ee493')

    if data.echo and data.echo ~= '' then
        addMessage('Echo', data.echo, '#c0c0c0ff')
    end

    local contextText = formatContext(data.context)
    if contextText then
        addMessage('Context', contextText, '#8ab4f8')
    end

    applyRoutePreview(data.route)
    addCards(data.cards)
end