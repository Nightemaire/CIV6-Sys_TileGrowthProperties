-- Tile Property Growth System
-- Author: Nightemaire
-- DateCreated: 6/20/2022 17:57:45
--------------------------------------------------------------
-- #region System Details
-- This system implements an efficient way of tracking properties that accumulate on tiles
-- with the intent of triggering events when they reach a specific threshold
--
-- Instead of iterating over every tile every turn, the 'growth' of a tile is tracked along with a few
-- other properties, and this is used to calculate when tiles will trigger. Since the turn should be known explicitly if
-- we know how quickly the tile is accumulating, and the threshold we're shooting for, we can store that tile's ID in a
-- table and when we reach that turn, we can check to see if it has triggered. If the growth of a tile changes, then
-- we need to recalculate the trigger turn and update the table that stores when all plots are supposed to trigger.
--
-- The table that stores when turns trigger is called the "TurnTable", and is described below, but it is essentially
-- a hash table.
--
-- The growth of a tile and its threshold can be defined unique to each tile, if desired. Although in regards to growth,
-- care should be taken since the system will occasionally call the GrowthCalculation function when updating a plot. 
-- The remaining properties are updated automatically by the system itself.
-- 
-- #endregion

print("Loading tile growth system...")

Debug_Tile_Growth = false;

-- ===========================================================================
-- #region SYSTEM CORE
-- ===========================================================================

-- #region PROPERTY LIST
PropertyList = {};

-- DefaultThreshold, MinVal, and MaxVal are the default values when a plot is initialized
hstructure PropertyListData
    ID:                 string;
    DefaultThreshold:   number;
    GrowthCalcFunc:     ifunction;
    CallbackFunc:       ifunction;
    MinVal:             number;
    MaxVal:             number;
    TriggerMode:        string;
    TriggerTest:        ifunction;
    ShowLens:           boolean;
    ShowTooltip:        boolean;
end

function DefineGrowthProperty(NewPropertyArgs : PropertyListData)
    if NewPropertyArgs ~= nil then
        ID = NewPropertyArgs.ID
        print("DEFINING GROWTH PROPERTY: "..ID)
        growthCalcFunc = NewPropertyArgs.GrowthCalcFunc
        if growthCalcFunc == nil then
            NewPropertyArgs.GrowthCalcFunc = function()
                print(">> Growth function was nil, growth will always be zero")
                return 0;
            end
        end

        if PropertyList[ID] == nil then
            PropertyList[ID] = NewPropertyArgs
        else
            print(">> Tried to add a property that already exists!")
        end

        SetTurnTable(ID, {})
    else
        print("ERROR: Tried to create a new growth property but the args were nil")
    end
end
function GetGrowthCalcFunc(PropertyID)
    return PropertyList[PropertyID].GrowthCalcFunc
end
function GetCallbackFunc(PropertyID)
    return PropertyList[PropertyID].CallbackFunc
end
function ChangeCallback(PropertyID, newCallbackFunc)
    PropertyList[PropertyID].CallbackFunc = newCallbackFunc
end
function GetAllPropertyIDs(LensView : boolean, TooltipView : boolean)
    local list = {}
    for k,v in pairs(PropertyList) do
        if not(LensView or TooltipView) then
            table.insert(list, k)
        elseif (LensView and v.ShowLens) or (TooltipView and v.ShowTooltip) then table.insert(list, k);
        end
    end
    return list
end

-- #endregion

-- #region TURN TABLES
-- Each property has an associated turn table. Basically this is a hash table, the key for each element corresponds to a turn number. Each element
-- is itself an array of key/val pairs, where the key is the plotID, and the value is irrelevant. The existance of the key is sufficient to represent the plot.
-- When the growth value of a plot property changes, the turn where it surpasses its threshold can be calculated, and this is used to update the appropriate
-- entry in the turn table, and the previous turn is used to remove that entry.
-- Each turn the game checks to see if there are any entries of plots that are scheduled to trigger, and checks to make sure they're ready before triggering them,
-- or recalculating the correct turn.
function GetTurnTable(PropertyID : string) 
    return Game:GetProperty("GrowthTurnTable_"..PropertyID)
end
function SetTurnTable(PropertyID : string, TurnTable : table) 
    Game:SetProperty("GrowthTurnTable_"..PropertyID, TurnTable)
end
function UpdateTurnTable(PropertyID : string, plotID : number, newTurn, prevTurn : number)
    if PropertyID == nil or plotID == nil or prevTurn == nil then return; end

    local turnTable = GetTurnTable(PropertyID)
    
    if newTurn == nil then return; end

    if turnTable[prevTurn] ~= nil then
        turnTable[prevTurn][plotID] = nil
    end
    if turnTable[newTurn] == nil then turnTable[newTurn] = {}; end
    turnTable[newTurn][plotID] = true

    SetTurnTable(PropertyID, turnTable)
