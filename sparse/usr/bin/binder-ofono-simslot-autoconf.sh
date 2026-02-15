#!/bin/bash

# Script managed by a systemd service to autoconfig the sime slot
# Version: 0.0.1
#
# Copyright (c) 2025 Berbascum <berbascum@ticv.cat>
# All rights reserved.
# Licensed under the BSD 3-Clause License.
#
# See the LICENSE file in the project root
#
# Upstream-Name: binder-ofono-simslot-autoconf
# Source: https://github.com/berbascum/binder-ofono-simslot-autoconf


## Some related check documentation
# gdbus introspect --system --dest org.freedesktop.ModemManager1 --object-path /org/freedesktop/ModemManager1/Modem/0 | grep PrimarySimSlot
  #interface org.freedesktop.ModemManager1.Modem
     # properties:
       # readonly u PrimarySimSlot = 0;

# gdbus introspect --system --dest org.freedesktop.ModemManager1 --object-path /org/freedesktop/ModemManager1/Modem/0 | grep "PrimarySimSlot = " | awk '{print $NF}' | grep ';' | sed 's/;//g'

#qmicli -d qrtr://0 --uim-get-card-status
#### Primary GW:   slot '1', application '1'
#### Secondary GW: slot '2', application '1'

## Initial checks
LOGFILE="/var/log/binder-ofono-simslot-autoconf.log"
qrtr-lookup | grep "MODEM:CMD" > ${LOGFILE} 2>&1
qmicli -d qrtr://0 --uim-get-card-status >> ${LOGFILE} 2>&1

write_binder_conf_sim_single_slot() {
    echo "Configuring binder.conf for sim slot${slot_num}"
    sed "s/ExpectSlots = slot./ExpectSlots = slot${slot_num}/g" -i /etc/ofono/binder.conf
    sed "s/^\[slot.\]/[slot${slot_num}]/g" -i /etc/ofono/binder.conf
    sed "s/^slot = ./slot = ${stack_num}/g" -i /etc/ofono/binder.conf
}

check_binder_conf_sim_single_slot() {
    echo "sim_mode = ${sim_mode} on slot${slot_num}" | tee -a ${LOGFILE}

    ## If slot with sim matches in binder.conf, not reconfigure
    if cat /etc/ofono/binder.conf | grep "slot${slot_num}"; then
	echo "Correct slot already configured in binder.conf" | tee -a ${LOGFILE}
        exit 0
    else
	write_binder_conf_sim_single_slot
        ## Restart ofono to reload slot changes
        sleep 1
        systemctl restart ofono.service
        sleep 1
        systemctl restart ModemManager.service
    fi
}

## Check slots for sim
slot1_has_sim=$(qmicli -d qrtr://0 --uim-get-card-status | grep "Primary GW" | grep "slot '1',")
slot2_has_sim=$(qmicli -d qrtr://0 --uim-get-card-status | grep "Secondary GW" | grep "slot '2',")

echo "slot1_has_sim = $slot1_has_sim" | tee -a ${LOGFILE}
echo "slot2_has_sim = $slot2_has_sim" | tee -a ${LOGFILE}


## TODO: dual-sim
if [ -n "${slot1_has_sim}" ] && [ -n "${slot2_has_sim}" ]; then
    sim_mode="dual-sim"
    #slot_num="1"
    #stack_num="0"
    echo "sim_mode = $sim_mode" | tee -a ${LOGFILE}
    #fn_set_single_sim_slot
    echo "Dual sim not supported. Skipping changes..." | tee -a ${LOGFILE}

    exit 0

## single-sim
elif [ -n "${slot1_has_sim}" ]; then
    sim_mode="single"
    slot_num="1"
    stack_num="0"
    check_binder_conf_sim_single_slot
elif [ -n "${slot2_has_sim}" ]; then
    sim_mode="single"
    slot_num="2"
    stack_num="1"
    check_binder_conf_sim_single_slot
else
    sim_mode="unknown"
    echo "sim_mode = ${sim_mode}: No sim detected" | tee -a ${LOGFILE}
    exit 0
fi

exit 0
