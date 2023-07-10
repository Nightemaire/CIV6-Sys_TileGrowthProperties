
# Plot Property Growth Event System

This system fills a gap in Civ 6 modding where working with and modifying plot properties can be limited, and become a resource intensive endeavour when trying to apply them to larger maps or to implement more complicated behaviors.

## Overview

More specifically, this system is useful in situations where the plot property should change over time. When the property is defined at every tile in the map, this can get unwieldy and require a lot of computation if each tile also needs to be periodically checked for some condition.

To alleviate this, a velocity parameter permits calculation of the exact time when a property should trigger. Now, we can just keep a table keyed by turn numbers, where each element is a list of the plots scheduled to trigger, and at the start of the turn we index the turn table with the turn number, check all the plots, and then nil out the entry since the turn is passed. More complicated behavior can be added by recalculating the growth in response to appropriate events, which then updates the trigger turn. Further complexity is possible such as variable thresholds, max and min values, and different methods of trigger latching.

At some point, it may make sense to simply expose a "compare" function that the developer can override, which would further extend the capabilities.

## The Basics

This is the intended workflow for creating and working with a growth property, assuming that the mod load order is setup correctly.

1. Access the system's functions by obtaining a reference to the ExposedMembers table at the top of your script. (You can set the variable name to whatever you want, just make sure you reference correctly later on)
```lua
local TG = ExposedMembers.TileGrowth
```
2. Create a new growth property with a unique name using something equivalent to the syntax below. If you're not familiar with havokscript, that's okay, hmake is essentially just creating an instance of a struct. This helps ensure proper typing and naming.
```lua
NewPropertyID = "SomeString"
TG.DefineGrowthProperty(
	hmake PropertyListData {
		ID					= NewPropertyID,
		DefaultThreshold	= 12345,
		GrowthCalcFunc      = foo,
		CallbackFunc      	= bar,
		MinVal          	= -10,
		MaxVal          	= 100,
		TriggerMode     	= "ONCE",
		TriggerTest     	= nil,
		ShowLens			= true,
		ShowTooltip			= true
	}
)
```
3. Initialize some or all plots with the new property, this can either be done dynamically, or all at once at the start. To initialize, you can explicitly call the InitPlotPropertyData() function, or you can just call UpdatePlot(), which is the primary method you'll use to if you need to adjust things. Keep in mind that the Init function requires the plot object, while the Update function requires the plot ID.
```lua
TG.UpdatePlot(NewPropertyID, plotID)
-- or...
TG.InitPlotPropertyData(NewPropertyID, pPlot)
```
If the plot isn't initialized yet, UpdatePlot() will do so anyway, and the result should end up exactly the same. If a plot needs to be reset back to the base state, UpdatePlot() cannot handle this, and the init function must be used.

4. Subscribe to game events that should modify the parameters of the plot, and when those events occur, call the UpdatePlot() function again. This will automatically call the GrowthCalcFunc you assigned in step one for the plot. This function is primarily for adjusting the growth rate, and the return must be a number that represents the new growth. But because the plot ID is available in this step, other properties can be modified here as well. After the GrowthCalcFunc is called, UpdatePlot() recalculates trigger information and updates the appropriate tables to make sure they're handled at the correct times.

## What's Cached

The system caches information in properties to ensure continuity between saves. The information is split between plot properties, and game properties.

### Plot Properties

Behind the scenes, the system caches the following information for each plot as their own individually assigned properties. Each property ID is prefixed by "GP_{PropertyID}_" to minimize the possibility of overwriting the properties, and to permit multiple properties on a plot at one time.

```lua
"Value"      	= number,	-- Stores the value of the plot from the last time it was checked
"Growth" 		= number,	-- Stores the current growth rate of the plot
"LastUpdate" 	= number,	-- Contains the turn number of the last time the value was updated
"Threshold"  	= number,	-- The current threshold which the system uses to evaluate when the trigger should occur
"MaxVal"		= number,	-- The maximum value of a property allowed for this plot
"MinVal"		= number,	-- The minimum value of a property allowed for this plot
"TriggersOn"	= number,	-- The estimated turn for when this plot should cross the assigned threshold
"Triggered"		= boolean,	-- A flag indicating whether this plot is or has been triggered, the behavior of this variable is governed by the property itself
```

All plot properties have read access exposed, but only some have write access. This is controlled to ensure continuity of the TurnTable. The properties that can be manually adjusted are: Value, Growth, Threshold, MaxVal, MinVal, and Triggered.

### Game Properties

Additionally, there is a table attached as a game property which contains indices of tiles that should trigger on any given turn. An event is registered for the start of every turn which removes the entry corresponding to the current game turn, and checks each tile in the list to see if it has triggered, and if so invokes the callback. The structure of the table is as follows:

```lua
TurnTable =
{
	[m] = 	{ 
				{ i_1 = true },
				{ i_2 = true },
				{ i_3 = true },
				...
			},
	[n] =	{ 
				{ j_1 = true },
				{ j_2 = true },
				{ j_3 = true },
				...
			},
	...
}
```

Where m and n are turn indices, and i_x and j_x are plot indices scheduled to trigger each turn. The value in the table for each turn is irrelevant, all we need to know is that an entry exists with the key we specify, (i.e. `TurnTable[n][i_1] ~= nil`). Each plot ID should only be represented in the table one time, and one time only. It is highly advisable to NOT modify the turn table...and it is purposefully not exposed, though if you're clever it may be possible...

### Disclaimer

I'm uncertain how much of an impact caching these properties will have on load times, rates of crashing, or save file sizes - but I expect there will be some effect. I hope it will be marginal on average size maps, but it could become serious on large maps with a lot of properties.

## UI Features

One major benefit of this framework is it comes prepackaged with two UI features. If you add a new property, you can set a flag to indicate whether you want the property to show up as a lens option, and whether some information is displayed in the plot tooltip. This is very useful for debugging, so even if you don't want the player to see the details, you can turn them on while you're developing.

At this time, it is beyond the scope of the framework to enable custom lensing or tooltip behavior - but if you know you're way around how this stuff is implemented you can probably figure it out yourself. If the demand for it is high, then an extension may be warranted.

***Many thanks to Astog and his 'More Lenses' mod, as this would not have been possible without it!***

## Potential Applications

With the basics in mind, here are a few ideas of things that could be implemented that utilize the growth property system.

* Waste Management/Pollution
* Sickness/Disease
* Dissent (Like a loyalty rework)
* Scenarios
* Population

Don't feel like you need to ask permission if you're inspired to try any of these :)