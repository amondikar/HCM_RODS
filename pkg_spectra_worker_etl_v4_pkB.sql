--------------------------------------------------------
--  File created - Saturday-February-28-2026   
--------------------------------------------------------
--------------------------------------------------------
--  DDL for Package Body PKG_SPECTRA_WORKER_ETL_V4
--------------------------------------------------------

  CREATE OR REPLACE EDITIONABLE PACKAGE BODY  "PKG_SPECTRA_WORKER_ETL_V4" AS

  ----------------------------------------------------------------
  -- Global variables
  ----------------------------------------------------------------
  g_run_id NUMBER;
  g_oauth_token VARCHAR2(4000);
  g_config_rec xx_int_saas_extract_config%ROWTYPE;

  ----------------------------------------------------------------
  -- Logging
  ----------------------------------------------------------------
  PROCEDURE log_etl(
    p_step IN VARCHAR2,
    p_msg  IN VARCHAR2,
    p_clob IN CLOB DEFAULT NULL
  ) IS
    PRAGMA AUTONOMOUS_TRANSACTION;
    l_text VARCHAR2(4000);
  BEGIN
    IF g_run_id IS NULL THEN
      RETURN;
    END IF;

    l_text := '[' || SUBSTR(p_step, 1, 40) || '] ' || SUBSTR(p_msg, 1, 3500);

    IF p_clob IS NOT NULL THEN
      l_text := l_text || ' | CLOB=' || DBMS_LOB.SUBSTR(p_clob, 500, 1);
    END IF;

    INSERT INTO spectra_worker_etl_log (status, message)
    VALUES ('log', l_text);

    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      NULL;
  END log_etl;

  ----------------------------------------------------------------
  -- Insert Log Detail (for detailed logging of large CLOBs)
  ----------------------------------------------------------------
  PROCEDURE insert_log_detail(
    p_run_id IN NUMBER,
    p_step   IN VARCHAR2,
    p_clob   IN CLOB
  ) IS
    PRAGMA AUTONOMOUS_TRANSACTION;
    l_pos   PLS_INTEGER := 1;
    l_seq   PLS_INTEGER := 1;
    l_chunk VARCHAR2(3900);
  BEGIN
    IF p_clob IS NULL THEN
      INSERT INTO xx_int.spectra_worker_etl_log_dtl (run_id, step_name, seq_no, message_text)
      VALUES (p_run_id, p_step, 1, '[NULL RESPONSE]');
      COMMIT;
      RETURN;
    END IF;

    WHILE l_pos <= DBMS_LOB.getlength(p_clob) LOOP
      l_chunk := DBMS_LOB.substr(p_clob, 3900, l_pos);
      INSERT INTO xx_int.spectra_worker_etl_log_dtl (run_id, step_name, seq_no, message_text)
      VALUES (p_run_id, p_step, l_seq, l_chunk);
      l_pos := l_pos + 3900;
      l_seq := l_seq + 1;
    END LOOP;

    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      NULL;
  END insert_log_detail;

  ----------------------------------------------------------------
  -- Get OAuth Token (parameterized)
  ----------------------------------------------------------------
  FUNCTION get_oauth_token(
    p_token_url      IN VARCHAR2,
    p_client_id      IN VARCHAR2,
    p_client_secret  IN VARCHAR2,
    p_scope          IN VARCHAR2
  ) RETURN VARCHAR2 IS
    l_req    UTL_HTTP.req;
    l_resp   UTL_HTTP.resp;
    l_body   VARCHAR2(4000);
    l_buffer VARCHAR2(32767);
    l_json   CLOB;
    l_token  VARCHAR2(4000);
  BEGIN
    l_body := 'grant_type=client_credentials' ||
              CHR(38) || 'scope=' || UTL_URL.escape(p_scope) ||
              CHR(38) || 'client_id=' || UTL_URL.escape(p_client_id) ||
              CHR(38) || 'client_secret=' || UTL_URL.escape(p_client_secret);

    log_etl('HTTP_PRE', 'Calling URL=' || p_token_url);
    insert_log_detail(g_run_id, 'HTTP_BODY_TOKEN_REQ', l_body);

    l_req := UTL_HTTP.begin_request(p_token_url, 'POST', 'HTTP/1.1');
    UTL_HTTP.set_header(l_req, 'Content-Type', 'application/x-www-form-urlencoded');
    UTL_HTTP.set_header(l_req, 'Content-Length', LENGTH(l_body));
    UTL_HTTP.write_text(l_req, l_body);

    l_resp := UTL_HTTP.get_response(l_req);
    DBMS_LOB.createtemporary(l_json, TRUE);

    BEGIN
      LOOP
        UTL_HTTP.read_text(l_resp, l_buffer, 32767);
        DBMS_LOB.writeappend(l_json, LENGTH(l_buffer), l_buffer);
      END LOOP;
    EXCEPTION
      WHEN UTL_HTTP.END_OF_BODY THEN
        NULL;
    END;

    UTL_HTTP.end_response(l_resp);

    SELECT jt.access_token
    INTO l_token
    FROM JSON_TABLE(l_json, '$' COLUMNS (access_token VARCHAR2(4000) PATH '$.access_token')) jt;

    RETURN 'Bearer ' || l_token;
  END get_oauth_token;

  ----------------------------------------------------------------
  -- Submit Extract Job (parameterized)
  ----------------------------------------------------------------
  FUNCTION submit_extract_job(
    p_job_request_url IN VARCHAR2,
    p_module_name     IN VARCHAR2,
    p_resource_name   IN VARCHAR2,
    p_version         IN VARCHAR2,
    p_format          IN VARCHAR2,
    p_advanced_query  IN CLOB,
    p_effective_date  IN VARCHAR2
  ) RETURN VARCHAR2 IS
    l_req       UTL_HTTP.req;
    l_resp      UTL_HTTP.resp;
    l_payload   CLOB;
    l_buffer    VARCHAR2(32767);
    l_body      CLOB;
    l_hdrs      CLOB;
    l_location  VARCHAR2(4000);
    l_adv_query_final CLOB;
  BEGIN
    DBMS_LOB.createtemporary(l_hdrs, TRUE);
    DBMS_LOB.createtemporary(l_body, TRUE);

    -- Replace {{EFFECTIVE_DATE}} placeholder in advanced query
    l_adv_query_final := REPLACE(p_advanced_query, '{{EFFECTIVE_DATE}}', NVL(p_effective_date, TO_CHAR(SYSDATE, 'YYYY-MM-DD')));

    -- Build payload
    SELECT JSON_OBJECT(
             'jobDefinitionName' VALUE 'AsyncDataExtraction',
             'serviceName' VALUE 'boss',
             'requestParameters' VALUE JSON_OBJECT(
               'boss.module' VALUE p_module_name,
               'boss.resource.name' VALUE p_resource_name,
               'boss.resource.version' VALUE p_version,
               'boss.outputFormat' VALUE p_format,
               'boss.request.system.param.effectiveDate' VALUE NVL(p_effective_date, TO_CHAR(SYSDATE, 'YYYY-MM-DD')),
               'boss.advancedQuery' VALUE ('' || l_adv_query_final)
             )
             RETURNING CLOB
           )
    INTO l_payload
    FROM dual;

    insert_log_detail(g_run_id, 'PAYLOAD_SENT', l_payload);

    l_req := UTL_HTTP.begin_request(p_job_request_url, 'POST', 'HTTP/1.1');
    UTL_HTTP.set_header(l_req, 'Content-Type', 'application/json');
    UTL_HTTP.set_header(l_req, 'Accept', 'application/json');
    UTL_HTTP.set_header(l_req, 'Authorization', g_oauth_token);
    UTL_HTTP.set_header(l_req, 'Content-Length', DBMS_LOB.getlength(l_payload));
    UTL_HTTP.write_text(l_req, l_payload);

    l_resp := UTL_HTTP.get_response(l_req);

    -- Read headers to get Location
    FOR i IN 1 .. UTL_HTTP.get_header_count(l_resp) LOOP
      DECLARE
        l_name  VARCHAR2(4000);
        l_value VARCHAR2(4000);
      BEGIN
        UTL_HTTP.get_header(l_resp, i, l_name, l_value);
        IF LOWER(l_name) = 'location' THEN
          l_location := l_value;
        END IF;
      END;
    END LOOP;

    -- Read body
    BEGIN
      LOOP
        UTL_HTTP.read_text(l_resp, l_buffer, 32767);
        DBMS_LOB.append(l_body, l_buffer);
      END LOOP;
    EXCEPTION
      WHEN UTL_HTTP.end_of_body THEN
        NULL;
    END;

    UTL_HTTP.end_response(l_resp);
    insert_log_detail(g_run_id, 'HTTP_BODY', l_body);

    RETURN REGEXP_SUBSTR(l_location, '[^/]+$', 1, 1);
  END submit_extract_job;

  ----------------------------------------------------------------
  -- Poll Status (parameterized)
  ----------------------------------------------------------------
  PROCEDURE poll_extract_status(
    p_api_base_url   IN VARCHAR2,
    p_request_id     IN VARCHAR2,
    p_poll_interval  IN NUMBER,
    p_timeout        IN NUMBER,
    p_status         OUT VARCHAR2,
    p_file_id        OUT VARCHAR2,
    p_output_url     OUT VARCHAR2
  ) IS
    l_req     UTL_HTTP.req;
    l_resp    UTL_HTTP.resp;
    l_url     VARCHAR2(4000);
    l_buffer  VARCHAR2(32767);
    l_json    CLOB;
    l_elapsed PLS_INTEGER := 0;
  BEGIN
    l_url := p_api_base_url || '/api/saas-batch/jobscheduler/v1/jobRequests/' || p_request_id || '/jobStatus';

    LOOP
      log_etl('POLL_STATUS_BEGIN', 'requestId=' || p_request_id);

      DBMS_LOB.createtemporary(l_json, TRUE);

      l_req := UTL_HTTP.begin_request(l_url, 'GET', 'HTTP/1.1');
      UTL_HTTP.set_header(l_req, 'Accept', 'application/json');
      UTL_HTTP.set_header(l_req, 'Authorization', g_oauth_token);

      l_resp := UTL_HTTP.get_response(l_req);

      BEGIN
        LOOP
          UTL_HTTP.read_text(l_resp, l_buffer, 32767);
          DBMS_LOB.append(l_json, l_buffer);
        END LOOP;
      EXCEPTION
        WHEN UTL_HTTP.end_of_body THEN
          NULL;
      END;

      UTL_HTTP.end_response(l_resp);

      IF l_json IS JSON THEN
        BEGIN
          SELECT jt.status, jt.file_id, jt.related_output_files
          INTO p_status, p_file_id, p_output_url
          FROM JSON_TABLE(
                 l_json, '$'
                 COLUMNS (
                   status VARCHAR2(50) PATH '$.status',
                   file_id VARCHAR2(200) PATH '$.id',
                   related_output_files VARCHAR2(2000) PATH '$.related_output_files'
                 )
               ) jt;

          log_etl('POLL_PARSED', 'status=' || NVL(p_status, '(null)')||p_output_url);
        EXCEPTION
          WHEN OTHERS THEN
            log_etl('POLL_JSONTABLE_ERR', SQLERRM);
        END;
      END IF;

      IF p_status IN ('SUCCEEDED', 'FAILED', 'CANCELED', 'WARNING') THEN
        log_etl('POLL_DONE', 'Final status=' || p_status ||p_output_url);
        EXIT;
      END IF;

      DBMS_SESSION.sleep(p_poll_interval);
      l_elapsed := l_elapsed + p_poll_interval;

      IF l_elapsed > p_timeout THEN
        RAISE_APPLICATION_ERROR(-20002, 'Poll timeout waiting for extract completion');
      END IF;

      IF DBMS_LOB.istemporary(l_json) = 1 THEN
        DBMS_LOB.freetemporary(l_json);
      END IF;
    END LOOP;
  END poll_extract_status;

