#!/bin/bash
. /usr/local/fang/lib_head.sh

var_time="INIT_time"
var_event="INIT_event"
var_vpn_user="INIT_vpn_user"
var_vpn_ip="INIT_vpn_ip"
var_vpn_realip="INIT_vpn_realip"
var_vpn_device="INIT_vpn_device"
var_ad_line="INIT_ad_line"
var_ad_sta="C"
var_ad_ip="INIT_ad_ip"
var_ad_gw="INIT_ad_gw"
var_ad_device="INIT_ad_device"
var_connecttime=0
var_bytes_sent=0
var_bytes_rcvd=0
var_cmd="INIT_cmd"
var_cmd_arg="INIT_cmd_arg"

#eth2vpn=`f_getconf eth2vpn`
#ethGW=`cat /etc/sysconfig/network-scripts/ifcfg-${eth2vpn} | grep GATEWAY | cut -d = -f 2`
mode=`f_getconf mode`

# In: $1:aDSLlinenumber $2:sta $3:starttime $4:aDSLIP $5:device
# function: set adsl info to pool table
# Example: f_pool_write $adline $sta $date $localip $device 
f_pool_write(){
	local serial=`c2n ${1:5}`
	arr_nat[${serial}]=$2
	arr_starttime[${serial}]=$3
	arr_adip[${serial}]=$4
	arr_device[${serial}]=$5
	#f_log "ARR_nat[2]:${arr_nat[$serial]} [2]:$2 ARR_adip[4]:${arr_adip[$serial]} [4]:$4 ARR_time[3]:${arr_starttime[$serial]} [3]:$3 ARR_device[5]:${arr_device[$serial]} [5]:$5"
}


f_snap(){
	rm -f ${snap}
	echo "[`date`] SNAP" >> ${snap}
	echo "ADSL Status:" >> ${snap}
	local prepare=""
	for (( i = 1;i <= ${adline}; i++ )) do
	{
		echo "${wan}`n2c ${i}` ${arr_nat[$i]} ${arr_starttime[$i]} ${arr_adip[$i]} ${arr_device[$i]}" >> ${snap}
		if [[ ${arr_nat[$i]} -eq 9999 ]];then
			prepare=$prepare" "${wan}`n2c ${i}`
		fi
	}
	done
	echo "------------" >> ${snap}
	local inuse=`ip a | grep 1492 | wc -l`
	echo "Pool :${adline} Configured / ${inuse} Avaible" >> ${snap}
	if [[ -n ${prepare} ]];then
		echo "Lines in preparing: ${prepare}" >> ${snap}
	fi
	echo "VPN Status:" >> ${snap}
	cat ${vpnFile} >> ${snap}
	echo "------------" >> ${snap}
	echo "VPN : `cat ${vpnFile} | wc -l` users online." >> ${snap}
	echo "SNAT Status:" >> ${snap}
	iptables -L -t nat | grep SNAT >> ${snap}
	echo "--- END ---" >> ${snap}
	
}
#return with target AD's name like "adCjm0001"
f_searchad(){
	case $1 in
	1stfree)
		local serial=1
		while [[ ${arr_nat[${serial}]} -ne 0 &&  ${serial} -lt ${adline} ]];do
			serial=$((serial+1))
		done
		if [[ ${serial} -eq ${adline} ]];then
			return 1
		else
			echo ${wan}`n2c ${serial}`
		fi
				
	;;
	*)
		local vpnip=$1
		local adline=`cat ${vpnFile} | grep ${vpnip} | awk '{print $7}'`
		if [[ ${adline} ]];then
			echo ${adline}
		else 
			return 1
		fi

	esac
}

f_joint(){
	local vpnip=$1
	local ad_line=$2
	local serial=`c2n ${ad_line:5}`
	local fwdip=${arr_adip[${serial}]}
        f_disjoint ${vpnip}
	ip rule add from ${vpnip} table ${ad_line}
        iptables -t nat -A POSTROUTING -s ${vpnip} -j SNAT --to-source ${fwdip}
	if [[ $? -eq 0 ]];then
		f_log "[$var_event] VPN:${vpnip} --SNAT--> AD:${fwdip} ${ad_line} Load[${arr_nat[${serial}]}]"
	else
		f_log "[$var_event] VPN:${vpnip} --Fail--> AD:${fwdip}"
		return 1
	fi
}

