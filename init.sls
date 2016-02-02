# software version information
{% set geoserver_version = '2.8.2' %}
{% set geoserver_md5 = '4e4e5614ee0bf4271f6887718eaeef3b' %}
{% set marlin_tag = '0.7.1' %}
{% set marlin_version = '0.7.1-Unsafe' %}
{% set marlin_md5 = 'ca309a98516b83462d2146780bb9236c' %}
{% set marlin_java2d_md5 = '91f4b3335cd19cee455542d485e670c2' %}
{% set jetty_version = '9.2.14.v20151106' %}
{% set jetty_md5 = '74e6b977e3b4087cf56cccccbbb19886' %}
{% set postgres_version = '9.5' %}


# portable flags
{% set slave_type = "" %}
{% set file_suffix = "" %}
{% if salt['grains.get']('borgslave:sync_server', None) %}
{% set slave_type = "portable" %}
{% set file_suffix = "_portable" %}
{% endif %}

# install nginx for portable slave
{% if slave_type == "portable" %}
nginx_pkg:
    pkgrepo.managed:
        - ppa: nginx/stable
    pkg.installed:
        - name: nginx-extras

/etc/nginx:
    file.recurse:
        - makedirs: True
        - clean: True
        - source: salt://borgslave-formula/files/nginx

nginx:
    service:
        - running
        - watch:
            - file: /etc/nginx
        - require:
            - pkg: nginx_pkg       
{% endif%}


# create borg user, to allow portable slave to sync from another slave
{% if slave_type == "" %}
borg:
    group.present:
        - gid: 8000

    user.present:
        - fullname: borg
        - shell: /bin/bash
        - home: /home/borg
        - gid: 8000
        - uid: 8000

/home/borg/.ssh/authorized_keys:
    file.managed:
        - source: salt://borgslave-formula/files/authorized_keys
        - makedirs: True
        - mode: 600
        - user: borg
        - group: borg
        - template: jinja
{% endif %}

borgpkgs:
    pkg.installed:
        - refresh: False
        - pkgs:
            - unzip
            - python-virtualenv
            - gdal-bin
            - python-dev
            - python3-dev


# Setup PostgreSQL + PostGIS
postgresql_pkg:
    pkgrepo.managed:
        - humanname: PostgreSQL
        - name: deb http://apt.postgresql.org/pub/repos/apt {{ grains["oscodename"] }}-pgdg main
        - key_url: https://www.postgresql.org/media/keys/ACCC4CF8.asc
    pkg.installed:
        - refresh: True
        - pkgs:
            - postgresql-{{ postgres_version }}-postgis-2.2
            - libpq-dev

postgresql:
    service:
        - running

/etc/postgresql/{{ postgres_version }}/main/postgresql.conf:
    file.managed:
        - source: salt://borgslave-formula/files/pgmain/postgresql.conf
        - template: jinja
        - makedirs: True
        - context:
            postgres_version: {{ postgres_version }}
        - watch_in:
            - service: postgresql

/etc/postgresql/{{ postgres_version }}/main/pg_hba.conf:
    file.managed:
        - source: salt://borgslave-formula/files/pgmain/pg_hba{{ file_suffix }}.conf
        - template: jinja
        - makedirs: True
        - watch_in:
            - service: postgresql

# copy over deployment keys (used for syncing the state repo and copying files from the master)
/etc/id_rsa_borg:
    file.managed:
        - source: salt://borgslave-formula/files/id_rsa_borg
        - mode: 600
        - template: jinja

/etc/id_rsa_borg.pub:
    file.managed:
        - source: salt://borgslave-formula/files/id_rsa_borg.pub
        - mode: 644
        - template: jinja


# set up pg_scofflaw, PostgreSQL client auth proxy
/opt/pg_scofflaw:
    git.latest:
        - name: "https://github.com/parksandwildlife/pg_scofflaw.git"
        - target: "/opt/pg_scofflaw"
        - watch_in:
            - supervisord: pg_scofflaw

/opt/pg_scofflaw/venv:
    virtualenv.managed:
        - python: /usr/bin/python3
        - requirements: /opt/pg_scofflaw/requirements.txt
        - require:
            - git: /opt/pg_scofflaw

