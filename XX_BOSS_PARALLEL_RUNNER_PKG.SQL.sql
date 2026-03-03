--------------------------------------------------------
--  File created - Saturday-February-28-2026   
--------------------------------------------------------
--------------------------------------------------------
--  DDL for Package XX_BOSS_PARALLEL_RUNNER_PKG
--------------------------------------------------------

  CREATE OR REPLACE EDITIONABLE PACKAGE "XX_INT"."XX_BOSS_PARALLEL_RUNNER_PKG" AS
  
  -- Main procedure to run all extracts in parallel
  PROCEDURE run_all_extracts_parallel(
    p_instance_code   IN VARCHAR2 DEFAULT 'DEV1',
    p_effective_date  IN VARCHAR2 DEFAULT NULL,  -- Format: 'YYYY-MM-DD', NULL = SYSDATE-365
    p_multi_file      IN BOOLEAN DEFAULT TRUE
  );

  -- Monitor job status
  PROCEDURE monitor_job_status(
    p_batch_id IN VARCHAR2
  );

END xx_boss_parallel_runner_pkg;

/
