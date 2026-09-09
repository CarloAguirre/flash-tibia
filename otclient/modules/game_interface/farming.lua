local FARMING_OPCODE = 217
local PICK_ITEM_ID = 3456
local BUILD_MAX_RANGE = 7

local materialsWindow = nil
local woodValueLabel = nil
local stoneValueLabel = nil
local statusLabel = nil
local buildSelectionLabel = nil
local buildQueueLabel = nil
local confirmBuildButton = nil
local cancelBuildButton = nil
local rewardResetEvent = nil

local walletValues = { wood = 0, stone = 0 }
local buildCatalog = { wood = {}, stone = {} }
local buildButtons = {}
local buildMode = nil
local buildQueue = {}
local buildQueueOrder = {}
local buildPending = false
local buildCursorActive = false
local mapPanel = nil
local previousMapMouseRelease = nil
local mapHandlerInstalled = false

local structureNames = {
    wall = 'Wall',
    door = 'Door',
    window = 'Window'
}

local function splitPayload(buffer)
    local parts = {}
    for value in tostring(buffer or ''):gmatch('([^|]+)') do
        parts[#parts + 1] = value
    end
    return parts
end

local function buildPositionKey(position)
    return string.format('%d:%d:%d', position.x, position.y, position.z)
end

local function setStatus(text, color)
    if not statusLabel then
        return
    end

    statusLabel:setText(text or '')
    if color then
        statusLabel:setColor(color)
    end
end

local function getStructureLabel(material, structureType)
    local materialName = material == 'wood' and tr('Wood') or tr('Stone')
    local structureName = tr(structureNames[structureType] or structureType)
    return string.format('%s %s', materialName, structureName)
end

local function queueCount()
    local count = 0
    for _, key in ipairs(buildQueueOrder) do
        if buildQueue[key] then
            count = count + 1
        end
    end
    return count
end

local function queuedCost()
    if not buildMode then
        return 0
    end
    local config = buildCatalog[buildMode.material] and buildCatalog[buildMode.material][buildMode.structureType]
    return config and (config.cost * queueCount()) or 0
end

local function updateBuildUi()
    local count = queueCount()
    local cost = queuedCost()

    if buildSelectionLabel then
        if buildMode then
            local config = buildCatalog[buildMode.material] and buildCatalog[buildMode.material][buildMode.structureType]
            local unitCost = config and config.cost or 0
            buildSelectionLabel:setText(string.format('%s  (%d)', getStructureLabel(buildMode.material, buildMode.structureType), unitCost))
        else
            buildSelectionLabel:setText(tr('Select a structure'))
        end
    end

    if buildQueueLabel then
        if count > 0 and buildMode then
            local available = walletValues[buildMode.material] or 0
            buildQueueLabel:setText(string.format('%d tile%s | %d / %d', count, count == 1 and '' or 's', cost, available))
            buildQueueLabel:setColor(cost <= available and '#7ee787ff' or '#ff7b72ff')
        else
            buildQueueLabel:setText(tr('Click map squares to plan'))
            buildQueueLabel:setColor('#9d9d9dff')
        end
    end

    if confirmBuildButton then
        local enough = buildMode and cost > 0 and cost <= (walletValues[buildMode.material] or 0)
        confirmBuildButton:setEnabled(not buildPending and enough)
    end
    if cancelBuildButton then
        cancelBuildButton:setEnabled(buildMode ~= nil or count > 0)
    end
end

local function setBuildButtonSelected(selectedWidget)
    for _, widget in pairs(buildButtons) do
        if widget then
            widget:setBorderWidth(widget == selectedWidget and 2 or 1)
            widget:setBorderColor(widget == selectedWidget and '#7ee787ff' or '#5a5a5aff')
        end
    end
end

local function removePreview(entry)
    if entry and entry.preview then
        g_map.removeThing(entry.preview)
        entry.preview = nil
    end
end

local function clearBuildQueue()
    for _, entry in pairs(buildQueue) do
        removePreview(entry)
    end
    buildQueue = {}
    buildQueueOrder = {}
    updateBuildUi()
end

local function enableBuildCursor()
    if buildCursorActive then
        return
    end
    if modules.client_options and modules.client_options.getOption('nativeCursor') then
        g_window.setSystemCursor('cross')
    else
        g_mouse.pushCursor('target')
    end
    buildCursorActive = true
end

local function disableBuildCursor()
    if not buildCursorActive then
        return
    end
    if modules.client_options and modules.client_options.getOption('nativeCursor') then
        g_window.restoreMouseCursor()
    else
        g_mouse.popCursor('target')
    end
    buildCursorActive = false
end

local function cancelBuildMode(silent)
    clearBuildQueue()
    buildMode = nil
    buildPending = false
    disableBuildCursor()
    setBuildButtonSelected(nil)
    updateBuildUi()
    if not silent then
        setStatus(tr('Ready'), '#9d9d9dff')
    end
end

local function addBuildPreview(position)
    if not buildMode then
        return false
    end

    local config = buildCatalog[buildMode.material] and buildCatalog[buildMode.material][buildMode.structureType]
    if not config or not config.itemId then
        setStatus(tr('Construction catalogue is not ready yet.'), '#ff7b72ff')
        return false
    end

    local preview = Item.create(config.itemId)
    if not preview then
        setStatus(tr('Could not create construction preview.'), '#ff7b72ff')
        return false
    end

    -- Client-only ghost: it is never sent to Canary and therefore has no server
    -- collision or persistence. The green translucent mark distinguishes it from
    -- a confirmed structure.
    preview:setMarked('#69db7c99')
    g_map.addThing(preview, position, -1)

    local key = buildPositionKey(position)
    buildQueue[key] = {
        position = { x = position.x, y = position.y, z = position.z },
        preview = preview
    }
    buildQueueOrder[#buildQueueOrder + 1] = key
    return true
end

local function toggleBuildPosition(position)
    if not buildMode or buildPending then
        return
    end

    local player = g_game.getLocalPlayer()
    if not player then
        return
    end

    local playerPos = player:getPosition()
    if playerPos.z ~= position.z or math.max(math.abs(playerPos.x - position.x), math.abs(playerPos.y - position.y)) > BUILD_MAX_RANGE then
        setStatus(tr('Build within 7 squares of your character.'), '#ffb86cff')
        return
    end

    local key = buildPositionKey(position)
    local existing = buildQueue[key]
    if existing then
        removePreview(existing)
        buildQueue[key] = nil
        updateBuildUi()
        return
    end

    if queueCount() >= 40 then
        setStatus(tr('Maximum 40 squares per build batch.'), '#ffb86cff')
        return
    end

    if addBuildPreview(position) then
        setStatus(tr('Planning construction...'), '#7ee787ff')
    end
    updateBuildUi()
end

local function onBuildMapMouseRelease(self, mousePosition, mouseButton)
    if buildMode and mouseButton == MouseLeftButton then
        local position = self:getPosition(mousePosition)
        if position then
            toggleBuildPosition(position)
        end
        return true
    end

    if previousMapMouseRelease then
        return previousMapMouseRelease(self, mousePosition, mouseButton)
    end
    return false
end

local function installMapHandler()
    if mapHandlerInstalled then
        return
    end
    mapPanel = modules.game_interface.getMapPanel()
    if not mapPanel then
        return
    end
    previousMapMouseRelease = mapPanel.onMouseRelease
    mapPanel.onMouseRelease = onBuildMapMouseRelease
    mapHandlerInstalled = true
end

local function restoreMapHandler()
    if mapHandlerInstalled and mapPanel then
        mapPanel.onMouseRelease = previousMapMouseRelease
    end
    previousMapMouseRelease = nil
    mapPanel = nil
    mapHandlerInstalled = false
end

local function selectBuildMode(material, structureType, widget)
    local config = buildCatalog[material] and buildCatalog[material][structureType]
    if not config then
        setStatus(tr('Construction catalogue is still loading.'), '#ffb86cff')
        return
    end

    if buildMode and (buildMode.material ~= material or buildMode.structureType ~= structureType) then
        clearBuildQueue()
    end

    buildMode = { material = material, structureType = structureType }
    buildPending = false
    setBuildButtonSelected(widget)
    enableBuildCursor()
    setStatus(string.format('%s: %s', tr('Build mode'), getStructureLabel(material, structureType)), '#7ee787ff')
    updateBuildUi()
end

local function confirmBuild()
    if not buildMode or buildPending then
        return
    end

    local positions = {}
    for _, key in ipairs(buildQueueOrder) do
        local entry = buildQueue[key]
        if entry then
            positions[#positions + 1] = string.format('%d,%d,%d', entry.position.x, entry.position.y, entry.position.z)
        end
    end

    if #positions == 0 then
        return
    end

    local protocol = g_game.getProtocolGame()
    if not protocol then
        return
    end

    buildPending = true
    updateBuildUi()
    setStatus(tr('Confirming construction...'), '#f0df9fff')
    protocol:sendExtendedOpcode(
        FARMING_OPCODE,
        string.format('build|confirm|%s|%s|%s', buildMode.material, buildMode.structureType, table.concat(positions, ';'))
    )
end

local function configureBuildButton(id, material, structureType)
    if not materialsWindow then
        return
    end
    local widget = materialsWindow:recursiveGetChildById(id)
    if not widget then
        return
    end
    buildButtons[material .. ':' .. structureType] = widget
    widget:setVirtual(true)
    widget:setBorderWidth(1)
    widget:setBorderColor('#5a5a5aff')
    widget.onClick = function()
        selectBuildMode(material, structureType, widget)
        return true
    end
end

local function refreshCatalogUi(material)
    local structures = buildCatalog[material]
    if not structures then
        return
    end
    for structureType, config in pairs(structures) do
        local widget = buildButtons[material .. ':' .. structureType]
        if widget and config.itemId then
            widget:setItemId(config.itemId)
            widget:setTooltip(string.format('%s\nCost: %d %s', getStructureLabel(material, structureType), config.cost, material == 'wood' and tr('Wood') or tr('Stone')))
        end
    end
    updateBuildUi()
end

local function createWindow()
    if materialsWindow then
        return
    end

    materialsWindow = g_ui.loadUI('farming', modules.game_interface.getRightPanel())
    if not materialsWindow then
        return
    end

    materialsWindow:setup()
    woodValueLabel = materialsWindow:recursiveGetChildById('woodValue')
    stoneValueLabel = materialsWindow:recursiveGetChildById('stoneValue')
    statusLabel = materialsWindow:recursiveGetChildById('farmingStatus')
    buildSelectionLabel = materialsWindow:recursiveGetChildById('buildSelection')
    buildQueueLabel = materialsWindow:recursiveGetChildById('buildQueue')
    confirmBuildButton = materialsWindow:recursiveGetChildById('confirmBuild')
    cancelBuildButton = materialsWindow:recursiveGetChildById('cancelBuild')

    configureBuildButton('woodWall', 'wood', 'wall')
    configureBuildButton('woodDoor', 'wood', 'door')
    configureBuildButton('woodWindow', 'wood', 'window')
    configureBuildButton('stoneWall', 'stone', 'wall')
    configureBuildButton('stoneDoor', 'stone', 'door')
    configureBuildButton('stoneWindow', 'stone', 'window')

    if confirmBuildButton then
        confirmBuildButton.onClick = confirmBuild
    end
    if cancelBuildButton then
        cancelBuildButton.onClick = function()
            cancelBuildMode(false)
        end
    end

    refreshCatalogUi('wood')
    refreshCatalogUi('stone')
    setStatus(tr('Ready'), '#9d9d9dff')
    updateBuildUi()
end

local function destroyWindow()
    if rewardResetEvent then
        removeEvent(rewardResetEvent)
        rewardResetEvent = nil
    end

    cancelBuildMode(true)

    if materialsWindow then
        materialsWindow:destroy()
        materialsWindow = nil
    end

    woodValueLabel = nil
    stoneValueLabel = nil
    statusLabel = nil
    buildSelectionLabel = nil
    buildQueueLabel = nil
    confirmBuildButton = nil
    cancelBuildButton = nil
    buildButtons = {}
end

local function syncWallet()
    if not g_game.isOnline() then
        return
    end

    local protocol = g_game.getProtocolGame()
    if protocol then
        protocol:sendExtendedOpcode(FARMING_OPCODE, 'sync')
    end
end

local function armFarming(menuPosition, lookThing, useThing, creatureThing)
    if not useThing or useThing:getId() ~= PICK_ITEM_ID then
        return
    end

    cancelBuildMode(true)

    local protocol = g_game.getProtocolGame()
    if not protocol then
        return
    end

    protocol:sendExtendedOpcode(FARMING_OPCODE, 'arm')
    setStatus(tr('Select a resource...'), '#f0df9fff')
    modules.game_interface.startUseWith(useThing)
end

local function canFarm(menuPosition, lookThing, useThing, creatureThing)
    return g_game.isOnline() and useThing and useThing:isItem() and useThing:getId() == PICK_ITEM_ID
end

local function handleWallet(parts)
    local values = {}
    local index = 2
    while index + 1 <= #parts do
        values[parts[index]] = tonumber(parts[index + 1]) or 0
        index = index + 2
    end

    walletValues.wood = values.wood or 0
    walletValues.stone = values.stone or 0
    if woodValueLabel then
        woodValueLabel:setText(tostring(walletValues.wood))
    end
    if stoneValueLabel then
        stoneValueLabel:setText(tostring(walletValues.stone))
    end
    updateBuildUi()
end

local function handleCatalog(parts)
    local material = parts[2]
    if not buildCatalog[material] then
        return
    end
    local index = 3
    while index + 2 <= #parts do
        local structureType = parts[index]
        local itemId = tonumber(parts[index + 1])
        local cost = tonumber(parts[index + 2])
        if structureType and itemId and cost then
            buildCatalog[material][structureType] = { itemId = itemId, cost = cost }
        end
        index = index + 3
    end
    refreshCatalogUi(material)
end

local function handleReward(parts)
    local material = parts[2] or 'material'
    local total = tonumber(parts[3]) or 0
    local materialName = material == 'wood' and tr('Wood') or (material == 'stone' and tr('Stone') or material)
    setStatus(string.format('+1 %s  (%d)', materialName, total), '#7ee787ff')

    if rewardResetEvent then
        removeEvent(rewardResetEvent)
    end
    rewardResetEvent = scheduleEvent(function()
        rewardResetEvent = nil
        if buildMode then
            setStatus(tr('Planning construction...'), '#7ee787ff')
        else
            setStatus(tr('Farming...'), '#9d9d9dff')
        end
    end, 900)
end

local function handleStatus(parts)
    local state = parts[2]
    if state == 'armed' then
        setStatus(tr('Select a resource...'), '#f0df9fff')
    elseif state == 'started' then
        local material = parts[3]
        local label = material == 'wood' and tr('Wood') or (material == 'stone' and tr('Stone') or tr('resource'))
        setStatus(string.format('%s: %s', tr('Farming'), label), '#9d9d9dff')
    elseif state == 'stopped' then
        local reason = parts[3] or ''
        if reason == 'depleted' then
            setStatus(tr('Resource depleted'), '#ffb86cff')
        elseif reason == 'too-far' then
            setStatus(tr('Too far from resource'), '#ffb86cff')
        elseif not buildMode then
            setStatus(tr('Ready'), '#9d9d9dff')
        end
    end
end

local function handleBuild(parts)
    local result = parts[2]
    if result == 'success' then
        local count = tonumber(parts[5]) or 0
        local cost = tonumber(parts[6]) or 0
        buildPending = false
        clearBuildQueue()
        setStatus(string.format('Built %d tile%s (-%d)', count, count == 1 and '' or 's', cost), '#7ee787ff')
        updateBuildUi()
    elseif result == 'error' then
        buildPending = false
        setStatus(parts[3] or tr('Construction failed.'), '#ff7b72ff')
        updateBuildUi()
    end
end

function onExtendedOpcode(protocol, opcode, buffer)
    createWindow()

    local parts = splitPayload(buffer)
    local messageType = parts[1]
    if messageType == 'wallet' then
        handleWallet(parts)
    elseif messageType == 'catalog' then
        handleCatalog(parts)
    elseif messageType == 'reward' then
        handleReward(parts)
    elseif messageType == 'status' then
        handleStatus(parts)
    elseif messageType == 'build' then
        handleBuild(parts)
    end
end

function onGameStart()
    createWindow()
    installMapHandler()
    if materialsWindow then
        materialsWindow:setupOnStart()
        materialsWindow:open()
    end
    scheduleEvent(syncWallet, 300)
end

function onGameEnd()
    cancelBuildMode(true)
    if materialsWindow then
        materialsWindow:hide()
    end
end

function init()
    connect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })

    ProtocolGame.registerExtendedOpcode(FARMING_OPCODE, onExtendedOpcode)
    modules.game_interface.addMenuHook('elderaFarming', tr('Farm'), armFarming, canFarm)

    createWindow()
    installMapHandler()
    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    modules.game_interface.removeMenuHook('elderaFarming', tr('Farm'))
    ProtocolGame.unregisterExtendedOpcode(FARMING_OPCODE)

    disconnect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })

    destroyWindow()
    restoreMapHandler()
end
