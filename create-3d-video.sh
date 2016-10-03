#!/bin/bash

#
# Author: Jason Charcalla 10-02-2016
#
# About:
# Create a 3d video the hard way by dumping all the frames to images. Videos can be
# synchronized with each other by analyzing the audio amplitude in the 1st 10 seconds.
# Control point detection and conversion them to equirectangular format with hugin
# and then joining them together in a top bottom stereoscopic video with ffmpeg.
#
# Changelog:
#
#

print_usage() {
        cat <<EOF
#
# equirectangular stereoscopic video creator
#
# This script extracts frames from left right video sources and then aligns 
# and outputs them as equirectangular images with Hugin. Once completed it
# merges them back together in a top / bottom sterescopic vide with ffmpeg.
#
# Requred packages are..
#	hugin
#	ffmpeg
#	bc
#	sox
#   # sift
#
#
# Jason Charcalla 09272016
# Usage:
#
# All of the folowing options are required 
#
# -K Image resolution. 2k,4k,5k,8k (translates to 16x9 2560x1440,3840x2160,5120x2880,5120x4320)
# -F Frame rate 15,24,25,30,48,50,60 (This will be ignored for now)
# -l Left video file
# -r Right video file
# -I Input path containing image files (This will create a tmp dir in here)
# -O Output path and filename for the resulting video
# -f Temp file format. This script currently dumps all video frames to temp images.
#    These can be either jpg or uncompressed tif. keep in mind the tiffs are large.
#    jpg,tif
# -V Camera feild of view. Kodak sp360 4k = 235. used for creating pto file.
# -Y yaw - This should rotate the camera left and right. I find I need to use 180
#    with my kodak sp3604k.
# -P pitch - same as above but sometimes 0
# -R Roll - same as above but sometimes 0
# -p PTO file, if none specified we will try to create one. This oprion is useful if 
#    you had to tweak a pto file created with debug mode.
# -s Syncronize video with loud sound detections, aka clap in the 1st 10 seconds after
#    camera start. y/n, y is default
# -d debug, Test mode, 1st frame only for verification. create pto for visual inspection.
#    This is helpful as alignent of the horizon is key in stereoscopic video. 
# -D Delay start, this is to trim the 1st x seconds from both clips. This way you can 
#    clap or make some loud noise for use in 1st 10 seconds for syncronization.
# -m Manual frame sync offset, 
# -c Control point detection method, sift or cpfind. NOTE: this only works if you 
#    manually modify the docker file to build sift. Default is cpfind.

# Possible future features features
# -n Thread count, used for ffmpeg and a few others. Don't set higher than physical cores.
# -C Composite overlay image
# -f Temporary file format ?? maybe jpg or tif

#
# ./create-3d-video.sh -K 4k -F 30 -V 235 -l left.MP4 -r right.MP4 -Y 180 -P 30 -R 0 -I /mnt/3d_wedding_test/ -O /mnt/3d_wedding_test/3
d_wedding_test.mp4
#
# Docker usage:
# This container requires a rw mount point which contains images
#
# Produce a slide show
####sudo docker run -v /mnt/:/mnt timelapse.1 -R 2k -F 15 -D 10 -C black -T 3 -I /mnt/test01/ -O /mnt/test.mp4 -E JPG
# Produce a timelapse
####sudo docker run -v /mnt/:/mnt timelapse.1 -R 2k -F 15 -D 0 -C black -T 0 -I /mnt/test01/ -O /mnt/test.mp4 -E JPG
#
EOF
exit 1
}