end

-- #endregion

-- #region PLOT PROPERTY DATA
function InitPlotPropertyData(PropertyID, pPlot)
    if pPlot ~= nil then
        local GrowthCalc = GetGrowthCalcFunc(PropertyID)
        local plotID = pPlot:GetIndex()
        DebugTileGrowth("Initializing plot: "..plotID)
        DebugTileGrowth(">> PlotID = "..plotID)

        local growth = GrowthCalc(plotID)
        DebugTileGrowth(">> Growth = "..growth)

        local CurrentTurn = Game.GetCurrentGameTurn()
        local Threshold = PropertyList[PropertyID].DefaultThreshold

        local TriggerTurn = EstimateTriggerTurn(growth, 0, Threshold, CurrentTurn)
        DebugTileGrowth(">> Trigger = "..TriggerTurn)

        DebugTileGrowth(">> Threshold = "..Threshold)

        WriteValue(PropertyID, pPlot, 0)
        WriteGrowth(PropertyID, pPlot, growth)
        WriteLastUpdate(PropertyID, pPlot, CurrentTurn)
        WriteThreshold(PropertyID, pPlot, Threshold)
        WriteTriggerTurn(PropertyID, pPlot, TriggerTurn)
        WriteTriggered(PropertyID, pPlot, false)
        WriteMaxVal(PropertyID, pPlot, PropertyList[PropertyID].MaxVal)
        WriteMinVal(PropertyID, pPlot, PropertyList[PropertyID].MinVal)

        LuaEvents.OnPlotPropertyInitialized(PropertyID, plotID)
    end
end
function PlotIsInitialized(PropertyID, plotID)
    local pPlot = Map.GetPlotByIndex(plotID)
    local Entry = pPlot:GetProperty("GP_"..PropertyID.."_Value")
    return Entry ~= nil
end

-- #region Accessors
function WriteValue(PropertyID, pPlot, value)               pPlot:SetProperty("GP_"..PropertyID.."_Value", value);              end
function WriteGrowth(PropertyID, pPlot, growth)             pPlot:SetProperty("GP_"..PropertyID.."_Growth", growth);            end
function WriteLastUpdate(PropertyID, pPlot, update)         pPlot:SetProperty("GP_"..PropertyID.."_LastUpdate", update);        end
function WriteThreshold(PropertyID, pPlot, threshold)       pPlot:SetProperty("GP_"..PropertyID.."_Threshold", threshold);      end
function WriteMaxVal(PropertyID, pPlot, maxVal)             pPlot:SetProperty("GP_"..PropertyID.."_MaxVal", maxVal);            end
function WriteMinVal(PropertyID, pPlot, minVal)             pPlot:SetProperty("GP_"..PropertyID.."_MinVal", minVal);            end
function WriteTriggered(PropertyID, pPlot, triggered)       pPlot:SetProperty("GP_"..PropertyID.."_Triggered", triggered);      end
function WriteTriggerTurn(PropertyID, pPlot, newTriggerTurn)
    local previousTurn = ReadTriggerTurn(PropertyID, pPlot)
    if newTriggerTurn <= Game.GetCurrentGameTurn() then newTriggerTurn = Game.GetCurrentGameTurn() + 1; end
    pPlot:SetProperty("GP_"..PropertyID.."_TriggersOn", newTriggerTurn)
    UpdateTurnTable(PropertyID, pPlot:GetIndex(), newTriggerTurn, previousTurn)
end

function ReadValue(PropertyID, pPlot)        if pPlot ~= nil then return pPlot:GetProperty("GP_"..PropertyID.."_Value");         else return 0;     end; end
function ReadGrowth(PropertyID, pPlot)       if pPlot ~= nil then return pPlot:GetProperty("GP_"..PropertyID.."_Growth");        else return 0;     end; end
function ReadLastUpdate(PropertyID, pPlot)   if pPlot ~= nil then return pPlot:GetProperty("GP_"..PropertyID.."_LastUpdate");    else return 0;     end; end
function ReadThreshold(PropertyID, pPlot)    if pPlot ~= nil then return pPlot:GetProperty("GP_"..PropertyID.."_Threshold");     else return 0;     end; end
function ReadMinVal(PropertyID, pPlot)       if pPlot ~= nil then return pPlot:GetProperty("GP_"..PropertyID.."_MaxVal");        else return 0;     end; end
function ReadMaxVal(PropertyID, pPlot)       if pPlot ~= nil then return pPlot:GetProperty("GP_"..PropertyID.."_MinVal");        else return 0;     end; end
function ReadTriggerTurn(PropertyID, pPlot)  if pPlot ~= nil then return pPlot:GetProperty("GP_"..PropertyID.."_TriggersOn");    else return 0;     end; end
function ReadTriggered(PropertyID, pPlot)    if pPlot ~= nil then return pPlot:GetProperty("GP_"..PropertyID.."_Triggered");     else return false; end; end
-- #endregion