/opt/pg_scofflaw/cert.pem:
    cmd.run:
        - name: 'openssl req -new -x509 -nodes -out /opt/pg_scofflaw/cert.pem -keyout /opt/pg_scofflaw/cert.pem -subj "/C=AU/ST=Western Australia/L=Perth/O=Department of Parks and Wildlife/CN=pg_scofflaw SSL cert"'
        - unless: "test -f /opt/pg_scofflaw/cert.pem"

/opt/pg_scofflaw/pg_scofflaw_auth_script:
    file.managed:
        - source: salt://borgslave-formula/files/pg_scofflaw_auth_script
        - template: jinja
        - mode: 755

pg_scofflaw.conf:
    file.managed:
        - name: /etc/{% if grains["os_family"] == "Debian" %}supervisor/conf.d/pg_scofflaw.conf{% elif grains["os_family"] == "Arch" %}supervisor.d/pg_scofflaw.ini{% endif %}
        - source: salt://borgslave-formula/files/pg_scofflaw.conf
        - watch_in:
            - supervisord: pg_scofflaw

pg_scofflaw:
    supervisord:
        - running

# set up dpaw-borg-state repository
/opt/dpaw-borg-state:
    cmd.run:
        - name: "hg clone {{ pillar['borg_client']['state_repo'] }} /opt/dpaw-borg-state -e 'ssh -o StrictHostKeyChecking=no -i /etc/id_rsa_borg'"
        - unless: "test -d /opt/dpaw-borg-state && test -d /opt/dpaw-borg-state/.hg" 
        - require:
            - file: /etc/id_rsa_borg

# set up borgslave-sync repository (i.e. sync client code)
/opt/dpaw-borg-state/code:
    cmd.run:
        - name: "git clone {{ pillar['borg_client']['code_repo'] }} /opt/dpaw-borg-state/code"
        - unless: "test -d /opt/dpaw-borg-state/code && test -d /opt/dpaw-borg-state/code/.git" 
        - require:
            - cmd: /opt/dpaw-borg-state

/opt/dpaw-borg-state/code/.env:
    file.managed:
        - source: salt://borgslave-formula/files/env{{ file_suffix }}
        - template: jinja
        - require:
            - cmd: /opt/dpaw-borg-state

/opt/dpaw-borg-state/code/venv:
    virtualenv.managed:
        - requirements: /opt/dpaw-borg-state/code/requirements.txt
        - require:
            - cmd: /opt/dpaw-borg-state/code

# add in pre-update hook to disable commits to the state repository
/opt/dpaw-borg-state/.hg/denied.sh:
    file.managed:
        - source: salt://borgslave-formula/files/denied.sh

/opt/dpaw-borg-state/.hg/hgrc:
    file.managed:
        - source: salt://borgslave-formula/files/hgrc
        - template: jinja
        - require:
            - virtualenv: /opt/dpaw-borg-state/code/venv

# check that borg DB is created locally
borg_slave:
    cmd.run:
        - name: "createdb {{ pillar["borg_client"]["pgsql_database"] }} && psql -d {{ pillar["borg_client"]["pgsql_database"] }} -f /opt/dpaw-borg-state/slave_create.sql"
        - user: postgres
        - unless: 'psql -l | grep "^ {{ pillar["borg_client"]["pgsql_database"] }}\b"'
        - require:
            - cmd: /opt/dpaw-borg-state

# add in oim DB user
'psql -d {{ pillar["borg_client"]["pgsql_database"] }} -c "CREATE ROLE \"{{ pillar["borg_client"]["pgsql_username"] }}\" WITH LOGIN SUPERUSER PASSWORD ''{{ pillar["borg_client"]["pgsql_password"] }}'';"':
    cmd.run:
        - user: postgres
        - unless: 'psql -d {{ pillar["borg_client"]["pgsql_database"] }} -c "SELECT * FROM pg_roles WHERE rolname = ''{{ pillar["borg_client"]["pgsql_username"] }}'';" | grep "^ {{ pillar["borg_client"]["pgsql_username"] }}\b"'
        - require: 
            - cmd: borg_slave