# Defaults
SYNC_VID="1"
PTO_FILE="working.pto"
DELAY_TIME="2"
DEBUG="n"
CP_DETECTOR="cpfind"
# Defaults to adjust yaw, pitch, and roll of hugin canvas.
# I typically seem to have to adjust yaw 180 degrees
MOD_YAW="180"
MOD_PITCH="0"
MOD_ROLL="0"
THREADS="3"
USER_PTO="0"
# temp directories
WORK_PATH="${IN_PATH}tmp/"
LEFT_TMP="${IN_PATH}tmp/left/"
RIGHT_TMP="${IN_PATH}tmp/right/"
# we should check that /dev/shm isnt full!
TIF_TMP="/dev/shm/3d_temp/"
# Location of ffmpeg binary, I think were going to need to use the static build in the container.
FFMPEG_BIN="/mnt/ffmpeg/ffmpeg-3.1.3-64bit-static/ffmpeg"
SIFT_BIN="/"
FRAME_CUR="0"
# some timing variables
START_TIME=$(date +%s)

if [ "$#" -le 4 ]; then
            print_usage
fi

while getopts h?K:F:r:l:f:V:Y:P:R:I:O:p:s:d:m:c: arg ; do
        case $arg in
        K) IMG_RESOLUTION=$OPTARG;;
        F) FRAME_RATE=$OPTARG;;
        r) RIGHT_VID=$OPTARG;;
        l) LEFT_VID=$OPTARG;;
	f) TMP_FRMT=$OPTARG;;
	V) CAM_FOV=$OPTARG;;
	Y) MOD_YAW=$OPTARG;;
	P) MOD_PITCH=$OPTARG;;
	R) MOD_ROLL=$OPTARG;;
	p) PTO_FILE=$OPTARG
	USER_PTO="1";;
	s) if [ $OPTARG == "n" ]
	    then
	      echo "Video sync disabled"	
	      SYNC_VID="0"
      	    else
	      echo "Error: Invalid -s option. Accept y/n only."
	      exit 1;
	    fi;;
    	D) if [ ${SYNC_VID} -eq "1" ]
    	   then 
       		if [ $OPTARG == "n" ]
		    then
		      DELAY_VID="0"
		    elif [ $OPTARG == "y" ]
		    then
		      DELAY_VID="1"
		    else
		      echo "Error: Invalid -D option. Accept y/n only."
		      exit 1;
		    fi
		   else
		     echo "Error: -D requires -s y"
		     exit 1;
		   fi;;
        I) IN_PATH=$OPTARG;;
        O) OUTPUT=$OPTARG;;
        d) DEBUG=$OPTARG;;
        c) CP_DETECTOR=$OPTARG;;
	m) FRAME_ADJ=$OPTARG
	   MAN_ADJ="1";;
        h|\?) print_usage; exit ;;
        esac
done


# Maybe I should count frames of both videos and use the lesser, also how to deal video sync of l/r.
LFRAME_COUNT=$(ffprobe -select_streams v -show_streams ${LEFT_VID} 2>/dev/null | grep nb_frames | cut -d "=" -f2)
RFRAME_COUNT=$(ffprobe -select_streams v -show_streams ${RIGHT_VID} 2>/dev/null | grep nb_frames | cut -d "=" -f2)

FRAME_RATE_ORIG=$(ffprobe -select_streams v -show_streams ${LEFT_VID} 2>/dev/null | grep avg_frame_rate | cut -d "=" -f2)
# Maths to calculate real frame rate
FRAME_RATE=$(echo "scale=2; ${FRAME_RATE_ORIG}" | bc)

# Calculate ms per frame
FRAME_MS=$(echo "scale=2; 1 / ${FRAME_RATE}" | bc)

# Set resolutions, final output will be 1:1 made up of top bottom
# 2:1 videos
#
# NOTE: Hugin requies a 2:1 aspect ratio because 180 is half of 360
case $IMG_RESOLUTION in
        2k) H_RES=2560
            V_RES=1440
	    HUGIN_V_RES=1280
            BIT_RATE="20M";;
        4k) H_RES=3840
            V_RES=2160
	    HUGIN_V_RES=1920
            BIT_RATE="35M";;
        5k) H_RES=5120
            V_RES=2880
            HUGIN_V_RES=2560
            BIT_RATE="50M";;
        8k) H_RES=7680
            V_RES=4320
	    HUGIN_V_RES=3840
            BIT_RATE="90M";;