function UI_GetData(PropertyID, pPlot)
    local UI_Data = nil
    if pPlot ~= nil then
        local val = ReadValue(PropertyID, pPlot)
        if val ~= nil then
            UI_Data = {}
            local growth = ReadGrowth(PropertyID, pPlot)
            local updated = ReadLastUpdate(PropertyID, pPlot)
            local triggerTurn = ReadTriggerTurn(PropertyID, pPlot)
            local CurrentTurn = Game.GetCurrentGameTurn()
            local newVal = val + ( (CurrentTurn - updated) * growth)
            local thold = ReadThreshold(PropertyID, pPlot)

            UI_Data.Value = newVal
            UI_Data.Growth = growth
            UI_Data.Threshold = thold
            UI_Data.TriggerTurn = triggerTurn
            UI_Data.ID = PropertyID
        end
    end

    return UI_Data
end

-- Modifiers
function UpdatePlotProperties(PropertyID, pPlot : object)
    if pPlot ~= nil then
        local PropertyData = PropertyList[PropertyID]
        local CurrentTurn = Game.GetCurrentGameTurn()

        local LastUpdated = ReadLastUpdate(PropertyID, pPlot)
        if LastUpdated == nil then return; end

        local CurrentValue = ReadValue(PropertyID, pPlot)
        local PreviousValue = CurrentValue

        -- Check to see if we've updated this turn already
        if LastUpdated ~= CurrentTurn then
            local CurrentGrowth = ReadGrowth(PropertyID, pPlot)
            -- Update the value to be current
            local NewValue = CurrentValue + ( (CurrentTurn - LastUpdated) * CurrentGrowth)

            local minVal = ReadMinVal(PropertyID, pPlot)
            local maxVal = ReadMaxVal(PropertyID, pPlot)

            if      NewValue < minVal then NewValue = minVal;
            elseif  NewValue > maxVal then NewValue = maxVal;
            end
            
            WriteValue(PropertyID, pPlot, NewValue)
            CurrentValue = NewValue
            WriteLastUpdate(PropertyID, pPlot, CurrentTurn)
        end
        
        return CheckTrigger(CurrentValue, PreviousValue, ReadThreshold(PropertyID, pPlot));
    end
end
function SetGrowth(PropertyID : string, plotID : number, newGrowth : number)
    if PropertyID ~= nil and plotID ~= nil and newGrowth ~= nil then
        DebugTileGrowth("Setting Tile Growth: "..PropertyID..", "..plotID..", "..newGrowth);
        local pPlot = Map.GetPlotByIndex(plotID)
        if pPlot == nil then return; end

        UpdatePlotProperties(PropertyID, pPlot)

        local CurrentValue = ReadValue(PropertyID, pPlot)
        local Threshold = ReadThreshold(PropertyID, pPlot)
        
        WriteTriggerTurn(PropertyID, pPlot, EstimateTriggerTurn(newGrowth, CurrentValue, Threshold))
    else
        DebugTileGrowth("Tried to set growth, but an arg was nil");
    end
end
function ChangeGrowth(PropertyID : string, plotID : number, adjustment : number)
    if PropertyID ~= nil and plotID ~= nil and adjustment ~= nil then
        DebugTileGrowth("Adjusting Tile Growth: "..PropertyID..", "..plotID..", "..adjustment);
        local pPlot = Map.GetPlotByIndex(plotID)
        if pPlot == nil then return; end

        UpdatePlotProperties(PropertyID, pPlot)

        local CurrentValue = ReadValue(PropertyID, pPlot)
        local CurrentGrowth = ReadGrowth(PropertyID, pPlot)
        local Threshold = ReadThreshold(PropertyID, pPlot)

        local newGrowth = CurrentGrowth + adjustment;
        
        WriteTriggerTurn(PropertyID, pPlot, EstimateTriggerTurn(newGrowth, CurrentValue, Threshold))
    else
        DebugTileGrowth("Tried to adjust growth, but an arg was nil");
    end
