--------------------------------------------------------
--  File created - Saturday-February-28-2026   
--------------------------------------------------------
--------------------------------------------------------
--  DDL for Package Body XX_BOSS_PARALLEL_RUNNER_PKG
--------------------------------------------------------

  CREATE OR REPLACE EDITIONABLE PACKAGE BODY "XX_INT"."XX_BOSS_PARALLEL_RUNNER_PKG" AS

  -- ========================================
  -- Run All Extracts in Parallel
  -- ========================================
  PROCEDURE run_all_extracts_parallel(
    p_instance_code   IN VARCHAR2 DEFAULT 'DEV1',
    p_effective_date  IN VARCHAR2 DEFAULT NULL,
    p_multi_file      IN BOOLEAN DEFAULT TRUE
  ) IS  
    
    l_job_name        VARCHAR2(100);
    l_job_count       NUMBER := 0;
    l_batch_id        VARCHAR2(100);
    l_effective_date  VARCHAR2(20);
    l_multi_file_str  VARCHAR2(10);
    l_error_msg        VARCHAR2(4000);
    l_query            clob;
    l_target_tbl_name  VARCHAR2(100);
    CURSOR c_configs IS
      SELECT config_name,target_table_name
      FROM xx_int_saas_extract_config
      WHERE instance_code = p_instance_code AND ENABLED='Y' 
      /*and 
      config_name in (
      'managerHierarchy_v20',
'objectChangeExtracts_v1',
'WORKER_ASSIGNMENTS_DEV1')
*/
      ORDER BY config_name;

  BEGIN

    -- Generate batch ID
    l_batch_id := 'BATCH_' || TO_CHAR(SYSDATE, 'YYYYMMDD_HH24MISS');

    -- Set default effective date if not provided
    l_effective_date := NVL(p_effective_date, TO_CHAR(SYSDATE-365, 'YYYY-MM-DD'));

    -- Convert boolean to string for dynamic SQL
    l_multi_file_str := CASE WHEN p_multi_file THEN 'TRUE' ELSE 'FALSE' END;

    DBMS_OUTPUT.PUT_LINE('========================================');
    DBMS_OUTPUT.PUT_LINE('BOSS Extract Parallel Execution');
    DBMS_OUTPUT.PUT_LINE('Batch ID: ' || l_batch_id);
    DBMS_OUTPUT.PUT_LINE('Instance: ' || p_instance_code);
    DBMS_OUTPUT.PUT_LINE('Effective Date: ' || l_effective_date);
    DBMS_OUTPUT.PUT_LINE('Multi-file: ' || l_multi_file_str);
    DBMS_OUTPUT.PUT_LINE('========================================');
  DBMS_OUTPUT.PUT_LINE('========================================');
    DBMS_OUTPUT.PUT_LINE('Building queries for all configs...');
    DBMS_OUTPUT.PUT_LINE('Target Table to be refreshed ...'  );
    DBMS_OUTPUT.PUT_LINE('========================================');
    
    -- Build all queries first
    FOR rec IN c_configs LOOP
      BEGIN
      l_query := xx_boss_query_builder_pkg.build_advanced_query(rec.config_name);
      l_target_tbl_name := rec.target_table_name ;
     DBMS_OUTPUT.PUT_LINE('Built query for: ' || rec.config_name || ' Table : '||l_target_tbl_name);
       -- Step 1: Rebuild all queries BEFORE submitting jobs
