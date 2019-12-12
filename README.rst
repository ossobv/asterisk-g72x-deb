OSSO build of the asterisk-g72x G.729 codec
===========================================

Using Docker::

    ./Dockerfile.build

If the build succeeds, the built Debian packages are placed inside (a
subdirectory of) ``Dockerfile.out/``.

At the moment, the Docker build builds packages for both Asterisk 11 and
Asterisk 13.


------------
Manual build
------------

Get source::

    hg clone http://asterisk.hosting.lv/hg asterisk-g72x
    NUM=$(hg -R asterisk-g72x id -n)

    HGUSER=x hg -R asterisk-g72x tag -r 20:ecc3fe501035 1.2
    HGUSER=x hg -R asterisk-g72x tag -r 31:b67ce8dc7501 1.3

    VER=$(hg -R asterisk-g72x log -r $NUM --template '{latesttag}+{latesttagdistance}+{node|short}\n')
    tar zcf asterisk-g72x_$VER.orig.tar.gz --exclude='.hg*' \
      asterisk-g72x

    rm -rf asterisk-g72x
    tar zxf asterisk-g72x_$VER.orig.tar.gz

Setup ``debian/`` dir::

    cd asterisk-g72x
    git clone https://github.com/ossobv/asterisk-g72x-deb.git debian


Optionally alter ``debian/changelog`` and then build::

    dpkg-buildpackage -us -uc -sa


TODO
----

* Should fix these ``unresolvable reference to symbol`` warnings::

    dpkg-shlibdeps: warning: ast_trans_frameout: it's probably a plugin
    dpkg-shlibdeps: warning: ast_module_unregister: it's probably a plugin
    dpkg-shlibdeps: warning: __ast_register_translator: it's probably a plugin
    dpkg-shlibdeps: warning: ast_register_file_version: it's probably a plugin
    dpkg-shlibdeps: warning: ast_log: it's probably a plugin
    dpkg-shlibdeps: warning: ast_module_register: it's probably a plugin
    dpkg-shlibdeps: warning: __ast_verbose: it's probably a plugin
    dpkg-shlibdeps: warning: ast_cli_unregister: it's probably a plugin
    dpkg-shlibdeps: warning: option_verbose: it's probably a plugin
    dpkg-shlibdeps: warning: ast_unregister_file_version: it's probably a plugin
    dpkg-shlibdeps: warning: ast_format_set: it's probably a plugin
    dpkg-shlibdeps: warning: ast_cli: it's probably a plugin
    dpkg-shlibdeps: warning: ast_cli_register: it's probably a plugin
    dpkg-shlibdeps: warning: ast_unregister_translator: it's probably a plugin

* Should add ``-dbg`` package?