esac

# Not sure if I need to use this now that I'm doing a single frame at a time
#case $TMP_FRMT in
#	jpg) IMG_OPT="-qscale:v 2";;
#	tif) IMG_OPT="-compression_algo deflate";;
#esac


# Make temp dirs for eyes
mkdir -p ${WORK_PATH}
mkdir ${LEFT_TMP}
mkdir ${RIGHT_TMP}
mkdir -p ${TIF_TMP}

##
## detect any offset in the 2 videos and adjust accordingly
##
## This is experimental and based on audio
## We will find the loudest point in the 1st 2 seconds of audio 
## from both videos and then subtract frames from the video that starts 1st
##
if [ "${SYNC_VID}" -eq "1" ]
then
	echo "#### Calculating video offsets #####"

	# Create low sample rate waves of the 20 seconds ofr each video
	echo "creating wav files"
	${FFMPEG_BIN} -ss 0 -i ${LEFT_VID} -t 10 -ar 22000 -ac 1 -acodec pcm_u8 ${WORK_PATH}left-eye.wav
	${FFMPEG_BIN} -ss 0 -i ${RIGHT_VID} -t 10 -ar 22000 -ac 1 -acodec pcm_u8 ${WORK_PATH}right-eye.wav

	# Convert wav's to needed dat files.
	# debug testing stuff
	echo "creating dat files"
	sox ${WORK_PATH}left-eye.wav ${WORK_PATH}left-eye.dat
	sox ${WORK_PATH}right-eye.wav ${WORK_PATH}right-eye.dat

	echo "sorting dat files"
	sort -k2 -n ${WORK_PATH}left-eye.dat | tail -n1
	sort -k2 -n ${WORK_PATH}right-eye.dat | tail -n1

	# Subtract right from left
	echo "doing some maths"
	LR_MINUS=$(echo "scale=3; $(sort -k2 -n ${WORK_PATH}left-eye.dat | tail -n1 | awk '{print $1}') - $(sort -k2 -n ${WORK_PATH}right-eye.dat | tail -n1 | awk '{print $1}')" | bc)
	echo "LR_MINUS: ${LR_MINUS}"
	# subtract left from right
	RL_MINUS=$(echo "scale=3; $(sort -k2 -n ${WORK_PATH}right-eye.dat | tail -n1 | awk '{print $1}') - $(sort -k2 -n ${WORK_PATH}left-eye.dat | tail -n1 | awk '{print $1}')" | bc)
	echo "RL_MINUS: ${RL_MINUS}"
	# determine which number isnt negative and call it MS_DIFF
	#echo "${LR_MINUS}" | grep "-" >/dev/null 2>&1 || MS_DIFF=${LR_MINUS} 
	#echo "${RL_MINUS}" | grep "-" >/dev/null 2>&1 || MS_DIFF=${RL_MINUS}

	echo "${LR_MINUS}" | grep "-" >/dev/null 2>&1 || NON_NEG="L"
	echo "${RL_MINUS}" | grep "-" >/dev/null 2>&1 || NON_NEG="R"

	if [ "${NON_NEG}" == "L" ]
  	  then
	    DIFF_MS=${LR_MINUS}
	elif [ "${NON_NEG}" == "R" ]
  	  then
	    DIFF_MS=${RL_MINUS}
	fi

	# Calculate difference in frames
	FRAME_DIFF=$(echo "${DIFF_MS} / ${FRAME_MS}" | bc)

	if [ "${NON_NEG}" == "L" ]
  	  then
		# advance things for seeking by frame number. Seems to take way longer than ffmpeg -ss
    	LFRAME_ADV=${FRAME_DIFF}
		RFRAME_ADV="0" 
		FRAME_COUNT=$(( LFRAME_COUNT - FRAME_DIFF ))
		# Set offset in milliseconds for use with ffmpeg -ss for only the side that need advanced
		LVID_MS=${DIFF_MS}
		RVID_MS="0"
		# set the audio to the non trimmed video
		AUDIO_SOURCE=${RIGHT_VID}
	elif [ "${NON_NEG}" == "R" ]
  	  then
		# advance things for seeking by frame number. Seems to take way longer than ffmpeg -ss
        LFRAME_ADV="0"
        RFRAME_ADV=${FRAME_DIFF}
		FRAME_COUNT=$(( RFRAME_COUNT - FRAME_DIFF ))
        # Set offset in milliseconds for use with ffmpeg -ss for only the side that need advanced
        LVID_MS="0"
        RVID_MS=${DIFF_MS}
	# set the audio to the non trimmed video
	AUDIO_SOURCE=${LEFT_VID}
	fi
	# This should add a delay in both videos so they start after the synchronization sound.	
	if [ ${DELAY_VID} -eq "1" ]
		then
			DELAY_TIME=$( echo "scale=2; ${DIFF_MS} + ${DELAY_TIME}" | bc )
			# Convert milliseconds to frames.
			DELAY_FRAMES=$( echo "${DELAY_TIME} * ${FRAME_RATE}" | bc )
			LFRAME_ADV=$( echo "scale=2; ${LFRAME_ADV} + ${DELAY_FRAMES}" | bc )
			RFRAME_ADV=$( echo "scale=2; ${RFRAME_ADV} + ${DELAY_FRAME}" | bc )
			# Set the -ss option for the audio merger. Not this needs a prepended space
			SS_OPTION=" -ss ${DELAY_TIME}"
	fi
