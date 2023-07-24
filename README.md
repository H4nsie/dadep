# dadep
The DAY AHEAD DAILY (and hourly) ENERGY PRICES for Domoticz

A small dzVents script for Domoticz for counting your electricity use (in Euro's) during the day. 

**Cost counters are updated every 5 min. Watch your realtime electricity, gas and water costs!**



One special field 'Electricity color' is filled with a color. Electricity color changes during the day from **BLUE** (normal), **RED** (more than 10% higher than day avarage) or **GREEN** (more than 10% cheaper than day avarage) - You can switch devices at cheap of expensive times, or install a RGB lamp to indicate to your family :-)

During the day, the counter 'Self produced percentage' is updated. It is calculated between used electricity and power obtained from your solar panals. Very nice to follow the percentage change when the sun shines, or car is charged.

Electricity prices are obtained hourly from ENTSOE (you need an API key, explained below), gasprices obtained daily from EEX (no API key needed). 

Enable the report function (at line 315) to send the report (composed in string _message_) to send a complete report to your (Telegram) family group app at 8:05AM to show stats of the previous day.




<img width="1261" alt="Scherm­afbeelding 2023-07-20 om 15 38 56" src="https://github.com/H4nsie/dadep/assets/8566538/ad16449e-f049-4027-9fdd-fb006d7c5cbb">



Installation steps:

1) **Create these 8 Virtual Counters in Domoticz**

Read the <a href="Domoticz Wiki">https://www.domoticz.com/wiki/Dummy_for_virtual_Switches</a> if you don't know how to!

* '**Elektriciteit prijs dit uur**'	-- your device for hourly kwh price 	| type: add dummy device -> Custom sensor (cents)
* '**Electriciteit kleur nu**'			-- your device for the color *1 			| type: add dummy device -> text device
* '**Elektraverbruik vandaag**'			-- your device for today's electric costs. resets at midnight. | type: add dummy device ->  Custom sensor (euro)
* '**Gasprijs nu**'								  -- your device for gasprice of today 	| type: add dummy device -> Custom sensor (cents)
* '**Gasprijs morgen**'					    -- your device for gasprice of tomorrow | type: add dummy device -> Custom sensor (cents)
* '**Gasverbruik vandaag**'					-- your device for today's gas costs. resets at midnight. | Type: add dummy device -> Custom sensor (euro)
* '**Waterverbruik vandaag**'				(**optional**) -- your dummy device for today's water costs. resets at midnight.  -> Custom sensor (euro) 
* '**Zelfproductie vandaag**'			  -- your dummy device for today's self produced perc. *2 -> Custom sensor (euro)

*1 Electricity color changes during the day from **BLUE** (normal), **RED** (more than 10% higher than day avarage) or **GREEN** (more than 10% cheaper than day avarage) - You can switch devices at cheap of expensice times, or install a RGB lamp to indicate to your family :-)

*2 Self produced today, until now. Percentage self produced (solar) against used today. Nice to follow as the sun shines!



2) **Configure the names of your creatd DUMMY sensors in the setting part of the script (dadep.lua)**

(only needed if you did choose an another name)

3) **Obtain an API key for ENTSOE**
   
  To request access to the Restful API, please register on the Transparency Platform (<a href="link">https://transparency.entsoe.eu/</a>) and send an email to transparency@entsoe.eu with “Restful API access” in the subject line. Indicate the email address you entered during registration in the email body. The ENTSO-E Helpdesk will make their best efforts to respond to your request within 3 working days.</li>

5) **Enter the your API key in the setting part of the script**

   local ApiEUtoken='YOUR_TOKEN_HERE'     -- your personal API token of user account from entsoe

6) **Configure the prices in the script (dadep.lua) for you current provider's prices**

* local EnergyTax = 0.12599					      -- Electric tax per kWh in euro
* local HandlingFee = 0.016528925619835	  -- Electric handling fee per kWh (excl vat)
* local GAStax = 0.48980			            -- Gas tax per m3 in euro
* local GAShandlingfee = 0.04959        	-- Gas handling fee per m3 (excl vat) in euro
* local GAStransport = 0.01652            -- Gas transport costs (excl vat) per m3 in euro
* local water_cost = 1.21                 -- Water the cost of m3 (1000 liters) water including taxes
* local Tax = 0.21	                      -- tax (0.21 for 21%)
* (These are my current prices (july 2023) for Zonneplan)

7) **Enable report function for family if you want**

   On line 315     	    _dz.helpers.telegramnote(dz, message)_ use a own function to send 'message' to family group app daily at 8:05

<img width="370" alt="Scherm­afbeelding 2023-07-20 om 16 48 37" src="https://github.com/H4nsie/dadep/assets/8566538/cec678ff-1f93-4da5-8da0-3b1f87323432">



5) **Place the script (dadep.lua) in your _domoticz/scripts/dzVents/scripts_ directory**

And have fun!


