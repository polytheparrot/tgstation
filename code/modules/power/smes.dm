// the SMES
// stores power

/obj/machinery/power/smes
	name = "power storage unit"
	desc = "A high-capacity superconducting magnetic energy storage (SMES) unit."
	icon_state = "smes"
	density = 1
	anchored = 1
	use_power = 0
	var/output = 50000
	var/lastout = 0
	var/loaddemand = 0
	var/capacity = 5e6
	var/charge = 1e6
	var/charging = 0
	var/chargemode = 0
	var/chargecount = 0
	var/chargelevel = 50000
	var/online = 1
	var/n_tag = null
	var/obj/machinery/power/terminal/terminal = null
	var/max_input = 200000
	var/max_output = 200000


/obj/machinery/power/smes/New()
	..()
	component_parts = list()
	component_parts += new /obj/item/weapon/circuitboard/smes(null)
	component_parts += new /obj/item/weapon/cell/high(null)
	component_parts += new /obj/item/weapon/cell/high(null)
	component_parts += new /obj/item/weapon/cell/high(null)
	component_parts += new /obj/item/weapon/cell/high(null)
	component_parts += new /obj/item/weapon/cell/high(null)
	component_parts += new /obj/item/weapon/stock_parts/capacitor(null)
	component_parts += new /obj/item/weapon/cable_coil(null, 5)
	RefreshParts()
	spawn(5)
		dir_loop:
			for(var/d in cardinal)
				var/turf/T = get_step(src, d)
				for(var/obj/machinery/power/terminal/term in T)
					if(term && term.dir == turn(d, 180))
						terminal = term
						break dir_loop

		if(!terminal)
			stat |= BROKEN
			return
		terminal.master = src
		update_icon()
	return

/obj/machinery/power/smes/RefreshParts()
	var/IO = 0
	var/C = 0
	for(var/obj/item/weapon/stock_parts/capacitor/CP in component_parts)
		IO += CP.rating
	max_input = 200000 * IO
	max_output = 200000 * IO
	for(var/obj/item/weapon/cell/PC in component_parts)
		C += PC.maxcharge
	capacity = C / (15000) * 1e6

/obj/machinery/power/smes/attackby(obj/item/I, mob/user)
	if(default_deconstruction_screwdriver(user, "[initial(icon_state)]-o", initial(icon_state), I))
		update_icon()
		return

	if(default_change_direction_wrench(user, I))
		terminal = null
		var/turf/T = get_step(src, dir)
		for(var/obj/machinery/power/terminal/term in T)
			if(term && term.dir == turn(dir, 180))
				terminal = term
				terminal.master = src
				user << "<span class='notice'>Terminal found.</span>"
				break
		if(!terminal)
			for(var/obj/structure/cable/C in T)
				if(C.d1 == turn(dir, 180) || C.d2 == turn(dir, 180))
					terminal = C
					user << "<span class='notice'>Cable found.</span>"
					break
		if(!terminal)
			user << "<span class='alert'>No power source found.</span>"
			return
		stat &= ~BROKEN
		update_icon()
		return

	default_deconstruction_crowbar(I)

/obj/machinery/power/smes/Del()
	message_admins("SMES deleted at ([x],[y],[z] - <A HREF='?_src_=holder;adminplayerobservecoodjump=1;X=[x];Y=[y];Z=[z]'>JMP</a>)")
	log_game("SMES deleted at ([x],[y],[z])")
	investigate_log("<font color='red'>deleted</font> at ([x],[y],[z])","singulo")
	..()

/obj/machinery/power/smes/update_icon()
	overlays.Cut()
	if(stat & BROKEN)	return

	if(panel_open)
		overlays.Cut()
		return


	overlays += image('icons/obj/power.dmi', "smes-op[online]")

	if(charging)
		overlays += image('icons/obj/power.dmi', "smes-oc1")
	else
		if(chargemode)
			overlays += image('icons/obj/power.dmi', "smes-oc0")

	var/clevel = chargedisplay()
	if(clevel>0)
		overlays += image('icons/obj/power.dmi', "smes-og[clevel]")
	return


/obj/machinery/power/smes/proc/chargedisplay()
	return round(5.5*charge/capacity)

#define SMESRATE 0.05			// rate of internal charge to external power


