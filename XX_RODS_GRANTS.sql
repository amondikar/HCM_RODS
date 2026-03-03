-- ========================================
-- GRANTS for XX_RODS - Full Development Setup
-- ========================================

-- Run this as SYSTEM or DBA user

-- ========================================
-- 1. BASIC SESSION & RESOURCE PRIVILEGES
-- ========================================

-- Connect to database
GRANT CREATE SESSION TO XX_RODS;

-- Create database objects
GRANT CREATE TABLE TO XX_RODS;
GRANT CREATE VIEW TO XX_RODS;
GRANT CREATE SEQUENCE TO XX_RODS;
GRANT CREATE PROCEDURE TO XX_RODS;
GRANT CREATE TRIGGER TO XX_RODS;
GRANT CREATE TYPE TO XX_RODS;
GRANT CREATE SYNONYM TO XX_RODS;
GRANT CREATE JOB TO XX_RODS;

-- ========================================
-- 2. QUOTA (Storage Space)
-- ========================================

-- Grant unlimited tablespace (or specify quota)
GRANT UNLIMITED TABLESPACE TO XX_RODS;

-- OR specify quota on specific tablespace:
-- ALTER USER XX_RODS QUOTA 10G ON USERS;
-- ALTER USER XX_RODS QUOTA 5G ON DATA;

-- ========================================
-- 3. EXECUTION PRIVILEGES (for PL/SQL packages)
-- ========================================

-- HTTP calls (for BOSS API)
GRANT EXECUTE ON UTL_HTTP TO XX_RODS;

-- File operations (if needed)
GRANT EXECUTE ON UTL_FILE TO XX_RODS;

-- Metadata operations
GRANT EXECUTE ON DBMS_METADATA TO XX_RODS;

-- Scheduler (for parallel jobs)
GRANT CREATE JOB TO XX_RODS;
GRANT EXECUTE ON DBMS_SCHEDULER TO XX_RODS;

-- Lock management
GRANT EXECUTE ON DBMS_LOCK TO XX_RODS;

-- LOB operations (for CLOB handling)
GRANT EXECUTE ON DBMS_LOB TO XX_RODS;

-- SQL operations
GRANT EXECUTE ON DBMS_SQL TO XX_RODS;

-- Output (for debugging)
GRANT EXECUTE ON DBMS_OUTPUT TO XX_RODS;

-- Utility
GRANT EXECUTE ON DBMS_UTILITY TO XX_RODS;

-- Session management
GRANT EXECUTE ON DBMS_SESSION TO XX_RODS;

-- Crypto (if encrypting credentials)
GRANT EXECUTE ON DBMS_CRYPTO TO XX_RODS;

-- Random (for generating IDs)
GRANT EXECUTE ON DBMS_RANDOM TO XX_RODS;

-- ========================================
-- 4. NETWORK ACCESS (Critical for BOSS API!)
-- ========================================

-- Allow outbound HTTPS connections to Oracle Cloud
BEGIN
  DBMS_NETWORK_ACL_ADMIN.APPEND_HOST_ACE(
    host       => '*.oraclecloud.com',
    ace        => xs$ace_type(
                    privilege_list => xs$name_list('http', 'connect', 'resolve'),
                    principal_name => 'XX_RODS',
                    principal_type => xs_acl.ptype_db
                  )
  );
END;
/

-- If you need access to other hosts (IDCS for OAuth):
BEGIN
  DBMS_NETWORK_ACL_ADMIN.APPEND_HOST_ACE(
    host       => '*.identity.oraclecloud.com',
    ace        => xs$ace_type(
                    privilege_list => xs$name_list('http', 'connect', 'resolve'),
                    principal_name => 'XX_RODS',
                    principal_type => xs_acl.ptype_db
                  )
  );
END;
/

-- For general internet access (be cautious in PROD):
BEGIN
  DBMS_NETWORK_ACL_ADMIN.APPEND_HOST_ACE(
    host       => '*',
    ace        => xs$ace_type(
                    privilege_list => xs$name_list('http', 'connect', 'resolve'),
                    principal_name => 'XX_RODS',
                    principal_type => xs_acl.ptype_db
                  )
  );
END;
/

-- ========================================
-- 5. SELECT ON DATA DICTIONARY VIEWS
-- ========================================

GRANT SELECT ON DBA_OBJECTS TO XX_RODS;
GRANT SELECT ON DBA_TABLES TO XX_RODS;
GRANT SELECT ON DBA_TAB_COLUMNS TO XX_RODS;
GRANT SELECT ON DBA_CONSTRAINTS TO XX_RODS;
GRANT SELECT ON DBA_INDEXES TO XX_RODS;
GRANT SELECT ON DBA_SCHEDULER_JOBS TO XX_RODS;
GRANT SELECT ON DBA_SCHEDULER_JOB_RUN_DETAILS TO XX_RODS;

-- Or use ALL_ views if DBA_ is too much:
GRANT SELECT ON ALL_OBJECTS TO XX_RODS;
GRANT SELECT ON ALL_TABLES TO XX_RODS;

-- ========================================
-- 6. ADVANCED FEATURES (Optional)
-- ========================================

