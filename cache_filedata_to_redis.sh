#!/bin/bash

if [ $# == 1 ];then
    file_date=$1
else
    file_date=`date -d "-9hour" +"%Y-%m-%d"`
fi

echo '==='${file_date}

log_path='/mnt/logs/cache_log/'
if [ ! -d ${log_path} ]; then
  mkdir ${log_path}
fi

#write log function
WriteLog()
{
    TIME=`date +%T`
    echo "[ ${TIME} ] : ${1} " >> "${log_path}${file_date}.log"
}


file_path='/mnt/file/'
if [ ! -d ${file_path} ]; then
  mkdir ${file_path}
fi
data_file=${file_path}'cache_data_'${file_date}'.txt'

#check file
if [ ! -f ${data_file} ]; then
	echo '==='${data_file}' is invalid==='
	WriteLog '==='${data_file}' is invalid==='
	
	exit 1
fi

#unix to dos
todos ${data_file}

#DB Number
db=xxxx

#flush db
redis-cli -p xxxx -n ${db} FLUSHDB

#to redis
cat ${data_file} | redis-cli -p xxxx -n ${db} --pipe

#del local file
find $file_path -mtime +3 -exec rm -rf {} \;
find $log_path -mtime +3 -exec rm -rf {} \;
