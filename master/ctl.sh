#!/bin/bash
. /usr/local/fang/lib_head.sh
f_fangstart(){
	/usr/local/fang/fang.sh &
	echo "Fang Service started!"
	iptables -t nat --flush
	echo "Pool Dialing ..."
	for (( i = 1;i <= ${adline}; i++ )) do
        {
               # sleep ${i}
                local serial=$(n2c $i)
                ifup ${wan}${serial}
                if [[ $? -eq 0 ]] ; then
                        echo "${wan}${serial} Ready " 
                else
                        echo "${wan}${serial} Wrong" 
                fi
        } &
        done
}	

f_fangstop(){

	echo "Pool Closing ..."
        for (( i = 1;i <= ${adline}; i++ )) do
        {
                #sleep ${i}
                local serial=$(n2c $i)
                ifdown ${wan}${serial}
                if [[ $? -eq 0 ]] ; then
                        echo "${wan}${serial} Closed " 
                else
                        echo "${wan}${serial} Wrong" 
                fi
        } &
        done	
	#sleep ${adline}
	echo "0 quit" > $pipe
}

f_crondstop(){
	echo "quit" > $pool_crond
}

f_crondstart(){
	/usr/local/fang/crond.sh &
	echo "Crond Service started."
}
f_vpnstart(){
	service $1 start
	echo `ps -eo pid,comm | grep $1 | awk '{print $1}'`
}

f_vpnstop(){
	service $1 stop
	local pid=`ps -eo pid,comm | grep $1 | awk '{print $1}'`
	if [[ $pid ]]; then
		kill $pid
	fi
}

f_kickuser(){
	echo "KICK $1" > ${pool_crond}
}
f_changepw(){
	local account=$1
	if [[ $2 ]];then
		local passwd=$2
	else
		local passwd=$RANDOM
	fi
	local filename="/etc/ppp/chap-secrets"
	#awk "\$1 ~ /${account}/{\$3=${passwd};}1" ${filename} 1<>${filename}
	grep ${account} ${filename}
	if [ $? -ne 0 ];then
		echo "No account ${account} , check it again"
		return 1
	else
		sed -i "s/${account} l2tpd .*/${account} l2tpd ${passwd} \*/g" $filename
		sed -i "s/${account} pptpd .*/${account} pptpd ${passwd} \*/g" $filename
		f_log "[CT] ${account} PW-> ${passwd} by ${USER}"
		echo " V V V V V V V V V V V V "
		grep ${account} ${filename}
		return 0
	fi
}
f_service(){
	local service=`ps -eo pid,comm,user,lstart,etime | grep $1`
	echo ${service}
}

f_snap(){
	local df=($(f_service fang.sh))
	local dc=($(f_service crond.sh))
	local dp=($(f_service pptpd))
	local dx=($(f_service xl2tpd))
	
	if [[ ! -n ${df[*]} ]];then
		df[0]="Not Running"
	fi
	if [[ ! -n ${dc[*]} ]];then
		dc[0]="Not Running"
	fi
	local domainip=`nslookup ttadsl.f3322.net | grep -A2 Name: | awk 'NR==2{print $2}'`
	local state_pptp=`netstat -ano | grep :1723 | awk '{print $4}'`
	local state_l2tp=`netstat -ano | grep :1701 | awk '{print $4}'`
	echo "0 snap" > $pipe
	clear
	echo "Data prepareing..."
	sleep 1
	echo "----------------------------------------------"
	echo "[ DomainName Resolved IP is 	              ${domainip} ]"
	echo ""
	echo "Core PID:[${df[0]}] Last:[${df[8]}] By:[${df[2]}]"
	echo "Cron PID:[${dc[0]}] Last:[${dc[8]}] By:[${dc[2]}]" 
	echo "PPTP PID:[${dp[0]}] Last:[${dp[8]}] By:[${dp[2]}] @ ${state_pptp}" 
	echo "L2TP PID:[${dx[0]}] Last:[${dx[8]}] By:[${dx[2]}] @ ${state_l2tp}" 
	echo "----------------------------------------------"
	cat $snap
}

function f_adinit(){
        if [ ! -f ${accFile} ];then
                echo "${accFile} load failed,check it first"
                exit 1
        fi
	sed -i '/#ADSL_ACCOUNT_LIST/,$d' /etc/ppp/chap-secrets 
	echo "#ADSL_ACCOUNT_LIST 注意！重要！！自动生成，不可以手动修改下述任何内容！" >> /etc/ppp/chap-secrets
        local accn=($(sed '/^#.*\|^$/d' ${accFile} | awk -F ":" '{print $1}'))
        local pass=($(sed '/^#.*\|^$/d' ${accFile} | awk -F ":" '{print $2}'))
        local totalline=`sed '/^#.*\|^$/d' ${accFile} | wc -l`

        for (( i =1;i <= ${totalline}; i++)) do
        {
                cat >> /etc/ppp/chap-secrets<<EOF
"${accn[$i-1]}"        *       "${pass[$i-1]}"
EOF
                echo "secrets write success."   

        }
        done
}

f_list(){
	case $1 in
		ip)
			cat ${logFile} | grep "UA" | awk '{print $5}' | sort | uniq -c | sort -k 1r
		;;
		*)
			echo "Not defined"
	esac
}
# main
case $1 in
	s)
		f_snap
	;;	
	stop)
		f_vpnstop pptpd
		f_vpnstop ipsec
		f_vpnstop xl2tpd
		f_advpnstop
		sleep 1
		f_fangstop
		f_crondstop
	;;
	start)
		f_crondstart
		f_fangstart
		sleep 20
		echo "Waiting for adup"
		ifup ${vpnif}
		f_snap
	;;
	kick)
		f_kickuser $2
	;;
	adini)
		f_adinit
	;;
	chpw)
		f_changepw $2 $3
	;;
	list)
		f_list $2
	;;
	*)
	echo "Usage: $0 [s|stop|start|kick {vpnuser|vpnip|vpnfromip|adip|adline}|chpw {vpnuser}"
esac
