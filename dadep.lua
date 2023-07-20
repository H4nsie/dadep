--[[
DADEP - The DAY AHEAD DAILY ENERGY PRICES
dzVents script for Domoticz
Spring 2023 v1.2 - H. van der Heijden 


Requirements:
Domoticz - v2023.1 and higher with
	- counter P1 Smart Meter for Electricity (type 251) (electricMeter in settings)
	- counter P1 Smart Meter for Gas (type 252) (gasMeter in settings)
	- counter General kWh for Solar Panels counter (sunMeter in settings)
	- counter General Counter Incremental for Water (waterMeter in settings) (optional)


History:
v0.1 initial
v0.2 changed from managed counters to custom sensors
v1.1 implemented: gas prices three days from 6-6u
v1.2 code cleanup

Based on:
forum: https://domoticz.com/forum/viewtopic.php?t=38880
original script by willemD, see https://www.domoticz.com/forum/viewtopic.php?p=296716#p296716

Todo:
1) Implement DST and timezone at line 114.
2) Determine next GREEN time and display in text device.
3) DONE: Display tomorrow's gasprice when available?
4) DONE: Gasprice is from 6:00 till 6:00, count correct value for today's use
5) Percentage electric used in GREEN for today?
6) Forecast cheapest hour of the day

]]--

-- SETTINGS

