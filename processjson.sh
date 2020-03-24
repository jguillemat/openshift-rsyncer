#!/bin/bash

#jq '.SOURCE_POD' info.json

#get value of dict
#jq -r '.SOURCE_PODS[]|"\(.POD_NAME) \(.POD_VOLUME_PATH)"' info.json

while read pod_name pod_path ; do
	echo "hola"
	echo "$pod_name"
	echo "$pod_path"
done < <(jq -r '.SOURCE_PODS[]|"\(.POD_NAME) \(.POD_VOLUME_PATH)"' info.json)
