# HCM RODS – Knowledge Transfer (KT) Sessions

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Architecture Overview](#2-architecture-overview)
3. [Database Objects](#3-database-objects)
4. [Core Packages](#4-core-packages)
5. [Configuration Management](#5-configuration-management)
6. [Installation & Setup](#6-installation--setup)
7. [Running Extracts](#7-running-extracts)
8. [Monitoring & Troubleshooting](#8-monitoring--troubleshooting)
9. [Maintenance](#9-maintenance)
10. [Appendix – Extracted Entities](#10-appendix--extracted-entities)

---

## 1. Project Overview

**HCM RODS** (Human Capital Management Read-Only Data Store) is a configuration-driven Oracle PL/SQL framework that extracts employee and organizational data from **Oracle Cloud HCM** (Fusion) via the **BOSS (Business Object SaaS Service) Bulk Extract API** and loads it into an Oracle database (typically Oracle Autonomous Data Warehouse – ADW).

### Key Facts

| Item | Detail |
|------|--------|
| Platform | Oracle Database / ADW |
| Source System | Oracle Cloud HCM (Fusion) |
| API | Oracle SaaS Batch Extract (BOSS API) |
| Authentication | OAuth 2.0 – Client Credentials |
| Language | PL/SQL |
| Created | February 2026 |

### What It Does

- Authenticates to Oracle Cloud HCM using OAuth 2.0
- Submits asynchronous bulk-extract jobs to the BOSS API
- Polls until each job completes
- Downloads the resulting ZIP files
- Unzips and parses the JSON payloads
- Loads parsed data into target Oracle staging tables
- Supports **parallel execution** of 100+ extract configurations simultaneously

---

## 2. Architecture Overview

```
┌──────────────────────────────────────────────────────────────┐
│                    Oracle Database / ADW                      │
│                                                              │
│  ┌──────────────────────┐   ┌───────────────────────────┐   │
│  │  XX_BOSS_PARALLEL_   │   │  XX_BOSS_QUERY_BUILDER_   │   │
│  │  RUNNER_PKG          │──▶│  PKG                      │   │
│  │  (Parallel launcher) │   │  (Dynamic query builder)  │   │
│  └──────────┬───────────┘   └───────────────────────────┘   │
│             │ DBMS_SCHEDULER jobs (one per config)           │
│             ▼                                                │
│  ┌──────────────────────┐                                    │
│  │  PKG_SPECTRA_WORKER_ │                                    │
│  │  ETL_V4              │  ◀── XX_INT_SAAS_EXTRACT_CONFIG   │
│  │  (Core ETL engine)   │        (100+ configurations)       │
│  └──────────┬───────────┘                                    │
│             │                                                │
└─────────────┼────────────────────────────────────────────────┘
              │ UTL_HTTP (OAuth + BOSS API calls)
              ▼
┌──────────────────────────────┐
│  Oracle Cloud HCM (Fusion)   │
│  BOSS Batch Extract API      │
└──────────────────────────────┘
```

### Data Flow

```
1. PARALLEL RUNNER  ──▶  reads XX_INT_SAAS_EXTRACT_CONFIG
                    ──▶  calls QUERY_BUILDER to assemble API queries
                    ──▶  spawns one DBMS_SCHEDULER job per config

2. Each SCHEDULER JOB  ──▶  calls PKG_SPECTRA_WORKER_ETL_V4
                            .run_extract_by_config()

3. ETL ENGINE  ──▶  get OAuth token
               ──▶  submit extract job (async)
               ──▶  poll until COMPLETED
               ──▶  download ZIP file(s)
               ──▶  unzip + parse JSON
               ──▶  load rows into target staging table
               ──▶  log result in XX_INT_EXTRACT_JOB_LOG
```

---

## 3. Database Objects

### 3.1 Tables

#### `XX_INT_SAAS_EXTRACT_CONFIG`
Master configuration table. One row per extract definition.

| Column | Type | Description |
|--------|------|-------------|
| CONFIG_ID | NUMBER | Primary key (auto-generated) |
| CONFIG_NAME | VARCHAR2(100) | Unique name for this extract (e.g. `WORKER_ASSIGNMENTS_DEV1`) |
| INSTANCE_CODE | VARCHAR2(50) | Environment identifier (`DEV1`, `PROD`, etc.) |
| OAUTH_TOKEN_URL | VARCHAR2(4000) | OAuth token endpoint URL |
| CLIENT_ID | VARCHAR2(500) | OAuth client ID |
| CLIENT_SECRET | VARCHAR2(500) | OAuth client secret |
| SCOPE_BOSS / SCOPE_SAAS_BATCH | VARCHAR2(500) | OAuth scopes |
| API_BASE_URL | VARCHAR2(4000) | Base URL for the BOSS API |
| MODULE_NAME | VARCHAR2(200) | HCM module (e.g. `hcmWorker`) |
| RESOURCE_NAME | VARCHAR2(200) | API resource (e.g. `workers`) |
| TARGET_TABLE_NAME | VARCHAR2(128) | Destination staging table |
| JSON_ARRAY_PATH | VARCHAR2(100) | JSON path to the data array (default: `items`) |
| TRUNCATE_BEFORE_LOAD | VARCHAR2(1) | `Y` = truncate target table before loading |
| ADVANCED_QUERY_TEMPLATE | CLOB | Full BOSS API advanced query JSON |
| POLL_INTERVAL_SEC | NUMBER | Seconds between status polls (default: 10) |
| POLL_TIMEOUT_SEC | NUMBER | Max poll wait time in seconds (default: 600) |
| ENABLED | VARCHAR2(1) | `Y` = active, `N` = disabled |
| QUERY_FIELDS | VARCHAR2(4000) | Comma-separated field names for query building |
| QUERY_ACCESSORS | CLOB | JSON accessors definition |
| AUTO_BUILD_QUERY | VARCHAR2(1) | `Y` = auto-build query from fields/accessors |
| APEX_CRED_STATIC | VARCHAR2(100) | APEX credential store name (optional) |
| MERGE_KEY_COLUMNS | VARCHAR2(500) | Comma-separated key columns for MERGE/upsert. `NULL` = TRUNCATE+INSERT mode |

#### `XX_INT_EXTRACT_JOB_LOG`
Tracks each extract job submitted within a batch run.

| Column | Description |
|--------|-------------|
| LOG_ID | Primary key |
| BATCH_ID | Groups all jobs from one parallel run (e.g. `BATCH_20260320_143000`) |
| CONFIG_NAME | Which extract configuration was run |
| STATUS | `QUEUED` → `RUNNING` → `COMPLETED` / `ERROR` |
| SUBMISSION_TIME | When the scheduler job started |
| COMPLETION_TIME | When the job finished |
| ERROR_MESSAGE | Error text if STATUS = ERROR |
| TARGET_TABLE_NAME | The staging table that was loaded |

#### `SPECTRA_WORKER_ETL_LOG`
ETL engine run-level log (one row per `run_extract_by_config` call).

| Column | Description |
|--------|-------------|
| RUN_ID | Auto-generated identity (primary key) |
| START_TIME / END_TIME | Execution window |
| STATUS | Current status text |
| MESSAGE | Log message |
| REQUEST_ID | BOSS API request/job ID |
| EXTRACT_FILE_URL | URL where the extract file was downloaded from |

#### `SPECTRA_WORKER_ETL_LOG_DTL`
Detailed step-level logging with large CLOB support (chunked into 3,900-character rows).

| Column | Description |
|--------|-------------|
| LOG_DTL_ID | Primary key |
| RUN_ID | Foreign key to SPECTRA_WORKER_ETL_LOG |
| STEP_NAME | Name of the processing step |
| SEQ_NO | Chunk sequence (for reassembling large CLOBs) |
| MESSAGE_TEXT | Up to 3,900 characters of log content |
| CREATED_TS | Timestamp |

#### `XX_INT_SAAS_JOB_FILES`
Stores downloaded file blobs and metadata for each extract job.

| Column | Description |
|--------|-------------|
| RUN_ID | ETL run ID |
| REQUEST_ID | BOSS API request ID |
| FILE_NAME | Name of the downloaded ZIP/file |
| DOWNLOAD_URL | URL used to download the file |
| MIME_TYPE | File MIME type |
| FILE_BLOB | Raw BLOB of the downloaded file |
| CREATED_TS | Timestamp |

#### `ERROR_LOG`
Centralized PL/SQL error log (used by `LOG_ERROR_PRC`).

Captures: username, OS user, machine, program, exception name, error code, error message, failed SQL context, full call stack, and error backtrace.

### 3.2 Sequences

| Sequence | Used By |
|----------|---------|
| `ISEQ$$_2149728` | CONFIG_ID in XX_INT_SAAS_EXTRACT_CONFIG |
| `XX_INT_EXTRACT_JOB_LOG_SEQ` | LOG_ID in XX_INT_EXTRACT_JOB_LOG |
| `ERROR_LOG_SEQ` | LOG_ID in ERROR_LOG |

---

## 4. Core Packages

### 4.1 `PKG_SPECTRA_WORKER_ETL_V4` – Core ETL Engine

**File:** `pkg_spectra_worker_etl_v4_pkg.sql` (spec) / `pkg_spectra_worker_etl_v4_pkB.sql` (body)

This is the heart of the framework. It handles the full extract lifecycle.

#### Key Procedures & Functions

| Name | Purpose |
|------|---------|
| `run_extract_by_config(p_config_name, p_effective_date, p_multi_file)` | **Main entry point.** Reads config from table and runs the full extract pipeline. |
| `run_extract_direct(...)` | Backward-compatible version that accepts all parameters directly instead of reading from config table. |
| `get_oauth_token(...)` | Generates an OAuth 2.0 bearer token using client credentials flow. |
| `get_oauth_token_apex(...)` | OAuth token generation using APEX credential store (3 variants: apex, apex1, apex2). |
| `submit_extract_job(...)` | Submits an async extract job to the BOSS API. Returns a `request_id`. |
| `poll_extract_status(...)` | Polls the BOSS API until the job completes or times out. Returns `status`, `file_id`, `output_url`. |
| `download_extract_output(...)` | Retrieves file metadata (list of output files) from the BOSS API. |
| `download_job_output_file(...)` | Downloads a single output file (backward compatible). |
| `download_job_output_files_multi(...)` | Downloads **all** output files from the job response (v4 multi-file support). |
| `unzip_and_load_worker_assignments(...)` | Unzips a single downloaded file and loads it. |
| `unzip_and_load_multi_files(...)` | Unzips and loads **all** downloaded files for a request. |
| `unzip_and_load_single_file(...)` | Loads a single file blob into a target table. |
| `load_json_to_table(...)` | Parses JSON and inserts **or merges** rows into the target table using `JSON_TABLE`. Supports upsert via `p_merge_key`. |
| `log_etl(p_step, p_msg, p_clob)` | Autonomous-transaction logger. |

#### `run_extract_by_config` – Parameter Reference

```sql
PKG_SPECTRA_WORKER_ETL_V4.run_extract_by_config(
  p_config_name    => 'WORKER_ASSIGNMENTS_DEV1',  -- Config name in XX_INT_SAAS_EXTRACT_CONFIG
  p_effective_date => '2025-01-01',               -- NULL = SYSDATE-365
  p_multi_file     => TRUE                        -- TRUE = download all output files
);
```

---

### 4.2 `XX_BOSS_PARALLEL_RUNNER_PKG` – Parallel Execution Engine

**File:** `XX_BOSS_PARALLEL_RUNNER_PKG.SQL.sql` (spec) / `XX_BOSS_PARALLEL_RUNNER_PKB.SQL.sql` (body)

Runs all enabled extract configurations for an instance code simultaneously using `DBMS_SCHEDULER`.

#### Procedures

| Name | Purpose |
|------|---------|
| `run_all_extracts_parallel(p_instance_code, p_effective_date, p_multi_file)` | Submits all enabled configs as parallel scheduler jobs. |
| `monitor_job_status(p_batch_id)` | Prints a progress summary (totals + per-job details) for a given batch. |

#### How Parallel Execution Works

1. Generates a unique `BATCH_ID` (e.g. `BATCH_20260320_143000`)
2. Reads all enabled configs for the given `INSTANCE_CODE`
3. Pre-builds API queries via `XX_BOSS_QUERY_BUILDER_PKG`
4. Inserts a `QUEUED` log entry per config into `XX_INT_EXTRACT_JOB_LOG`
5. Creates one `DBMS_SCHEDULER` job per config (job names: `BOSS_EXT_<name>_<n>`)
6. Each scheduler job runs `PKG_SPECTRA_WORKER_ETL_V4.run_extract_by_config` and updates the log to `RUNNING` → `COMPLETED` / `ERROR`
7. Scheduler jobs are set to `AUTO_DROP = TRUE` (self-cleaning)

---

### 4.3 `XX_BOSS_QUERY_BUILDER_PKG` – Dynamic Query Builder

**File:** `xx_boss_query_builder_pkg.sql` (spec) / `xx_boss_query_builder_pkB.sql` (body)

Constructs the BOSS API `advancedQuery` JSON from field/accessor definitions stored in `XX_INT_SAAS_EXTRACT_CONFIG`.

#### Procedures & Functions

| Name | Purpose |
|------|---------|
| `build_advanced_query(p_config_name)` | Returns the fully assembled `advancedQuery` CLOB for a config. |
| `parse_query_to_columns(p_config_name)` | Parses an existing query and extracts its field/accessor definitions. |
| `rebuild_all_queries(p_instance_code)` | Rebuilds queries for all configs of a given instance. |

---

### 4.4 `LOG_ERROR_PRC` – Centralized Error Logger

**File:** `LOG_ERROR_PRC.sql`

A standalone procedure used across all packages for structured error logging to the `ERROR_LOG` table.

Captures:
- Session info (username, OS user, machine, program, SID) from `V$SESSION`
- Program unit and line number from `UTL_CALL_STACK`
- Exception name, error code, and error message
- Surrounding source lines from `USER_SOURCE` via backtrace line number
- Full call stack and error backtrace

---

## 5. Configuration Management

### 5.1 Config Table Key Columns

The `XX_INT_SAAS_EXTRACT_CONFIG` table drives everything. A single row defines:

- **Credentials** (OAuth URL, client ID, secret, scope)
- **API target** (base URL, module, resource, version)
- **Query** (advanced query JSON or fields/accessors for auto-building)
- **Load behavior** (target table, JSON path, truncate flag)
- **Timing** (poll interval, timeout)
- **Enable flag** (`ENABLED = 'Y'` to include in parallel runs)

### 5.2 Adding a New Extract

1. Insert a row into `XX_INT_SAAS_EXTRACT_CONFIG` with the required credentials and API details.
2. Set `ENABLED = 'Y'` and `AUTO_BUILD_QUERY = 'Y'` if using the query builder.
3. Populate `QUERY_FIELDS` (comma-separated field names) and `QUERY_ACCESSORS` (JSON).
4. Run `XX_BOSS_QUERY_BUILDER_PKG.build_advanced_query(p_config_name => '<your_config>')` to verify the generated query.
5. Create the target staging table (matching the expected JSON structure).
6. Test with a single run before including in parallel batch.

### 5.3 MERGE / Upsert Mode

By default, each extract run **truncates** the target table then inserts all rows. Setting `MERGE_KEY_COLUMNS` switches to **upsert** mode: existing rows are updated in place, new rows are inserted — no data is lost between runs.

```sql
-- Enable MERGE mode for a config (upsert on PERSON_NUMBER)
UPDATE xx_int_saas_extract_config
SET merge_key_columns = 'PERSON_NUMBER'
WHERE config_name = 'WORKER_ASSIGNMENTS_DEV1';
COMMIT;

-- Multi-column key
UPDATE xx_int_saas_extract_config
SET merge_key_columns = 'PERSON_NUMBER,EFFECTIVE_DATE'
WHERE config_name = 'WORKER_ASSIGNMENTS_DEV1';
COMMIT;

-- Revert to TRUNCATE+INSERT mode
UPDATE xx_int_saas_extract_config
SET merge_key_columns = NULL
WHERE config_name = 'WORKER_ASSIGNMENTS_DEV1';
COMMIT;
```

You can also call `load_json_to_table` directly with a merge key:

```sql
BEGIN
  pkg_spectra_worker_etl_v4.load_json_to_table(
    p_run_id          => 1,
    p_request_id      => 'REQ123',
    p_json            => :my_json_clob,
    p_table_name      => 'STAGING_WORKERS',
    p_json_array_path => 'items',
    p_truncate        => FALSE,        -- ignored when p_merge_key is set
    p_merge_key       => 'PERSON_NUMBER'
  );
END;
/
```

**How the MERGE works internally:**

```sql
MERGE INTO staging_table t
USING (
  SELECT jt.*  -- JSON_TABLE data + RUN_ID, REQUEST_ID, CREATION_DATE, LAST_UPDATE_DATE
  FROM JSON_TABLE(:json, '$.items[*]' COLUMNS (...)) jt
) s
ON (t.PERSON_NUMBER = s.PERSON_NUMBER)          -- key column(s)
WHEN MATCHED THEN
  UPDATE SET t.col1 = s.col1, ...,              -- all non-key columns
             t.LAST_UPDATE_DATE = s.LAST_UPDATE_DATE
WHEN NOT MATCHED THEN
  INSERT (PERSON_NUMBER, col1, ..., CREATION_DATE, ...)
  VALUES (s.PERSON_NUMBER, s.col1, ..., s.CREATION_DATE, ...)
```

### 5.4 Enabling / Disabling an Extract

```sql
-- Disable a specific extract
UPDATE xx_int_saas_extract_config
SET enabled = 'N'
WHERE config_name = 'WORKER_ASSIGNMENTS_DEV1';
COMMIT;

-- Enable it again
UPDATE xx_int_saas_extract_config
SET enabled = 'Y'
WHERE config_name = 'WORKER_ASSIGNMENTS_DEV1';
COMMIT;
```

### 5.5 APEX Credential Store (Optional)

For environments using Oracle APEX, credentials can be stored in the APEX credential store instead of plaintext in the config table. Set the `APEX_CRED_STATIC`, `APEX_APP_ID`, and `APEX_WORKSPACE` columns, then use `get_oauth_token_apex()` variants.

---

## 6. Installation & Setup

### 6.1 Prerequisites

- Oracle Database 19c+ (23ai preferred for native JSON support)
- Oracle APEX (optional, for credential management)
- Network ACL grants allowing `UTL_HTTP` outbound to Oracle Cloud HCM endpoints
- Schema: `XX_INT` (or update all references to your schema)

### 6.2 Deployment Order

Run the following scripts **in order**:

```
1. DDL Scripts                        -- Create all tables, sequences, indexes
2. XX_RODS_GRANTS.sql                 -- Grant required permissions
3. LOG_ERROR_PRC.sql                  -- Error logging procedure
4. get_exception_name.sql             -- Exception name mapping utility
5. pkg_spectra_worker_etl_v4_pkg.sql  -- ETL package spec
6. pkg_spectra_worker_etl_v4_pkB.sql  -- ETL package body
7. xx_boss_query_builder_pkg.sql      -- Query builder spec
8. xx_boss_query_builder_pkB.sql      -- Query builder body
9. XX_BOSS_PARALLEL_RUNNER_PKG.SQL.sql  -- Parallel runner spec
10. XX_BOSS_PARALLEL_RUNNER_PKB.SQL.sql -- Parallel runner body
11. INSERT INTO xx_int_saas_extract_config  -- Seed configuration data
```

### 6.3 Network ACL (UTL_HTTP)

The database must be allowed to call Oracle Cloud HCM endpoints:

```sql
BEGIN
  DBMS_NETWORK_ACL_ADMIN.APPEND_HOST_ACE(
    host    => '*.oraclecloud.com',
    ace     => xs$ace_type(
                 privilege_list => xs$name_list('connect', 'resolve'),
                 principal_name => 'XX_INT',
                 principal_type => xs_acl.ptype_db
               )
  );
END;
/
```

### 6.4 Wallet / SSL

If the database requires a wallet for HTTPS connections:

```sql
UTL_HTTP.SET_WALLET('file:/path/to/wallet', 'wallet_password');
```

---

## 7. Running Extracts

### 7.1 Run All Extracts in Parallel (Recommended)

```sql
BEGIN
  xx_boss_parallel_runner_pkg.run_all_extracts_parallel(
    p_instance_code  => 'DEV1',   -- or 'PROD'
    p_effective_date => NULL,      -- NULL = SYSDATE-365; or 'YYYY-MM-DD'
    p_multi_file     => TRUE       -- TRUE = download all output files per job
  );
END;
/
```

The procedure prints the `BATCH_ID` to `DBMS_OUTPUT`. Save it for monitoring.

### 7.2 Run a Single Extract

```sql
BEGIN
  pkg_spectra_worker_etl_v4.run_extract_by_config(
    p_config_name    => 'WORKER_ASSIGNMENTS_DEV1',
    p_effective_date => '2025-01-01',
    p_multi_file     => TRUE
  );
END;
/
```

### 7.3 Run with Direct Parameters (Backward Compatible)

```sql
BEGIN
  pkg_spectra_worker_etl_v4.run_extract_direct(
    p_oauth_token_url  => 'https://<idcs-host>/oauth2/v1/token',
    p_client_id        => '<client_id>',
    p_client_secret    => '<client_secret>',
    p_scope_saas_batch => 'https://<hcm-host>/hcmRestApi/.default',
    p_api_base_url     => 'https://<hcm-host>/hcmRestApi/resources/11.13.18.05',
    p_module_name      => 'hcmWorker',
    p_resource_name    => 'workers',
    p_target_table     => 'STAGING_WORKERS',
    p_advanced_query   => '{"query":{"fields":[...]}}',
    p_json_array_path  => 'items',
    p_truncate         => TRUE
  );
END;
/
```

---

## 8. Monitoring & Troubleshooting

### 8.1 Monitor a Batch Run

```sql
-- Summary + per-job status
BEGIN
  xx_boss_parallel_runner_pkg.monitor_job_status(
    p_batch_id => 'BATCH_20260320_143000'  -- Replace with actual batch ID
  );
END;
/
```

Output shows: total / completed / running / queued / error counts, progress %, and duration per job.

### 8.2 Check Currently Running Scheduler Jobs

```sql
SELECT
  job_name,
  TO_CHAR(last_start_date, 'HH24:MI:SS') AS started,
  ROUND((SYSDATE - last_start_date) * 24 * 60, 1) AS running_minutes
FROM user_scheduler_jobs
WHERE job_name LIKE 'BOSS_EXT_%'
AND state = 'RUNNING';
```

### 8.3 Check Completed Scheduler Jobs

```sql
SELECT
  job_name,
  status,
  TO_CHAR(log_date, 'HH24:MI:SS') AS completed_at,
  additional_info
FROM user_scheduler_job_run_details
WHERE job_name LIKE 'BOSS_EXT_%'
ORDER BY log_date DESC;
```

### 8.4 View Errors for a Batch

```sql
SELECT config_name, error_message, submission_time, completion_time
FROM xx_int_extract_job_log
WHERE batch_id = 'BATCH_20260320_143000'
AND status = 'ERROR';
```

### 8.5 View ETL Detail Log

```sql
-- View step-level log for a specific run
SELECT step_name, seq_no, message_text, created_ts
FROM spectra_worker_etl_log_dtl
WHERE run_id = <run_id>
ORDER BY seq_no;
```

### 8.6 View Error Log

```sql
SELECT
  log_timestamp,
  program_unit,
  exception_name,
  error_message,
  SUBSTR(failed_sql, 1, 500) AS failed_sql
FROM error_log
ORDER BY log_timestamp DESC
FETCH FIRST 20 ROWS ONLY;
```

### 8.7 Common Issues

| Symptom | Likely Cause | Resolution |
|---------|-------------|------------|
| `ORA-29273: HTTP request failed` | Network ACL not set or SSL wallet missing | Check ACL grants and wallet config |
| Jobs stuck in `QUEUED` | Scheduler not started or max jobs reached | Check `DBMS_SCHEDULER` configuration |
| `ERROR: ORA-01403` (no data found) | Config name not found | Verify `CONFIG_NAME` and `INSTANCE_CODE` in config table |
| OAuth token error | Wrong client ID/secret or expired credentials | Update credentials in `XX_INT_SAAS_EXTRACT_CONFIG` |
| Extract times out | `POLL_TIMEOUT_SEC` too low or large data volume | Increase `POLL_TIMEOUT_SEC` in config or run during off-peak |
| JSON load errors | Mismatch between JSON structure and target table DDL | Run `Get Actual Field Names from BOSS API Response` helper |

---

## 9. Maintenance

### 9.1 Clean Up Completed Scheduler Jobs

Scheduler jobs with `AUTO_DROP = TRUE` clean themselves up automatically. To manually drop lingering jobs:

```sql
-- Drop all BOSS extract jobs (use with caution)
BEGIN
  FOR r IN (
    SELECT job_name FROM user_scheduler_jobs
    WHERE job_name LIKE 'BOSS_EXT_%'
  ) LOOP
    DBMS_SCHEDULER.DROP_JOB(r.job_name, force => TRUE);
  END LOOP;
END;
/
```

### 9.2 Purge Old Job Logs

```sql
-- Remove job logs older than 90 days
DELETE FROM xx_int_extract_job_log
WHERE creation_date < SYSDATE - 90;
COMMIT;

-- Remove ETL detail logs older than 90 days
DELETE FROM spectra_worker_etl_log_dtl
WHERE created_ts < SYSTIMESTAMP - INTERVAL '90' DAY;
COMMIT;
```

### 9.3 Rebuild All Queries

After modifying field/accessor configurations, rebuild all API queries:

```sql
BEGIN
  xx_boss_query_builder_pkg.rebuild_all_queries(p_instance_code => 'DEV1');
END;
/
```

### 9.4 Discover API Response Fields

To see what fields an API endpoint actually returns (useful when setting up a new extract):

```sql
-- Refer to: "Get Actual Field Names from BOSS API Response" helper script
-- This queries the BOSS API and prints available field names
```

---

## 10. Appendix – Extracted Entities

Over 100 extract configurations are pre-seeded covering the following HCM data domains:

### Employment & Assignments
- Worker Assignments
- Work Relationships
- Employment History
- Manager Hierarchy
- Object Change Extracts

### Organization Structure
- Jobs & Job Families
- Grades & Grade Steps
- Positions
- Locations
- Departments
- Business Units

### Person Data
- Person Names
- Email Addresses
- Phone Numbers
- Physical Addresses
- Person Identifiers
- Passports & Travel Documents
- Visas & Permits
- Person Images

### Compensation & Payroll
- Payroll Elements
- Salary Costing
- Tax Reporting Units
- Legislative Information
- Collective Agreements

### Relationships & Contacts
- Emergency Contacts
- Dependents & Beneficiaries
- Person Types

### Reference Data
- Actions & Action Reasons
- Assignment Statuses

---

*Documentation generated: March 2026*
*Project: HCM RODS – Oracle Cloud HCM Read-Only Data Store*
