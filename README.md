# auto_stereoscopic-vr-video
This continer and script is a prototype that makes use of tools such as hugin and ffmpeg to automatically align and create top/bottom stereoscop vr video. I created it for use with my pair of Kodak pixpro sp360 4k cameras. It has the ability to output higher quaility video than the kodak software and also can attempt to syncronize the left/right video streams by audio. Proccessing with this script is painfully slow as each frame is extracted to a uncompressed tiff for hugin proccessing. A better method might be to convert the hugin pto file into a ffmpeg RemapFilter map file for pixel remapping. Be aware this script requires large amounts of free space.

Usage:

-K Image resolution. 2k,4k,5k,8k (translates to 16x9 2560x1440,3840x2160,5120x2880,5120x4320)

-F Frame rate 15,24,25,30,48,50,60 (This will be ignored for now)

-l Left video file

-r Right video file

-I Input path containing image files (This will create a tmp dir in here)

-O Output path and filename for the resulting video

-f Temp file format. This script currently dumps all video frames to temp images.
    These can be either jpg or uncompressed tif. keep in mind the tiffs are large.
    jpg,tif

-V Camera feild of view. Kodak sp360 4k = 235. used for creating pto file.

-Y yaw - This should rotate the camera left and right. I find I need to use 180
    with my kodak sp3604k.

-P pitch - same as above but sometimes 0

-R Roll - same as above but sometimes 0

-p PTO file, if none specified we will try to create one. This oprion is useful if 
    you had to tweak a pto file created with debug mode.

-s Syncronize video with loud sound detections, aka clap in the 1st 10 seconds after
    camera start. y/n, y is default

-d debug, Test mode, 1st frame only for verification. create pto for visual inspection.
    This is helpful as alignent of the horizon is key in stereoscopic video. 

-D Delay start, this is to trim the 1st x seconds from both clips. This way you can 
    clap or make some loud noise for use in 1st 10 seconds for syncronization.

-m Manual frame sync offset, in the form of -m <L|R><frame count>. This means if
    left frame 0 matches right frame 5 you would use -m R5. Audio from the side that
    starts with zero will be used.

-c Control point detection method, sift or cpfind. NOTE: this only works if you 
    manually modify the docker file to build sift. Default is cpfind.

Possible future features features

-n Thread count, used for ffmpeg and a few others. Don't set higher than physical cores.

-C Composite overlay image

-f Temporary file format ?? maybe jpg or tif


./create-3d-video.sh -K 4k -V 235 -l left.MP4 -r right.MP4 -Y 180 -P 30 -R 0 -I < input path > -O < output mp4 file >

Docker usage:
This container requires a rw mount point which contains images

Create a pto fiile for inspection in hugin. pto file will be in <input path>/tmp along with tiff and wav files. Remove "-d y" to proccess video.

sudo docker run -v /mnt/tmp/:/mnt stereoscopic-v3 -K 4k -V 235 -s n -l left.MP4 -r right.MP4 -Y 180 -P "-14" -I <input path> -O <output path> -d y


A sample video can be found here.
https://www.youtube.com/watch?v=AJ1Nw1C1Foo&feature=youtu.be