else	
	if [ ${MAN_ADJ} -eq "1" ]
	then
		echo "Manual frame adjustment engadged."
		# determin what eye we want to adjust
		echo "${FRAME_ADJ}" | grep "L" >/dev/null 2>&1 && EYE_ADJ="L"
		echo "${FRAME_ADJ}" | grep "R" >/dev/null 2>&1 && EYE_ADJ="R"
		# get the amount of frames
		echo "FRAME_ADJ: ${FRAME_ADJ}"
		FRAME_DIFF=$(echo "${FRAME_ADJ}" | cut -c 2)
		DIFF_MS=$(echo "${FRAME_DIFF} * ${FRAME_MS}" | bc )
		if [ ${EYE_ADJ} == "L" ]
		then
			echo "Advancing left eye frames"
		        RFRAME_ADV="0"
		        RVID_MS="0"
			LFRAME_ADV=${FRAME_DIFF}
			LVID_MS=${DIFF_MS}
                	FRAME_COUNT=$(( LFRAME_COUNT - FRAME_DIFF ))
		        # set the audio to the non trimmed video
		        AUDIO_SOURCE=${RIGHT_VID}
		elif [ ${EYE_ADJ} == "R" ]
		then
                        echo "Advancing right eye frames"
                        LFRAME_ADV="0"
                        LVID_MS="0"
                        RFRAME_ADV=${FRAME_DIFF}
                        RVID_MS=${DIFF_MS}
                	FRAME_COUNT=$(( RFRAME_COUNT - FRAME_DIFF ))
		        # set the audio to the non trimmed video
		        AUDIO_SOURCE=${LEFT_VID}
		fi
	else	
		echo "Not synchronizing videos."
		RFRAME_ADV="0"
		RVID_MS="0"
		LFRAME_ADV="0"
		LVID_MS="0"
		AUDIO_SOURCE=${LEFT_VID}
		DIFF_MS="0"
		FRAME_COUNT=${LFRAME_COUNT}
		FRAME_DIFF="0"
	fi
fi

echo "LFRAME_COUNT: ${LFRAME_COUNT}"
echo "RFRAME_COUNT: ${RFRAME_COUNT}"
echo "FRAME_COUNT: ${FRAME_COUNT}"
echo "FRAME_MS: ${FRAME_MS}"
echo "DIFF_MS: ${DIFF_MS}"
echo "FRAME_DIFF: ${FRAME_DIFF}"
echo "LFRAME_ADV: ${LFRAME_ADV}"
echo "RFRAME_ADV: ${RFRAME_ADV}"

