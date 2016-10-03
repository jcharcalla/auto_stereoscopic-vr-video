START_TIME=$(date +%s)
echo ${START_TIME}
sleep 5
END_TIME=$(date +%s)
echo ${END_TIME}
RUN_TIME=$( echo "scale=2; ${END_TIME} - ${START_TIME}" | bc)
RUN_TIME=$( echo "scale=2; ${RUN_TIME} / 60" | bc)
RUN_MIN=$(( END_TIME - START_TIME ))
RUN_MIN=$(( RUN_MIN / 60 ))
echo ${RUN_TIME}
echo ${RUN_MIN}
