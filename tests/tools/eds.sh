#
# Helper functions to start your own e-d-s instance. This depends
# on you having your own D-Bus session bus started (first).
#
#
# Copyright (C) 2011 Collabora Ltd. <http://www.collabora.co.uk/>
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.

eds_tmpdir=$(mktemp -d)

cur_dir=`dirname $0`

eds_init_settings () {
    export XDG_DATA_HOME=$eds_tmpdir/.local
    export XDG_CACHE_HOME=$eds_tmpdir/.cache
    export XDG_CONFIG_HOME=$eds_tmpdir/.config
    mkdir -p $XDG_CONFIG_HOME/evolution/sources
    cp $cur_dir/test.source $XDG_CONFIG_HOME/evolution/sources/
    cp $cur_dir/other.source $XDG_CONFIG_HOME/evolution/sources/
}

# This should be called on INT TERM and EXIT
eds_stop () {
    rm -rf $eds_tmpdir
    rm -rf $eds_tmpdir
}

