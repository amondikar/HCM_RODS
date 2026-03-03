--------------------------------------------------------
--  File created - Saturday-February-28-2026   
--------------------------------------------------------
--------------------------------------------------------
--  DDL for Package PKG_SPECTRA_WORKER_ETL_V4
--------------------------------------------------------

  CREATE OR REPLACE EDITIONABLE PACKAGE  "PKG_SPECTRA_WORKER_ETL_V4" AS

  ----------------------------------------------------------------
  -- Package: PKG_SPECTRA_WORKER_ETL_V4
  -- Purpose: Oracle SaaS Extract ETL Framework
  -- Version: 4.0 - Multi-file support added
  ----------------------------------------------------------------

  ----------------------------------------------------------------
  -- Direct Parameter Version (Backward Compatible)
  -- Use when you want to pass parameters directly
  ----------------------------------------------------------------
  PROCEDURE run_extract_direct(
    p_oauth_token_url    IN VARCHAR2,
    p_client_id          IN VARCHAR2,
    p_client_secret      IN VARCHAR2,
    p_scope_saas_batch   IN VARCHAR2,
    p_api_base_url       IN VARCHAR2,
    p_module_name        IN VARCHAR2,
    p_resource_name      IN VARCHAR2,
    p_target_table       IN VARCHAR2,
    p_advanced_query     IN CLOB,
    p_json_array_path    IN VARCHAR2 DEFAULT 'items',
    p_truncate           IN BOOLEAN DEFAULT TRUE
  );

  ----------------------------------------------------------------
  -- Configuration-Driven Execution (Recommended)
  -- NEW: Added p_multi_file parameter for multi-file support
  ----------------------------------------------------------------
  PROCEDURE run_extract_by_config(
    p_config_name    IN VARCHAR2,
    p_effective_date IN VARCHAR2 DEFAULT NULL,
    p_multi_file     IN BOOLEAN DEFAULT TRUE  -- NEW: Enable multi-file processing
  );

  ----------------------------------------------------------------
  -- OAuth Token Generation
  ----------------------------------------------------------------
  FUNCTION get_oauth_token(
    p_token_url    IN VARCHAR2,
    p_client_id    IN VARCHAR2,
    p_client_secret IN VARCHAR2,
    p_scope        IN VARCHAR2
  ) RETURN VARCHAR2;
  FUNCTION get_oauth_token_apex(
    p_token_url    IN VARCHAR2,
    p_client_id    IN VARCHAR2,
    p_client_secret IN VARCHAR2,
    p_scope        IN VARCHAR2
  ) RETURN VARCHAR2;
  FUNCTION get_oauth_token_apex1(
    p_token_url    IN VARCHAR2,
    p_client_id    IN VARCHAR2,
    p_client_secret IN VARCHAR2,
    p_scope        IN VARCHAR2
  ) RETURN VARCHAR2;
  FUNCTION get_oauth_token_apex2(
    p_token_url    IN VARCHAR2,
    p_client_id    IN VARCHAR2,
    p_client_secret IN VARCHAR2,
    p_scope        IN VARCHAR2
  ) RETURN VARCHAR2;

  ----------------------------------------------------------------
  -- Submit Extract Job
  ----------------------------------------------------------------
  FUNCTION submit_extract_job(
    p_job_request_url IN VARCHAR2,
    p_module_name     IN VARCHAR2,
    p_resource_name   IN VARCHAR2,
    p_version         IN VARCHAR2,
    p_format          IN VARCHAR2,
    p_advanced_query  IN CLOB,
    p_effective_date  IN VARCHAR2
  ) RETURN VARCHAR2;

  ----------------------------------------------------------------
  -- Poll Extract Status
  ----------------------------------------------------------------
  PROCEDURE poll_extract_status(
    p_api_base_url   IN VARCHAR2,
    p_request_id     IN VARCHAR2,
    p_poll_interval  IN NUMBER,
    p_timeout        IN NUMBER,
    p_status         OUT VARCHAR2,
    p_file_id        OUT VARCHAR2,
    p_output_url     OUT VARCHAR2
  );

  ----------------------------------------------------------------
  -- Download Extract Output (File Metadata)
  ----------------------------------------------------------------
  FUNCTION download_extract_output(
    p_file_id    IN VARCHAR2,
    p_output_url IN VARCHAR2
  ) RETURN CLOB;

  ----------------------------------------------------------------
  -- Download Single Job Output File (Backward Compatible)
  ----------------------------------------------------------------
  PROCEDURE download_job_output_file(
    p_run_id           IN NUMBER,
    p_request_id       IN VARCHAR2,
    p_outputfiles_json IN CLOB,
    p_oauth_token      IN VARCHAR2,
    p_file_name        OUT VARCHAR2,
    p_download_url     OUT VARCHAR2
  );

  ----------------------------------------------------------------
  -- NEW: Download Multiple Job Output Files
  -- Downloads ALL files from the JSON response
  ----------------------------------------------------------------
  PROCEDURE download_job_output_files_multi(
    p_run_id           IN NUMBER,
    p_request_id       IN VARCHAR2,
    p_outputfiles_json IN CLOB,
    p_oauth_token      IN VARCHAR2,
    p_files_downloaded OUT NUMBER
  );

  ----------------------------------------------------------------
  -- Unzip and Load Worker Assignments (Single File - Backward Compatible)
  ----------------------------------------------------------------
  PROCEDURE unzip_and_load_worker_assignments(
    p_run_id     IN NUMBER,
    p_request_id IN VARCHAR2
  );

  ----------------------------------------------------------------
  -- NEW: Unzip and Load Multiple Files
  -- Processes ALL downloaded files for a request
  ----------------------------------------------------------------
  PROCEDURE unzip_and_load_multi_files(
    p_run_id          IN NUMBER,
    p_request_id      IN VARCHAR2,
    p_table_name      IN VARCHAR2,
    p_json_array_path IN VARCHAR2 DEFAULT 'items',
    p_truncate_first  IN BOOLEAN DEFAULT TRUE
  );

  ----------------------------------------------------------------
  -- NEW: Unzip and Load Single File (Helper)
  -- Processes a single file blob
  ----------------------------------------------------------------
  PROCEDURE unzip_and_load_single_file(
    p_run_id          IN NUMBER,
    p_request_id      IN VARCHAR2,
    p_file_name       IN VARCHAR2,
    p_file_blob       IN BLOB,
    p_table_name      IN VARCHAR2,
    p_json_array_path IN VARCHAR2 DEFAULT 'items',
    p_truncate        IN BOOLEAN DEFAULT FALSE
  );

  ----------------------------------------------------------------
  -- Load JSON to Table
  ----------------------------------------------------------------
  PROCEDURE load_json_to_table(
    p_run_id          IN NUMBER,
    p_request_id      IN VARCHAR2,
    p_json            IN CLOB,
    p_table_name      IN VARCHAR2,
    p_json_array_path IN VARCHAR2 DEFAULT 'items',
    p_truncate        IN BOOLEAN DEFAULT TRUE
  );

  ----------------------------------------------------------------
  -- Logging Utility
  ----------------------------------------------------------------
  PROCEDURE log_etl(
    p_step IN VARCHAR2,
    p_msg  IN VARCHAR2,
    p_clob IN CLOB DEFAULT NULL
  );

END pkg_spectra_worker_etl_v4;

/