/obj/machinery/power/smes/process()

	if(stat & BROKEN)	return

	//store machine state to see if we need to update the icon overlays
	var/last_disp = chargedisplay()
	var/last_chrg = charging
	var/last_onln = online

	if(terminal)
		var/excess = terminal.surplus()

		if(charging)
			if(excess >= 0)		// if there's power available, try to charge

				var/load = min((capacity-charge)/SMESRATE, chargelevel)		// charge at set rate, limited to spare capacity

				charge += load * SMESRATE	// increase the charge

				add_load(load)		// add the load to the terminal side network

			else					// if not enough capcity
				charging = 0		// stop charging
				chargecount  = 0

		else
			if(chargemode)
				if(chargecount > rand(3,6))
					charging = 1
					chargecount = 0

				if(excess > chargelevel)
					chargecount++
				else
					chargecount = 0
			else
				chargecount = 0

	if(online)		// if outputting
		lastout = min( charge/SMESRATE, output)		//limit output to that stored

		charge -= lastout*SMESRATE		// reduce the storage (may be recovered in /restore() if excessive)

		add_avail(lastout)				// add output to powernet (smes side)

		if(charge < 0.0001)
			online = 0					// stop output if charge falls to zero
			investigate_log("lost power and turned <font color='red'>off</font>","singulo")

	// only update icon if state changed
	if(last_disp != chargedisplay() || last_chrg != charging || last_onln != online)
		update_icon()

	updateDialog()
	return

// called after all power processes are finished
// restores charge level to smes if there was excess this ptick


/obj/machinery/power/smes/proc/restore()
	if(stat & BROKEN)
		return

	if(!online)
		loaddemand = 0
		return

	var/excess = powernet.netexcess		// this was how much wasn't used on the network last ptick, minus any removed by other SMESes

	excess = min(lastout, excess)				// clamp it to how much was actually output by this SMES last ptick

	excess = min((capacity-charge)/SMESRATE, excess)	// for safety, also limit recharge by space capacity of SMES (shouldn't happen)

	// now recharge this amount

	var/clev = chargedisplay()

	charge += excess * SMESRATE
	powernet.netexcess -= excess		// remove the excess from the powernet, so later SMESes don't try to use it

	loaddemand = lastout-excess

	if(clev != chargedisplay() )
		update_icon()
	return


/obj/machinery/power/smes/add_load(var/amount)
	if(terminal && terminal.powernet)
		terminal.powernet.newload += amount


/obj/machinery/power/smes/attack_ai(mob/user)
	add_fingerprint(user)
	if(stat & BROKEN) return
	interact(user)


/obj/machinery/power/smes/attack_hand(mob/user)
	add_fingerprint(user)
	if(stat & BROKEN) return
	interact(user)


/obj/machinery/power/smes/interact(mob/user)
	if(get_dist(src, user) > 1 && !istype(user, /mob/living/silicon/ai))
		user.unset_machine()
		user << browse(null, "window=smes")
		return

	user.set_machine(src)

	var/t = "<TT><B>SMES Power Storage Unit</B> [n_tag? "([n_tag])" : null]<HR><PRE>"

	t += "Stored capacity : [round(100.0*charge/capacity, 0.1)]%<BR><BR>"

	t += "Input: [charging ? "Charging" : "Not Charging"]    [chargemode ? "<B>Auto</B> <A href = '?src=\ref[src];cmode=1'>Off</A>" : "<A href = '?src=\ref[src];cmode=1'>Auto</A> <B>Off</B> "]<BR>"


	t += "Input level:  <A href = '?src=\ref[src];input=-4'>M</A> <A href = '?src=\ref[src];input=-3'>-</A> <A href = '?src=\ref[src];input=-2'>-</A> <A href = '?src=\ref[src];input=-1'>-</A> [add_lspace(chargelevel,5)] <A href = '?src=\ref[src];input=1'>+</A> <A href = '?src=\ref[src];input=2'>+</A> <A href = '?src=\ref[src];input=3'>+</A> <A href = '?src=\ref[src];input=4'>M</A><BR>"

	t += "<BR><BR>"

	t += "Output: [online ? "<B>Online</B> <A href = '?src=\ref[src];online=1'>Offline</A>" : "<A href = '?src=\ref[src];online=1'>Online</A> <B>Offline</B> "]<BR>"

	t += "Output level: <A href = '?src=\ref[src];output=-4'>M</A> <A href = '?src=\ref[src];output=-3'>-</A> <A href = '?src=\ref[src];output=-2'>-</A> <A href = '?src=\ref[src];output=-1'>-</A> [add_lspace(output,5)] <A href = '?src=\ref[src];output=1'>+</A> <A href = '?src=\ref[src];output=2'>+</A> <A href = '?src=\ref[src];output=3'>+</A> <A href = '?src=\ref[src];output=4'>M</A><BR>"

	t += "Output load: [round(loaddemand)] W<BR>"

	t += "<BR></PRE><HR><A href='?src=\ref[src];close=1'>Close</A>"

	t += "</TT>"
	user << browse(t, "window=smes;size=460x300")
	onclose(user, "smes")
	return


/obj/machinery/power/smes/Topic(href, href_list)
	if(..())
		return

