#!/usr/bin/env bash

while :
do
    declare -a Operations=('buy' 'sell' 'fail' 'buy' 'sell' 'buy' 'sell' );

    operationName=`echo ${Operations[$[ RANDOM % ${#Operations[@]} ]]}`

    echo "Calling operation $operationName"

    curl -k $ORDERMGR/$operationName

    sleep 1.5
done