----------------------------------------------------------------
  -- Direct Parameter Version (Backward Compatible)
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
  ) IS
    l_run_id      NUMBER;
    l_status      VARCHAR2(30);
    l_request_id  VARCHAR2(200);
    l_file_id     VARCHAR2(200);
    l_output_url  VARCHAR2(1000);
    l_json        CLOB;
    l_file_name   VARCHAR2(200);
    l_download_href VARCHAR2(1000);
    l_effective_date VARCHAR2(20);
  BEGIN
    -- Start log
    INSERT INTO spectra_worker_etl_log (status, message)
    VALUES ('STARTED', 'ETL run initiated (direct parameters)')
    RETURNING run_id INTO l_run_id;
    g_run_id := l_run_id;

    log_etl('START', 'Direct execution started');

    l_effective_date := TO_CHAR(SYSDATE, 'YYYY-MM-DD');

    -- Get OAuth token
    g_oauth_token := get_oauth_token_apex2(
      p_oauth_token_url,
      p_client_id,
      p_client_secret,
      p_scope_saas_batch
    );

    log_etl('TOKEN', 'OAuth token received');

    -- Submit extract job
    l_request_id := submit_extract_job(
      p_api_base_url || '/api/saas-batch/jobscheduler/v1/jobRequests',
      p_module_name,
      p_resource_name,
      'v1',  -- default version
      'json', -- default format
      p_advanced_query,
      l_effective_date
    );

    log_etl('SUBMIT', 'Job submitted: ' || l_request_id);

    -- Poll status (use default timeouts)
    poll_extract_status(
      p_api_base_url,
      l_request_id,
      10,  -- default poll interval
      600, -- default timeout
      l_status,
      l_file_id,
      l_output_url
    );

    log_etl('POLL', 'Status: ' || l_status);

    IF l_status <> 'SUCCEEDED' THEN
      RAISE_APPLICATION_ERROR(-20001, 'Extract failed with status: ' || l_status);
    END IF;

    -- Download file metadata
    l_json := download_extract_output(l_file_id, l_output_url);

    log_etl('DOWNLOAD_META', 'File metadata retrieved');

    -- Get download URL from metadata
    SELECT jt.file_name, jt.download_href
    INTO l_file_name, l_download_href
    FROM JSON_TABLE(
      l_json, '$.items[*]'
      COLUMNS (
        file_name VARCHAR2(200) PATH '$.fileName',
        download_href VARCHAR2(4000) PATH '$."$context".links.enclosure.href'
      )
    ) jt
    FETCH FIRST 1 ROW ONLY;

    log_etl('DOWNLOAD_URL', l_download_href);

    -- Download actual file
    download_job_output_file(
      p_run_id => g_run_id,
      p_request_id => l_request_id,
      p_outputfiles_json => l_json,
      p_oauth_token => g_oauth_token,
      p_file_name => l_file_name,
      p_download_url => l_download_href
    );

    log_etl('DOWNLOADED', l_file_name);

    -- Unzip and load
    unzip_and_load_worker_assignments(g_run_id, l_request_id);

    log_etl('LOADED', 'Data loaded to table: ' || p_target_table);

    -- Update log
    UPDATE spectra_worker_etl_log
    SET end_time = SYSDATE,
        status = 'SUCCEEDED',
        message = 'ETL completed successfully',
        request_id = l_request_id
    WHERE run_id = l_run_id;

    COMMIT;

  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DECLARE
  l_err VARCHAR2(4000);
