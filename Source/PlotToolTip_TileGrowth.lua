-- PlotToolTip_Utilization
-- Author: Nightemaire
-- DateCreated: 6/22/2022 22:13:13
--------------------------------------------------------------
-- ===========================================================================
-- INCLUDES
-- ===========================================================================
include "PlotTooltip_Expansion2";

-- ===========================================================================
-- CACHE BASE FUNCTIONS
-- ===========================================================================
XP2_FetchData = FetchData;
XP2_GetDetails = GetDetails;

print("Initializing Plot Property Growth Tooltip UI Script");

-- ===========================================================================
-- OVERRIDE BASE FUNCTIONS
-- ===========================================================================
function FetchData(pPlot)
	--print("Calling overridden data fetch");
	local data = XP2_FetchData(pPlot);

	local AllProperties = ExposedMembers.TileGrowth.GetAllPropertyIDs(false, true)
	data.plotID = pPlot:GetIndex()
	data.PlotProperties = {}
	for k,propID in pairs(AllProperties) do
		table.insert(data.PlotProperties, ExposedMembers.TileGrowth.UI_GetData(propID, pPlot))
	end

	return data;
end

function GetDetails(data)
	--print("Calling overridden GetDetails()");
	local details : table = XP2_GetDetails(data);

	if data.PlotProperties == nil then return details; end
	if table.count(data.PlotProperties) <= 0 then return details; end

	for k,v in pairs(data.PlotProperties) do
		--[[
		local UI_Data = {
			Value = newVal,
			Growth = growth,
			Threshold = thold,
			TriggerTurn = triggerTurn,
			ID = PropertyID
		}
		--]]

		-- Turn the utilization into a percent of the threshold
		local percentUtil = math.floor((v.Value*100)/v.Threshold)
		local percentGrowth = math.floor((v.Growth*100)/v.Threshold)

		-- Args: 1 = ID, 2 = Value, 3 = Threhsold, 4 = PercentGrowth, 5 = TriggerTurn
		-- <Text>{1_PropertyID}: {2_Count}/{3_Count} | {4_Count}% | Turn {5_Count}</Text>
		local TipString = v.Value.."/"..v.Threshold.." | "..percentGrowth.."% | Turn "..v.TriggerTurn
		--table.insert(details, Locale.Lookup("LOC_PLOT_PROPERTY_TOOLTIP_TEXT", v[5], v[1], v[3], percentGrowth, v[4]));
		table.insert(details, "Plot ID: "..data.plotID);
		table.insert(details, v.ID..":");
		table.insert(details, TipString);
	end
	
	return details;
end