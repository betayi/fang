#!/bin/bash
. /usr/local/fang/lib_head.sh

mod="[CR]"

f_service(){
        local service=`ps -eo pid,comm,user,lstart,etime | grep $1`
        echo ${service}
}

trap "exec 969>&-;exec 969<&-;exit 0" EXIT 
f_log "${mod} Service Start"
if [[ -p ${pool_crond} ]];then
	rm -rf ${pool_crond}
fi
mkfifo ${pool_crond}
exec 969<>${pool_crond}

while read -u969 line;do
	req=($line)
	cmd=${req[0]}
	body=${req[1]}
	
	f_log "${mod} ${cmd} ${body}"
	
	case $cmd in
		quit)
			f_log "${mod} $0 Shutdown"
			break
		;;
		RESET)
		if [[ $body ]];then
			kill -INT `cat /var/run/ppp-${body}.pid | awk 'NR==1'`
		fi
		;;
		KICK)
		if [[ $body ]];then
			vpnpid=`cat ${vpnFile} | grep ${body} | awk '{print $4}'`
			for each in ${vpnpid[*]};do
				kill -INT `cat /var/run/${each}.pid`
			done
 
		fi
		;;
		DETECT)
		if [[ $body ]];then
			pid=($(f_service ${body}))
			if [[ ! -n ${pid[0]} ]];then
				f_log "$body Not Running"
				echo "START ${body}" >&969
			else
				f_log "$body Running PID ${pid}"
			fi
			
		fi
		;;
		START)
			`${SYS_DIR}/${body} &`
			echo "DETECT ${body}" >&969
		;;
		*)
		f_log "Unknow REQ: ${line}"	
	esac
done

f_log "${mod} Service Stop"
rm -rf ${pool_crond}