# If it continues to get stuck on the last frame un-comment this
# FRAME_COUNT=$(( RFRAME_COUNT - 10 ))

# Exit if frame diffrence is to high meaning false positive in audio detection.
if [ "${FRAME_DIFF}" -ge "15" ]
then
	echo "HIGH DISCREPANCY IN VIDEO SYNC, TRY CLAPPING YOUR HANDS OR WRITING BETTER CODE"
	exit 1;
fi


# function for creating initial hugin pto file
create_pto () {
	# Copy the original frames in case you need to check them
	# or modify the pto
	echo "Copying 1st frames to work area for inspection"
	cp ${TIF_TMP}left-eye.tif ${WORK_PATH}left-eye.tif
	cp ${TIF_TMP}right-eye.tif ${WORK_PATH}right-eye.tif
	# Generate initial file, -p 2 = circular fisheye. Pipe outpute to next command.
	echo "Creating initial pto file"
	if [ ${CP_DETECTOR} == "cpfind" ]
	then
		echo "Using cpfind for control point detection"
		pto_gen -p 2 -f ${CAM_FOV} -o ${WORK_PATH}${PTO_FILE} ${TIF_TMP}left-eye.tif ${TIF_TMP}right-eye.tif
		echo "pto_gen -p 2 -f ${CAM_FOV} -o ${WORK_PATH}${PTO_FILE} ${WORK_PATH}left-eye.tif ${WORK_PATH}right-eye.tif"
		#
		# Find control points in images
		cpfind --fullscale --celeste --multirow -n ${THREADS} -o ${WORK_PATH}working.pto ${WORK_PATH}${PTO_FILE}
		# Clean up bad control points
		cpclean -o ${WORK_PATH}${PTO_FILE} ${WORK_PATH}${PTO_FILE}
		#
	elif [ ${CP_DETECTOR} == "sift" ]
	then
		echo "Using sift for control point detection"
		autopano-sift-c --projection 2,${CAM_FOV} --lens-type 2 --stereographic 1 \
		--maxmatches 150 --maxdim 2880 ${WORK_PATH}${PTO_FILE} ${TIF_TMP}left-eye.tif \
		${TIF_TMP}right-eye.tif
		
	fi
	# Search for lines
	linefind -o ${WORK_PATH}${PTO_FILE} ${WORK_PATH}${PTO_FILE}
        # optimize the images. I think were skipping barrel distortion.
	autooptimiser -a -p -s -o ${WORK_PATH}${PTO_FILE} ${WORK_PATH}${PTO_FILE}
	# The modify step sets the canvas size and centers/straightens the image
	# pano_modify -c -s --canvas=AUTO -o ${WORK_PATH}working.pto ${WORK_PATH}working.pto
	pano_modify -c -s --canvas=${H_RES}x${HUGIN_V_RES} -o ${WORK_PATH}${PTO_FILE} ${WORK_PATH}${PTO_FILE}
	# the above centering sometimes makes the image point the wrong direction
	# so we can manually rotate th yaw, pitch, and roll here.
	pano_modify --rotate=${MOD_YAW},${MOD_PITCH},${MOD_ROLL} -o ${WORK_PATH}${PTO_FILE} ${WORK_PATH}${PTO_FILE}
}