end
function ChangeThreshold(PropertyID : string, plotID : number, newThreshold : number)
    if PropertyID ~= nil and plotID ~= nil and newThreshold ~= nil then
        DebugTileGrowth("Setting New Threshold: "..PropertyID..", "..plotID..", "..newThreshold);
        local pPlot = Map.GetPlotByIndex(plotID)
        if pPlot == nil then return; end

        UpdatePlotProperties(PropertyID, pPlot)
        
        local CurrentValue = ReadValue(PropertyID, pPlot)
        local CurrentGrowth = ReadGrowth(PropertyID, pPlot)
        local NewTurn = EstimateTriggerTurn(CurrentGrowth, CurrentValue, newThreshold)

        WriteThreshold(PropertyID, pPlot, newThreshold)
        WriteTriggerTurn(PropertyID, pPlot, NewTurn)
    else
        DebugTileGrowth("Tried to adjust threshold, but an arg was nil");
    end
end
function SetValue(PropertyID : string, plotID : number, newValue)
    if PropertyID ~= nil and plotID ~= nil and newValue ~= nil then

        local pPlot = Map.GetPlotByIndex(plotID)
        if pPlot == nil then return; end
        
        local CurrentGrowth = ReadGrowth(PropertyID, pPlot)
        local Threshold = ReadThreshold(PropertyID, pPlot)

        WriteTriggerTurn(PropertyID, pPlot, EstimateTriggerTurn(CurrentGrowth, newValue, Threshold))
    end
end
function SetMaxAndMin(PropertyID : string, plotID : number, newMin, newMax)
    local pPlot = Map.GetPlotByIndex(plotID)
    WriteMaxVal(PropertyID, pPlot, newMax)
    WriteMinVal(PropertyID, pPlot, newMin)
end

-- Trigger Management
function SnoozeTrigger(PropertyID : string, plotID : number, delay)
    local pPlot = Map.GetPlotByIndex(plotID)
    if pPlot == nil then return; end

    UpdatePlotProperties(PropertyID, pPlot)

    local currentTriggerTurn = ReadTriggerTurn(PropertyID, pPlot)
    local currentGameTurn = Game.GetCurrentGameTurn()
    local newTurn = currentTriggerTurn + delay;
    if newTurn <= currentGameTurn then newTurn = currentGameTurn + 1; end

    WriteTriggerTurn(PropertyID, pPlot, newTurn)

    print("Snoozing plot: "..plotID..", from "..currentTriggerTurn.." to "..newTurn)
end
function ClearTrigger(PropertyID, plotID)
    if PropertyID ~= nil and plotID ~= nil then
        local pPlot = Map.GetPlotByIndex(plotID)
        if pPlot == nil then return; end

        WriteTriggered(PropertyID, pPlot, false)
        
        UpdatePlotProperties(PropertyID, Entry)
        WriteTriggerTurn(PropertyID, pPlot, EstimatePlotTrigger(PropertyID, pPlot))
    end
end
function SetTrigger(PropertyID, plotID)
    if PropertyID ~= nil and plotID ~= nil then
        local pPlot = Map.GetPlotByIndex(plotID)
        if pPlot == nil then return; end
        
        WriteTriggered(PropertyID, pPlot, true)
    end
end
function CheckTrigger(NewVal, OldVal, Threshold)
    local triggered = false
    local direction = 0

    if OldVal < Threshold and NewVal >= Threshold then
        triggered = true
        direction = 1
    elseif OldVal >= Threshold and NewVal < Threshold then
        triggered = true
        direction = -1
    end

    return triggered, direction
end


-- Utiltiies/Calculations
function EstimateTriggerTurn(Growth : number, Value : number, Threshold : number)
    local triggerTurn = math.huge
    local CurrentTurn = Game.GetCurrentGameTurn()
    if Growth > 0 then
        -- Get the difference between the trigger threshold and the current value
        local diff = Threshold - Value
        -- Number of turns is the diff divided by the growth rounded up
        local turns = math.ceil(diff / Growth)

        -- We never want to set a trigger to be less than or equal to the current turn, because then it would never trigger
        if turns <= 0 then
            triggerTurn = CurrentTurn + 1;
        else
        -- And so the expected improvement turn is the number of turns plus the current turn
            triggerTurn = CurrentTurn + turns
        end
    end

    return triggerTurn
end
function EstimatePlotTrigger(PropertyID, pPlot)
    if pPlot == nil then return -1; end
    if not(PlotIsInitialized(PropertyID, pPlot:GetIndex())) then return -1; end

    return EstimateTriggerTurn(ReadGrowth(PropertyID, pPlot), ReadValue(PropertyID, pPlot), ReadThreshold(PropertyID, pPlot))