//world << "[href] ; [href_list[href]]"

	if( href_list["close"] )
		usr << browse(null, "window=smes")
		usr.unset_machine()
		return

	else if( href_list["cmode"] )
		chargemode = !chargemode
		if(!chargemode)
			charging = 0
		investigate_log("input/output; [chargelevel>output?"<font color='green'>":"<font color='red'>"][chargelevel]/[output]</font> | Output-mode: [online?"<font color='green'>on</font>":"<font color='red'>off</font>"] | Input-mode: [chargemode?"<font color='green'>auto</font>":"<font color='red'>off</font>"] by [usr.key]","singulo")
		update_icon()

	else if( href_list["online"] )
		online = !online
		investigate_log("input/output; [chargelevel>output?"<font color='green'>":"<font color='red'>"][chargelevel]/[output]</font> | Output-mode: [online?"<font color='green'>on</font>":"<font color='red'>off</font>"] | Input-mode: [chargemode?"<font color='green'>auto</font>":"<font color='red'>off</font>"] by [usr.key]","singulo")
		update_icon()

	else if( href_list["input"] )

		var/i = text2num(href_list["input"])

		var/d = 0
		switch(i)
			if(-4)
				chargelevel = 0
			if(4)
				chargelevel = max_input		//30000

			if(1)
				d = 100
			if(-1)
				d = -100
			if(2)
				d = 1000
			if(-2)
				d = -1000
			if(3)
				d = 10000
			if(-3)
				d = -10000

		chargelevel += d
		chargelevel = max(0, min(max_input, chargelevel))	// clamp to range
		investigate_log("input/output; [chargelevel>output?"<font color='green'>":"<font color='red'>"][chargelevel]/[output]</font> | Output-mode: [online?"<font color='green'>on</font>":"<font color='red'>off</font>"] | Input-mode: [chargemode?"<font color='green'>auto</font>":"<font color='red'>off</font>"] by [usr.key]","singulo")
		src.updateUsrDialog()

	else if( href_list["output"] )

		var/i = text2num(href_list["output"])

		var/d = 0
		switch(i)
			if(-4)
				output = 0
			if(4)
				output = max_output		//30000

			if(1)
				d = 100
			if(-1)
				d = -100
			if(2)
				d = 1000
			if(-2)
				d = -1000
			if(3)
				d = 10000
			if(-3)
				d = -10000

		output += d
		output = max(0, min(max_output, output))	// clamp to range

		investigate_log("input/output; [chargelevel>output?"<font color='green'>":"<font color='red'>"][chargelevel]/[output]</font> | Output-mode: [online?"<font color='green'>on</font>":"<font color='red'>off</font>"] | Input-mode: [chargemode?"<font color='green'>auto</font>":"<font color='red'>off</font>"] by [usr.key]","singulo")
		src.updateUsrDialog()


/obj/machinery/power/smes/proc/ion_act()
	if(src.z == 1)
		if(prob(1)) //explosion
			world << "\red SMES explosion in [src.loc.loc]"
			for(var/mob/M in viewers(src))
				M.show_message("\red The [src.name] is making strange noises!", 3, "\red You hear sizzling electronics.", 2)
			sleep(10*pick(4,5,6,7,10,14))
			var/datum/effect/effect/system/harmless_smoke_spread/smoke = new /datum/effect/effect/system/harmless_smoke_spread()
			smoke.set_up(3, 0, src.loc)
			smoke.attach(src)
			smoke.start()
			explosion(src.loc, -1, 0, 1, 3, 0)
			del(src)
			return
		if(prob(15)) //Power drain
			world << "\red SMES power drain in [src.loc.loc]"
			var/datum/effect/effect/system/spark_spread/s = new /datum/effect/effect/system/spark_spread
			s.set_up(3, 1, src)
			s.start()
			if(prob(50))
				emp_act(1)
			else
				emp_act(2)
		if(prob(5)) //smoke only
			world << "\red SMES smoke in [src.loc.loc]"
			var/datum/effect/effect/system/harmless_smoke_spread/smoke = new /datum/effect/effect/system/harmless_smoke_spread()
			smoke.set_up(3, 0, src.loc)
			smoke.attach(src)
			smoke.start()


/obj/machinery/power/smes/emp_act(severity)
	online = 0
	charging = 0
	output = 0
	charge -= 1e6/severity
	if (charge < 0)
		charge = 0
	spawn(100)
		output = initial(output)
		charging = initial(charging)
		online = initial(online)
	..()



/obj/machinery/power/smes/magical
	name = "magical power storage unit"
	desc = "A high-capacity superconducting magnetic energy storage (SMES) unit. Magically produces power."
	process()
		capacity = INFINITY
		charge = INFINITY
		..()



/proc/rate_control(var/S, var/V, var/C, var/Min=1, var/Max=5, var/Limit=null)
	var/href = "<A href='?src=\ref[S];rate control=1;[V]"
	var/rate = "[href]=-[Max]'>-</A>[href]=-[Min]'>-</A> [(C?C : 0)] [href]=[Min]'>+</A>[href]=[Max]'>+</A>"
	if(Limit) return "[href]=-[Limit]'>-</A>"+rate+"[href]=[Limit]'>+</A>"
	return rate


#undef SMESRATE