/*BEGIN
  xx_boss_simple_query_pkg.rebuild_all_queries(p_instance_code);   
 -- DBMS_OUTPUT.PUT_LINE('✓ All queries rebuilt successfully');
END;*/
      EXCEPTION
        WHEN OTHERS THEN
          DBMS_OUTPUT.PUT_LINE('ERROR building query for ' || rec.config_name || ': ' || SQLERRM);
      END;
    END LOOP;
    
    DBMS_OUTPUT.PUT_LINE('========================================');
    DBMS_OUTPUT.PUT_LINE('BOSS Extract Parallel Execution');
    DBMS_OUTPUT.PUT_LINE('Batch ID: ' || l_batch_id);
    DBMS_OUTPUT.PUT_LINE('Instance: ' || p_instance_code);
    DBMS_OUTPUT.PUT_LINE('Effective Date: ' || l_effective_date);
    DBMS_OUTPUT.PUT_LINE('========================================');
    -- Create log entries for tracking
    FOR rec IN c_configs LOOP
      INSERT INTO xx_int_extract_job_log (
        log_id,
        batch_id,
        config_name,
        status,
        submission_time,
        created_by,
        creation_date,target_table_name
      ) VALUES (
        xx_int_extract_job_log_seq.NEXTVAL,
        l_batch_id,
        rec.config_name,
        'QUEUED',
        SYSDATE,
        USER,
        SYSDATE,rec.target_table_name
      );
    END LOOP;
    COMMIT;

    -- Submit each extract job in parallel using DBMS_SCHEDULER
    FOR rec IN c_configs LOOP

      l_job_count := l_job_count + 1;
      l_job_name := 'BOSS_EXT_' || SUBSTR(REPLACE(rec.config_name, ' ', '_'), 1, 15) || '_' || l_job_count;

      DBMS_OUTPUT.PUT_LINE('Submitting: ' || rec.config_name || ' as job ' || l_job_name);

      -- Create and start scheduler job
      BEGIN
        DBMS_SCHEDULER.CREATE_JOB(
          job_name        => l_job_name,
          job_type        => 'PLSQL_BLOCK',
          job_action      => 'DECLARE
            l_error_msg        VARCHAR2(4000);
                                l_start_time DATE := SYSDATE;
                              BEGIN
                                -- Update status to RUNNING
                                UPDATE xx_int_extract_job_log
                                SET status = ''RUNNING'',
                                    submission_time = SYSDATE
                                WHERE batch_id = ''' || l_batch_id || '''
                                AND config_name = ''' || rec.config_name || ''';
                                COMMIT;

                                -- Execute the actual ETL procedure
                                xx_int.pkg_spectra_worker_etl_v4.run_extract_by_config(
                                  p_config_name => ''' || rec.config_name || ''',
                                  p_effective_date => ''' || l_effective_date || ''',
                                  p_multi_file => ' || l_multi_file_str || '
                                );

                                -- Update status to COMPLETED
                                UPDATE xx_int_extract_job_log
                                SET status = ''COMPLETED'',
                                    completion_time = SYSDATE
                                WHERE batch_id = ''' || l_batch_id || '''
                                AND config_name = ''' || rec.config_name || ''';
                                COMMIT;

                              EXCEPTION
                                WHEN OTHERS THEN
                                l_error_msg := SQLERRM; 
                                  -- Update status to ERROR
                                  UPDATE xx_int_extract_job_log
                                  SET status = ''ERROR'',
                                      error_message =   SUBSTR(l_error_msg, 1, 4000),
                                      completion_time = SYSDATE
                                  WHERE batch_id = ''' || l_batch_id || '''
                                  AND config_name = ''' || rec.config_name || ''';
                                  COMMIT;
                                  RAISE;
                              END;',
          start_date      => SYSTIMESTAMP,
          enabled         => TRUE,
          auto_drop       => TRUE,
          comments        => 'BOSS Extract: ' || rec.config_name
        );
      EXCEPTION
        WHEN OTHERS THEN
          DBMS_OUTPUT.PUT_LINE('ERROR creating job for ' || rec.config_name || ': ' || SQLERRM);