# the build of jetty that comes packaged with GeoServer is old and has a number of irritating bugs,
# so let's unpack a newer edition and use that
jetty-server:
    archive:
        - extracted
        - name: /opt/
        - source: http://download.eclipse.org/jetty/{{ jetty_version }}/dist/jetty-distribution-{{ jetty_version }}.tar.gz
        - source_hash: md5={{ jetty_md5 }}
        - if_missing: /opt/jetty-distribution-{{ jetty_version }}
        - archive_format: tar
        - tar_options: v
        - watch_in:
            - supervisord: geoserver
            - file: deploy_geoserver
            - file: setup_data_dir
            - file: jetty-server
            - cmd: jetty-server

    file.recurse:
        - name: /opt/jetty-distribution-{{ jetty_version }}
        - source: salt://borgslave-formula/jetty
        - include_empty: True
        - template: jinja
        - require:
            - archive: jetty-server
        - watch_in:
            - supervisord: geoserver
            - cmd: jetty-server
    cmd.run:
        - name: chown -R www-data:www-data /opt/jetty-distribution-{{ jetty_version }}
        - require:
            - file: jetty-server


# install self-contained GeoServer instance
geoserverpkgs:
    pkg.installed:
        - refresh: False
        - pkgs:
            - supervisor
            - {% if grains["os_family"] == "Debian" %}openjdk-7-jdk{% elif grains["os_family"] == "Arch" %}jdk7-openjdk{% endif %}

    archive:
        - extracted
        - name: /opt/
        - source: http://downloads.sourceforge.net/project/geoserver/GeoServer/{{ geoserver_version }}/geoserver-{{ geoserver_version }}-bin.zip
        - if_missing: /opt/geoserver-{{ geoserver_version }}/
        - source_hash: md5={{ geoserver_md5 }}
        - archive_format: zip
        - watch_in:
            - supervisord: geoserver
            - file: deploy_geoserver

# wire up GeoServer to jetty
deploy_geoserver:
    file.symlink:
        - name: /opt/jetty-distribution-{{ jetty_version }}/webapps
        - target: /opt/geoserver-{{ geoserver_version }}/webapps
        - force: True
   
setup_data_dir:
    file.symlink:
        - name: /opt/jetty-distribution-{{ jetty_version }}/data_dir
        - target: /opt/geoserver-{{ geoserver_version }}/data_dir
        - force: True
    

# set up supervisor job for GeoServer
geoserver.conf:
    file.managed:
        - name: /etc/{% if grains["os_family"] == "Debian" %}supervisor/conf.d/geoserver.conf{% elif grains["os_family"] == "Arch" %}supervisor.d/geoserver.ini{% endif %}
        - source: salt://borgslave-formula/files/geoserver.conf
        - template: jinja
        - context:
            marlin_version: {{ marlin_version }}
        - watch_in:
            - supervisord: geoserver

# set up supervisor job for slave_poll
slave_poll.conf:
    file.managed:
        - name: /etc/{% if grains["os_family"] == "Debian" %}supervisor/conf.d/slave_poll.conf{% elif grains["os_family"] == "Arch" %}supervisor.d/slave_poll.ini{% endif %}
        - source: salt://borgslave-formula/files/slave_poll.conf
        - watch_in:
            - supervisord: slave_poll

# kill the geoserver/slave sync instance during a package upgrade
'supervisorctl stop geoserver slave_poll; supervisorctl reread;':
    cmd.run:
        - onchanges:
            - archive: geoserverpkgs
            - file: geoserver.conf
            - file: slave_poll.conf
            - file: pg_scofflaw.conf

# last bit of GeoServer jetty wiring
/opt/geoserver:
    file.symlink:
        - target: /opt/jetty-distribution-{{ jetty_version }}
        - force: True


# add marlin 2D renderer, it has marginally better performance at high threadcounts
/opt/geoserver/lib/marlin-{{ marlin_version }}.jar:
    file.managed:
        - source: https://github.com/bourgesl/marlin-renderer/releases/download/v{{ marlin_tag }}/marlin-{{ marlin_version }}.jar
        - source_hash: md5={{ marlin_md5 }}