while [ "${FRAME_CUR}" -lt "${FRAME_COUNT}" ]
do
  # Calculate out the current time code.
  VID_MS=$( echo "scale=2; ${FRAME_CUR} / ${FRAME_RATE}" | bc )
  #
  LVID_MS=$( echo "scale=2; ${VID_MS} + ${LFRAME_ADV} / ${FRAME_RATE}" | bc )
  RVID_MS=$( echo "scale=2; ${VID_MS} + ${RFRAME_ADV} / ${FRAME_RATE}" | bc )
  # Pad a zero, ffmpeg -ss doesnt like .nn so lets do 0.nn or 0n.nn
  LVID_MS=$( printf "%0.2f" ${LVID_MS} )
  RVID_MS=$( printf "%0.2f" ${RVID_MS} )

  echo "#############################"
  echo "#############################"
  echo "Current frame: ${FRAME_CUR}"
  echo "Left frame: $(( FRAME_CUR + LFRAME_ADV ))"
  echo "Right frame: $(( FRAME_CUR + RFRAME_ADV ))"
  echo "Frame rate: ${FRAME_RATE}"
  echo "millisecond offset: ${DIFF_MS}"
  echo "Seconds.Milliseconds: ${VID_MS}"
  echo "Left Seconds.Milliseconds: ${LVID_MS}"
  echo "Right Seconds.Milliseconds: ${RVID_MS}"
  echo "#############################"
  echo "#############################"

  if [ "${FRAME_CUR}" -eq 1 ]
  then
  	if [ ${DEBUG} == y ]
  		then
	      echo "Debug mode set. Exiting for pto and 1st frame manual review."
	      exit 0;
	fi      
  fi

  # dump frame from each l/r video stream, maybe i should write these to /dev/shm
  # i decided against using the deflate compression as itt was adding a lot of time
  #${FFMPEG_BIN} -i ${LEFT_VID} -vf "select=eq(n\,${FRAME_CUR})" -compression_algo raw -pix_fmt rgb24 -vframes 1 ${TIF_TMP}left-eye.tif
  echo "Extracting l/r frames from video sources"
  echo "If we hang here type "y" and hit enter twice."
  echo "ffmpeg output was suppressed and it needs to overwrite."

#  ${FFMPEG_BIN} -i ${LEFT_VID} -vf "select=eq(n\,$(( FRAME_CUR + LFRAME_ADV )))" -compression_algo raw -pix_fmt rgb24 -vframes 1 ${TIF_TMP}left-eye.tif >/dev/null 2>&1
#  ${FFMPEG_BIN} -i ${LEFT_VID} -vf "select=eq(n\,$(( FRAME_CUR + LFRAME_ADV )))" -compression_algo raw -pix_fmt rgb24 -vframes 1 ${TIF_TMP}left-eye.tif
# Try the acurate seek way, should be faster way to get to exact frame
${FFMPEG_BIN} -accurate_seek -ss ${LVID_MS} -i ${LEFT_VID} -compression_algo raw -pix_fmt rgb24 -vframes 1 ${TIF_TMP}left-eye.tif >/dev/null 2>&1
echo "${FFMPEG_BIN} -accurate_seek -ss ${LVID_MS} -i ${LEFT_VID} -compression_algo raw -pix_fmt rgb24 -vframes 1 ${TIF_TMP}left-eye.tif >/dev/null 2>&1"
#  ${FFMPEG_BIN} -i ${RIGHT_VID} -vf "select=eq(n\,$(( FRAME_CUR + RFRAME_ADV )))" -compression_algo raw -pix_fmt rgb24 -vframes 1 ${TIF_TMP}right-eye.tif >/dev/null 2>&1
#  ${FFMPEG_BIN} -i ${RIGHT_VID} -vf "select=eq(n\,$(( FRAME_CUR + RFRAME_ADV )))" -compression_algo raw -pix_fmt rgb24 -vframes 1 ${TIF_TMP}right-eye.tif
${FFMPEG_BIN} -accurate_seek -ss ${RVID_MS} -i ${RIGHT_VID} -compression_algo raw -pix_fmt rgb24 -vframes 1 ${TIF_TMP}right-eye.tif >/dev/null 2>&1
echo "${FFMPEG_BIN} -accurate_seek -ss ${RVID_MS} -i ${RIGHT_VID} -compression_algo raw -pix_fmt rgb24 -vframes 1 ${TIF_TMP}right-eye.tif >/dev/null 2>&1"
  # if were at frame 1 call the create pto function to analize
  
  if [ "${FRAME_CUR}" -eq 0 ]
  then
	if [ "${USER_PTO}" -eq 1 ]
	then
		echo "Using user defined pto file, we probably don't want to modify it."
	else
	  	create_pto
	  	echo "Creating initial pto file, this may take a minute..."
	fi
  fi

  echo "Creating aligned left / right equirectangular images."
  # current frame number padded with zeros
  FILE_NUM=$(printf "%07d\n" $FRAME_CUR)
  # use the pto to nona the images.
  # I may need to create 2 pto files with sed or awk, that way i can output to the correct dirs.
  # looks like I can do just 1 image with -i, image on the end should overide whats in the pto file if
  # it was modified.
  #nona -z 95 -r ldr -m JPEG_m -o ${LEFT_TMP}left_eye ${WORK_PATH}working.pto
  nona -z 90 -r ldr -m JPEG -i 0 -o ${LEFT_TMP}left_eye${FILE_NUM} ${WORK_PATH}${PTO_FILE} ${TIF_TMP}left-eye.tif ${TIF_TMP}right-eye.tif
  echo "nona -z 90 -r ldr -m JPEG -i 0 -o ${LEFT_TMP}left_eye${FILE_NUM} ${WORK_PATH}${PTO_FILE} ${TIF_TMP}left-eye.tif ${TIF_TMP}right-eye.tif"
  #nona -z 95 -r ldr -m JPEG_m -o ${RIGHT_TMP}right_eye ${WORK_PATH}working.pto
  nona -z 90 -r ldr -m JPEG -i 1 -o ${RIGHT_TMP}right_eye${FILE_NUM} ${WORK_PATH}${PTO_FILE} ${TIF_TMP}left-eye.tif ${TIF_TMP}right-eye.tif
  echo "nona -z 90 -r ldr -m JPEG -i 1 -o ${RIGHT_TMP}right_eye${FILE_NUM} ${WORK_PATH}${PTO_FILE} ${TIF_TMP}left-eye.tif ${TIF_TMP}right-eye.tif"
  # clean up temp tiff images, or do we just overwrite them? overwriting prompts us, maybe i can y to all
  rm -f ${TIF_TMP}left-eye.tif
  rm -f ${TIF_TMP}right-eye.tif

  FRAME_CUR=$(( FRAME_CUR + 1 ))