BEGIN
  l_err := SUBSTR(SQLERRM, 1, 4000);
      UPDATE spectra_worker_etl_log
      SET end_time = SYSDATE,
          status = 'ERROR',
          message = 'ERROR=' || l_err || CHR(10) ||
                   'STACK=' || DBMS_UTILITY.format_error_stack || CHR(10) ||
                   'BACKTRACE=' || DBMS_UTILITY.format_error_backtrace
      WHERE run_id = l_run_id;
      COMMIT;
      RAISE;
      END;
  END run_extract_direct;
  ----------------------------------------------------------------
  -- Download Extract Output (from original code)
  ----------------------------------------------------------------
  FUNCTION download_extract_output(
    p_file_id IN VARCHAR2,
    p_output_url IN VARCHAR2
  ) RETURN CLOB IS
    l_req UTL_HTTP.req;
    l_resp UTL_HTTP.resp;
    l_url VARCHAR2(4000);
    l_http_code varchar2(100);
    l_buffer VARCHAR2(32767);
    l_json CLOB;
      c_extract_file_base_url CONSTANT VARCHAR2(4000) :=
        'https://fa-espx-dev1-saasfaprod1.fa.ocs.oraclecloud.com/api/saas-batch/jobfilemanager/v1/jobRequests/{{jobRequestId}}/outputFiles';

  BEGIN
    l_url := REPLACE(c_extract_file_base_url, 
                     '{{jobRequestId}}', p_file_id);

    log_etl('HTTP_PRE', 'Calling URL=' || l_url);

    l_req := UTL_HTTP.begin_request(l_url, 'GET', 'HTTP/1.1');

    IF REGEXP_LIKE(g_oauth_token, '^\s*Bearer\s', 'i') THEN
      UTL_HTTP.set_header(l_req, 'Authorization', g_oauth_token);
    ELSE
      UTL_HTTP.set_header(l_req, 'Authorization', 'Bearer ' || g_oauth_token);
    END IF;

    UTL_HTTP.set_header(l_req, 'Accept', 'application/json');

    l_resp := UTL_HTTP.get_response(l_req);
    DBMS_LOB.createtemporary(l_json, TRUE);

    BEGIN
      LOOP
        UTL_HTTP.read_text(l_resp, l_buffer, 32767);
        DBMS_LOB.writeappend(l_json, LENGTH(l_buffer), l_buffer);
      END LOOP;
    EXCEPTION
      WHEN UTL_HTTP.END_OF_BODY THEN
        NULL;
    END;
        l_http_code := l_resp.status_code;
    log_etl('got l_http_code', l_http_code);

    log_etl('got download file name response', DBMS_LOB.SUBSTR(l_json, 3900, 1));
    UTL_HTTP.end_response(l_resp);

    RETURN l_json;
  END download_extract_output;

  ----------------------------------------------------------------
  -- Download Job Output File (from original code) - SINGLE FILE VERSION
  -- KEPT AS IS FOR BACKWARD COMPATIBILITY
  ----------------------------------------------------------------
  PROCEDURE download_job_output_file(
    p_run_id IN NUMBER,
    p_request_id IN VARCHAR2,
    p_outputfiles_json IN CLOB,
    p_oauth_token IN VARCHAR2,
    p_file_name OUT VARCHAR2,
    p_download_url OUT VARCHAR2
  ) IS
    l_req UTL_HTTP.req;
    l_resp UTL_HTTP.resp;
    l_raw RAW(32767);
    l_len PLS_INTEGER;
    l_blob BLOB;
    l_mime VARCHAR2(200);
    l_auth_hdr VARCHAR2(4000);
    l_name VARCHAR2(100);
    l_url VARCHAR2(4000);
  BEGIN
    -- Parse JSON to get first file
    SELECT jt.file_name, jt.download_href
    INTO p_file_name, p_download_url
    FROM JSON_TABLE(
      p_outputfiles_json, '$.items[*]'
      COLUMNS (
        file_name VARCHAR2(200) PATH '$.fileName',
        download_href VARCHAR2(4000) PATH '$."$context".links.enclosure.href'
      )
    ) jt
    FETCH FIRST 1 ROW ONLY;

    log_etl('DOWNLOAD_FILE', 'Downloading: ' || p_file_name || ' from ' || p_download_url);

    -- Download file
    l_url := p_download_url;
    l_req := UTL_HTTP.begin_request(l_url, 'GET', 'HTTP/1.1');

    IF REGEXP_LIKE(p_oauth_token, '^\s*Bearer\s', 'i') THEN
      UTL_HTTP.set_header(l_req, 'Authorization', p_oauth_token);
    ELSE
      UTL_HTTP.set_header(l_req, 'Authorization', 'Bearer ' || p_oauth_token);
    END IF;

    l_resp := UTL_HTTP.get_response(l_req);

    DBMS_LOB.createtemporary(l_blob, TRUE);

    BEGIN
      LOOP
        UTL_HTTP.read_raw(l_resp, l_raw, 32767);
        DBMS_LOB.writeappend(l_blob, UTL_RAW.length(l_raw), l_raw);
      END LOOP;
    EXCEPTION
      WHEN UTL_HTTP.END_OF_BODY THEN
        NULL;
    END;

    UTL_HTTP.end_response(l_resp);

    -- Store BLOB
    INSERT INTO xx_int_saas_job_files (run_id, request_id, file_name, download_url, mime_type, file_blob)
    VALUES (p_run_id, p_request_id, p_file_name, p_download_url, 'application/zip', l_blob);

    COMMIT;

    log_etl('FILE_STORED', 'File stored in table: ' || p_file_name || ' (size: ' || DBMS_LOB.getlength(l_blob) || ' bytes)');

  EXCEPTION
    WHEN OTHERS THEN
      log_etl('DOWNLOAD_ERROR', 'Error downloading file: ' || SQLERRM);
      RAISE;
  END download_job_output_file;

  ----------------------------------------------------------------
  -- NEW: Download Multiple Job Output Files 
  -- This procedure downloads ALL files from the JSON response
  ----------------------------------------------------------------
  PROCEDURE download_job_output_files_multi(
    p_run_id IN NUMBER,
    p_request_id IN VARCHAR2,
    p_outputfiles_json IN CLOB,
    p_oauth_token IN VARCHAR2,
    p_files_downloaded OUT NUMBER
  ) IS
    l_req UTL_HTTP.req;
    l_resp UTL_HTTP.resp;
    l_raw RAW(32767);
    l_blob BLOB;
    l_auth_hdr VARCHAR2(4000);
    l_url VARCHAR2(4000);
    l_file_count NUMBER := 0;

    -- Cursor to get all files from JSON
    CURSOR c_files IS
      SELECT jt.file_name,
             jt.file_size,
             jt.time_created,
             jt.file_href,
             jt.download_href
      FROM JSON_TABLE(
        p_outputfiles_json,
        '$.items[*]'
        COLUMNS (
          file_name     VARCHAR2(200)  PATH '$.fileName',
          file_size     NUMBER          PATH '$.fileSize',
          time_created  VARCHAR2(50)    PATH '$.timeCreated',
          file_href     VARCHAR2(4000)  PATH '$."$context".links."$self".href',
          download_href VARCHAR2(4000)  PATH '$."$context".links.enclosure.href'
        )
      ) jt;

  BEGIN
    log_etl('MULTI_DOWNLOAD_START', 'Starting multi-file download for request: ' || p_request_id);

    -- Loop through all files
    FOR rec IN c_files LOOP
      BEGIN
        l_file_count := l_file_count + 1;

        log_etl('DOWNLOAD_FILE_' || l_file_count, 
                'Downloading file: ' || rec.file_name || 
                ' (size: ' || rec.file_size || ' bytes)');

        -- Download file
        l_url := rec.download_href;
        l_req := UTL_HTTP.begin_request(l_url, 'GET', 'HTTP/1.1');

        IF REGEXP_LIKE(p_oauth_token, '^\s*Bearer\s', 'i') THEN
          UTL_HTTP.set_header(l_req, 'Authorization', p_oauth_token);
        ELSE
          UTL_HTTP.set_header(l_req, 'Authorization', 'Bearer ' || p_oauth_token);
        END IF;

        l_resp := UTL_HTTP.get_response(l_req);

        DBMS_LOB.createtemporary(l_blob, TRUE);

        BEGIN
          LOOP
            UTL_HTTP.read_raw(l_resp, l_raw, 32767);
            DBMS_LOB.writeappend(l_blob, UTL_RAW.length(l_raw), l_raw);
          END LOOP;
        EXCEPTION
          WHEN UTL_HTTP.END_OF_BODY THEN
            NULL;
        END;

        UTL_HTTP.end_response(l_resp);

        -- Store BLOB
        INSERT INTO xx_int_saas_job_files 
          (run_id, request_id, file_name, download_url, mime_type, file_blob)
        VALUES 
          (p_run_id, p_request_id, rec.file_name, rec.download_href, 'application/zip', l_blob);

        COMMIT;

        log_etl('FILE_STORED_' || l_file_count, 
                'File stored: ' || rec.file_name || 
                ' (' || DBMS_LOB.getlength(l_blob) || ' bytes downloaded)');

      EXCEPTION
        WHEN OTHERS THEN
          log_etl('DOWNLOAD_ERROR_FILE_' || l_file_count, 
                  'Error downloading file ' || rec.file_name || ': ' || SQLERRM);
          -- Fail entire job if any file fails
          RAISE_APPLICATION_ERROR(-20002, 
            'Failed to download file: ' || rec.file_name || ' - ' || SQLERRM);
      END;

    END LOOP;

    p_files_downloaded := l_file_count;

    log_etl('MULTI_DOWNLOAD_COMPLETE', 
            'Successfully downloaded ' || l_file_count || ' file(s)');

    IF l_file_count = 0 THEN
      RAISE_APPLICATION_ERROR(-20003, 
        'No files found in JSON response for request: ' || p_request_id);
    END IF;

  EXCEPTION
    WHEN OTHERS THEN
      log_etl('MULTI_DOWNLOAD_FAILED', 
              'Multi-file download failed: ' || SQLERRM);
      RAISE;
  END download_job_output_files_multi;

  ----------------------------------------------------------------
  -- NEW: Unzip and Load Multiple Files
  -- This procedure processes ALL downloaded files for a request
  ----------------------------------------------------------------
  PROCEDURE unzip_and_load_multi_files(
    p_run_id          IN NUMBER,
    p_request_id      IN VARCHAR2,
    p_table_name      IN VARCHAR2,
    p_json_array_path IN VARCHAR2 DEFAULT 'items',
    p_truncate_first  IN BOOLEAN DEFAULT TRUE,
    p_merge_key       IN VARCHAR2 DEFAULT NULL
  ) IS
    l_zip_blob BLOB;
    l_file_name VARCHAR2(200);
    l_files_processed NUMBER := 0;

    CURSOR c_files IS
      SELECT file_name, file_blob
      FROM xx_int_saas_job_files
      WHERE run_id = p_run_id
        AND request_id = p_request_id
      ORDER BY file_name;

  BEGIN
    log_etl('MULTI_UNZIP_START', 
            'Starting multi-file unzip and load for request: ' || p_request_id);

    FOR rec IN c_files LOOP
      BEGIN
        l_files_processed := l_files_processed + 1;

        log_etl('UNZIP_FILE_' || l_files_processed, 
                'Processing file: ' || rec.file_name);

        -- Call the existing unzip procedure for each file
        -- Assuming the existing procedure handles a single zip file
        unzip_and_load_single_file(
          p_run_id          => p_run_id,
          p_request_id      => p_request_id,
          p_file_name       => rec.file_name,
          p_file_blob       => rec.file_blob,
          p_table_name      => p_table_name,
          p_json_array_path => p_json_array_path,
          p_truncate        => (l_files_processed = 1 AND p_truncate_first AND p_merge_key IS NULL),
          p_merge_key       => p_merge_key
        );

        log_etl('UNZIP_COMPLETE_' || l_files_processed, 
                'Completed processing: ' || rec.file_name);

      EXCEPTION
        WHEN OTHERS THEN
          log_etl('UNZIP_ERROR_FILE_' || l_files_processed, 
                  'Error processing file ' || rec.file_name || ': ' || SQLERRM);
          -- Fail entire job if any file fails
          RAISE_APPLICATION_ERROR(-20004, 
            'Failed to process file: ' || rec.file_name || ' - ' || SQLERRM);
      END;

    END LOOP;

    log_etl('MULTI_UNZIP_COMPLETE', 
            'Successfully processed ' || l_files_processed || ' file(s)');

    IF l_files_processed = 0 THEN
      RAISE_APPLICATION_ERROR(-20005, 
        'No files found to process for request: ' || p_request_id);
    END IF;

  EXCEPTION
    WHEN OTHERS THEN
      log_etl('MULTI_UNZIP_FAILED', 
              'Multi-file processing failed: ' || SQLERRM);
      RAISE;
  END unzip_and_load_multi_files;

  ----------------------------------------------------------------
  -- Helper procedure to unzip and load a single file
  -- (This wraps the existing unzip_and_load_worker_assignments logic)
  ----------------------------------------------------------------
  PROCEDURE unzip_and_load_single_file(
    p_run_id          IN NUMBER,
    p_request_id      IN VARCHAR2,
    p_file_name       IN VARCHAR2,
    p_file_blob       IN BLOB,
    p_table_name      IN VARCHAR2,
    p_json_array_path IN VARCHAR2 DEFAULT 'items',
    p_truncate        IN BOOLEAN DEFAULT FALSE,
    p_merge_key       IN VARCHAR2 DEFAULT NULL
  ) IS
    -- Declare variables needed for unzipping
    l_files apex_zip.t_files;
    l_json_content CLOB;
    l_file_blob BLOB;
    i PLS_INTEGER;

    -- Helper to convert BLOB to CLOB
    PROCEDURE blob_to_clob(p_blob IN BLOB, p_clob OUT CLOB) IS
      l_dest_offset INTEGER := 1;
      l_src_offset INTEGER := 1;
      l_lang_ctx INTEGER := DBMS_LOB.default_lang_ctx;
      l_warning INTEGER;
    BEGIN
      DBMS_LOB.createtemporary(p_clob, TRUE);
      DBMS_LOB.converttoclob(
        dest_lob => p_clob,
        src_blob => p_blob,
        amount => DBMS_LOB.lobmaxsize,
        dest_offset => l_dest_offset,
        src_offset => l_src_offset,
        blob_csid => NLS_CHARSET_ID('AL32UTF8'),
        lang_context => l_lang_ctx,
        warning => l_warning
      );
    END;

  BEGIN
    log_etl('UNZIP_SINGLE', 'Unzipping file: ' || p_file_name);

    -- Unzip the BLOB
    l_files := apex_zip.get_files(p_zipped_blob => p_file_blob);

    -- Process each file in the zip
    FOR i IN 1 .. l_files.COUNT LOOP
      log_etl('ZIP_ENTRY', 'Processing zip entry: ' || l_files(i));

      -- Skip non-JSON files
      IF LOWER(l_files(i)) NOT LIKE '%.json%' THEN
        CONTINUE;
      END IF;

      -- Get file content as BLOB
      l_file_blob := apex_zip.get_file_content(
        p_zipped_blob => p_file_blob,
        p_file_name => l_files(i)
      );

      -- Convert BLOB to CLOB
      blob_to_clob(l_file_blob, l_json_content);

      log_etl('JSON_SIZE', 'Size: ' || DBMS_LOB.getlength(l_json_content) || ' chars');

      -- Load to table (using existing load procedure)
      load_json_to_table(
        p_run_id          => p_run_id,
        p_request_id      => p_request_id,
        p_json            => l_json_content,
        p_table_name      => p_table_name,
        p_json_array_path => p_json_array_path,
        p_truncate        => p_truncate,
        p_merge_key       => p_merge_key
      );

      log_etl('LOADED_FROM_ZIP', 'Loaded data from: ' || l_files(i));
    END LOOP;

  EXCEPTION
    WHEN OTHERS THEN
      log_etl('UNZIP_SINGLE_ERROR', 
              'Error in unzip_and_load_single_file for ' || p_file_name || ': ' || SQLERRM);
      RAISE;
  END unzip_and_load_single_file;

  ----------------------------------------------------------------
  -- Original unzip_and_load_worker_assignments (kept for backward compatibility)
  ----------------------------------------------------------------
  PROCEDURE unzip_and_load_worker_assignments(
    p_run_id IN NUMBER,
    p_request_id IN VARCHAR2
  ) IS
    l_zip_blob BLOB;
    l_zip_name VARCHAR2(400);
    l_files apex_zip.t_files;
    l_file_blob BLOB;
    l_json_clob CLOB;
    l_src_file VARCHAR2(400);

    PROCEDURE blob_to_clob(p_blob IN BLOB, p_clob OUT CLOB) IS
      l_dest_offset INTEGER := 1;
      l_src_offset INTEGER := 1;
      l_lang_ctx INTEGER := DBMS_LOB.default_lang_ctx;
      l_warning INTEGER;
    BEGIN
      DBMS_LOB.createtemporary(p_clob, TRUE);
      DBMS_LOB.converttoclob(
        dest_lob => p_clob,
        src_blob => p_blob,
        amount => DBMS_LOB.lobmaxsize,
        dest_offset => l_dest_offset,
        src_offset => l_src_offset,
        blob_csid => NLS_CHARSET_ID('AL32UTF8'),
        lang_context => l_lang_ctx,
        warning => l_warning
      );
    END;

  BEGIN
    log_etl('UNZIP_START', 'Starting unzip for request: ' || p_request_id);

    -- Get the first zip file for this run (backward compatible behavior)
    SELECT file_blob, file_name
    INTO l_zip_blob, l_zip_name
    FROM xx_int_saas_job_files
    WHERE run_id = p_run_id
      AND request_id = p_request_id
    ORDER BY created_ts DESC
    FETCH FIRST 1 ROW ONLY;

    log_etl('UNZIP_FILE', 'Processing: ' || l_zip_name);

    l_files := apex_zip.get_files(p_zipped_blob => l_zip_blob);
    log_etl('FILE_COUNT', TO_CHAR(l_files.COUNT));

    FOR i IN 1 .. l_files.COUNT LOOP
      l_src_file := l_files(i);

      IF LOWER(l_src_file) NOT LIKE '%.json%' THEN
        CONTINUE;
      END IF;

      log_etl('ZIP_ENTRY', l_src_file);

      l_file_blob := apex_zip.get_file_content(
        p_zipped_blob => l_zip_blob,
        p_file_name => l_src_file
      );

      blob_to_clob(l_file_blob, l_json_clob);

      log_etl('JSON_LEN', TO_CHAR(DBMS_LOB.getlength(l_json_clob)));

      load_json_to_table(
        p_run_id          => p_run_id,
        p_request_id      => p_request_id,
        p_json            => l_json_clob,
        p_table_name      => NVL(g_config_rec.target_table_name, 'XX_INT_WORKER_ASSIGNMENT_STG'),
        p_json_array_path => NVL(g_config_rec.json_array_path, 'items'),
        p_truncate        => (NVL(g_config_rec.truncate_before_load, 'Y') = 'Y' AND i = 1),
        p_merge_key       => g_config_rec.merge_key_columns
      );

      log_etl('LOADED', 'Data loaded from: ' || l_src_file);
    END LOOP;

    COMMIT;

  EXCEPTION
    WHEN OTHERS THEN
      log_etl('UNZIP_ERROR', 'Error in unzip: ' || SQLERRM);
      RAISE;
  END unzip_and_load_worker_assignments;

  ----------------------------------------------------------------
  -- Load JSON to Table (using original implementation with JSON_DATAGUIDE)
  ----------------------------------------------------------------
  PROCEDURE load_json_to_table(
    p_run_id          IN NUMBER,
    p_request_id      IN VARCHAR2,
    p_json            IN CLOB,
    p_table_name      IN VARCHAR2,
    p_json_array_path IN VARCHAR2 DEFAULT 'items',
    p_truncate        IN BOOLEAN DEFAULT TRUE,
    p_merge_key       IN VARCHAR2 DEFAULT NULL  -- Comma-separated key columns for MERGE (NULL = INSERT)
  ) IS
    l_dataguide CLOB;
    l_insert_sql CLOB;
    l_json_cols  CLOB := '';
    l_col_name   VARCHAR2(128);
    l_col_type   VARCHAR2(50);
    l_table_exists NUMBER;
    l_create_table BOOLEAN := FALSE;
    l_ddl CLOB;

    TYPE t_column_info IS RECORD (
      col_name  VARCHAR2(128),
      col_path  VARCHAR2(4000),
      col_type  VARCHAR2(50),
      json_type VARCHAR2(60)
    );
    TYPE t_columns IS TABLE OF t_column_info;
    l_columns t_columns := t_columns();

    FUNCTION flatten_path(p_path VARCHAR2, p_array_path VARCHAR2) RETURN VARCHAR2 IS
      l_flat_path VARCHAR2(4000);
    BEGIN
      l_flat_path := REGEXP_REPLACE(p_path, '^\$\.' || p_array_path || '\.', '');
      l_flat_path := REPLACE(l_flat_path, '.', '_');
      l_flat_path := REPLACE(l_flat_path, '"', '');
      l_flat_path := REPLACE(l_flat_path, '$', '');
      l_flat_path := REGEXP_REPLACE(l_flat_path, '[^A-Za-z0-9_]', '_');
      l_flat_path := REGEXP_REPLACE(l_flat_path, '_+', '_');
      l_flat_path := TRIM('_' FROM l_flat_path);
      RETURN UPPER(SUBSTR(l_flat_path, 1, 128));
    END;

    FUNCTION convert_path_for_json_table(p_path VARCHAR2, p_array_path VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
      RETURN REGEXP_REPLACE(p_path, '^\$\.' || p_array_path || '\.', '$.');
    END;

    PROCEDURE ensure_static_columns IS
      l_exists NUMBER;
    BEGIN
      -- RUN_ID
      SELECT COUNT(*) INTO l_exists
      FROM user_tab_columns
      WHERE table_name = UPPER(p_table_name) AND column_name = 'RUN_ID';
      IF l_exists = 0 THEN
        EXECUTE IMMEDIATE 'ALTER TABLE ' || p_table_name || ' ADD (RUN_ID NUMBER)';
      END IF;

      -- REQUEST_ID
      SELECT COUNT(*) INTO l_exists
      FROM user_tab_columns
      WHERE table_name = UPPER(p_table_name) AND column_name = 'REQUEST_ID';
      IF l_exists = 0 THEN
        EXECUTE IMMEDIATE 'ALTER TABLE ' || p_table_name || ' ADD (REQUEST_ID VARCHAR2(100))';
      END IF;

      -- CREATION_DATE
      SELECT COUNT(*) INTO l_exists
      FROM user_tab_columns
      WHERE table_name = UPPER(p_table_name) AND column_name = 'CREATION_DATE';
      IF l_exists = 0 THEN
        EXECUTE IMMEDIATE 'ALTER TABLE ' || p_table_name || ' ADD (CREATION_DATE DATE)';
      END IF;

      -- LAST_UPDATE_DATE
      SELECT COUNT(*) INTO l_exists
      FROM user_tab_columns
      WHERE table_name = UPPER(p_table_name) AND column_name = 'LAST_UPDATE_DATE';
      IF l_exists = 0 THEN
        EXECUTE IMMEDIATE 'ALTER TABLE ' || p_table_name || ' ADD (LAST_UPDATE_DATE DATE)';
      END IF;
    END ensure_static_columns;

  BEGIN
    SELECT COUNT(*) INTO l_table_exists
    FROM user_tables
    WHERE table_name = UPPER(p_table_name);

    IF l_table_exists = 0 THEN
      l_create_table := TRUE;

      -- Create table with static columns first
      l_ddl := 'CREATE TABLE ' || p_table_name || ' (' ||
               'RUN_ID NUMBER, ' ||
               'REQUEST_ID VARCHAR2(100), ' ||
               'CREATION_DATE DATE, ' ||
               'LAST_UPDATE_DATE DATE';
    END IF;

    SELECT JSON_DATAGUIDE(p_json, DBMS_JSON.FORMAT_FLAT)
    INTO l_dataguide
    FROM DUAL;

    -- Collect columns (handle duplicates from null types)
    DECLARE
      TYPE t_temp_cols IS TABLE OF t_column_info INDEX BY VARCHAR2(200);
      l_temp_cols t_temp_cols;
      l_temp_key VARCHAR2(200);
    BEGIN
      FOR r IN (
        SELECT jt.path, jt.jtype, jt.length
        FROM JSON_TABLE(
          l_dataguide, '$[*]'
          COLUMNS (
            path   VARCHAR2(4000) PATH '$."o:path"',
            jtype  VARCHAR2(60)   PATH '$.type',
            length NUMBER         PATH '$."o:length"'
          )
        ) jt
        WHERE jt.path LIKE '$.' || p_json_array_path || '.%'
          AND jt.path NOT LIKE '%."$context"%'
          AND jt.path NOT LIKE '%."$id"'
          AND jt.path NOT LIKE '%.links%'
          AND jt.jtype IN ('string', 'number', 'date', 'boolean', 'null')
      ) LOOP
        l_col_name := flatten_path(r.path, p_json_array_path);

        IF l_col_name IS NOT NULL THEN
          IF l_temp_cols.EXISTS(l_col_name) THEN
            IF l_temp_cols(l_col_name).json_type = 'null' AND r.jtype != 'null' THEN
              l_temp_cols(l_col_name).col_type := CASE r.jtype
                WHEN 'number'  THEN 'NUMBER'
                WHEN 'string'  THEN 'VARCHAR2(4000)'
                WHEN 'date'    THEN 'TIMESTAMP'
                WHEN 'boolean' THEN 'VARCHAR2(5)'
                ELSE 'VARCHAR2(4000)'
              END;
              l_temp_cols(l_col_name).col_path  := convert_path_for_json_table(r.path, p_json_array_path);
              l_temp_cols(l_col_name).json_type := r.jtype;
            END IF;
          ELSE
            IF r.jtype != 'null' THEN
              l_temp_cols(l_col_name).col_name  := l_col_name;
              l_temp_cols(l_col_name).col_path  := convert_path_for_json_table(r.path, p_json_array_path);
              l_temp_cols(l_col_name).col_type  := CASE r.jtype
                WHEN 'number'  THEN 'NUMBER'
                WHEN 'string'  THEN 'VARCHAR2(4000)'
                WHEN 'date'    THEN 'TIMESTAMP'
                WHEN 'boolean' THEN 'VARCHAR2(5)'
                ELSE 'VARCHAR2(4000)'
              END;
              l_temp_cols(l_col_name).json_type := r.jtype;
            END IF;
          END IF;
        END IF;
      END LOOP;

      l_temp_key := l_temp_cols.FIRST;
      WHILE l_temp_key IS NOT NULL LOOP
        IF l_temp_cols(l_temp_key).json_type != 'null' THEN
          l_columns.EXTEND;
          l_columns(l_columns.COUNT) := l_temp_cols(l_temp_key);
        END IF;
        l_temp_key := l_temp_cols.NEXT(l_temp_key);
      END LOOP;
    END;

    IF l_columns.COUNT = 0 THEN
      RAISE_APPLICATION_ERROR(-20001, 'No columns found in JSON');
    END IF;

    -- Create or alter table for JSON columns
    FOR i IN 1 .. l_columns.COUNT LOOP
      IF NOT l_create_table THEN
        BEGIN
          DECLARE l_exists NUMBER;
          BEGIN
            SELECT COUNT(*) INTO l_exists
            FROM user_tab_columns
            WHERE table_name = UPPER(p_table_name)
              AND column_name = l_columns(i).col_name;

            IF l_exists = 0 THEN
              EXECUTE IMMEDIATE 'ALTER TABLE ' || p_table_name ||
                                ' ADD (' || l_columns(i).col_name || ' ' || l_columns(i).col_type || ')';
            END IF;
          END;
        END;
      ELSE
        -- Note we already have 4 columns, so always prepend comma for JSON cols
        l_ddl := l_ddl || ', ' || l_columns(i).col_name || ' ' || l_columns(i).col_type;
      END IF;

      IF i > 1 THEN l_json_cols := l_json_cols || ', '; END IF;
      l_json_cols := l_json_cols || l_columns(i).col_name || ' PATH ''' || l_columns(i).col_path || '''';
    END LOOP;

    IF l_create_table THEN
      l_ddl := l_ddl || ')';
      EXECUTE IMMEDIATE l_ddl;
    ELSE
      -- Ensure static columns exist even for existing table
      ensure_static_columns;

      IF p_truncate AND p_merge_key IS NULL THEN
        EXECUTE IMMEDIATE 'TRUNCATE TABLE ' || p_table_name;
      END IF;
    END IF;

    -- Insert or merge data (static + JSON columns)
    DECLARE
      l_col_list    CLOB := '';
      l_select_list CLOB := '';
      l_on_clause   CLOB := '';
      l_update_set  CLOB := '';
      l_keys_upper  VARCHAR2(4000);
    BEGIN
      -- Column list
      l_col_list :=
        'RUN_ID, REQUEST_ID, CREATION_DATE, LAST_UPDATE_DATE';

      -- Select list
      l_select_list :=
        ':2 AS RUN_ID, :3 AS REQUEST_ID, SYSDATE AS CREATION_DATE, SYSDATE AS LAST_UPDATE_DATE';

      FOR i IN 1 .. l_columns.COUNT LOOP
        l_col_list    := l_col_list || ', ' || l_columns(i).col_name;
        l_select_list := l_select_list || ', jt.' || l_columns(i).col_name;
      END LOOP;

      IF p_merge_key IS NOT NULL THEN
        -- MERGE path: build ON clause + UPDATE SET from the key column list
        l_keys_upper := ',' || UPPER(REPLACE(p_merge_key, ' ', '')) || ',';

        -- ON clause: t.KEY1 = s.KEY1 AND t.KEY2 = s.KEY2 ...
        DECLARE
          l_rest  VARCHAR2(4000) := UPPER(REPLACE(p_merge_key, ' ', '')) || ',';
          l_pos   PLS_INTEGER := 1;
          l_comma PLS_INTEGER;
          l_key   VARCHAR2(128);
          l_first BOOLEAN := TRUE;
        BEGIN
          LOOP
            l_comma := INSTR(l_rest, ',', l_pos);
            EXIT WHEN l_comma = 0;
            l_key := TRIM(SUBSTR(l_rest, l_pos, l_comma - l_pos));
            IF l_key IS NOT NULL THEN
              IF NOT l_first THEN l_on_clause := l_on_clause || ' AND '; END IF;
              l_on_clause := l_on_clause || 't.' || l_key || ' = s.' || l_key;
              l_first := FALSE;
            END IF;
            l_pos := l_comma + 1;
          END LOOP;
        END;

        -- UPDATE SET: tracking cols + every non-key JSON column
        l_update_set :=
          't.RUN_ID = s.RUN_ID, t.REQUEST_ID = s.REQUEST_ID, t.LAST_UPDATE_DATE = s.LAST_UPDATE_DATE';
        FOR i IN 1 .. l_columns.COUNT LOOP
          IF INSTR(l_keys_upper, ',' || l_columns(i).col_name || ',') = 0 THEN
            l_update_set := l_update_set ||
              ', t.' || l_columns(i).col_name || ' = s.' || l_columns(i).col_name;
          END IF;
        END LOOP;

        -- Assemble MERGE statement
        l_insert_sql :=
          'MERGE INTO ' || p_table_name || ' t' ||
          ' USING (SELECT ' || l_select_list ||
          ' FROM JSON_TABLE(:1, ''$.' || p_json_array_path || '[*]'' COLUMNS (' ||
          l_json_cols || ')) jt) s' ||
          ' ON (' || l_on_clause || ')' ||
          ' WHEN MATCHED THEN UPDATE SET ' || l_update_set ||
          ' WHEN NOT MATCHED THEN INSERT (' || l_col_list || ')' ||
          ' VALUES (s.RUN_ID, s.REQUEST_ID, s.CREATION_DATE, s.LAST_UPDATE_DATE';
        FOR i IN 1 .. l_columns.COUNT LOOP
          l_insert_sql := l_insert_sql || ', s.' || l_columns(i).col_name;
        END LOOP;
        l_insert_sql := l_insert_sql || ')';

      ELSE
        -- INSERT path (original behaviour)
        l_insert_sql :=
          'INSERT INTO ' || p_table_name || ' (' || l_col_list || ')' ||
          ' SELECT ' || l_select_list ||
          ' FROM JSON_TABLE(:1, ''$.' || p_json_array_path || '[*]'' COLUMNS (' ||
          l_json_cols || ')) jt';
      END IF;
    END;

    log_etl('INSERT_OR_MERGE_JSON_TO_TABLE', l_insert_sql);
    EXECUTE IMMEDIATE l_insert_sql USING p_run_id, p_request_id, p_json;
    COMMIT;
  END load_json_to_table;

  ----------------------------------------------------------------
  -- MAIN: Configuration-Driven Execution - MODIFIED FOR MULTI-FILE
  ----------------------------------------------------------------
  PROCEDURE run_extract_by_config(
    p_config_name    IN VARCHAR2,
    p_effective_date IN VARCHAR2 DEFAULT NULL,
    p_multi_file     IN BOOLEAN DEFAULT TRUE  -- NEW: Flag to enable multi-file processing
  ) IS
    l_run_id      NUMBER;
    l_status      VARCHAR2(30);
    l_request_id  VARCHAR2(200);
    l_file_id     VARCHAR2(200);
    l_output_url  VARCHAR2(1000);
    l_json        CLOB;
    l_msg         VARCHAR2(1000);
    l_files_downloaded NUMBER := 0;

    -- Variables for single-file mode (backward compatibility)
    l_file_name   VARCHAR2(200);
    l_download_href VARCHAR2(1000);
    l_file_size   VARCHAR2(200);
    l_time_created VARCHAR2(200);
    l_file_href   VARCHAR2(1000);
    c_extract_file_base_url VARCHAR2(1000);

  BEGIN
    -- Load configuration
    SELECT * INTO g_config_rec
    FROM xx_int_saas_extract_config
    WHERE config_name = p_config_name AND active_flag = 'Y';

    -- Start log
    INSERT INTO spectra_worker_etl_log (status, message)
    VALUES ('STARTED', 'ETL run initiated for config: ' || p_config_name)
    RETURNING run_id INTO l_run_id;
    g_run_id := l_run_id;

    log_etl('CONFIG', 'Using configuration: ' || p_config_name);
    log_etl('MULTI_FILE_MODE', 'Multi-file processing: ' || CASE WHEN p_multi_file THEN 'ENABLED' ELSE 'DISABLED' END);

    -- Get OAuth token
    g_oauth_token := get_oauth_token_apex2(
      g_config_rec.oauth_token_url,
      g_config_rec.client_id,
      g_config_rec.client_secret,
      g_config_rec.scope_saas_batch
    );

    log_etl('TOKEN', 'OAuth token received');

    -- Submit extract job
    l_request_id := submit_extract_job(
      g_config_rec.api_base_url || '/api/saas-batch/jobscheduler/v1/jobRequests',
      g_config_rec.module_name,
      g_config_rec.resource_name,
      g_config_rec.resource_version,
      g_config_rec.output_format,
      g_config_rec.advanced_query_template,
      NVL(p_effective_date, TO_CHAR(SYSDATE, 'YYYY-MM-DD'))
    );

    log_etl('SUBMIT', 'Job submitted: ' || l_request_id);

    -- Poll status
    poll_extract_status(
      g_config_rec.api_base_url,
      l_request_id,
      g_config_rec.poll_interval_sec,
      g_config_rec.poll_timeout_sec,
      l_status,
      l_file_id,
      l_output_url
    );

    log_etl('POLL_COMPLETE', 'Status: ' || l_status || ', File ID: ' || l_file_id);

    -- Check status
    IF l_status <> 'SUCCEEDED' THEN
      l_msg := 'Extract did not succeed. Final status = ' || l_status;
      UPDATE spectra_worker_etl_log
      SET end_time  = SYSDATE,
          status    = 'FAILED',
          message   = l_msg,
          request_id = l_request_id
      WHERE run_id = l_run_id;
      COMMIT;
      RAISE_APPLICATION_ERROR(-20001, l_msg);
    END IF;

    -- Download file metadata
    log_etl('GET_FILE_META', 'Retrieving file metadata for: ' || l_file_id);
    l_json := download_extract_output(l_file_id, l_output_url);
    log_etl('FILE_META_RECEIVED', DBMS_LOB.SUBSTR(l_json, 4000, 1));

    -- NEW: Multi-file processing logic
    IF p_multi_file THEN
      -- Download all files
      log_etl('MULTI_FILE_DOWNLOAD', 'Starting multi-file download');

      download_job_output_files_multi(
        p_run_id => g_run_id,
        p_request_id => l_request_id,
        p_outputfiles_json => l_json,
        p_oauth_token => g_oauth_token,
        p_files_downloaded => l_files_downloaded
      );

      log_etl('MULTI_FILE_DOWNLOADED', 'Downloaded ' || l_files_downloaded || ' file(s)');

      -- Truncate target table before loading (only when not in merge mode)
      IF g_config_rec.target_table_name IS NOT NULL
         AND g_config_rec.merge_key_columns IS NULL THEN
        BEGIN
          EXECUTE IMMEDIATE 'TRUNCATE TABLE ' || g_config_rec.target_table_name;
          log_etl('TABLE_TRUNCATED', 'Target table truncated: ' || g_config_rec.target_table_name);
        EXCEPTION
          WHEN OTHERS THEN
            log_etl('TRUNCATE_WARNING', 'Could not truncate table: ' || SQLERRM);
        END;
      END IF;

      -- Unzip and load all files
      log_etl('MULTI_FILE_LOAD', 'Starting multi-file load');

      unzip_and_load_multi_files(
        p_run_id          => g_run_id,
        p_request_id      => l_request_id,
        p_table_name      => NVL(g_config_rec.target_table_name, 'XX_INT_WORKER_ASSIGNMENT_STG'),
        p_json_array_path => NVL(g_config_rec.json_array_path, 'items'),
        p_truncate_first  => FALSE,  -- Already truncated above (only when not merging)
        p_merge_key       => g_config_rec.merge_key_columns
      );

      log_etl('MULTI_FILE_COMPLETE', 'All files processed successfully');

    ELSE
      -- Original single-file processing (backward compatibility)
      log_etl('SINGLE_FILE_MODE', 'Using single-file processing');

      SELECT jt.file_name,
             jt.file_size,
             jt.time_created,
             jt.file_href,
             jt.download_href
      INTO l_file_name,
           l_file_size,
           l_time_created,
           l_file_href,
           l_download_href
      FROM JSON_TABLE(
        l_json,
        '$.items[*]'
        COLUMNS (
          file_name     VARCHAR2(200)  PATH '$.fileName',
          file_size     NUMBER          PATH '$.fileSize',
          time_created  VARCHAR2(50)    PATH '$.timeCreated',
          file_href     VARCHAR2(4000)  PATH '$."$context".links."$self".href',
          download_href VARCHAR2(4000)  PATH '$."$context".links.enclosure.href'
        )
      ) jt
      FETCH FIRST 1 ROW ONLY;

      log_etl('SINGLE_FILE_INFO', 'File: ' || l_file_name || ', Size: ' || l_file_size);

      download_job_output_file(
        p_run_id => g_run_id,
        p_request_id => l_request_id,
        p_outputfiles_json => l_json,
        p_oauth_token => g_oauth_token,
        p_file_name => l_file_name,
        p_download_url => l_download_href
      );

      log_etl('SINGLE_FILE_DOWNLOADED', l_file_name);

      unzip_and_load_worker_assignments(g_run_id, l_request_id);

      log_etl('SINGLE_FILE_LOADED', 'Data loaded successfully');
    END IF;

    -- Update configuration
    UPDATE xx_int_saas_extract_config
    SET last_run_date = SYSDATE
    WHERE config_name = p_config_name;

    -- Update log
    UPDATE spectra_worker_etl_log
    SET end_time = SYSDATE, 
        status = 'SUCCEEDED', 
        message = 'ETL completed successfully' ||
                  CASE WHEN p_multi_file THEN ' (' || l_files_downloaded || ' files processed)' ELSE '' END,
        request_id = l_request_id
    WHERE run_id = l_run_id;

    COMMIT;

  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DECLARE
        l_err VARCHAR2(4000);
      BEGIN
        l_err := SUBSTR(SQLERRM, 1, 4000);

        log_etl('ERROR_OCCURRED', l_err);

        UPDATE spectra_worker_etl_log
        SET end_time = SYSDATE, 
            status = 'ERROR', 
            message = 'ERROR: ' || l_err || CHR(10) ||
                     'STACK: ' || DBMS_UTILITY.format_error_stack || CHR(10) ||
                     'BACKTRACE: ' || DBMS_UTILITY.format_error_backtrace,
            request_id = l_request_id
        WHERE run_id = l_run_id;
        COMMIT;
        RAISE;
      END;
  END run_extract_by_config;
FUNCTION get_oauth_token_apex(
    p_token_url     IN VARCHAR2,
    p_client_id     IN VARCHAR2,
    p_client_secret IN VARCHAR2,
    p_scope         IN VARCHAR2
) RETURN VARCHAR2
IS
    -- APEX credentials config
    c_workspace   CONSTANT VARCHAR2(100) := 'XX_INT';
    c_app_id      CONSTANT NUMBER        := 100;
    c_cred_id     CONSTANT VARCHAR2(100) := 'SPECTRA_BOSS_CRED';

    -- Fixed POST body — no concatenation
    c_post_body   CONSTANT VARCHAR2(500) := 'grant_type=client_credentials&scope=urn:opc:resource:fusion:espx-dev1:saas-batch/';

    l_idcs_resp   CLOB;
    l_token       VARCHAR2(4000);

BEGIN
    -- Set workspace + create APEX session
    APEX_UTIL.SET_WORKSPACE(p_workspace => c_workspace);
    APEX_SESSION.CREATE_SESSION(
        p_app_id   => 100,
        p_page_id  => 1,
        p_username => 'XX_INT'
    );

    -- Set headers
    APEX_WEB_SERVICE.SET_REQUEST_HEADERS(
        p_name_01  => 'Content-Type',
        p_value_01 => 'application/x-www-form-urlencoded',
        p_name_02  => 'Accept',
        p_value_02 => 'application/json',
        p_reset    => TRUE
    );

    -- Call IDCS — APEX injects Basic Auth from SPECTRA_BOSS_CRED
    -- p_token_url, p_client_id, p_client_secret, p_scope
    -- now sourced from APEX credential — config table values ignored
    l_idcs_resp := APEX_WEB_SERVICE.MAKE_REST_REQUEST(
                       p_url                  => c_post_body,
                       p_http_method          => 'POST',
                       p_body                 => c_post_body,
                       p_credential_static_id => c_cred_id
                   );

    -- Validate
    IF APEX_WEB_SERVICE.G_STATUS_CODE != 200 THEN
        RAISE_APPLICATION_ERROR(-20001,
            'GET_OAUTH_TOKEN failed. HTTP: ' || APEX_WEB_SERVICE.G_STATUS_CODE
            || ' Error: '                    || JSON_VALUE(l_idcs_resp, '$.error')
            || ' Desc: '                     || JSON_VALUE(l_idcs_resp, '$.error_description'));
    END IF;

    -- Parse token
    l_token := JSON_VALUE(l_idcs_resp, '$.access_token');

    IF l_token IS NULL THEN
        RAISE_APPLICATION_ERROR(-20002,
            'GET_OAUTH_TOKEN: Token parse failed. Response: '
            || SUBSTR(l_idcs_resp, 1, 500));
    END IF;

    -- Clean up
    APEX_SESSION.DELETE_SESSION(p_session_id => APEX_APPLICATION.G_INSTANCE);

    RETURN l_token;

EXCEPTION
    WHEN OTHERS THEN
        BEGIN
            APEX_SESSION.DELETE_SESSION(p_session_id => APEX_APPLICATION.G_INSTANCE);
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
        RAISE;
END get_oauth_token_apex;
 FUNCTION get_oauth_token_apex1(
    p_token_url     IN VARCHAR2,
    p_client_id     IN VARCHAR2,
    p_client_secret IN VARCHAR2,
    p_scope         IN VARCHAR2
) RETURN VARCHAR2
IS
    l_post_body   VARCHAR2(1000);
    l_idcs_resp   CLOB;
    l_token       VARCHAR2(4000);

BEGIN
    -- ----------------------------------------------------------------
    -- Validate APEX config values loaded from xx_int_saas_extract_config
    -- ----------------------------------------------------------------
    IF g_config_rec.apex_workspace IS NULL THEN
        RAISE_APPLICATION_ERROR(-20001,
            'APEX_WORKSPACE not configured in xx_int_saas_extract_config '
            || 'for instance: ' || g_config_rec.instance_code);
    END IF;

    IF g_config_rec.apex_cred_static IS NULL THEN
        RAISE_APPLICATION_ERROR(-20002,
            'APEX_CRED_STATIC not configured in xx_int_saas_extract_config '
            || 'for instance: ' || g_config_rec.instance_code);
    END IF;

    IF p_scope IS NULL THEN
        RAISE_APPLICATION_ERROR(-20003,
            'SCOPE not configured in xx_int_saas_extract_config '
            || 'for instance: ' || g_config_rec.instance_code);
    END IF;

    -- ----------------------------------------------------------------
    -- Build POST body from p_scope parameter
    -- ----------------------------------------------------------------
    l_post_body := 'grant_type=client_credentials'
                || '&scope=' || p_scope;

    DBMS_OUTPUT.PUT_LINE('--- GET_OAUTH_TOKEN ---');
    DBMS_OUTPUT.PUT_LINE('Instance    : ' || g_config_rec.instance_code);
    DBMS_OUTPUT.PUT_LINE('Token URL   : ' || p_token_url);
    DBMS_OUTPUT.PUT_LINE('Workspace   : ' || g_config_rec.apex_workspace);
    DBMS_OUTPUT.PUT_LINE('App ID      : ' || g_config_rec.apex_app_id);
    DBMS_OUTPUT.PUT_LINE('Credential  : ' || g_config_rec.apex_cred_static);
    DBMS_OUTPUT.PUT_LINE('Batch User  : ' || g_config_rec.apex_batch_user);
    DBMS_OUTPUT.PUT_LINE('Scope       : ' || p_scope);
    DBMS_OUTPUT.PUT_LINE('POST Body   : ' || l_post_body);

    -- ----------------------------------------------------------------
    -- STEP 1: APEX session — all values from config table
    -- ----------------------------------------------------------------
    APEX_UTIL.SET_WORKSPACE(
        p_workspace => g_config_rec.apex_workspace
    );

    APEX_SESSION.CREATE_SESSION(
        p_app_id   => g_config_rec.apex_app_id,
        p_page_id  => 1,
        p_username => NVL(g_config_rec.apex_batch_user, 'BATCH_USER')
    );

    -- ----------------------------------------------------------------
    -- STEP 2: Set headers
    -- ----------------------------------------------------------------
    APEX_WEB_SERVICE.SET_REQUEST_HEADERS(
        p_name_01  => 'Content-Type',
        p_value_01 => 'application/x-www-form-urlencoded',
        p_name_02  => 'Accept',
        p_value_02 => 'application/json',
        p_reset    => TRUE
    );

    -- ----------------------------------------------------------------
    -- STEP 3: Call IDCS
    --         Token URL    — from p_token_url (config.oauth_token_url)
    --         POST body    — built from p_scope (config.scope_saas_batch)
    --         Credential   — from config.apex_cred_static
    --         Basic Auth   — injected by APEX from credential store
    -- ----------------------------------------------------------------
    l_idcs_resp := APEX_WEB_SERVICE.MAKE_REST_REQUEST(
                       p_url                  => p_token_url,
                       p_http_method          => 'POST',
                       p_body                 => l_post_body,
                       p_credential_static_id => g_config_rec.apex_cred_static
                   );

    DBMS_OUTPUT.PUT_LINE('HTTP Status : ' || APEX_WEB_SERVICE.G_STATUS_CODE);

    -- ----------------------------------------------------------------
    -- STEP 4: Validate response
    -- ----------------------------------------------------------------
    IF APEX_WEB_SERVICE.G_STATUS_CODE != 200 THEN
        RAISE_APPLICATION_ERROR(-20004,
            'GET_OAUTH_TOKEN failed. HTTP: ' || APEX_WEB_SERVICE.G_STATUS_CODE
            || ' Error: '                    || JSON_VALUE(l_idcs_resp, '$.error')
            || ' Desc: '                     || JSON_VALUE(l_idcs_resp, '$.error_description'));
    END IF;

    -- ----------------------------------------------------------------
    -- STEP 5: Parse token
    -- ----------------------------------------------------------------
    l_token := JSON_VALUE(l_idcs_resp, '$.access_token');

    IF l_token IS NULL THEN
        RAISE_APPLICATION_ERROR(-20005,
            'GET_OAUTH_TOKEN: Token parse failed. Response: '
            || SUBSTR(l_idcs_resp, 1, 500));
    END IF;

    DBMS_OUTPUT.PUT_LINE('Token Type  : ' || JSON_VALUE(l_idcs_resp, '$.token_type'));
    DBMS_OUTPUT.PUT_LINE('Expires In  : ' || JSON_VALUE(l_idcs_resp, '$.expires_in') || ' seconds');
    DBMS_OUTPUT.PUT_LINE('Token       : ' || SUBSTR(l_token, 1, 50) || '...');

    -- ----------------------------------------------------------------
    -- STEP 6: Clean up APEX session
    -- ----------------------------------------------------------------
    APEX_SESSION.DELETE_SESSION(p_session_id => APEX_APPLICATION.G_INSTANCE);

    RETURN l_token;

EXCEPTION
    WHEN OTHERS THEN
        BEGIN
            APEX_SESSION.DELETE_SESSION(p_session_id => APEX_APPLICATION.G_INSTANCE);
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
        RAISE;
END get_oauth_token_apex1;
FUNCTION get_oauth_token_APEX2(
    p_token_url     IN VARCHAR2,
    p_client_id       IN VARCHAR2,
    p_client_secret IN VARCHAR2,
    p_scope         IN VARCHAR2
) RETURN VARCHAR2
IS
    l_post_body     VARCHAR2(1000);
    l_idcs_resp     CLOB;
    l_token         VARCHAR2(4000);

    -- Fallback UTL_HTTP variables
    l_http_req      UTL_HTTP.REQ;
    l_http_resp     UTL_HTTP.RESP;
    l_raw_creds     VARCHAR2(2000);
    l_encoded_creds VARCHAR2(2000);
    l_buffer        VARCHAR2(32767);
    l_response      CLOB;
    l_status        NUMBER;

BEGIN
    -- ----------------------------------------------------------------
    -- Build POST body from scope parameter
    -- ----------------------------------------------------------------
    l_post_body := 'grant_type=client_credentials'
                || '&scope=' || p_scope;

    DBMS_OUTPUT.PUT_LINE('--- GET_OAUTH_TOKEN ---');
    DBMS_OUTPUT.PUT_LINE('Instance    : ' || g_config_rec.instance_code);
    DBMS_OUTPUT.PUT_LINE('Token URL   : ' || p_token_url);
    DBMS_OUTPUT.PUT_LINE('Scope       : ' || p_scope);
    DBMS_OUTPUT.PUT_LINE('POST Body   : ' || l_post_body);

    -- ----------------------------------------------------------------
    -- APEX columns populated = use APEX credential (secure)
    -- APEX columns NULL      = fallback to UTL_HTTP (old method)
    -- ----------------------------------------------------------------
    IF    g_config_rec.apex_workspace   IS NOT NULL
      AND g_config_rec.apex_cred_static IS NOT NULL
      AND g_config_rec.apex_app_id      IS NOT NULL
    THEN
        -- ============================================================
        -- NEW METHOD — APEX Credential Store
        -- client_id + client_secret encrypted in APEX
        -- never exposed in config table or code
        -- ============================================================
        DBMS_OUTPUT.PUT_LINE('Auth Method : APEX Credential');
        DBMS_OUTPUT.PUT_LINE('Workspace   : ' || g_config_rec.apex_workspace);
        DBMS_OUTPUT.PUT_LINE('App ID      : ' || g_config_rec.apex_app_id);
        DBMS_OUTPUT.PUT_LINE('Credential  : ' || g_config_rec.apex_cred_static);
        DBMS_OUTPUT.PUT_LINE('Batch User  : ' || g_config_rec.apex_batch_user);

        -- Set workspace
        APEX_UTIL.SET_WORKSPACE(
            p_workspace => g_config_rec.apex_workspace
        );

        -- Create APEX session
        APEX_SESSION.CREATE_SESSION(
            p_app_id   => g_config_rec.apex_app_id,
            p_page_id  => 1,
            p_username => NVL(g_config_rec.apex_batch_user, 'XX_INT')
        );

        DBMS_OUTPUT.PUT_LINE('Session     : ' || APEX_APPLICATION.G_INSTANCE);

        -- Set request headers
        APEX_WEB_SERVICE.SET_REQUEST_HEADERS(
            p_name_01  => 'Content-Type',
            p_value_01 => 'application/x-www-form-urlencoded',
            p_name_02  => 'Accept',
            p_value_02 => 'application/json',
            p_reset    => TRUE
        );

        -- Call IDCS
        -- APEX automatically injects:
        -- Authorization: Basic Base64(client_id:client_secret)
        -- from APEX encrypted credential store
        l_idcs_resp := APEX_WEB_SERVICE.MAKE_REST_REQUEST(
                           p_url                  => p_token_url,
                           p_http_method          => 'POST',
                           p_body                 => l_post_body,
                           p_credential_static_id => g_config_rec.apex_cred_static
                       );

        DBMS_OUTPUT.PUT_LINE('HTTP Status : ' || APEX_WEB_SERVICE.G_STATUS_CODE);

        -- Validate response
        IF APEX_WEB_SERVICE.G_STATUS_CODE != 200 THEN
            RAISE_APPLICATION_ERROR(-20001,
                'GET_OAUTH_TOKEN (APEX) failed.'
                || ' Instance: ' || g_config_rec.instance_code
                || ' HTTP: '     || APEX_WEB_SERVICE.G_STATUS_CODE
                || ' Error: '    || JSON_VALUE(l_idcs_resp, '$.error')
                || ' Desc: '     || JSON_VALUE(l_idcs_resp, '$.error_description'));
        END IF;

        -- Parse token
        l_token := JSON_VALUE(l_idcs_resp, '$.access_token');

        -- Clean up APEX session
        APEX_SESSION.DELETE_SESSION(
            p_session_id => APEX_APPLICATION.G_INSTANCE
        );

    ELSE
        -- ============================================================
        -- OLD METHOD — UTL_HTTP with client_id/secret from config table
        -- Used when APEX columns not yet configured
        -- e.g. STAGE / PROD before APEX credential is set up
        -- ============================================================
        DBMS_OUTPUT.PUT_LINE('Auth Method : UTL_HTTP Basic Auth (fallback)');
        DBMS_OUTPUT.PUT_LINE('Client ID   : ' || p_client_id);

        -- Build Basic Auth header
        l_raw_creds     := p_client_id || ':' || p_client_secret;
        l_encoded_creds := REPLACE(
                               REPLACE(
                                   UTL_RAW.CAST_TO_VARCHAR2(
                                       UTL_ENCODE.BASE64_ENCODE(
                                           UTL_RAW.CAST_TO_RAW(l_raw_creds)
                                       )
                                   ),
                               CHR(13)),
                           CHR(10));

        -- Call IDCS
        l_http_req := UTL_HTTP.BEGIN_REQUEST(
                          url    => p_token_url,
                          method => 'POST'
                      );

        UTL_HTTP.SET_HEADER(l_http_req, 'Authorization', 'Basic ' || l_encoded_creds);
        UTL_HTTP.SET_HEADER(l_http_req, 'Content-Type',  'application/x-www-form-urlencoded');
        UTL_HTTP.SET_HEADER(l_http_req, 'Content-Length', LENGTHB(l_post_body));
        UTL_HTTP.SET_HEADER(l_http_req, 'Accept',         'application/json');

        UTL_HTTP.WRITE_TEXT(l_http_req, l_post_body);

        l_http_resp := UTL_HTTP.GET_RESPONSE(l_http_req);
        l_status    := l_http_resp.status_code;

        DBMS_OUTPUT.PUT_LINE('HTTP Status : ' || l_status);

        BEGIN
            LOOP
                UTL_HTTP.READ_TEXT(l_http_resp, l_buffer, 32767);
                l_response := l_response || l_buffer;
            END LOOP;
        EXCEPTION
            WHEN UTL_HTTP.END_OF_BODY THEN NULL;
        END;
        UTL_HTTP.END_RESPONSE(l_http_resp);

        -- Validate response
        IF l_status != 200 THEN
            RAISE_APPLICATION_ERROR(-20002,
                'GET_OAUTH_TOKEN (UTL_HTTP) failed.'
                || ' Instance: ' || g_config_rec.instance_code
                || ' HTTP: '     || l_status
                || ' Response: ' || SUBSTR(l_response, 1, 500));
        END IF;

        -- Parse token
        l_token := JSON_VALUE(l_response, '$.access_token');

    END IF;

    -- ----------------------------------------------------------------
    -- Final token validation
    -- ----------------------------------------------------------------
    IF l_token IS NULL THEN
        RAISE_APPLICATION_ERROR(-20003,
            'GET_OAUTH_TOKEN: Token parse failed.'
            || ' Instance: ' || g_config_rec.instance_code);
    END IF;

    DBMS_OUTPUT.PUT_LINE('Token OK    : ' || SUBSTR(l_token, 1, 50) || '...');
    DBMS_OUTPUT.PUT_LINE('--- END GET_OAUTH_TOKEN ---');

    RETURN l_token;

EXCEPTION
    WHEN OTHERS THEN
        -- Clean up HTTP
        BEGIN
            UTL_HTTP.END_RESPONSE(l_http_resp);
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
        -- Clean up APEX session
        BEGIN
            APEX_SESSION.DELETE_SESSION(
                p_session_id => APEX_APPLICATION.G_INSTANCE
            );
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
        DBMS_OUTPUT.PUT_LINE('GET_OAUTH_TOKEN ERROR : ' || SQLERRM);
        RAISE;
END get_oauth_token_APEX2;
END pkg_spectra_worker_etl_v4;

/