#clear all rule and snat with arg [vpnip]
f_disjoint(){
	local vpnip=$1
	ip rule del from ${vpnip}  >/dev/null 2>&1
	local oldfwd=`iptables -t nat -L | grep ${vpnip} | cut -d : -f 2` 
	for each in ${oldfwd[*]} 
	do
		iptables -t nat -D POSTROUTING -s ${vpnip} -j SNAT --to-source ${each}
		f_log "[$var_event] VPN:${vpnip} <--DROP--> AD:${oldfwd}"
	done
	
}

# Send a sign of reconnect ad  to pool crond.
f_redial(){
	local ad_line=$1
	exec 5<>${pool_crond}
	echo "RESET ${ad_line}" >&5
	exec 5<&-
	exec 5>&-
}

f_vpn_up(){
	f_log "[$var_event] IQT:[$var_time] USER:${var_vpn_user} IP:${var_vpn_ip} DEV:${var_vpn_device} FROM:${var_vpn_realip}"
	local ad_line=`f_searchad 1stfree`
	local serial=`c2n ${ad_line:5}`
	f_joint ${var_vpn_ip} ${ad_line}
	echo "`now` ${var_vpn_user} ${var_vpn_ip} ${var_vpn_device} ${var_vpn_realip} --> ${ad_line} ${arr_adip[${serial}]} ${arr_device[${serial}]}" >> ${vpnFile}
	((arr_nat[${serial}]=arr_nat[${serial}]+1))
}

f_vpn_down(){
	f_log "[$var_event] IQT:[$var_time] ${var_vpn_user} with ${var_vpn_ip} from ${var_vpn_realip} last ${var_connecttime} second and sent ${var_bytes_sent} bytes and rcvd ${var_bytes_rcvd} bytes"
	local ad_line=`f_searchad ${var_vpn_ip}`
	local serial=`c2n ${ad_line:5}` 
	cmd="sed -i '/${var_vpn_ip}/d' ${vpnFile}"
	eval $cmd
	f_disjoint ${var_vpn_ip}
	if [[ ! ${arr_nat[${serial}]} -gt 1 ]];then
		arr_nat[${serial}]=9999
		f_redial $ad_line
	else
		((arr_nat[${serial}]=arr_nat[${serial}]-1))
	fi
	
}
	
f_ad_up(){
	f_pool_write ${var_ad_line} 0 ${var_time} ${var_ad_ip} ${var_ad_device}
	local serial=`c2n ${var_ad_line:5}`
        ip route flush table ${var_ad_line}
        ip route add default via ${var_ad_gw} dev ${var_ad_device} table ${var_ad_line}
	f_log "[$var_event] IQT:[$var_time] ${var_ad_line} ${var_ad_ip} ${var_ad_device} DefautRTGW:${var_ad_gw}"
	# when vpn's ad restart;
	if [[ ${vpnif} =~ ${var_ad_line} ]];then
		ip rule add from ${var_ad_ip} table ${var_ad_line}
		f_advpnstart
		[[ $? == 1 ]] && f_log "[ER] advpnstart failed."
	fi
}

f_ad_down(){
	f_log "[$var_event] IQT:[$var_time] ${var_ad_line} ${var_ad_ip} ${var_ad_device}"
	# when vpn's ad shutdown;
	if [[ ${vpnif} =~ ${var_ad_line} ]];then
		ip rule del from ${var_ad_ip}
	fi
}

#main
trap "exec 6>&-;exec 6<&-;rm -rf $pipe;exit 0" EXIT 
echo "${now} [FN] Started" >> ${logFile}
	rm -rf $pipe
	mkfifo $pipe
	exec 6<>$pipe

while read -u6 line;do
	req=($line)
	var_time=${req[0]}
	var_event=${req[1]}
	var_vpn_user=${req[2]}
	var_vpn_ip=${req[3]} 
	var_vpn_realip=${req[4]}
	var_vpn_device=${req[5]}
	var_ad_line=${req[2]}
	var_ad_ip=${req[3]}
	var_ad_gw=${req[5]}
	var_ad_device=${req[4]}
	var_connecttime=${req[5]}
	var_bytes_sent=${req[6]}
	var_bytes_rcvd=${req[7]}
	var_cmd=${req[2]}
	var_cmd_arg=${req[3]}
	case ${var_event} in
		quit)
			f_log "${mod} $0 Shutdown"
			break
		;;
		snap)
			f_snap
		;;
		UV)
			f_vpn_up
		;;
		UA)
			f_ad_up
		;;
		DV)
			f_vpn_down
		;;
		DA)
			f_ad_down
		;;
		*)
			f_log "[FN] Queue Content:${line} Event:${var_event} not defined."
	esac

done

f_log "[FN] Stopped"
rm -rf $pipe

