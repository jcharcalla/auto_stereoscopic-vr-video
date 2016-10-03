#
# Stereoscopic vr 100316
#
# v2
#
# This container will create aligned top bottom stereoscopic vr
# videos from two side by side circular fishey kodak sp360 4k camera
# using hugin, ffmpeg, sox, bc, and sift if you enable it. This
# technique is terribly inefficient as I dump every frame from the
# videos to uncompressed tiff files. It also requires a lot of 
# temporary space. One idea to improve this proccess may be if it
# is possible to create a map file for the ffmpeg remap filter
# based on the .pto file. Additionally the merger of the videos 
# should happen in one shot but at this point it 3 steps.
#
#
# Additional options are required
#
# Pass -h for options
# sudo docker run -v </mountpoint/>:/</mountpoint> <container name> -h
#`
FROM ubuntu:latest
MAINTAINER Jason Charcalla

RUN apt-get update && apt-get install -y bc \
ffmpeg \
sox \
hugin \
&& rm -rf /var/lib/apt/lists/*

###
### Enable sift, this is commented out because of patents.
### Install procedure based on...
# https://mayukhmukherjee.wordpress.com/2014/04/05/installing-hugin-autopano-sift-c-in-linux/
###
#RUN apt-get update && apt-get install -y mercurial \
#libxml2-dev libpano13-dev libtiff-dev \
#libpng-dev build-essential autoconf automake libtool flex bison gdb \
#libc6-dev libgcc1 cmake pkg-config checkinstall \
#&& rm -rf /var/lib/apt/lists/*

#RUN cd /tmp && hg clone http://hg.code.sf.net/p/hugin/autopano-sift-c apsc.hg
#RUN mkdir /tmp/apsc.hg.build && cd /tmp/apsc.hg.build && \
#cmake ../apsc.hg -DCMAKE_INSTALL_PREFIX=/usr/local \
#-DCPACK_BINARY_DEB:BOOL=ON -DCPACK_BINARY_NSIS:BOOL=OFF \
#-DCPACK_BINARY_RPM:BOOL=OFF -DCPACK_BINARY_STGZ:BOOL=OFF \
#-DCPACK_BINARY_TBZ2:BOOL=OFF -DCPACK_BINARY_TGZ:BOOL=OFF \
#-DCPACK_BINARY_TZ:BOOL=OFF -DCMAKE_BUILD_TYPE=Debug && \
#make package && dpkg -i autopano-sift-C-2.5.2-Linux.deb


COPY create-3d-video.sh /usr/local/bin/

ENTRYPOINT ["/usr/local/bin/create-3d-video.sh"]
CMD ["-h"]