done

# merge into 3d video, NOTE: for best quality I'm outputting these in 1:1 aspect ratio. Youtube supports this.
echo "Creating top bottom stereoscopic video"
#echo "ffmpeg command: ${FFMPEG_BIN} -i ${LEFT_TMP}left_eye%07d.jpg -vf \"[in] pad=iw:2*ih [left]; movie=${RIGHT_TMP}right_eye%07d.jpg [right];[left][right] overlay=0:main_h/2 [out]\" -preset medium -pix_fmt yuv420p -c:v libx264 -b:v ${BIT_RATE} -s ${H_RES}x${H_RES} -r ${FRAME_RATE} -strict -2 ${WORK_PATH}intermediate.mp4"

#${FFMPEG_BIN} -framerate ${FRAME_RATE} -i ${LEFT_TMP}left_eye'%07d'.jpg -vf "[in] pad=iw:2*ih [left]; movie=${RIGHT_TMP}right_eye'%07d'.jpg [right];[left][right] overlay=0:main_h/2 [out]" -preset medium -pix_fmt yuv420p -c:v libx264 -b:v ${BIT_RATE} -s ${H_RES}x${H_RES} -r ${FRAME_RATE} -strict -2 ${WORK_PATH}intermediate.mp4

# /mnt/ffmpeg/ffmpeg-3.1.3-64bit-static/ffmpeg -i work/tmp/left/left_eye%07d.jpg -vf "[in] pad=iw:2*ih [left]; movie=work/tmp/right/right_eye%07d.jpg [right];[left][right] overlay=0:main_h/2 [out]" -preset medium -pix_fmt yuv420p -c:v libx264 -b:v 35M -s 3840x1920 -strict -2 out-scaled-3849x1920.mp4

