
CREATE EXTENSION postgis;
CREATE SCHEMA IF NOT EXISTS publish;
CREATE SCHEMA IF NOT EXISTS gs_auth;

CREATE TABLE IF NOT EXISTS gs_auth.group_members (
    groupname character varying(128) NOT NULL,
    username character varying(128) NOT NULL
);
CREATE TABLE IF NOT EXISTS gs_auth.group_roles (
    groupname character varying(128) NOT NULL,
    rolename character varying(64) NOT NULL
);
CREATE TABLE IF NOT EXISTS gs_auth.groups (
    name character varying(128) NOT NULL,
    enabled character(1) NOT NULL
);
CREATE TABLE IF NOT EXISTS gs_auth.role_props (
    rolename character varying(64) NOT NULL,
    propname character varying(64) NOT NULL,
    propvalue character varying(2048)
);
CREATE TABLE IF NOT EXISTS gs_auth.roles (
    name character varying(64) NOT NULL,
    parent character varying(64)
);
CREATE TABLE IF NOT EXISTS gs_auth.user_props (
    username character varying(128) NOT NULL,
    propname character varying(64) NOT NULL,
    propvalue character varying(2048)
);
CREATE TABLE IF NOT EXISTS gs_auth.user_roles (
    username character varying(128) NOT NULL,
    rolename character varying(64) NOT NULL
);
CREATE TABLE IF NOT EXISTS gs_auth.users (
    name character varying(128) NOT NULL,
    password character varying(254),
    enabled character(1) NOT NULL
);
ALTER TABLE ONLY gs_auth.group_members
    ADD CONSTRAINT gs_auth_group_members_pkey PRIMARY KEY (groupname, username);
ALTER TABLE ONLY gs_auth.group_roles
    ADD CONSTRAINT gs_auth_group_roles_pkey PRIMARY KEY (groupname, rolename);
ALTER TABLE ONLY gs_auth.groups
    ADD CONSTRAINT gs_auth_groups_pkey PRIMARY KEY (name);
ALTER TABLE ONLY gs_auth.role_props
    ADD CONSTRAINT gs_auth_role_props_pkey PRIMARY KEY (rolename, propname);
ALTER TABLE ONLY gs_auth.roles
    ADD CONSTRAINT gs_auth_roles_pkey PRIMARY KEY (name);
ALTER TABLE ONLY gs_auth.user_props
    ADD CONSTRAINT gs_auth_user_props_pkey PRIMARY KEY (username, propname);
ALTER TABLE ONLY gs_auth.user_roles
    ADD CONSTRAINT gs_auth_user_roles_pkey PRIMARY KEY (username, rolename);
ALTER TABLE ONLY gs_auth.users
    ADD CONSTRAINT gs_auth_users_pkey PRIMARY KEY (name);

CREATE INDEX gs_auth_group_members_idx ON gs_auth.group_members USING btree (username, groupname);
CREATE INDEX gs_auth_group_roles_idx ON gs_auth.group_roles USING btree (rolename, groupname);
CREATE INDEX gs_auth_user_props_idx1 ON gs_auth.user_props USING btree (propname, propvalue);
CREATE INDEX gs_auth_user_props_idx2 ON gs_auth.user_props USING btree (propname, username);
CREATE INDEX gs_auth_user_roles_idx ON gs_auth.user_roles USING btree (rolename, username);

INSERT INTO gs_auth.roles VALUES ('ADMIN', NULL), ('GROUP_ADMIN', NULL);
INSERT INTO gs_auth.roles VALUES ('domain_admins', 'ADMIN');

