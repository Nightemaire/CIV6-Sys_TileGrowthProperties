
Plot Property Growth Event System

# Overview
This is intended to fill a gap in Civ 6 modding where working with and modifying plot properties can be a resource intensive endeavour. It specifically applies to situations where the plot property should change over time. When the property is defined at every tile in the map, this can get unwieldy and require a lot of computation if each tile also needs to be checked for some condition. In order to alleviate this, a property system that leverages dynamic events and growth rates to reduce the burden of needing to check every property all the time.

# The Basics
This would be the intended workflow of creating a growth property:
1. Create a new "Growth_Property" with a unique name
2. Determine what values of the new property matter (thresholds), and what should happen when those thresholds are crossed (events)
3. Initialize plots with the new property, which should include an initial value and growth rate, as well as the callback events for when the values are attained
4. Subscribe to game events that should modify the rate at which the property grows (or shrinks), and when those events occur, update the growth rates for the necessary tiles

## Behind the scenes, the system caches the following information for each plot as a property:
Plot_Data = {
	Value           = 0,									-- Stores the value of the plot from the last time it was checked
	Growth 		    = Growth,								-- Stores the current growth rate of the plot
	LastUpdate 	    = Game.GetCurrentGameTurn(),			-- Contains the turn number of the last time the value was updated
	Threshold       = PropertyData.DefaultThreshold,		-- The current threshold which the system uses to evaluate when the trigger should occur
	TriggersOn 	    = TriggerTurn,							-- The estimated turn for when this plot should cross the specified threshold
};

-- Additionally, there is a table attached as a game property which contains indices of tiles that should trigger on any given turn.
-- An event is registered for the start of every turn which removes the entry corresponding to the current game turn, and checks each tile in the list to see if it has triggered, and if so invokes the callback


