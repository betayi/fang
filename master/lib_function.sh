#!/bin/bash
#write by yh

. /usr/local/fang/lib_head.sh

function n2c(){
	printf "%04d\n" $1
}

function c2n(){
	echo $1 | awk '{printf int($1)}'
}
	

function clearveth(){
        local old_veth=`ip link | grep veth | awk '{print $2}' | cut -d "@" -f 1`
        for each in ${old_veth[*]}
        do
        {
                ip link del ${each} 2>/dev/null
		if [ $? -eq 0 ];then
			echo "${each} clear success."
		else
			echo "${each} clear failed."
		fi
        }
        done
}

function setveth()
{
        local serial=$(n2c $1)
        ip link add link $eth2bas dev veth${serial} type macvlan
        ip link set veth${serial} up
        if [ $? -eq 0 ];then
                echo "veth${serial} set success."
        else
                echo "veth${serial} set failed."
                exit 1
        fi
}

function cleartable(){
	sed -i '10,$d' /etc/iproute2/rt_tables
        if [ $? -eq 0 ];then
                echo "rt_tables clear success."
        else
                echo "rt_tables clear failed."
                exit 1
        fi
}

function settable()
{
	local serial=$(n2c $1)
	echo "$1 ${wan}${serial}" >> /etc/iproute2/rt_tables
}

function clearadacc(){
	sed -i '/#ADSL_ACCOUNT_LIST/,$d' /etc/ppp/chap-secrets
	echo "#ADSL_ACCOUNT_LIST : Do Not modify this list by manaul." >> /etc/ppp/chap-secrets
}

function wansetup(){
        if [ ! -f ${accFile} ];then
		echo "${accFile} load failed,check it first"
		exit 1
	fi

	clearveth
        cleartable
        clearadacc
 
	local accn=($(sed '/^#.*\|^$/d' ${accFile} | awk -F ":" '{print $1}'))
        local pass=($(sed '/^#.*\|^$/d' ${accFile} | awk -F ":" '{print $2}'))
	local totalline=`sed '/^#.*\|^$/d' ${accFile} | wc -l`	
        
	for (( i =1;i <= ${totalline}; i++)) do
        {
		local serial=$(n2c ${i})
		setveth ${i}
		settable ${i}
                [ -f /etc/sysconfig/network-scripts/ifcfg-${wan}${serial} ] && rm -f /etc/sysconfig/network-scripts/ifcfg-${wan}${serial}
        	cat > /etc/sysconfig/network-scripts/ifcfg-${wan}${serial}<<EOF
USERCTL=yes
BOOTPROTO=dialup
NAME=DSLppp${serial}
DEVICE=${wan}${serial}
TYPE=xDSL
ONBOOT=no
PIDFILE=/var/run/pppoe-${wan}${serial}.pid
FIREWALL=NONE
PING=.
PPPOE_TIMEOUT=80
LCP_FAILURE=3
LCP_INTERVAL=20
CLAMPMSS=1412
CONNECT_POLL=6
CONNECT_TIMEOUT=60
DEFROUTE=no
SYNCHRONOUS=no
ETH=veth${serial}
PROVIDER=DSLppp${serial}
USER=${accn[$i-1]}
PEERDNS=no
DEMAND=no
EOF
		[ ! -z /etc/sysconfig/network-scripts/ifcfg-${wan}${serial} ] && echo "ifcfg-${wan}${serial} success." 
        	cat >> /etc/ppp/chap-secrets<<EOF
"${accn[$i-1]}"        *       "${pass[$i-1]}"
EOF
		echo "secrets write success."	

        }
        done
}

# Added by YH 2018-4-10
# rip:get a random ip by args
# Usage: rip "10 10" "0 1"
# Result: 10.0-1.*.*
function rip(){
	local aa=$1
	local bb=$2
	local cc=$3
	local dd=$4
	aa=${aa:="1 254"}
	bb=${bb:="1 254"}
	cc=${cc:="1 254"}
	dd=${dd:="1 254"}
	local a=`seq $aa | while read i;do echo "$i $RANDOM";done | sort -k2n | cut -d" " -f1 | tail -1`
	local b=`seq $bb | while read i;do echo "$i $RANDOM";done | sort -k2n | cut -d" " -f1 | tail -1`
	local c=`seq $cc | while read i;do echo "$i $RANDOM";done | sort -k2n | cut -d" " -f1 | tail -1`
	local d=`seq $dd | while read i;do echo "$i $RANDOM";done | sort -k2n | cut -d" " -f1 | tail -1`
	echo "$a.$b.$c.$d"
}

