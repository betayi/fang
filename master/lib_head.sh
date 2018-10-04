#!/bin/bash
#write by yh

function f_getconf(){
	local name=$1
	if [[ $2 ]];then
		local conf=$2
	else
		local conf="/usr/local/fang/fang.conf"
	fi
	name=`sed '/^'${name}'=/!d;s/.*=//' ${conf}`
	echo ${name}
}


#eth2vpn=`f_getconf eth2vpn`
#ethGW=`cat /etc/sysconfig/network-scripts/ifcfg-${eth2vpn} | grep GATEWAY | cut -d = -f 2`
eth2bas=`f_getconf eth2bas`
wan="adChy"
#
vpnif="adChy0000"

SYS_DIR=`f_getconf dir`

curDay=`date +"%Y%m%d"`
now=`date -d today +%F_%T`

logFile="${SYS_DIR}/log/"`f_getconf log`
#connFile="${SYS_DIR}/log/conn.log"
#staFile="${SYS_DIR}/ad.status"
vpnFile="${SYS_DIR}/`f_getconf file_vpn`"
#standby="${SYS_DIR}/queue"
accFile="${SYS_DIR}/`f_getconf file_adsl`"

pipe="${SYS_DIR}/`f_getconf pipe_fang`"
pool_crond="${SYS_DIR}/`f_getconf pipe_cron`"
snap=`f_getconf file_snap`

adline=`sed '/^#.*\|^$/d' ${accFile} | wc -l`

function connct_type(){
if [[ -n $PEERNAME  ]]; then
 	echo "vp"
else
	echo "ad"
fi
}

function now(){
	echo `date -d today +%F_%T`
}
function n2c(){
        printf "%04d\n" $1
}

function c2n(){
        echo $1 | awk '{printf int($1)}'
}

function f_log(){
	local content=$1
	if [[ $2 ]];then
		local log=$2
	else
		local log=${logFile}
	fi
	echo "`now` ${content}" >> ${log}
}

# Usage:
# f_usrinfo V2CUSM0000001.P2@Cgz
function f_usrinfo(){
	local account=$1
	g_usr_type=`echo $account | cut -c -1`
	g_usr_level=`echo $account | cut -c 2`
	g_usr_group=`echo $account | cut -c 3-6`
	g_usr_serial=`echo $acount | cut -c 10-13`
	g_usr_phone=`echo $account | cut -c 3-13`
	g_usr_zone=`echo $account | cut -c 18-20`
	g_usr_agent=`echo $account | cut -c 15-16`
}

# Usage:
# f_usedip 192.168.1.1 cusm 
# Return:Found
function f_usedip(){
	local ip=$1
	local keyword=$2
	if [[ ! -n $3 ]];then
		local tfile=${vpnFile}
	else
		local tfile=$3
	fi
	local iplist=($(cat ${tfile} | grep ${keyword} | awk '{print $8}'))
	if echo "${iplist[@]}" | grep -w ${ip} &>/dev/null; then
		echo "Found"
	fi
}

f_getifip(){
        if [[ $1 ]];then
                local ifname=$1
        else
                local ifname="ppp0"
        fi
        local ip=$(ip add | grep ${ifname} | awk 'NR==2{print $2}')
        echo ${ip}
}

f_advpnstart(){
        #find domain ISP's Server address and to source route table
	local domainip=`nslookup members.3322.net | awk 'NR==7{print $2}'`
	ip rule del to ${domainip}
	ip rule add to ${domainip} table ${var_ad_line}
	#refresh the dynamic ip to domain with account
	local ddnip=`lynx -mime_header -auth=tianting123:tt123456 "http://members.3322.net/dyndns/update?system=dyndns&hostname=ttadsl.f3322.net" | awk 'END{print $2}'`
	local ifip=$(ifconfig|sed -n '/inet addr/s/^[^:]*:\([0-9.]\{7,15\}\) .*/\1/p')
	local finded=`echo ${ifip} | grep "${ddnip}"`
	if [[ ${finded} == 1 ]] ;then
		f_log "[FN] Dynamic IP Expired" 
		return 1
	fi 

	
        #更改PPTP listen IP
        sed -i '$d' /etc/pptpd.conf
        echo "listen ${var_ad_ip}" >> /etc/pptpd.conf
        f_log "[FN] /etc/pptpd.conf changed lisetn with ${var_ad_ip}"
	#更改xl2tp ipsec listen ip
        sed -i "18c listen-addr = ${var_ad_ip}" /etc/xl2tpd/xl2tpd.conf
	f_log "[FN] /etc/xl2tpd/xl2tpd.conf changed listen-addr with ${var_ad_ip}"
	sed -i "/left=/c\    left=${var_ad_ip}" /etc/ipsec.d/ppp0.conf
	sed -i "/listen=/c\    listen=${var_ad_ip}" /etc/ipsec.conf
	f_log "[FN] /etc/ipsec.d/ppp0.conf & /etc/ipsec.conf changed left/listen with ${var_ad_ip}"
	# restart vpn service
	service pptpd restart
	service ipsec restart
	service xl2tpd restart
	return 0
}

f_advpnstop(){
	ifdown ${vpnif}
}
