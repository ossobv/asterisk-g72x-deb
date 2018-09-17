FROM debian:stretch
MAINTAINER Walter Doekes <wjdoekes+bcg729@osso.nl>

# This one should be before the From, but it's not legal for Docker 1.13
# yet. Use a hack to s/debian:stretch/debian:OTHER/g above instead.
ARG oscodename=stretch
ARG upname=asterisk-g72x
ARG upversion=1.3+20+3058c45eb60d
ARG debepoch=
ARG debversion=0osso0

ENV DEBIAN_FRONTEND noninteractive

# Copy debian dir, check version
RUN mkdir -p /build/debian
COPY ./changelog /build/debian/changelog
RUN . /etc/os-release && fullversion="${upversion}-${debversion}+${ID%%[be]*}${VERSION_ID}" && \
    expected="${upname} (${debepoch}${fullversion}) ${oscodename}; urgency=medium" && \
    head -n1 /build/debian/changelog && \
    if test "$(head -n1 /build/debian/changelog)" != "${expected}"; \
    then echo "${expected}  <-- mismatch" >&2; false; fi

# This time no "keeping the build small". We only use this container for
# building/testing and not for running, so we can keep files like apt
# cache.
RUN echo 'APT::Install-Recommends "0";' >/etc/apt/apt.conf.d/01norecommends
#RUN sed -i -e 's:deb.debian.org:apt.osso.nl:;s:security.debian.org:apt.osso.nl/debian-security:' /etc/apt/sources.list
#RUN sed -i -e 's:security.ubuntu.com:apt.osso.nl:;s:archive.ubuntu.com:apt.osso.nl:' /etc/apt/sources.list
RUN apt-get update -q
RUN apt-get install -y apt-utils
RUN apt-get dist-upgrade -y
RUN apt-get install -y \
    bzip2 ca-certificates curl mercurial \
    dirmngr gnupg \
    build-essential dh-autoreconf devscripts dpkg-dev equivs quilt

# Set up upstream source, move debian dir and jump into dir.
#
# Trick to allow caching of asterisk*.tar.gz files. Download them
# once using the curl command below into .cache/* if you want. The COPY
# is made conditional by the "[2]" "wildcard". (We need one existing
# file (README.rst) so the COPY doesn't fail.)
COPY ./README.rst .cache/${upname}_${upversion}.orig.tar.g[z] /build/
RUN if ! test -s /build/${upname}_${upversion}.orig.tar.gz; then \
    cd /build && \
    hg clone http://asterisk.hosting.lv/hg asterisk-g72x && \
    NUM=$(hg -R asterisk-g72x id -n) && \
    HGUSER=x hg -R asterisk-g72x tag -r 20:ecc3fe501035 1.2 && \
    HGUSER=x hg -R asterisk-g72x tag -r 31:b67ce8dc7501 1.3 && \
    VER=$(hg -R asterisk-g72x log -r $NUM --template '{latesttag}+{latesttagdistance}+{node|short}\n') && \
    tar zcf asterisk-g72x_$VER.orig.tar.gz --exclude='.hg*' "${upname}" && \
    rm -rf "${upname}" && \
    # To cache this file, find a failed build and copy from there:
    echo "# mkdir -p .cache && CONTAINER_ID=\$(docker ps -a|awk '{if(\$2==\"IMAGE_ID\")print \$1}') && \\" >&2 && \
    echo "  docker cp \$CONTAINER_ID:/build/asterisk-g72x_$VER.orig.tar.gz .cache/" >&2; \
    fi
RUN ls -l /build/*.orig.tar.gz /build/${upname}_${upversion}.orig.tar.gz | sort -u && \
    if ! test -s /build/${upname}_${upversion}.orig.tar.gz; then \
    echo "\${upversion} mismatch; please change" >&2 && false; fi
RUN cd /build && tar zxf "${upname}_${upversion}.orig.tar.gz" && \
    mv debian "${upname}/"
WORKDIR "/build/${upname}"

# We require (lib)bcg729 from elsewhere
RUN echo "deb http://ppa.osso.nl/debian stretch osso" >/etc/apt/sources.list.d/osso-ppa.list && \
    # apt-key adv --keyserver pgp.mit.edu --recv-keys 0xBEAD51B6B36530F5 && \
    curl https://ppa.osso.nl/support+ppa@osso.nl.gpg | apt-key add - && \
    apt-get update
# We could fetch asterisk-dev from elsewhere as well, but instead we'll
# use include-tars.
# RUN printf "%s\n" "Package: asterisk asterisk-*" "Pin: version 1:11.*" "Pin-Priority: 600" \
#     >/etc/apt/preferences.d/asterisk.pref
RUN cd .. && for version in 11 13; do \
    curl --fail -O https://junk.devs.nu/asterisk-$version-include.tar.bz2 && \
    tar jxf asterisk-$version-include.tar.bz2; done
RUN test $(md5sum ../asterisk-11-include.tar.bz2 | awk '{print $1}') = 2d0e18839d469f0929bc45738faa1b77
RUN test $(md5sum ../asterisk-13-include.tar.bz2 | awk '{print $1}') = cad97c28885add2c0b3fe7b7c713f2aa

# Apt-get prerequisites according to control file.
COPY ./control debian/control
RUN mk-build-deps --install --remove --tool "apt-get -y" debian/control

# Set up build env
RUN printf "%s\n" \
    QUILT_PATCHES=debian/patches \
    QUILT_NO_DIFF_INDEX=1 \
    QUILT_NO_DIFF_TIMESTAMPS=1 \
    'QUILT_REFRESH_ARGS="-p ab --no-timestamps --no-index"' \
    'QUILT_DIFF_OPTS="--show-c-function"' \
    >~/.quiltrc
COPY . debian/

# Build!
RUN DEB_BUILD_OPTIONS=parallel=1 dpkg-buildpackage -us -uc -sa

# TODO: for bonus points, we could run quick tests here;
# for starters dpkg -i tests?

# Write output files (store build args in ENV first).
ENV oscodename=$oscodename \
    upname=$upname upversion=$upversion debversion=$debversion
CMD . /etc/os-release && fullversion=${upversion}-${debversion}+${ID%%[be]*}${VERSION_ID} && \
    dist=Docker.out && \
    if ! test -d "/${dist}"; then echo "Please mount ./${dist} for output" >&2; false; fi && \
    echo && . /etc/os-release && mkdir "/${dist}/${oscodename}/${upname}_${fullversion}" && \
    mv /build/*${fullversion}* "/${dist}/${oscodename}/${upname}_${fullversion}/" && \
    mv /build/${upname}_${upversion}.orig.tar.gz "/${dist}/${oscodename}/${upname}_${fullversion}/" && \
    chown -R ${UID}:root "/${dist}/${oscodename}" && \
    cd / && find "${dist}/${oscodename}/${upname}_${fullversion}" -type f && \
    echo && echo 'Output files created succesfully'