# add audio track from one of the videos, I should try to do this in the above step.
# we need to choose the longer video here.
#${FFMPEG_BIN} -i ${AUDIO_SOURCE} -i ${WORK_PATH}intermediate.mp4 -c copy -map 0:v:0 -map 1:a:0 -shortest ${OUTPUT}
#echo "Adding Audio track: {FFMPEG_BIN} -i ${AUDIO_SOURCE} -i ${WORK_PATH}intermediate.mp4 -c copy -map 0:v:0 -map 1:a:0 -shortest ${OUTPUT}"

##
## Big note:
##
## I had trouble creating the top bottom video in one shot. for some reason I would end up with duplicate
## frames cauesing the clip to be longer than intended. All efforts with -framerate 30000/1001 and 
## the fps=fps=30000/1001 filter on both clips failed. I will just have to create multiple clips.
## and merge them which adds more temp space and is neither efficient or good for quality
##

# Create the right clip 
echo "Creating right clip: ${FFMPEG_BIN} -framerate ${FRAME_RATE_ORIG} -i ${RIGHT_TMP}right_eye%07d.jpg -preset medium -pix_fmt yuv420p -c:v libx264 -b:v 55M -s ${H_RES}x${HUGIN_V_RES} ${WORK_PATH}right_int.mp4"
${FFMPEG_BIN} -framerate ${FRAME_RATE_ORIG} -i ${RIGHT_TMP}right_eye%07d.jpg -preset medium -pix_fmt yuv420p -c:v libx264 -b:v 55M -s ${H_RES}x${HUGIN_V_RES} ${WORK_PATH}right_int.mp4

# merge the above right clip with the left images
echo "Merging clips: ${FFMPEG_BIN} -framerate ${FRAME_RATE_ORIG} -i ${LEFT_TMP}left_eye%07d.jpg -vf \"[in] pad=iw:2*ih [left]\;movie=${WORK_PATH}right_int.mp4 [right]\;[left][right]  overlay=0:main_h/2 [out]\" -preset medium -pix_fmt yuv420p -c:v libx264 -b:v ${BIT_RATE} -s ${H_RES}x${H_RES} ${WORK_PATH}intermediate.mp4"
${FFMPEG_BIN} -framerate ${FRAME_RATE_ORIG} -i ${LEFT_TMP}left_eye%07d.jpg -vf "[in] pad=iw:2*ih [left];movie=${WORK_PATH}right_int.mp4 [right];[left][right]  overlay=0:main_h/2 [out]" -preset medium -pix_fmt yuv420p -c:v libx264 -b:v ${BIT_RATE} -s ${H_RES}x${H_RES} ${WORK_PATH}intermediate.mp4

# add audio track from one of the videos, I should try to do this in the above step.
echo "Adding audio track: ${FFMPEG_BIN} -i ${AUDIO_SOURCE} -i ${WORK_PATH}intermediate.mp4 -c copy -map 1:v:0 -map 0:a:0 -shortest ${OUTPUT}"
${FFMPEG_BIN}${SS_OPTION} -i ${AUDIO_SOURCE} -i ${WORK_PATH}intermediate.mp4 -c copy -map 1:v:0 -map 0:a:0 -shortest ${OUTPUT}

# I should add the metadata injector here

# clean up
rm ${WORK_PATH}right_int.mp4
rm ${WORK_PATH}intermediate.mp4
rm ${WORK_PATH}working.pto
rm ${LEFT_TMP}left_eye*
rm ${RIGHT_TMP}right_eye
rm ${WORK_PATH}left-eye.tif
rm ${WORK_PATH}right-eye.tif
rmdir ${WORK_PATH}
rmdir ${TIF_TMP}

# Print some stats about the job
END_TIME=$(date +%s)
RUN_TIME=$( echo "scale=2; ${END_TIME} - ${START_TIME}" | bc)
RUN_TIME=$( echo "scale=2; ${RUN_TIME} / 60" | bc)
echo "Video took ${RUN_TIME} minutes to proccess."
exit 0;
