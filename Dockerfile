ARG osdistro=debian
ARG oscodename=stretch

FROM $osdistro:$oscodename
LABEL maintainer="Walter Doekes <wjdoekes+asterisk-g72x@osso.nl>"
LABEL dockerfile-vcs=https://github.com/ossobv/asterisk-g72x-deb

ARG DEBIAN_FRONTEND=noninteractive

# This time no "keeping the build small". We only use this container for
# building/testing and not for running, so we can keep files like apt
# cache. We do this before copying anything and before getting lots of
# ARGs from the user. That keeps this bit cached.
RUN echo 'APT::Install-Recommends "0";' >/etc/apt/apt.conf.d/01norecommends
# We'll be ignoring "debconf: delaying package configuration, since apt-utils
#   is not installed"
RUN apt-get update -q && \
    apt-get dist-upgrade -y && \
    apt-get install -y \
        ca-certificates curl \
        build-essential devscripts dh-autoreconf dpkg-dev equivs quilt && \
    printf "%s\n" \
        QUILT_PATCHES=debian/patches QUILT_NO_DIFF_INDEX=1 \
        QUILT_NO_DIFF_TIMESTAMPS=1 'QUILT_DIFF_OPTS="--show-c-function"' \
        'QUILT_REFRESH_ARGS="-p ab --no-timestamps --no-index"' \
        >~/.quiltrc

# Apt-get prerequisites according to control file.
COPY control /build/debian/control
RUN mk-build-deps --install --remove --tool "apt-get -y" /build/debian/control

# debian, deb, stretch, asterisk-g72x, 1.3+20+3058c45eb60d, '', 0osso1
ARG osdistro osdistshort oscodename upname upversion debepoch= debversion

COPY changelog /build/debian/changelog
RUN . /etc/os-release && \
    sed -i -e "1s/+[^+)]*)/+${osdistshort}${VERSION_ID})/;1s/) stable;/) ${oscodename};/" \
        /build/debian/changelog && \
    fullversion="${upversion}-${debversion}+${osdistshort}${VERSION_ID}" && \
    expected="${upname} (${debepoch}${fullversion}) ${oscodename}; urgency=medium" && \
    head -n1 /build/debian/changelog && \
    if test "$(head -n1 /build/debian/changelog)" != "${expected}"; \
    then echo "${expected}  <-- mismatch" >&2; false; fi

# Trick to allow caching of UPNAME*.tar.gz files. Download them
# once using the curl command below into .cache/* if you want. The COPY
# is made conditional by the "[bg]" "wildcard". (We need one existing
# file (README.rst) so the COPY doesn't fail.)
COPY ./README.rst .cache/${upname}_${upversion}.orig.tar.[bg]* /build/
# RUN if ! test -s /build/${upname}_${upversion}.orig.tar.gz; then \
#     cd /build && \
#     hg clone http://asterisk.hosting.lv/hg asterisk-g72x && \
#     NUM=$(hg -R asterisk-g72x id -n) && \
#     HGUSER=x hg -R asterisk-g72x tag -r 20:ecc3fe501035 1.2 && \
#     HGUSER=x hg -R asterisk-g72x tag -r 31:b67ce8dc7501 1.3 && \
#     VER=$(hg -R asterisk-g72x log -r $NUM --template '{latesttag}+{latesttagdistance}+{node|short}\n') && \
#     tar zcf asterisk-g72x_$VER.orig.tar.gz --exclude='.hg*' "${upname}" && \
#     rm -rf "${upname}" && \
#     # To cache this file, find a failed build and copy from there:
#     echo "# mkdir -p .cache && CONTAINER_ID=\$(docker ps -a|awk '{if(\$2==\"IMAGE_ID\")print \$1}') && \\" >&2 && \
#     echo "  docker cp \$CONTAINER_ID:/build/asterisk-g72x_$VER.orig.tar.gz .cache/" >&2; \
#     fi
# RUN ls -l /build/*.orig.tar.gz /build/${upname}_${upversion}.orig.tar.gz | sort -u && \
#     if ! test -s /build/${upname}_${upversion}.orig.tar.gz; then \
#     echo "\${upversion} mismatch; please change" >&2 && false; fi
RUN (test -f /build/${upname}_${upversion}.orig.tar.bz2 || \
     curl -o /build/${upname}_${upversion}.orig.tar.bz2 \
       http://asterisk.hosting.lv/src/${upname}-${upversion}.tar.bz2) && \
    test $(md5sum /build/${upname}_${upversion}.orig.tar.bz2 | awk '{print $1}') = e99e153e88fe45cde0a7b04e22f1a414
RUN cd /build && tar jxf "${upname}_${upversion}.orig.tar.bz2" && \
    mv debian "${upname}-${upversion}/"
COPY asterisk-g72x-g729-ast11.install asterisk-g72x-g729-ast13.install \
    asterisk-g72x-g729-ast16.install asterisk-g72x-g729-ast18.install \
    compat rules source /build/${upname}-${upversion}/debian/
WORKDIR /build/${upname}-${upversion}

# We'll use include-tars so we can build for multiple asterisk versions.
# RUN printf "%s\n" "Package: asterisk asterisk-*" "Pin: version 1:11.*" "Pin-Priority: 600" \
#     >/etc/apt/preferences.d/asterisk.pref
RUN set -x && \
    cd .. && for version in 18 16 13 11; do \
    curl --fail -O https://junk.devs.nu/a/asterisk/asterisk-$version-include.tar.bz2 && \
    tar jxf asterisk-$version-include.tar.bz2; done && \
    test $(md5sum asterisk-18-include.tar.bz2 | awk '{print $1}') = bddb6ba2a27e80470cccacc67a725ffb && \
    test $(md5sum asterisk-16-include.tar.bz2 | awk '{print $1}') = f2135dd7204514f6899374618aa7873f && \
    test $(md5sum asterisk-13-include.tar.bz2 | awk '{print $1}') = cad97c28885add2c0b3fe7b7c713f2aa && \
    test $(md5sum asterisk-11-include.tar.bz2 | awk '{print $1}') = 2d0e18839d469f0929bc45738faa1b77 && \
    set +x

# Build!
RUN DEB_BUILD_OPTIONS=parallel=1 dpkg-buildpackage -us -uc -sa

# Get build args so we can make a version string.
ENV oscodename=$oscodename osdistshort=$osdistshort \
    upname=$upname upversion=$upversion debversion=$debversion

# Do a quick test that all subpackages got their own codec_g729.so file.
RUN . /etc/os-release && fullversion=${upversion}-${debversion}+${osdistshort}${VERSION_ID} && \
    packages=$(sed -e '/^Package:/!d;s/^[^:]*: //' debian/control) && \
    for pkg in $packages; do deb=../${pkg}_${fullversion}_amd64.deb; \
      echo "Checking .so in $deb" >&2; dpkg-deb -c "$deb" | \
      grep -F './usr/lib/asterisk/modules/codec_g729.so'; done

# Write output files.
RUN . /etc/os-release && fullversion=${upversion}-${debversion}+${osdistshort}${VERSION_ID} && \
    mkdir -p /dist/${upname}_${fullversion} && \
    mv /build/${upname}_${upversion}.orig.tar.bz2 /dist/${upname}_${fullversion}/ && \
    mv /build/*${fullversion}* /dist/${upname}_${fullversion}/ && \
    cd / && find dist/${upname}_${fullversion} -type f >&2