-- Analyze tables
GRANT ANALYZE ANY TO XX_RODS;

-- Materialized views
GRANT CREATE MATERIALIZED VIEW TO XX_RODS;
GRANT QUERY REWRITE TO XX_RODS;

-- Database links (if connecting to other databases)
GRANT CREATE DATABASE LINK TO XX_RODS;

-- External tables (if loading from files)
GRANT CREATE ANY DIRECTORY TO XX_RODS;
GRANT READ ANY FILE GROUP TO XX_RODS;

-- ========================================
-- 7. ROLES (Simplifies management)
-- ========================================

-- Standard developer role
GRANT CONNECT TO XX_RODS;
GRANT RESOURCE TO XX_RODS;

-- DBA role (only if XX_RODS needs admin capabilities - NOT recommended for regular dev)
-- GRANT DBA TO XX_RODS;

-- ========================================
-- 8. APEX INTEGRATION (if using APEX)
-- ========================================

-- If you're using APEX
-- GRANT APEX_ADMINISTRATOR_ROLE TO XX_RODS;

-- For APEX workspace
-- BEGIN
--   APEX_INSTANCE_ADMIN.ADD_WORKSPACE(
--     p_workspace_id   => NULL,
--     p_workspace      => 'XX_RODS_WS',
--     p_primary_schema => 'XX_RODS'
--   );
-- END;
-- /

-- ========================================
-- 9. ACCESS TO XX_INT OBJECTS (if needed)
-- ========================================

-- If XX_RODS needs to access XX_INT's tables/packages

-- Tables
GRANT SELECT, INSERT, UPDATE, DELETE ON XX_INT.XX_INT_SAAS_EXTRACT_CONFIG TO XX_RODS;
GRANT SELECT, INSERT, UPDATE, DELETE ON XX_INT.XX_INT_EXTRACT_JOB_LOG TO XX_RODS;

-- Sequences
GRANT SELECT ON XX_INT.XX_INT_EXTRACT_JOB_LOG_SEQ TO XX_RODS;

-- Packages (execute)
GRANT EXECUTE ON XX_INT.PKG_SPECTRA_WORKER_ETL_V4 TO XX_RODS;
GRANT EXECUTE ON XX_INT.XX_BOSS_SIMPLE_QUERY_PKG TO XX_RODS;
GRANT EXECUTE ON XX_INT.XX_BOSS_PARALLEL_RUNNER_PKG TO XX_RODS;

-- Create synonyms in XX_RODS for easier access
CREATE OR REPLACE SYNONYM XX_RODS.XX_INT_SAAS_EXTRACT_CONFIG FOR XX_INT.XX_INT_SAAS_EXTRACT_CONFIG;
CREATE OR REPLACE SYNONYM XX_RODS.XX_INT_EXTRACT_JOB_LOG FOR XX_INT.XX_INT_EXTRACT_JOB_LOG;
CREATE OR REPLACE SYNONYM XX_RODS.PKG_SPECTRA_WORKER_ETL_V4 FOR XX_INT.PKG_SPECTRA_WORKER_ETL_V4;

-- ========================================
-- 10. VERIFY GRANTS
-- ========================================

PROMPT
PROMPT ========================================
PROMPT Verifying Grants for XX_RODS
PROMPT ========================================

-- Check system privileges
SELECT privilege 
FROM dba_sys_privs 
WHERE grantee = 'XX_RODS'
ORDER BY privilege;

-- Check role grants
SELECT granted_role 
FROM dba_role_privs 
WHERE grantee = 'XX_RODS'
ORDER BY granted_role;

-- Check tablespace quota
SELECT tablespace_name, max_bytes, bytes 
FROM dba_ts_quotas 
WHERE username = 'XX_RODS';

-- Check network ACLs
SELECT host, lower_port, upper_port, privilege 
FROM dba_network_acl_privileges 
WHERE principal = 'XX_RODS'
ORDER BY host;

PROMPT
PROMPT ========================================
PROMPT XX_RODS Setup Complete!
PROMPT ========================================
PROMPT
PROMPT Next Steps:
PROMPT 1. Connect as XX_RODS
PROMPT 2. Run the DDL script to create tables
PROMPT 3. Create packages (ETL, query builder, parallel runner)
PROMPT 4. Test BOSS API connectivity
PROMPT
PROMPT ========================================

-- ========================================
-- BONUS: Sample Connection Test
-- ========================================

/*
-- Connect as XX_RODS and test:

CONN xx_rods/password@database

-- Test HTTP access
SELECT UTL_HTTP.REQUEST('https://www.oracle.com') FROM DUAL;

-- Test scheduler
BEGIN
  DBMS_SCHEDULER.CREATE_JOB(
    job_name   => 'TEST_JOB',
    job_type   => 'PLSQL_BLOCK',
    job_action => 'BEGIN DBMS_OUTPUT.PUT_LINE(''Test''); END;',
    enabled    => TRUE,
    auto_drop  => TRUE
  );
END;
/

-- Verify job ran
SELECT * FROM USER_SCHEDULER_JOB_RUN_DETAILS 
WHERE job_name = 'TEST_JOB';
*/

-- ========================================