-- prices, change to the energy costs of your provider
local EnergyTax = 0.12599									-- Electric tax per kWh in euro
local HandlingFee = 0.016528925619835						-- Electric handling fee per kWh (excl vat)
local GAStax = 0.48980										-- Gas tax per m3 in euro
local GAShandlingfee = 0.04959								-- Gas handling fee per m3 (excl vat) in euro
local GAStransport = 0.01652                                -- Gas transport costs (excl vat) per m3 in euro
local water_cost = 1.21                                     -- Water the cost of m3 (1000 liters) water including taxes (br: https://www.brabantwater.nl/rekening-en-betalen/tarieven )
local Tax = 0.21											-- tax (0.21 for 21%)

local ApiEUtoken='YOUR_TOKEN_HERE'     -- your personal API token of user account from entsoe
local colordeviation = 10									-- percentage deviation from mean to price for red - green - blue

-- Your EXISTING counter devices names
local electricMeter = 'Electriciteit' 						-- change to name of your current ELECTRIC P1 Meter between quotes or id without quotes
local sunMeter = 'Zonnepanelen' 						    -- change to name of your current SUN (solar modem) Meter between quotes or id without quotes
local gasMeter = 'Gas'                                      -- change to name of your current GAS P1 Meter between quotes or id without quotes
local waterMeter = 'Water'                                  -- change to the name of your water counter between quotes or id without quotes, or don't change if you do not have a water meter. 

-- dummy hardware devices to be ADDED
local kwhPrice='Elektriciteit prijs dit uur'				-- your device for hourly kwh price 	| type: add dummy device -> Custom sensor (cents)
local kwhColor='Electriciteit kleur nu'						-- your device for the color 			| type: add dummy device -> text device
local electricCostToday = 'Elektraverbruik vandaag'			-- your device for today's electric costs. resets at midnight. | type: add dummy device ->  Custom sensor (euro)
local gasPrice = 'Gasprijs nu'								-- your device for gasprice of today 	| type: add dummy device -> Custom sensor (cents)
local gasPriceTomorrow = 'Gasprijs morgen'					-- your device for gasprice of tomorrow | type: add dummy device -> Custom sensor (cents)
local gasCostToday = 'Gasverbruik vandaag'					-- your device for today's gas costs. resets at midnight. | Type: add dummy device -> Custom sensor (euro)
local waterCostToday = 'Waterverbruik vandaag'				-- your dummy device for today's water costs. resets at midnight.  -> Custom sensor (euro)
local self_produce_perc = 'Zelfproductie vandaag'			-- your dummy device for today's self produced perc. -> Custom sensor (euro)


-- settings, below here no changes are needed
local UrlStart='https://web-api.tp.entsoe.eu/api?'          --the kwh API website 
local DocType='A44'                                         --day ahead prices document type 
local PriceRegion='10YNL----------L'                        --region is set to The Netherlands (adapt to your need as per API documentation)
local GASurl='https://gasandregistry.eex.com/Gas/EGSI/EGSI_Day_45_Days.csv'  --the gas API website
local GAShub = 'TTF'                                        -- the transport hub
local GAScorrectionfactor = 0.009769444                     -- convert from eur/MWh to cents/m3
local debug = false;										-- change to 'true' for debugging in Domoticz's logfile


return {
	on = {
		timer = {
		    'every 5 minutes',		-- update the counters
		    'at 00:00',				-- reset daily counters
		    'at 23:59',				-- for daily costs report, save to user vars
		    'at 08:05',				-- for report in family app
		},
		httpResponses = {
			'ENTSOE', -- ENTSOE https request callback
			'EEXgas', -- EEX https request callback
		},
		devices = {
		    'Testbutton', -- dummy decive for for triggering for debug purposes
		},
	},
	logging = {
		level = domoticz.LOG_INFO,        --remove comment signs to display logs
		marker = 'DADEP',
	},
	data = {
        	data_kwh = { initial={} },                             -- table, kWh prices per hour
        	data_total_price_today2 = {initial=0},                 -- integer, cumulative electric price today, resets at midnight 
        	data_total_price_thishour = {initial=0},               -- integer, cumulative electric price this hour, resets at whole hour
        	data_total_price_todayGAS = {initial=0},               -- integer, cumulative GAS price today, resets at midnight 
        	data_total_price_thishourGAS = {initial=0},            -- integer, cumulative GAS price this hour, resets at whole hour 
        	data_prev_cntr_usage = {initial=0},                    -- integer, remember previous electric counter usage
        	data_prev_cntr_return = {initial=0},                   -- integer, remember previous electric counter return
        	data_prev_cntr_GAS = {initial=0},                      -- integer, remember previous GAS counter
        	
        	-- integers, remember at 23:59 today's usage for reporting tomorrow
        	data_report_electric_yesterday_usage = {initial=0},    
        	data_report_electric_yesterday_return = {initial=0},
        	data_report_electric_yesterday_cost = {initial=0},
        	data_report_gas_yesterday_usage = {initial=0},
        	data_report_gas_yesterday_cost = {initial=0},
        	data_report_water_yesterday_usage = {initial=0},
        	data_report_water_yesterday_cost = {initial=0},
           	data_report_sun_yesterday_usage = {initial=0},
	},

	execute = function(dz, item)
    	    
    	data_kwh=dz.data.data_kwh   -- table for price per hour for this day 

    	    
    	-- function to retrieve electric prices
    	function get_energy_prices()
    	   local PricePeriodStart=dz.time.dateToDate(dz.time.rawDate,'yyyy-mm-dd', 'yyyymmdd0000', 0 ) -- start today at 00:00
           local PricePeriodEnd=dz.time.dateToDate(dz.time.rawDate,'yyyy-mm-dd', 'yyyymmdd2300', 1 * 24 * 60 * 60 ) -- end tomorrow at 23:00 (you can ask for tomorrow, ENTSOE only returns what if available )
           if debug then dz.log("Start: "..PricePeriodStart, dz.LOG_INFO) end
           if debug then dz.log("End: "..PricePeriodEnd, dz.LOG_INFO) end
           local EUurl=UrlStart .. 'securityToken=' .. ApiEUtoken .. '&documentType=' .. DocType .. '&in_Domain=' .. PriceRegion .. '&out_Domain=' .. PriceRegion .. '&periodStart=' .. PricePeriodStart .. '&periodEnd=' .. PricePeriodEnd
	       dz.log("URL : " .. EUurl, dz.LOG_INFO)
    	   dz.openURL({
    		  url = EUurl,
    		  method = 'GET',
    		  callback = 'ENTSOE' -- callback
    			})
    	end -- get_energy_prices()
    	
    	
    	-- function to retrieve gas prices
    	function get_gas_prices()
    	    dz.log('Getting GAS prices')
            dz.openURL({
                url = GASurl,
                method = 'GET',
                callback = 'EEXgas', -- callback
            })
    	end -- get_gas_prices()
    	
    	
    	function enumerate_timeseries(timeSerie)
            local TIMEZONE = 2 *3600  -- TODO use DST function isdt https://www.domoticz.com/wiki/DzVents:_next_generation_Lua_scripting
            seriesStart = timeSerie.Period.timeInterval.start
            --dz.log ('This series starts at '.. seriesStart)

            -- get first time series
            local hournow = os.date("%Y-%m-%d %H:00:00")
            local meanTotal =0
            local meanCount =0
            local current_hour_price =0
            local nextgreen ='N/A'
            for id = 1, 24 do
                position = tonumber(timeSerie.Period.Point[id].position)
                rawPrice = tonumber(timeSerie.Period.Point[id]['price.amount']) / 1000    -- From MW to kW
                -- that price is at DateTime: time from SeriesStart(UTC) + timezone + id*3600
                EnergyPrice = dz.utils.round((rawPrice + EnergyTax + HandlingFee ) * (1 + Tax) ,3) * 100   -- rounding to 3 dec and *100 delivers 1 decimal at EnergyPrice
                priceDate = dz.time.timestampToDate(   dz.time.dateToTimestamp(seriesStart,'(%d+)%-(%d+)%-(%d+)T(%d+):(%d+)Z')  , 'yyyy-mm-dd hh:MM:00', TIMEZONE + (id-1)*3600)
                if debug then dz.log ('EnergyPrice '.. tostring(EnergyPrice).. ' at position '.. tostring(position).. ' at '.. priceDate) end
				-- need to update the current hour price in domoticz?
				if priceDate == hournow then
					--dz.devices(kwhPrice).updateCounter(EnergyPrice) --update device this hour energy price
					dz.devices(kwhPrice).updateCustomSensor(EnergyPrice) -- test
					dz.log ('Updated device for current hour with price '.. tostring(EnergyPrice))
					current_hour_price = EnergyPrice
				end
				-- then count for mean value of this serie
				meanTotal = meanTotal + EnergyPrice
				meanCount = meanCount +1
				-- is today? then fill the kwh-price/hour data
				if ( os.date("%Y-%m-%d") == dz.time.timestampToDate( dz.time.dateToTimestamp(priceDate,'(%d+)%-(%d+)%-(%d+) (%d+):(%d+)')  , 'yyyy-mm-dd') ) then
					priceHour = dz.time.timestampToDate(   dz.time.dateToTimestamp(priceDate,'(%d+)%-(%d+)%-(%d+) (%d+):(%d+)')   , 'hh') 
					if debug then dz.log('Storing price '..EnergyPrice .. 'in data_kwh at '..priceHour) end
					data_kwh[tonumber(priceHour)] = EnergyPrice
				end
				
				-- determine next GREEN time (TODO)
				--difference = os.difftime (dz.time.dateToTimestamp(priceDate), dz.time.dateToTimestamp(hournow)) / 3600
				--dz.log ('DIFFERENCE '..difference)
				--if difference>= 0 and nextgreen =='N/A' then -- if upcoming hour and not yet determined
					---if dz.utils.round(((EnergyPrice - mean ) / mean ) *100 ,0) 
					--end
				--end	
            end -- for id loop
    		
    		-- calculate mean value this Serie
    		local mean = dz.utils.round( meanTotal / meanCount, 0)
    		dz.log ('Mean value for this series is '.. mean)
    		-- if current_hour_price !=0 (only updated if current hour occurs in series! then update color
    		if current_hour_price ~=0 then
    			local currentColor = "BLUE"
    			local percentage_diff = dz.utils.round(((current_hour_price - mean ) / mean ) *100 ,0)
    			if debug then dz.log( 'Percentage diff from mean is '..tostring(percentage_diff) ) end
    			if percentage_diff > colordeviation then currentColor = "RED" end
    			if percentage_diff < -(colordeviation) then currentColor = "GREEN" end
    			dz.log( 'Color is now: '..currentColor)
    			dz.devices(kwhColor).updateText(currentColor)
       		end
  	
    	end --enumerate_timeseries(timeSerie)
    	
    	
    	-- MAIN LOOP    	
    	
        -- trigger HTTPS callback
    	if item.isHTTPResponse then
    	   if debug then dz.log("HTTP Response on:"..item.trigger, dz.LOG_INFO) end
    	   
    	   -- process ENTSOE prices
    	   if item.trigger=="ENTSOE" and item.ok and item.isXML then
                if item.xml.Acknowledgement_MarketDocument then
                    dz.log('Fout met XML - '..item.xml.Acknowledgement_MarketDocument.Reason.text,dz.LOG_INFO) 
                else
                    entsoe_data = item.xml.Publication_MarketDocument
                    
                    -- TODO convert report UTC to local time to check if correct values
                    periodstart = entsoe_data['period.timeInterval']['start']
                    periodend = entsoe_data['period.timeInterval']['end']
                    dz.log("TODO Report starts: ".. periodstart .. " and ends: "..periodend)
                    
                    -- if after 13:00 the 'tomorrow prices', ENTSOE answers with tomorrow in a second TimeSeries. Determine if we haven 1 or 2 series:
                    if entsoe_data.TimeSeries.Period then enumerate_timeseries(entsoe_data.TimeSeries) end
                    if entsoe_data.TimeSeries[1] then enumerate_timeseries(entsoe_data.TimeSeries[1]) end
                    if entsoe_data.TimeSeries[2] then enumerate_timeseries(entsoe_data.TimeSeries[2]) end
                end
    	   end -- if item.trigger=="ENTSOE" and item.ok and item.isXML then

           -- process EEX price    	   
    	   if item.trigger=="EEXgas" and item.ok and item.hasLines then   -- hasLines, because is .csv
    	       dz.log('Retrieved GAS prices!'..item.statusCode)
    	       local pricetable = item.lines
    	       local yesterday = os.date("%Y-%m-%d" ,os.time()-24*60*60)
    	       local today = os.date("%Y-%m-%d")
    	       local tomorrow = os.date("%Y-%m-%d" ,os.time()+24*60*60)

    	       -- do a table walk
               for i,line in ipairs(pricetable) do
                    --dz.log(line)
                    -- csv format: Delivery Day;Calculation Day;Hub;Value;Unit;
                    local DeliveryDay, CalculationDay, Hub, Value, Unit = line:match("%s*(.-);%s*(.-);%s*(.-);%s*(.-);%s*(.-)")
                    
                    if DeliveryDay == today and Hub == GAShub then
                        gasprijs_now = dz.utils.round( (GAStax + GAShandlingfee + GAStransport + (Value * GAScorrectionfactor) ) * (1+ Tax), 3)*100 --ct to eur
                        dz.log('Gasprijs vandaag van 6u - morgen 6u: '..tostring(gasprijs_now))
                        
                    elseif DeliveryDay == tomorrow and Hub == GAShub then
                        gasprijs_tomorrow = dz.utils.round( (GAStax + GAShandlingfee + GAStransport + (Value * GAScorrectionfactor) ) * (1+ Tax), 3)*100 --ct to eur
						dz.log('Gasprijs morgen na 6u: '..tostring(gasprijs_tomorrow))
						-- and fill sensor for info
						dz.devices(gasPriceTomorrow).updateCustomSensor(gasprijs_tomorrow)
						
					elseif DeliveryDay == yesterday and Hub == GAShub then
                        gasprijs_yesterday = dz.utils.round( (GAStax + GAShandlingfee + GAStransport + (Value * GAScorrectionfactor) ) * (1+ Tax), 3)*100 --ct to eur
						dz.log('Gasprijs vandaag tot 6u: '..tostring(gasprijs_yesterday))
                    end 
                     
                end -- tablewalk     
                
                dz.log(gasprijs_now)
                -- prices are valid from 6-6, what price is NOW?
               	if tonumber(os.date("%H")) < 6 then
	                dz.log('Gasprijs nu (before 6 today): '..tostring(gasprijs_yesterday))
	                dz.devices(gasPrice).updateCustomSensor(gasprijs_yesterday)
	            elseif tonumber(os.date("%H")) >= 6 then 
	                dz.log('Gasprijs nu (after 6 today): '..tostring(gasprijs_now))
	                dz.devices(gasPrice).updateCustomSensor(gasprijs_now)           
	            end       
                
    	   end -- item.trigger=="EZGASprices" then
    	   
    	   
    	-- GET PRICES EVERY WHOLE HOUR   
    	elseif (item.isTimer and os.date("%M") == "00") or item.name == '#Testbutton'   then   -- only at whole hour
    	   get_energy_prices()
    	   get_gas_prices()
    	end   
    	
    	-- If TIME is 23:39 store counters and stats to data for report function tomorrow
    	if (item.isTimer and os.date("%H:%M") == "23:59") or (item.isDevice and item.name == '#Testbutton') then
    	   dz.log('Report function called, to store values')
    	   -- store all countertoday values for reporting tomorrow.
    	   dz.data.data_report_electric_yesterday_usage = dz.devices(electricMeter).counterToday
    	   dz.data.data_report_electric_yesterday_return = dz.devices(electricMeter).counterDeliveredToday
    	   dz.data.data_report_electric_yesterday_cost = dz.utils.round(dz.devices(electricCostToday).sensorValue,2)
    	   dz.data.data_report_gas_yesterday_usage = dz.devices(gasMeter).counterToday
    	   dz.data.data_report_gas_yesterday_cost = dz.utils.round(dz.devices(gasCostToday).sensorValue,2)
    	   if dz.devices(waterMeter) ~= nil then dz.data.data_report_water_yesterday_usage = dz.devices(waterMeter).counterToday end
    	   if dz.devices(waterMeter) ~= nil then dz.data.data_report_water_yesterday_cost =  dz.utils.round(dz.devices(waterMeter).counterToday * water_cost ,2) end
    	   dz.data.data_report_sun_yesterday_usage = dz.devices(sunMeter).counterToday
    	   -- and reset tomorrow's price for gas, since we do not know yet.
    	   dz.devices(gasPriceTomorrow).updateCustomSensor(0)
  
    	-- If TIME is 8:05 send Yesterday's usage report to family Telegram app.
    	elseif (item.isTimer and os.date("%H:%M") == "08:05") or (item.isDevice and item.name == '#Testbutton') then
    	   dz.log('Report function called')
    	   -- compose the message
    	   local message = 'Energiekosten gisteren: \n\z
		      Gas 💨 € ' .. dz.data.data_report_gas_yesterday_cost .. ' (' .. dz.data.data_report_gas_yesterday_usage .. ' m3)\n\z
		      Electra ⚡ € ' ..  dz.data.data_report_electric_yesterday_cost .. ' (' .. dz.data.data_report_electric_yesterday_usage - dz.data.data_report_electric_yesterday_return .. ' kWh)\n\z
		      Water 💧 € ' ..  dz.data.data_report_water_yesterday_cost .. ' (' .. dz.data.data_report_water_yesterday_usage .. ' m3)\n\z
		      TOTAAL kosten: €'.. dz.data.data_report_gas_yesterday_cost + dz.data.data_report_electric_yesterday_cost + dz.data.data_report_water_yesterday_cost ..'\n\z\n\z
		      Zonnepanelen opgewekt ☀️ ' .. dz.data.data_report_sun_yesterday_usage .. ' kWh\n\z
		      Electra uit het net ⚡ ' .. dz.data.data_report_electric_yesterday_usage .. ' kWh\n\z
		      Electra teruggeleverd ⚡ ' .. dz.data.data_report_electric_yesterday_return .. ' kWh\n\z
		      Electra zelf verbruikt ⚡ '.. dz.data.data_report_sun_yesterday_usage + dz.data.data_report_electric_yesterday_usage - dz.data.data_report_electric_yesterday_return .. ' kWh\n\z
		      Zelfvoorzienend electra '.. dz.utils.round( ( dz.data.data_report_sun_yesterday_usage / (dz.data.data_report_sun_yesterday_usage + dz.data.data_report_electric_yesterday_usage - dz.data.data_report_electric_yesterday_return)*100) ,0)..' %' 
		    -- than send the above message  
    	    --dz.helpers.telegramnote(dz, message)  
    	
    	-- if other time, than calc realtime costs!
    	elseif item.isTimer or (item.isDevice and item.name == 'Testbutton') then
    	
    	   -- get counter values from P1 for electric and GAS
    	   local cntr_usage_now = dz.devices(electricMeter).usage1 + dz.devices(electricMeter).usage2
    	   local cntr_return_now = dz.devices(electricMeter).return1 + dz.devices(electricMeter).return2
    	   local cntr_gas_now = dz.devices(gasMeter).counter
    	    	   
   	        if data_kwh[0] == nil then -- we were started for first time and not loaded energy prices at whole hour, then load now first!
    	       get_energy_prices()
    	   
    	    -- initial zero?, so don't calc at this time
    	    elseif dz.data.data_prev_cntr_usage ~= 0 and dz.data.data_prev_cntr_return ~= 0 and dz.data.data_prev_cntr_GAS ~=0 then
    	   
    	   		-- calc today's delta counters, against previous stored 
        	   delta_usage = cntr_usage_now - dz.data.data_prev_cntr_usage
        	   delta_return = cntr_return_now - dz.data.data_prev_cntr_return
        	   
        	   price_now = data_kwh[ tonumber(os.date("%H")) ] -- price of current hour
        	   
        	   if debug then dz.log ('Usage delta '.. delta_usage .. ' return delta ' .. delta_return .. ' at price '..price_now) end
        	   
        	   --update device this hour ELECTRIC usage in euro
        	   dz.data.data_total_price_thishour = ( delta_usage - delta_return )/1000 * price_now 
        	   local priceToday = dz.utils.round(((dz.data.data_total_price_thishour/100)+(dz.data.data_total_price_today2/100)),2)
               dz.devices(electricCostToday).updateCustomSensor(priceToday)             

               -- and now for GAS
               local gasprijs = dz.devices(gasPrice).sensorValue
				delta_gas = cntr_gas_now - dz.data.data_prev_cntr_GAS
				dz.data.data_total_price_thishourGAS = delta_gas * gasprijs
        	   local GASpriceToday = dz.utils.round(((dz.data.data_total_price_thishourGAS/100)+(dz.data.data_total_price_todayGAS/100)),2)
				dz.devices(gasCostToday).updateCustomSensor(GASpriceToday) -- test
               if debug then dz.log ('Usage delta '.. delta_gas ..  ' at price '..gasprijs) end

               -- and now for WATER
               if dz.devices(waterMeter) ~= nil then
                   local cntr_usageWATER_now = dz.devices(waterMeter).counterToday
                   priceToday = dz.utils.round( water_cost * cntr_usageWATER_now, 2)
                   dz.devices(waterCostToday).updateCustomSensor(priceToday)
               end  
                              
               -- update counter for self produced percentage 
               local perc_usage_sun = dz.utils.round(dz.devices(sunMeter).counterToday / ( dz.devices(sunMeter).counterToday + dz.devices(electricMeter).counterToday - dz.devices(electricMeter).counterDeliveredToday)*100,0)
               dz.devices(self_produce_perc).updateCustomSensor(perc_usage_sun)
               
    	     end
    	   
    	   -- shift counters to prev data at new hour (or initial start)
    	   -- (hourly shift for gas is not needed, because price stays same all day)
    	   if (os.date("%M") == "00" or dz.data.data_prev_cntr_usage == 0 or dz.data.data_prev_cntr_return == 0 or dz.data.data_prev_cntr_GAS == 0) then
    	       dz.log('HOURLY SHIFT CALLED')
    	       dz.data.data_prev_cntr_usage = cntr_usage_now
    	       dz.data.data_prev_cntr_return = cntr_return_now
    	       -- and reset cumm current hour price and add to total
    	       dz.data.data_total_price_today2 = dz.data.data_total_price_today2 + dz.data.data_total_price_thishour
    	       dz.data.data_total_price_thishour = 0
    	       
    	       
    	       -- and for GAS
    	       dz.log(tostring(cntr_gas_now))
    	       dz.log(tostring(dz.data.data_prev_cntr_GAS))
    	       dz.data.data_prev_cntr_GAS = cntr_gas_now
    	       dz.log(tostring(dz.data.data_prev_cntr_GAS))
    	       dz.data.data_total_price_todayGAS = dz.data.data_total_price_todayGAS + dz.data.data_total_price_thishourGAS

               dz.data.data_total_price_thishourGAS =0
    	       
    	       
    	       -- at midnight reset daily cumulative price to 0
        	   if (os.date("%H:%M") == "00:00" ) then
        	       -- electric
        	       dz.data.data_total_price_today2 = 0
        	       dz.data.data_total_price_thishour = 0
                   -- gas
                   dz.data.data_total_price_todayGAS = 0
                   dz.data.data_total_price_thishourGAS = 0
        	   end
    	       
    	   end
    	  
    	
    	end
 	
    	
    end -- execute
}	    