/opt/geoserver/lib/marlin-{{ marlin_version }}-sun-java2d.jar:
    file.managed:
        - source: https://github.com/bourgesl/marlin-renderer/releases/download/v{{ marlin_tag }}/marlin-{{ marlin_version }}-sun-java2d.jar
        - source_hash: md5={{ marlin_java2d_md5 }}


# trash example layers
/opt/geoserver/data_dir/workspaces:
    file.directory:
        - clean: True
        - onchanges:
            - archive: geoserverpkgs
    
/opt/geoserver/data_dir/layergroups:
    file.recurse:
        - source: salt://borgslave-formula/files/layergroups
        - clean: True
        - include_empty: True
        - onchanges:
            - archive: geoserverpkgs

/opt/geoserver/data_dir/gwc-layers:
    file.recurse:
        - source: salt://borgslave-formula/files/gwc-layers
        - clean: True
        - include_empty: True
        - onchanges:
            - archive: geoserverpkgs


# fix default security configuration
/opt/geoserver/data_dir/security:
    file.recurse:
        - source: salt://borgslave-formula/files/security{{ file_suffix }}
        - include_empty: True
        - template: jinja
        - watch_in:
            - supervisord: geoserver

# because we set the master PW, out-of-box geoserver will have a broken keystore.
/opt/geoserver/data_dir/security/geoserver.jkecs:
    file.absent:
        - onchanges:
            - archive: geoserverpkgs

# change all of the contact info for each of the GeoServer plugins
/opt/geoserver/data_dir:
    file.recurse:
        - source: salt://borgslave-formula/files/data_dir
        - template: jinja
        - watch_in:
            - supervisord: geoserver

    cmd.run:
        - name: chown -R www-data:www-data /opt/geoserver-{{ geoserver_version }}/data_dir
        - require:
            - file: /opt/geoserver/data_dir

'chown -R www-data:www-data /opt/geoserver-{{ geoserver_version }}; chmod +x /opt/geoserver/bin/*.sh;':
    cmd.run:
        - onchanges:
            - archive: geoserverpkgs


# Last-minute GeoServer clobbering
geoserver_patch_clone:
    cmd.run:
        - name: "git clone https://github.com/parksandwildlife/geoserver-patch.git /opt/geoserver-patch"
        - unless: "test -d /opt/geoserver-patch && test -d /opt/geoserver-patch/.git" 
        - require:
            - file: /etc/id_rsa_borg

geoserver_patch_sync:
    cmd.run:
        - name: "git pull"
        - cwd: /opt/geoserver-patch
        - require:
            - cmd: geoserver_patch_clone

geoserver_patch_install:
    cmd.run:
        - name: "cp -rf /opt/geoserver-patch/{{ geoserver_version }}/* /opt/geoserver-{{ geoserver_version }}/webapps/geoserver"
        - user: www-data
        - group: www-data
        - onlyif: "test -f /opt/geoserver-patch/{{ geoserver_version }}"
        - watch:
            - cmd: geoserver_patch_sync

# if a new version of GeoServer has been extracted, clobber the sync state cache!
'rm -rf /opt/dpaw-borg-state/code/.sync_status':
    cmd.run:
        - onchanges:
            - archive: geoserverpkgs

'supervisorctl update':
    cmd.run:
        - onchanges:
            - archive: jetty-server
            - archive: geoserverpkgs
            - file: slave_poll.conf
            - file: geoserver.conf

geoserver:
    supervisord:
        - running

# jetty takes ages to bootstrap, give it time
geoserver_wait:
    cmd.run:
        - name: 'sleep 20'
        - require:
            - supervisord: geoserver


# run a full sync (if necessary)
'/opt/dpaw-borg-state/code/venv/bin/honcho -e /opt/dpaw-borg-state/code/.env run /opt/dpaw-borg-state/code/venv/bin/python /opt/dpaw-borg-state/code/slave_sync.py':
    cmd.run:
        - cwd: /opt/dpaw-borg-state
        - require:
            - cmd: geoserver_wait

slave_poll:
    supervisord:
        - running