l_error_msg := SQLERRM; 
          -- Update log with error
          UPDATE xx_int_extract_job_log
          SET status = 'ERROR',
              error_message = 'Failed to create scheduler job: ' ||        SUBSTR(l_error_msg, 1, 4000)
          WHERE batch_id = l_batch_id
          AND config_name = rec.config_name;
          COMMIT;
      END;

    END LOOP;

    DBMS_OUTPUT.PUT_LINE('========================================');
    DBMS_OUTPUT.PUT_LINE('Total Jobs Submitted: ' || l_job_count);
    DBMS_OUTPUT.PUT_LINE('Batch ID: ' || l_batch_id);
    DBMS_OUTPUT.PUT_LINE('All jobs are running in parallel!');
    DBMS_OUTPUT.PUT_LINE('========================================');
    DBMS_OUTPUT.PUT_LINE(' ');
    DBMS_OUTPUT.PUT_LINE('To monitor progress, run:');
    DBMS_OUTPUT.PUT_LINE('BEGIN');
    DBMS_OUTPUT.PUT_LINE('  xx_boss_parallel_runner_pkg.monitor_job_status(');
    DBMS_OUTPUT.PUT_LINE('    p_batch_id => ''' || l_batch_id || '''');
    DBMS_OUTPUT.PUT_LINE('  );');
    DBMS_OUTPUT.PUT_LINE('END;');
    DBMS_OUTPUT.PUT_LINE('/');
    DBMS_OUTPUT.PUT_LINE('========================================');

  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('ERROR: ' || SQLERRM);
      RAISE;
  END run_all_extracts_parallel;

  -- ========================================
  -- Monitor Job Status
  -- ========================================
  PROCEDURE monitor_job_status(
    p_batch_id IN VARCHAR2
  ) IS

    l_total_jobs     NUMBER;
    l_completed_jobs NUMBER;
    l_error_jobs     NUMBER;
    l_running_jobs   NUMBER;
    l_queued_jobs    NUMBER;

  BEGIN

    SELECT 
      COUNT(*),
      SUM(CASE WHEN status = 'COMPLETED' THEN 1 ELSE 0 END),
      SUM(CASE WHEN status = 'ERROR' THEN 1 ELSE 0 END),
      SUM(CASE WHEN status = 'RUNNING' THEN 1 ELSE 0 END),
      SUM(CASE WHEN status = 'QUEUED' THEN 1 ELSE 0 END)
    INTO
      l_total_jobs,
      l_completed_jobs,
      l_error_jobs,
      l_running_jobs,
      l_queued_jobs
    FROM xx_int_extract_job_log
    WHERE batch_id = p_batch_id;

    DBMS_OUTPUT.PUT_LINE('========================================');
    DBMS_OUTPUT.PUT_LINE('Job Status for Batch: ' || p_batch_id);
    DBMS_OUTPUT.PUT_LINE('========================================');
    DBMS_OUTPUT.PUT_LINE('Total Jobs    : ' || l_total_jobs);
    DBMS_OUTPUT.PUT_LINE('Completed     : ' || l_completed_jobs);
    DBMS_OUTPUT.PUT_LINE('Running       : ' || l_running_jobs);
    DBMS_OUTPUT.PUT_LINE('Queued        : ' || l_queued_jobs);
    DBMS_OUTPUT.PUT_LINE('Errors        : ' || l_error_jobs);
    DBMS_OUTPUT.PUT_LINE('Progress      : ' || ROUND((l_completed_jobs/l_total_jobs)*100, 1) || '%');
    DBMS_OUTPUT.PUT_LINE('========================================');

    -- Show individual job details
    DBMS_OUTPUT.PUT_LINE('Job Details:');
    DBMS_OUTPUT.PUT_LINE('----------------------------------------');

    FOR rec IN (
      SELECT 
        config_name,
        status,
        TO_CHAR(submission_time, 'YYYY-MM-DD HH24:MI:SS') AS submission_time,
        TO_CHAR(completion_time, 'YYYY-MM-DD HH24:MI:SS') AS completion_time,
        ROUND((completion_time - submission_time) * 24 * 60, 1) AS duration_minutes,
        error_message
      FROM xx_int_extract_job_log
      WHERE batch_id = p_batch_id
      ORDER BY submission_time
    ) LOOP
      DBMS_OUTPUT.PUT_LINE(
        RPAD(rec.config_name, 40) || ' | ' ||
        RPAD(rec.status, 12) || ' | ' ||
        NVL(TO_CHAR(rec.duration_minutes), 'N/A') || ' min'
      );

      IF rec.error_message IS NOT NULL THEN
        DBMS_OUTPUT.PUT_LINE('  ERROR: ' || SUBSTR(rec.error_message, 1, 200));
      END IF;
    END LOOP;

  END monitor_job_status;

END xx_boss_parallel_runner_pkg;

/