end

-- #endregion

-- #endregion

-- ===========================================================================
-- #region DEBUGGING
-- ===========================================================================

function DebugTileGrowth(msg)
    if Debug_Tile_Growth then print(msg); end
end

-- #endregion

-- ===========================================================================
-- #region GAMEPLAY
-- ===========================================================================

function OnGameTurnStarted()
    for p,_ in pairs(PropertyList) do
        CheckTurnTable(p, Game.GetCurrentGameTurn())
    end
end
GameEvents.OnGameTurnStarted.Add(OnGameTurnStarted)

function CheckTurnTable(PropertyID : string, Turn : number)
    local TurnTable = GetTurnTable(PropertyID)

    local PlotsToTrigger = {}

    if TurnTable ~= nil and Turn ~= nil then
        local TurnData = TurnTable[Turn]

        -- Check if there are plot entries for this turn
        if TurnData ~= nil then
            -- Clear the entry from the table
            TurnTable[Turn] = nil

            -- Iterate over the keys of TurnData (which are the plot IDs scheduled to trigger this turn)
            for plotID,_ in pairs(TurnData) do
                local ThisPlot = Map.GetPlotByIndex(plotID)
                if ThisPlot ~= nil then
                    local Triggered, Direction = UpdatePlotProperties(PropertyID, ThisPlot)

                    -- If this plot triggered, attempt to invoke the callback function if it exists
                    if Triggered and not(ReadTriggered(PropertyID, thisPlot)) then
                        table.insert(PlotsToTrigger, {PropertyID, plotID, Direction})
                    end
                end
            end
            
            -- Make sure to update the turn table at the end
            SetTurnTable(PropertyID, TurnTable)
        end
    end

    -- We trigger outside the checking loop so that if needed, the triggers can update the turn table without it getting overwritten
    for k,trigger in pairs(PlotsToTrigger) do
        PlotTrigger(trigger[1], trigger[2], trigger[3])
    end

end

function UpdatePlot(PropertyID : string, plotID : number)
    if PropertyID ~= nil and plotID ~= nil then
        local pPlot = Map.GetPlotByIndex(plotID)

		if not(PlotIsInitialized(PropertyID, plotID)) then
			InitPlotPropertyData(PropertyID, pPlot)
        else
            GrowthCalc = GetGrowthCalcFunc(PropertyID)
            newGrowth = GrowthCalc(plotID)
            UpdatePlotProperties(PropertyID, pPlot)
		end
    end
end

function PlotTrigger(PropertyID, plotID, direction)
    --print("Plot growth triggered: "..PropertyID..", "..plotID)
    local CallbackFunc = GetCallbackFunc(PropertyID)
    if CallbackFunc ~= nil and type(CallbackFunc) == "function" then
        CallbackFunc(plotID, direction)
    else
        print("ERROR: Invalid callback function")
    end

    SetTrigger(PropertyID, plotID)
end

-- #endregion

-- ===========================================================================
-- #region UTILITY
-- ===========================================================================

function notNilOrNegative(val)
	if val == nil then return false; end
	if val < 0 then return false; end

	return true
end

-- #endregion

-- ===========================================================================
-- #region EXPOSED MEMBERS
-- ===========================================================================

TileGrowth = {}

TileGrowth.DefineGrowthProperty = DefineGrowthProperty
TileGrowth.GetAllPropertyIDs = GetAllPropertyIDs

TileGrowth.SetGrowth = SetGrowth
TileGrowth.ChangeGrowth = ChangeGrowth
TileGrowth.ChangeThreshold = ChangeThreshold
TileGrowth.ChangeCallback = ChangeCallback
TileGrowth.SetValue = SetValue
TileGrowth.SetMaxAndMin = SetMaxAndMin

TileGrowth.SnoozeTrigger = SnoozeTrigger
TileGrowth.ClearTrigger = ClearTrigger
TileGrowth.SetTrigger = SetTrigger

TileGrowth.ReadValue = ReadValue
TileGrowth.ReadGrowth = ReadGrowth
TileGrowth.ReadThreshold = ReadThreshold
TileGrowth.ReadLastUpdate = ReadLastUpdate
TileGrowth.ReadTriggerTurn = ReadTriggerTurn
TileGrowth.ReadTriggered = ReadTriggered

TileGrowth.InitPlotPropertyData = InitPlotPropertyData
TileGrowth.UpdatePlot = UpdatePlot

TileGrowth.UI_GetData = UI_GetData

ExposedMembers.TileGrowth = TileGrowth

-- #endregion

print("Tile growth loaded!")