--------------------------------------------------------
--  File created - Thursday-April-09-2026   
--------------------------------------------------------
--------------------------------------------------------
--  DDL for Procedure XX_RODS_LOAD_ASG_EIT_EXTRACT_V3_PRC
--------------------------------------------------------
set define off;

  CREATE OR REPLACE EDITIONABLE PROCEDURE "XX_INT"."XX_RODS_LOAD_ASG_EIT_EXTRACT_V3_PRC" (
    p_report_path          IN  VARCHAR2,
    p_report_name          IN  VARCHAR2,
    p_format               IN  VARCHAR2 DEFAULT NULL,
    p_template             IN  VARCHAR2 DEFAULT NULL,
   p_deliveryOptionId       IN number,
    p_payrollActionId       IN number,
    p_flowInstanceName       IN VARCHAR2,
    p_sequence              IN NUMBER,
    p_isBursting        in BOOLEAN,
     p_isChunking        in BOOLEAN,
    p_locale               IN  VARCHAR2 DEFAULT 'en-US',
    p_recreate_table_flag  IN  VARCHAR2 DEFAULT 'Y',  -- NEW
    p_run_id_out           OUT NUMBER,
    p_detail_table_out     OUT VARCHAR2,
    p_rows_inserted_out    OUT NUMBER                  -- NEW
)
IS
/*******************************************************************************
 *  File Name      : XX9638_LOAD_REPORT_DYN_TYPED_PRC.sql
 *  Object Name    : XX9638_LOAD_REPORT_DYN_TYPED_PRC
 *  Schema         : XX_INT
 *
 *  Summary:
 *  --------
 *  This procedure calls Oracle BI Publisher (PublicReportService / runReport)
 *  from ADW, retrieves the report output as BLOB, converts it to CLOB,
 *  dynamically detects header structure, infers column types
 *  (NUMBER / DATE / VARCHAR2(4000)), and loads parsed rows into a dynamically
 *  generated detail table (XXREP_<REPORT_NAME>).
 *
 *  The procedure supports:
 *    • Template selection (attributeTemplate)
 *    • Locale selection (attributeLocale)
 *    • Report parameters: LDG, Effective Date, LIMIT, OFFSET
 *    • Pagination of large reports (5,000 row pages or user-defined)
 *    • DATE and NUMBER detection using multi-row sampling
 *    • Conditional DROP/CREATE of detail tables (Dev vs Prod mode)
 *    • Automatic RUN_ID logging
 *    • Fully instrumented BIP call logging (XX9638_BIP_CALL_LOG)
 *    • Error logging including SQLCODE / SQLERRM
 *
 *  Dependencies:
 *  -------------
 *    • XXINT_RUN_BIP_REPORT (custom function to call SOAP BIP runReport)
 *    • XX9638_REPORT_RAW (stores original report BLOB per run)
 *    • XX9638_BIP_CALL_LOG (new logging table for BIP calls)
 *    • UTL_HTTP (enabled via Network ACL)
 *    • DBMS_LOB (BLOB → CLOB conversion)
 *    • DBMS_SQL (dynamic bind & insert for variable columns)
 *
 *  High-Level Flow:
 *  ----------------
 *    1. Log the initial run (parameter snapshot) into XX9638_BIP_CALL_LOG
 *    2. Call BI Publisher runReport using xxint_run_bip_report
 *    3. Insert raw BLOB into XX9638_REPORT_RAW and store RUN_ID
 *    4. Convert BLOB → CLOB (AL32UTF8)
 *    5. Identify header row by skipping XML preamble/blank lines
 *    6. Split header by pipe '|'
 *    7. Sample ~50 rows from the file to detect column types:
 *          - NUMBER (regex)
 *          - DATE (multiple formats)
 *          - VARCHAR2(4000)
 *    8. Generate a detail table name: XXREP_<REPORT_NAME>
 *    9. DROP/CREATE table (if p_recreate_table_flag = 'Y')
 *   10. Build dynamic INSERT statement (DBMS_SQL + bind variables)
 *   11. Loop through the file, split lines by '|', cast types, insert rows
 *   12. Log success or error details to XX9638_BIP_CALL_LOG
 *   13. Return RUN_ID, table name, and number of rows inserted
 *
 *
 *  Change History:
 *  ---------------
 *
 *  Version |    Date     | Author        | Change Description
 *  --------+-------------+---------------+-------------------------------------
 *   1.0    | 2025-01-15  | M. Amondikar  | Initial version - basic BIP call,
 *         |             |               | dynamic table creation, VARCHAR only.
 *  --------+-------------+---------------+-------------------------------------
 *   1.1    | 2025-01-20  | M. Amondikar  | Added NUMBER detection with sampling.
 *  --------+-------------+---------------+-------------------------------------
 *   1.2    | 2025-01-23  | M. Amondikar  | Added DATE detection with regex +
 *         |             |               | TO_DATE fallback.
 *  --------+-------------+---------------+-------------------------------------
 *   1.3    | 2025-01-25  | M. Amondikar  | Added template support
 *         |             |               | (attributeTemplate).
 *  --------+-------------+---------------+-------------------------------------
 *   1.4    | 2025-01-26  | M. Amondikar  | Added locale support
 *         |             |               | (attributeLocale = 'en-US').
 *  --------+-------------+---------------+-------------------------------------
 *   1.5    | 2025-01-27  | M. Amondikar  | Added LIMIT/OFFSET paging for BIP.
 *  --------+-------------+---------------+-------------------------------------
 *   1.6    | 2025-01-29  | M. Amondikar  | Added optional table recreate flag
 *         |             |               | (dev/prod mode).
 *  --------+-------------+---------------+-------------------------------------
 *   1.7    | 2025-01-30  | M. Amondikar  | Added run row count output
 *         |             |               | (p_rows_inserted_out).
 *  --------+-------------+---------------+-------------------------------------
 *   1.8    | 2025-01-31  | M. Amondikar  | Introduced full BIP call logging table
 *         |             |               | with success/error tracking.
 *  --------+-------------+---------------+-------------------------------------
 *   1.9    | 2025-02-01  | M. Amondikar  | Added SQLCODE/SQLERRM safe logging
 *         |             |               | and EXCEPTION enhancements.
 *  --------+-------------+---------------+-------------------------------------
 *   1.10    | 2026-04-07  | M. Amondikar  | Added to get hcm extract output
 *         |             |               | and EXCEPTION enhancements.
 *******************************************************************************/

    ------------------------------------------------------------------
    -- Collection types
  --  SELECT * FROM XX9638_REPORT_RAW
---SELECT * FROM XX9638_REPORT_LINES
---SELECT * FROM XX9638_REPORT_DETAIL
---SELECT * FROM XX9638_BIP_CALL_LOG
--SELECT * FROM XXREP_R_9638_WWMS_RECON
    ------------------------------------------------------------------
    TYPE t_varchar_tab IS TABLE OF VARCHAR2(4000);
    TYPE t_name_map    IS TABLE OF PLS_INTEGER INDEX BY VARCHAR2(400);

    TYPE t_col_type IS RECORD (
        all_numeric BOOLEAN,
        all_date    BOOLEAN
    );

    TYPE t_col_type_tab IS TABLE OF t_col_type;

    ------------------------------------------------------------------
    -- Raw + conversion
    ------------------------------------------------------------------
    l_blob       BLOB;
    l_clob       CLOB;
    l_dest_off   INTEGER := 1;
    l_src_off    INTEGER := 1;
    l_lang_ctx   INTEGER := DBMS_LOB.default_lang_ctx;
    l_warning    INTEGER;
P_EFFECTIVE_DATE DATE ;
P_LDG VARCHAR2 ;
P_LIMIT INTEGER := 1000000;
P_OFFSET INTEGER := 0;
    l_is_bursting BOOLEAN;
  l_is_chunking  BOOLEAN;
    ------------------------------------------------------------------
    -- Run / line parsing
    ------------------------------------------------------------------
    l_run_id     NUMBER;
    l_len        INTEGER;
    l_pos        INTEGER := 1;
    l_next       INTEGER;
    l_line_no    INTEGER := 0;
    l_line       VARCHAR2(4000);

    ------------------------------------------------------------------
    -- Header / columns
    ------------------------------------------------------------------
    l_header_line VARCHAR2(4000);
    l_headers     t_varchar_tab := t_varchar_tab();
    l_col_names   t_varchar_tab := t_varchar_tab();
    l_cols        t_varchar_tab := t_varchar_tab();
    l_name_map    t_name_map;
    l_type_info   t_col_type_tab;
    l_col_types   t_varchar_tab := t_varchar_tab();   -- 'NUMBER','DATE','VARCHAR2(4000)'

    ------------------------------------------------------------------
    -- Dynamic table / insert
    ------------------------------------------------------------------
    l_table_name   VARCHAR2(30);
    l_create_sql   CLOB;
    l_insert_sql   CLOB;
    l_cur          INTEGER;
    l_rows         INTEGER;
    l_total_rows   NUMBER := 0;                       -- NEW: count rows

    ------------------------------------------------------------------
    -- Sampling vars for type detection
    ------------------------------------------------------------------
    l_sample_pos   INTEGER;
    l_sample_max   CONSTANT PLS_INTEGER := 50;
    l_sample_count PLS_INTEGER := 0;
    l_tmp_line     VARCHAR2(4000);
    l_tmp_cols     t_varchar_tab;
    l_next2        INTEGER;

    ------------------------------------------------------------------
    -- Logging
    ------------------------------------------------------------------
    l_log_id       NUMBER;
    l_success_flag VARCHAR2(1) := 'N';

    ------------------------------------------------------------------
    -- Helpers
    ------------------------------------------------------------------
    PROCEDURE create_bip_log (
        p_log_id OUT NUMBER
    )
    IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        INSERT INTO xx9638_bip_call_log (
            report_name,
            report_path,
            template_name,
            format,
            locale,
            effective_date,
            ldg,
            limit_val,
            offset_val,
            table_name,
            success_flag,
            rows_inserted
        )
        VALUES (
            p_report_name,
            p_report_path,
            p_template,
            p_format,
            p_locale,
            p_effective_date,
            p_ldg,
            p_limit,
            p_offset,
            NULL,
            'N',
            0
        )
        RETURNING log_id INTO p_log_id;

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END create_bip_log;

    PROCEDURE update_bip_log (
        p_run_id         IN NUMBER   DEFAULT NULL,
        p_table_name     IN VARCHAR2 DEFAULT NULL,
        p_rows_inserted  IN NUMBER   DEFAULT NULL,
        p_success_flag   IN VARCHAR2 DEFAULT NULL,
        p_error_code     IN NUMBER   DEFAULT NULL,
        p_error_message  IN VARCHAR2 DEFAULT NULL,
        p_append_message IN BOOLEAN  DEFAULT FALSE
    )
    IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        IF l_log_id IS NOT NULL THEN
            UPDATE xx9638_bip_call_log
               SET run_id        = CASE WHEN p_run_id IS NOT NULL THEN p_run_id ELSE run_id END,
                   table_name    = CASE WHEN p_table_name IS NOT NULL THEN p_table_name ELSE table_name END,
                   rows_inserted = CASE WHEN p_rows_inserted IS NOT NULL THEN p_rows_inserted ELSE rows_inserted END,
                   success_flag  = CASE WHEN p_success_flag IS NOT NULL THEN p_success_flag ELSE success_flag END,
                   error_code    = CASE WHEN p_error_code IS NOT NULL THEN p_error_code ELSE null END,
                   error_message =
                       CASE
                           WHEN p_error_message IS NULL THEN error_message
                           WHEN p_append_message THEN
                               SUBSTR(
                                   NVL(error_message, '')
                                   || CASE WHEN error_message IS NOT NULL THEN CHR(10) ELSE '' END
                                   || p_error_message,
                                   1,
                                   4000
                               )
                           ELSE
                               SUBSTR(p_error_message, 1, 4000)
                       END
             WHERE log_id = l_log_id;
            COMMIT;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
    END update_bip_log;

    PROCEDURE append_debug_log (
        p_step IN VARCHAR2,
        p_text IN VARCHAR2
    )
    IS
    BEGIN
        update_bip_log(
            p_error_message =>
                '[' || TO_CHAR(SYSTIMESTAMP, 'YYYY-MM-DD HH24:MI:SS.FF3') || '] '
                || p_step || ': '
                || SUBSTR(p_text, 1, 2500),
            p_append_message => TRUE
        );
    END append_debug_log;

    FUNCTION compact_xml_preview (
        p_text   IN CLOB,
        p_length IN PLS_INTEGER DEFAULT 500
    ) RETURN VARCHAR2
    IS
        l_preview VARCHAR2(32767);
    BEGIN
        IF p_text IS NULL THEN
            RETURN '<null>';
        END IF;

        l_preview := DBMS_LOB.SUBSTR(p_text, p_length, 1);
        l_preview := REPLACE(REPLACE(REPLACE(l_preview, CHR(13), ' '), CHR(10), ' '), CHR(9), ' ');
        l_preview := REGEXP_REPLACE(l_preview, ' {2,}', ' ');
        RETURN l_preview;
    EXCEPTION
        WHEN OTHERS THEN
            RETURN '<preview_error:' || SUBSTR(SQLERRM, 1, 150) || '>';
    END compact_xml_preview;

    FUNCTION safe_clob_length (p_text IN CLOB) RETURN NUMBER
    IS
    BEGIN
        IF p_text IS NULL THEN
            RETURN 0;
        END IF;
        RETURN DBMS_LOB.getlength(p_text);
    EXCEPTION
        WHEN OTHERS THEN
            RETURN 0;
    END safe_clob_length;

    PROCEDURE log_key_http_headers (
        p_prefix IN VARCHAR2,
        p_resp   IN OUT NOCOPY UTL_HTTP.resp
    )
    IS
        l_name  VARCHAR2(256);
        l_value VARCHAR2(4000);
    BEGIN
        append_debug_log(
            p_prefix || '_HTTP_STATUS',
            'status_code=' || p_resp.status_code || ', reason=' || p_resp.reason_phrase
        );

        FOR i IN 1 .. UTL_HTTP.get_header_count(p_resp) LOOP
            UTL_HTTP.get_header(p_resp, i, l_name, l_value);
            IF UPPER(l_name) IN ('CONTENT-TYPE', 'CONTENT-ENCODING', 'TRANSFER-ENCODING', 'CONTENT-LENGTH') THEN
                append_debug_log(
                    p_prefix || '_HTTP_HEADER',
                    l_name || '=' || SUBSTR(l_value, 1, 300)
                );
            END IF;
        END LOOP;
    EXCEPTION
        WHEN OTHERS THEN
            append_debug_log(p_prefix || '_HEADER_READ_ERR', SUBSTR(SQLERRM, 1, 300));
    END log_key_http_headers;

    PROCEDURE read_http_response_clob (
        p_resp IN OUT NOCOPY UTL_HTTP.resp,
        p_clob OUT CLOB
    )
    IS
        l_raw_buf    RAW(32767);
        l_blob       BLOB;
        l_dest_off   INTEGER := 1;
        l_src_off    INTEGER := 1;
        l_lang_ctx   INTEGER := DBMS_LOB.default_lang_ctx;
        l_warning    INTEGER;
    BEGIN
        DBMS_LOB.createtemporary(l_blob, TRUE);
        DBMS_LOB.createtemporary(p_clob, TRUE);

        BEGIN
            LOOP
                UTL_HTTP.read_raw(p_resp, l_raw_buf, 32767);
                DBMS_LOB.writeappend(l_blob, UTL_RAW.LENGTH(l_raw_buf), l_raw_buf);
            END LOOP;
        EXCEPTION
            WHEN UTL_HTTP.end_of_body THEN
                NULL;
        END;

        IF DBMS_LOB.getlength(l_blob) > 0 THEN
            DBMS_LOB.CONVERTTOCLOB(
                dest_lob     => p_clob,
                src_blob     => l_blob,
                amount       => DBMS_LOB.LOBMAXSIZE,
                dest_offset  => l_dest_off,
                src_offset   => l_src_off,
                blob_csid    => NLS_CHARSET_ID('AL32UTF8'),
                lang_context => l_lang_ctx,
                warning      => l_warning
            );
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            IF DBMS_LOB.ISTEMPORARY(l_blob) = 1 THEN
                DBMS_LOB.FREETEMPORARY(l_blob);
            END IF;
            RAISE;
    END read_http_response_clob;

    FUNCTION xxint_run_bip_report (

       p_report_path    IN VARCHAR2, -- e.g. '/Custom/Interfaces/MyReport.xdo'
    p_format         IN VARCHAR2, -- 'xml','csv','pdf','html', etc.
    p_template       IN VARCHAR2, --MWFINAL
    p_effective_date IN DATE,
    p_ldg            IN VARCHAR2,
    p_limit          IN NUMBER,
    p_offset         IN NUMBER,
        p_locale        IN VARCHAR2 
) RETURN BLOB

IS

    ------------------------------------------------------------------
    -- CONSTANTS: change for your environment
    ------------------------------------------------------------------
  /*  c_bip_url      CONSTANT VARCHAR2(4000) :=
        'https://fa-espx-saasfaprod1.fa.ocs.oraclecloud.com/xmlpserver/services/ExternalReportWSSService';
    c_bip_user     CONSTANT VARCHAR2(200)  := 'MWUSER';
    c_bip_password CONSTANT VARCHAR2(200)  := ')N<Gx5{nj#4@';*/

 c_bip_url      CONSTANT VARCHAR2(4000) :=
        'https://fa-espx-dev1-saasfaprod1.fa.ocs.oraclecloud.com/xmlpserver/services/ExternalReportWSSService';
    c_bip_user     CONSTANT VARCHAR2(200)  := 'MWUSER';
    c_bip_password CONSTANT VARCHAR2(200)  := 'Welcome1234$';

     ------------------------------------------------------------------
    -- HTTP + SOAP variables
    ------------------------------------------------------------------
    l_req        UTL_HTTP.req;
    l_resp       UTL_HTTP.resp;
    l_buf        VARCHAR2(32767);
    l_response   CLOB;
    l_envelope   CLOB;
    l_header_name  VARCHAR2(256);
    l_header_value VARCHAR2(4000);

    ------------------------------------------------------------------
    -- XML / base64 / fault variables
    ------------------------------------------------------------------
    l_xml          XMLTYPE;
    l_b64          CLOB;           -- base64-encoded reportBytes as CLOB
    l_report_blob  BLOB;
    l_pos          PLS_INTEGER := 1;
    l_chunk        VARCHAR2(32000);
    l_raw          RAW(32767);
    l_fault        VARCHAR2(4000);
    l_report_file_id      VARCHAR2(4000);
    l_report_content_type VARCHAR2(4000);

    ------------------------------------------------------------------
    -- Helper: build Basic Auth header
    ------------------------------------------------------------------
    FUNCTION basic_auth (p_user IN VARCHAR2, p_pwd IN VARCHAR2)
        RETURN VARCHAR2
    IS
        l_raw RAW(32767);
    BEGIN
        l_raw := UTL_RAW.cast_to_raw(p_user || ':' || p_pwd);
        RETURN 'Basic ' ||
               UTL_RAW.cast_to_varchar2(UTL_ENCODE.base64_encode(l_raw));
    END basic_auth;

    FUNCTION xml_escape (p_value IN VARCHAR2)
        RETURN VARCHAR2
    IS
    BEGIN
        IF p_value IS NULL THEN
            RETURN NULL;
        END IF;

        RETURN DBMS_XMLGEN.CONVERT(p_value, DBMS_XMLGEN.ENTITY_ENCODE);
    END xml_escape;

    FUNCTION build_param_item (
        p_name  IN VARCHAR2,
        p_value IN VARCHAR2
    ) RETURN CLOB
    IS
    BEGIN
        IF p_value IS NULL THEN
            RETURN '';
        END IF;

        RETURN '    <pub:item>'
            || '      <pub:name>' || xml_escape(p_name) || '</pub:name>'
            || '      <pub:values>'
            || '        <pub:item>' || xml_escape(p_value) || '</pub:item>'
            || '      </pub:values>'
            || '    </pub:item>';
    END build_param_item;

    FUNCTION download_report_file (p_file_id IN VARCHAR2)
        RETURN BLOB
    IS
    l_req2          UTL_HTTP.req;
    l_resp2         UTL_HTTP.resp;
    l_buf2          VARCHAR2(32767);
    l_response2     CLOB;
    l_envelope2     CLOB;
    l_header_name2  VARCHAR2(256);
    l_header_value2 VARCHAR2(4000);
        l_xml2          XMLTYPE;
        l_b64_chunk     CLOB;
        l_chunk_blob    BLOB;
        l_next_offset   NUMBER := 0;
        l_begin_idx     NUMBER := 0;
        l_chunk_size    CONSTANT NUMBER := 1024;
        l_fault2        VARCHAR2(4000);
        l_file_id2      VARCHAR2(4000) := p_file_id;
        l_chunk_varchar VARCHAR2(32000);
        l_chunk_raw     RAW(32767);
    BEGIN
        DBMS_LOB.createtemporary(l_chunk_blob, TRUE);

        LOOP
            DBMS_LOB.createtemporary(l_response2, TRUE);
            l_envelope2 :=
                  '<?xml version="1.0" encoding="UTF-8"?>'
               || '<soap12:Envelope xmlns:soap12="http://www.w3.org/2003/05/soap-envelope"'
                || '                  xmlns:pub="http://xmlns.oracle.com/oxp/service/PublicReportService">'
               || '  <soap12:Header/>'
                || '  <soap12:Body>'
               || '    <pub:downloadReportDataChunk>'
               || '      <pub:fileID>' || xml_escape(l_file_id2) || '</pub:fileID>'
               || '      <pub:beginIdx>' || TO_CHAR(l_begin_idx) || '</pub:beginIdx>'
               || '      <pub:size>' || TO_CHAR(l_chunk_size) || '</pub:size>'
               || '    </pub:downloadReportDataChunk>'
               || '  </soap12:Body>'
               || '</soap12:Envelope>';

            UTL_HTTP.set_transfer_timeout(300);

            l_req2 := UTL_HTTP.begin_request(
                          url          => c_bip_url,
                          method       => 'POST',
                          http_version => 'HTTP/1.1');

            UTL_HTTP.set_header(
                l_req2,
                'Content-Type',
                'application/soap+xml; charset=UTF-8'
            );
            UTL_HTTP.set_header(l_req2, 'SOAPAction', 'downloadReportDataChunk');
            UTL_HTTP.set_header(l_req2, 'Accept', '*/*');
            UTL_HTTP.set_header(l_req2, 'Accept-Encoding', 'identity');
            UTL_HTTP.set_header(l_req2, 'Connection', 'keep-alive');
            UTL_HTTP.set_header(l_req2, 'User-Agent', 'PostmanRuntime/7.52.0');

            UTL_HTTP.set_header(
                l_req2,
                'Authorization',
                'Basic TVdVU0VSOldlbGNvbWUxMjM0JA=='
            );
            UTL_HTTP.write_text(l_req2, l_envelope2);
            l_resp2 := UTL_HTTP.get_response(l_req2);
            log_key_http_headers('DOWNLOAD_CHUNK', l_resp2);

            read_http_response_clob(l_resp2, l_response2);

            UTL_HTTP.end_response(l_resp2);
            l_xml2 := XMLTYPE(l_response2);

            BEGIN
                l_b64_chunk := l_xml2.extract('//*[local-name()="reportDataChunk"]/text()').getClobVal();
            EXCEPTION
                WHEN OTHERS THEN
                    l_b64_chunk := NULL;
            END;

            BEGIN
                l_next_offset := TO_NUMBER(
                    l_xml2.extract('//*[local-name()="reportDataOffset"]/text()').getStringVal()
                );
            EXCEPTION
                WHEN OTHERS THEN
                    l_next_offset := -1;
            END;

            BEGIN
                l_file_id2 := l_xml2.extract('//*[local-name()="reportDataFileID"]/text()').getStringVal();
            EXCEPTION
                WHEN OTHERS THEN
                    NULL;
            END;

            IF l_b64_chunk IS NOT NULL AND DBMS_LOB.getlength(l_b64_chunk) > 0 THEN
                l_pos := 1;
                WHILE l_pos <= DBMS_LOB.getlength(l_b64_chunk) LOOP
                    l_chunk_varchar := DBMS_LOB.SUBSTR(l_b64_chunk, 32000, l_pos);
                    l_chunk_raw := UTL_ENCODE.base64_decode(UTL_RAW.cast_to_raw(l_chunk_varchar));
                    DBMS_LOB.writeappend(l_chunk_blob, UTL_RAW.LENGTH(l_chunk_raw), l_chunk_raw);
                    l_pos := l_pos + 32000;
                END LOOP;
            ELSIF l_next_offset <> -1 THEN
                BEGIN
                    l_fault2 :=
                        l_xml2.extract(
                            '//*[local-name()="Fault"]/*[local-name()="faultstring" or local-name()="Text"]/text()'
                        ).getStringVal();
                EXCEPTION
                    WHEN OTHERS THEN
                        l_fault2 := NULL;
                END;

                RAISE_APPLICATION_ERROR(
                    -20002,
                    'downloadReportDataChunk returned no data for fileID '
                    || p_file_id
                    || CASE WHEN l_fault2 IS NOT NULL THEN '. Fault: ' || l_fault2 ELSE '' END
                    || '. First 1500 chars of SOAP response: '
                    || SUBSTR(l_response2, 1, 1500)
                );
            END IF;

            EXIT WHEN l_next_offset = -1;
            l_begin_idx := l_next_offset;
        END LOOP;

        RETURN l_chunk_blob;
    EXCEPTION
        WHEN OTHERS THEN
            BEGIN
                UTL_HTTP.end_response(l_resp2);
            EXCEPTION
                WHEN OTHERS THEN NULL;
            END;
            RAISE;
    END download_report_file;

BEGIN
    ------------------------------------------------------------------
    -- 1) Build SOAP 1.2 envelope (optional attributeFormat)
    ------------------------------------------------------------------
    DBMS_LOB.createtemporary(l_response, TRUE);

    l_envelope :=
          '<?xml version="1.0" encoding="UTF-8"?>'
       || '<soap12:Envelope xmlns:soap12="http://www.w3.org/2003/05/soap-envelope"'
       || '                  xmlns:pub="http://xmlns.oracle.com/oxp/service/PublicReportService">'
       || '  <soap12:Header/>'
       || '  <soap12:Body>'
       || '    <pub:runReport>'
       || '      <pub:reportRequest>'
       -- inside reportRequest
                    || '<pub:attributeLocale>en-US</pub:attributeLocale>'
   || ' <pub:parameterNameValues>'
  -- Effective Date
 || CASE
    WHEN p_payrollActionId IS NOT NULL THEN
      '    <pub:item>' ||
      '      <pub:name>payrollActionId</pub:name>' ||
      '      <pub:values>' ||
      '        <pub:item>' || p_payrollActionId || '</pub:item>' ||
      '      </pub:values>' ||
      '    </pub:item>'
    ELSE
      ''
  END ||

  -- LDG

   '</pub:parameterNameValues>'
    || '<pub:attributeTemplate>' || TO_CHAR(p_template) || 
   '</pub:attributeTemplate>'
  || '<pub:attributeFormat>' || TO_CHAR(p_format)||'</pub:attributeFormat>'
      -- end inside reportRequest
       ||          CASE
                     WHEN p_format IS NOT NULL THEN
                       '<pub:attributeFormat>' || LOWER(TRIM(p_format)) || '</pub:attributeFormat>'
                     ELSE
                       ''  -- let BIP use the report's default format
                   END
       || '        <pub:flattenXML>false</pub:flattenXML>'
       || '        <pub:reportAbsolutePath>' || p_report_path || '</pub:reportAbsolutePath>'
       || '        <pub:sizeOfDataChunkDownload>-1</pub:sizeOfDataChunkDownload>'

       || '      </pub:reportRequest>'
       || '      <pub:userID></pub:userID>'
       || '      <pub:password></pub:password>'
       || '    </pub:runReport>'
       || '  </soap12:Body>'
       || '</soap12:Envelope>';

    append_debug_log(
        'RUNREPORT_REQUEST',
        'path=' || p_report_path
        || ', template=' || NVL(p_template, '<null>')
        || ', format=' || NVL(p_format, '<null>')
        || ', locale=' || NVL(p_locale, '<null>')
    );

    ------------------------------------------------------------------
    -- 2) Send HTTP request
    ------------------------------------------------------------------
    UTL_HTTP.set_transfer_timeout(300);

    l_req := UTL_HTTP.begin_request(
                 url          => c_bip_url,
                 method       => 'POST',
                 http_version => 'HTTP/1.1');

    UTL_HTTP.set_header(
        l_req,
        'Content-Type',
        'application/soap+xml; charset=UTF-8'
    );
    UTL_HTTP.set_header(l_req, 'SOAPAction', 'runReport');

    UTL_HTTP.set_header(
        l_req,
        'Authorization',
        'Basic TVdVU0VSOldlbGNvbWUxMjM0JA=='
    );

    UTL_HTTP.write_text(l_req, l_envelope);

    l_resp := UTL_HTTP.get_response(l_req);
    append_debug_log(
        'EXTRACT_RUNREPORT_HTTP_STATUS',
        'status_code=' || l_resp.status_code || ', reason=' || l_resp.reason_phrase
    );

    BEGIN
        FOR i IN 1 .. UTL_HTTP.get_header_count(l_resp) LOOP
            UTL_HTTP.get_header(l_resp, i, l_header_name, l_header_value);
            append_debug_log(
                'EXTRACT_RUNREPORT_HTTP_HEADER',
                l_header_name || '=' || SUBSTR(l_header_value, 1, 400)
            );
        END LOOP;
    EXCEPTION
        WHEN OTHERS THEN
            append_debug_log('EXTRACT_HEADER_READ_ERR', SQLERRM);
    END;

    read_http_response_clob(l_resp, l_response);

    UTL_HTTP.end_response(l_resp);
    append_debug_log('RUNREPORT_RESPONSE_PREVIEW', compact_xml_preview(l_response));

    IF safe_clob_length(l_response) = 0 THEN
        append_debug_log('RUNREPORT_EMPTY_RESPONSE', 'HTTP body was empty');
        RAISE_APPLICATION_ERROR(-20003, 'BIP runReport returned an empty HTTP response body.');
    END IF;

    ------------------------------------------------------------------
    -- 3) Parse SOAP and get reportBytes as CLOB (no 32K limit)
    ------------------------------------------------------------------
    l_xml := XMLTYPE(l_response);

    BEGIN
        -- extract any <reportBytes> text node as CLOB
        l_b64 := l_xml.extract('//*[local-name()="reportBytes"]/text()').getClobVal();
    EXCEPTION
        WHEN OTHERS THEN
            l_b64 := NULL;
    END;

    BEGIN
        l_report_file_id := l_xml.extract('//*[local-name()="reportFileID"]/text()').getStringVal();
    EXCEPTION
        WHEN OTHERS THEN
            l_report_file_id := NULL;
    END;

    BEGIN
        l_report_content_type := l_xml.extract('//*[local-name()="reportContentType"]/text()').getStringVal();
    EXCEPTION
        WHEN OTHERS THEN
            l_report_content_type := NULL;
    END;

    ------------------------------------------------------------------
    -- 4) If no reportBytes, check for SOAP Fault and raise that
    ------------------------------------------------------------------
    IF l_b64 IS NULL THEN
        BEGIN
            -- Fault text can be under <faultstring> or <env:Text>
            l_fault :=
                l_xml.extract(
                    '//*[local-name()="Fault"]/*[local-name()="faultstring" or local-name()="Text"]/text()'
                ).getStringVal();
        EXCEPTION
            WHEN OTHERS THEN
                l_fault := NULL;
        END;

        IF l_fault IS NOT NULL THEN
            append_debug_log('RUNREPORT_FAULT', l_fault);
            RAISE_APPLICATION_ERROR(-20001, 'BIP runReport fault: ' || l_fault);
        ELSIF l_report_file_id IS NOT NULL THEN
            append_debug_log(
                'RUNREPORT_FILEID',
                'reportFileID=' || l_report_file_id
                || ', reportContentType=' || NVL(l_report_content_type, '<null>')
            );
            RETURN download_report_file(l_report_file_id);
        ELSE
            append_debug_log(
                'RUNREPORT_NOREPORTBYTES',
                'reportFileID=' || NVL(l_report_file_id, '<null>')
                || ', reportContentType=' || NVL(l_report_content_type, '<null>')
                || ', responsePreview=' || compact_xml_preview(l_response)
            );
            RAISE_APPLICATION_ERROR(
                -20001,
                'runReport did not return reportBytes. First 1500 chars of SOAP response: '
                ||l_envelope

                --||SUBSTR(l_response, 1, 1500)
            );
        END IF;
    END IF;

    ------------------------------------------------------------------
    -- 5) Base64 decode CLOB into BLOB, in chunks
    ------------------------------------------------------------------
    DBMS_LOB.createtemporary(l_report_blob, TRUE);

    WHILE l_pos <= DBMS_LOB.getlength(l_b64) LOOP
        l_chunk := DBMS_LOB.SUBSTR(l_b64, 32000, l_pos);        -- CLOB -> VARCHAR2 chunk
        l_raw   := UTL_ENCODE.base64_decode(UTL_RAW.cast_to_raw(l_chunk));
        DBMS_LOB.writeappend(l_report_blob, UTL_RAW.LENGTH(l_raw), l_raw);
        l_pos   := l_pos + 32000;
    END LOOP;

    RETURN l_report_blob;

EXCEPTION
    WHEN OTHERS THEN
        BEGIN
            UTL_HTTP.end_response(l_resp);
        EXCEPTION
            WHEN OTHERS THEN NULL;
        END;
        RAISE;
END xxint_run_bip_report;
FUNCTION xxint_run_EXTRACT_report (

       p_report_path    IN VARCHAR2, -- e.g. '/Custom/Interfaces/MyReport.xdo'
    p_format         IN VARCHAR2, -- 'xml','csv','pdf','html', etc.
    p_template       IN VARCHAR2, --MWFINAL
    p_deliveryOptionId IN number,
    p_payrollActionId            IN number,
    p_flowInstanceName          IN VARCHAR2,
    p_sequence         IN NUMBER,
    p_isBursting        in BOOLEAN,
     p_isChunking        in BOOLEAN,
      p_locale        IN VARCHAR2 
) RETURN BLOB

IS

    ------------------------------------------------------------------
    -- CONSTANTS: change for your environment
    ------------------------------------------------------------------
  /*  c_bip_url      CONSTANT VARCHAR2(4000) :=
        'https://fa-espx-saasfaprod1.fa.ocs.oraclecloud.com/xmlpserver/services/ExternalReportWSSService';
    c_bip_user     CONSTANT VARCHAR2(200)  := 'MWUSER';
    c_bip_password CONSTANT VARCHAR2(200)  := ')N<Gx5{nj#4@';*/

 c_bip_url      CONSTANT VARCHAR2(4000) :=
        'https://fa-espx-dev1-saasfaprod1.fa.ocs.oraclecloud.com/xmlpserver/services/ExternalReportWSSService';
    c_bip_user     CONSTANT VARCHAR2(200)  := 'MWUSER';
    c_bip_password CONSTANT VARCHAR2(200)  := 'WHlcobE1234$';

     ------------------------------------------------------------------
    -- HTTP + SOAP variables
    ------------------------------------------------------------------
    l_req        UTL_HTTP.req;
    l_resp       UTL_HTTP.resp;
    l_buf        VARCHAR2(32767);
    l_response   CLOB;
    l_envelope   CLOB;

    ------------------------------------------------------------------
    -- XML / base64 / fault variables
    ------------------------------------------------------------------
    l_xml          XMLTYPE;
    l_b64          CLOB;           -- base64-encoded reportBytes as CLOB
    l_report_blob  BLOB;
    l_pos          PLS_INTEGER := 1;
    l_chunk        VARCHAR2(32000);
    l_raw          RAW(32767);
    l_fault        VARCHAR2(4000);
    l_report_file_id      VARCHAR2(4000);
    l_report_content_type VARCHAR2(4000);

    ------------------------------------------------------------------
    -- Helper: build Basic Auth header
    ------------------------------------------------------------------
    FUNCTION basic_auth (p_user IN VARCHAR2, p_pwd IN VARCHAR2)
        RETURN VARCHAR2
    IS
        l_raw RAW(32767);
    BEGIN
        l_raw := UTL_RAW.cast_to_raw(p_user || ':' || p_pwd);
        RETURN 'Basic ' ||
               UTL_RAW.cast_to_varchar2(UTL_ENCODE.base64_encode(l_raw));
    END basic_auth;

    FUNCTION xml_escape (p_value IN VARCHAR2)
        RETURN VARCHAR2
    IS
    BEGIN
        IF p_value IS NULL THEN
            RETURN NULL;
        END IF;

        RETURN DBMS_XMLGEN.CONVERT(p_value, DBMS_XMLGEN.ENTITY_ENCODE);
    END xml_escape;

    FUNCTION build_param_item (
        p_name  IN VARCHAR2,
        p_value IN VARCHAR2
    ) RETURN CLOB
    IS
    BEGIN
        IF p_value IS NULL THEN
            RETURN '';
        END IF;

        RETURN '    <pub:item>'
            || '      <pub:name>' || xml_escape(p_name) || '</pub:name>'
            || '      <pub:values>'
            || '        <pub:item>' || xml_escape(p_value) || '</pub:item>'
            || '      </pub:values>'
            || '    </pub:item>';
    END build_param_item;

    FUNCTION download_report_file (p_file_id IN VARCHAR2)
        RETURN BLOB
    IS
        l_req2          UTL_HTTP.req;
        l_resp2         UTL_HTTP.resp;
        l_buf2          VARCHAR2(32767);
        l_response2     CLOB;
        l_envelope2     CLOB;
        l_xml2          XMLTYPE;
        l_b64_chunk     CLOB;
        l_chunk_blob    BLOB;
        l_next_offset   NUMBER := 0;
        l_begin_idx     NUMBER := 0;
        l_chunk_size    CONSTANT NUMBER := 1024;
        l_fault2        VARCHAR2(4000);
        l_file_id2      VARCHAR2(4000) := p_file_id;
        l_decode_pos    PLS_INTEGER := 1;
        l_chunk_varchar VARCHAR2(32000);
        l_chunk_raw     RAW(32767);
    BEGIN
        DBMS_LOB.createtemporary(l_chunk_blob, TRUE);

        LOOP
            l_response2 := NULL;
            l_envelope2 :=
                  '<?xml version="1.0" encoding="UTF-8"?>'
               || '<soap12:Envelope xmlns:soap12="http://www.w3.org/2003/05/soap-envelope"'
                || '                  xmlns:pub="http://xmlns.oracle.com/oxp/service/PublicReportService">'
               || '  <soap12:Header/>'
                || '  <soap12:Body>'
               || '    <pub:downloadReportDataChunk>'
               || '      <pub:fileID>' || xml_escape(l_file_id2) || '</pub:fileID>'
               || '      <pub:beginIdx>' || TO_CHAR(l_begin_idx) || '</pub:beginIdx>'
               || '      <pub:size>' || TO_CHAR(l_chunk_size) || '</pub:size>'
               || '    </pub:downloadReportDataChunk>'
               || '  </soap12:Body>'
               || '</soap12:Envelope>';

            append_debug_log(
                'DOWNLOAD_CHUNK_REQUEST',
                'fileID=' || p_file_id || ', beginIdx=' || l_begin_idx || ', size=' || l_chunk_size
            );

            UTL_HTTP.set_transfer_timeout(300);

            l_req2 := UTL_HTTP.begin_request(
                          url          => c_bip_url,
                          method       => 'POST',
                          http_version => 'HTTP/1.1');

            UTL_HTTP.set_header(
                l_req2,
                'Content-Type',
                'application/soap+xml; charset=UTF-8'
            );
            UTL_HTTP.set_header(l_req2, 'SOAPAction', 'downloadReportDataChunk');

            UTL_HTTP.set_header(l_req2, 'Authorization', basic_auth(c_bip_user, c_bip_password));
            UTL_HTTP.write_text(l_req2, l_envelope2);
            l_resp2 := UTL_HTTP.get_response(l_req2);

            BEGIN
                LOOP
                    UTL_HTTP.read_text(l_resp2, l_buf2, 32767);
                    l_response2 := l_response2 || l_buf2;
                END LOOP;
            EXCEPTION
                WHEN UTL_HTTP.end_of_body THEN
                    NULL;
            END;

            UTL_HTTP.end_response(l_resp2);
            append_debug_log('DOWNLOAD_CHUNK_RESPONSE_PREVIEW', compact_xml_preview(l_response2));

            IF safe_clob_length(l_response2) = 0 THEN
                append_debug_log(
                    'DOWNLOAD_CHUNK_EMPTY_RESPONSE',
                    'fileID=' || p_file_id || ', beginIdx=' || l_begin_idx
                );
                RAISE_APPLICATION_ERROR(-20004, 'downloadReportDataChunk returned an empty HTTP response body.');
            END IF;

            l_xml2 := XMLTYPE(l_response2);

            BEGIN
                l_b64_chunk := l_xml2.extract('//*[local-name()="reportDataChunk"]/text()').getClobVal();
            EXCEPTION
                WHEN OTHERS THEN
                    l_b64_chunk := NULL;
            END;

            BEGIN
                l_next_offset := TO_NUMBER(
                    l_xml2.extract('//*[local-name()="reportDataOffset"]/text()').getStringVal()
                );
            EXCEPTION
                WHEN OTHERS THEN
                    l_next_offset := -1;
            END;

            BEGIN
                l_file_id2 := l_xml2.extract('//*[local-name()="reportDataFileID"]/text()').getStringVal();
            EXCEPTION
                WHEN OTHERS THEN
                    NULL;
            END;

            IF l_b64_chunk IS NOT NULL AND DBMS_LOB.getlength(l_b64_chunk) > 0 THEN
                l_decode_pos := 1;
                WHILE l_decode_pos <= DBMS_LOB.getlength(l_b64_chunk) LOOP
                    l_chunk_varchar := DBMS_LOB.SUBSTR(l_b64_chunk, 32000, l_decode_pos);
                    l_chunk_raw := UTL_ENCODE.base64_decode(UTL_RAW.cast_to_raw(l_chunk_varchar));
                    DBMS_LOB.writeappend(l_chunk_blob, UTL_RAW.LENGTH(l_chunk_raw), l_chunk_raw);
                    l_decode_pos := l_decode_pos + 32000;
                END LOOP;
            ELSIF l_next_offset <> -1 THEN
                BEGIN
                    l_fault2 :=
                        l_xml2.extract(
                            '//*[local-name()="Fault"]/*[local-name()="faultstring" or local-name()="Text"]/text()'
                        ).getStringVal();
                EXCEPTION
                    WHEN OTHERS THEN
                        l_fault2 := NULL;
                END;

                RAISE_APPLICATION_ERROR(
                    -20002,
                    'downloadReportDataChunk returned no data for fileID '
                    || p_file_id
                    || CASE WHEN l_fault2 IS NOT NULL THEN '. Fault: ' || l_fault2 ELSE '' END
                    || '. First 1500 chars of SOAP response: '
                    || SUBSTR(l_response2, 1, 1500)
                );
            END IF;

            EXIT WHEN l_next_offset = -1;
            l_begin_idx := l_next_offset;
        END LOOP;

        RETURN l_chunk_blob;
    EXCEPTION
        WHEN OTHERS THEN
            BEGIN
                UTL_HTTP.end_response(l_resp2);
            EXCEPTION
                WHEN OTHERS THEN NULL;
            END;
            RAISE;
    END download_report_file;

BEGIN
    ------------------------------------------------------------------
    -- 1) Build SOAP 1.2 envelope (optional attributeFormat)
    ------------------------------------------------------------------
    DBMS_LOB.createtemporary(l_response, TRUE);

    l_envelope :=
          '<?xml version="1.0" encoding="UTF-8"?>'
       || '<soap12:Envelope xmlns:soap12="http://www.w3.org/2003/05/soap-envelope"'
       || '                  xmlns:pub="http://xmlns.oracle.com/oxp/service/PublicReportService">'
       || '  <soap12:Header/>'
       || '  <soap12:Body>'
       || '    <pub:runReport>'
       || '      <pub:reportRequest>'
       || '        <pub:attributeLocale>' || xml_escape(NVL(p_locale, 'en-US')) || '</pub:attributeLocale>'
       || '        <pub:parameterNameValues>'
       || build_param_item('deliveryOptionId', TO_CHAR(p_deliveryOptionId))
       || build_param_item('payrollActionId', TO_CHAR(p_payrollActionId))
       || build_param_item('flowInstanceName', p_flowInstanceName)
       || build_param_item('sequence', TO_CHAR(p_sequence))
       || build_param_item('isBursting', CASE WHEN p_isBursting THEN 'true' ELSE 'false' END)
       || build_param_item('isChunking', CASE WHEN p_isChunking THEN 'true' ELSE 'false' END)
       || '        </pub:parameterNameValues>'
       || CASE
              WHEN p_template IS NOT NULL THEN
                  '<pub:attributeTemplate>' || xml_escape(p_template) || '</pub:attributeTemplate>'
              ELSE
                  ''
          END
       || CASE
              WHEN p_format IS NOT NULL THEN
                  '<pub:attributeFormat>' || LOWER(TRIM(xml_escape(p_format))) || '</pub:attributeFormat>'
              ELSE
                  ''
          END
       || '        <pub:flattenXML>false</pub:flattenXML>'
       || '        <pub:reportAbsolutePath>' || xml_escape(p_report_path) || '</pub:reportAbsolutePath>'
       || '        <pub:sizeOfDataChunkDownload>-1</pub:sizeOfDataChunkDownload>'

       || '      </pub:reportRequest>'
       || '      <pub:userID></pub:userID>'
       || '      <pub:password></pub:password>'
       || '    </pub:runReport>'
       || '  </soap12:Body>'
       || '</soap12:Envelope>';

    append_debug_log(
        'EXTRACT_RUNREPORT_REQUEST',
        'path=' || p_report_path
        || ', template=' || NVL(p_template, '<null>')
        || ', format=' || NVL(p_format, '<null>')
        || ', locale=' || NVL(p_locale, '<null>')
        || ', deliveryOptionId=' || NVL(TO_CHAR(p_deliveryOptionId), '<null>')
        || ', payrollActionId=' || NVL(TO_CHAR(p_payrollActionId), '<null>')
        || ', flowInstanceName=' || NVL(p_flowInstanceName, '<null>')
        || ', sequence=' || NVL(TO_CHAR(p_sequence), '<null>')
        || ', isBursting=' || CASE WHEN p_isBursting THEN 'true' ELSE 'false' END
        || ', isChunking=' || CASE WHEN p_isChunking THEN 'true' ELSE 'false' END
    );

    ------------------------------------------------------------------
    -- 2) Send HTTP request
    ------------------------------------------------------------------
    UTL_HTTP.set_transfer_timeout(300);

    l_req := UTL_HTTP.begin_request(
                 url          => c_bip_url,
                 method       => 'POST',
                 http_version => 'HTTP/1.1');

    UTL_HTTP.set_header(
        l_req,
        'Content-Type',
        'application/soap+xml; charset=UTF-8'
    );
    UTL_HTTP.set_header(l_req, 'SOAPAction', 'runReport');
    UTL_HTTP.set_header(l_req, 'Accept', '*/*');
    UTL_HTTP.set_header(l_req, 'Accept-Encoding', 'identity');
    UTL_HTTP.set_header(l_req, 'Connection', 'keep-alive');
    UTL_HTTP.set_header(l_req, 'User-Agent', 'PostmanRuntime/7.52.0');

    UTL_HTTP.set_header(l_req, 'Authorization', basic_auth(c_bip_user, c_bip_password));

    UTL_HTTP.write_text(l_req, l_envelope);

    l_resp := UTL_HTTP.get_response(l_req);
    log_key_http_headers('EXTRACT_RUNREPORT', l_resp);

    read_http_response_clob(l_resp, l_response);

    UTL_HTTP.end_response(l_resp);
    append_debug_log('EXTRACT_RUNREPORT_RESPONSE_PREVIEW', compact_xml_preview(l_response));

    IF safe_clob_length(l_response) = 0 THEN
        append_debug_log('EXTRACT_RUNREPORT_EMPTY_RESPONSE', 'HTTP body was empty');
        RAISE_APPLICATION_ERROR(-20003, 'BIP runReport returned an empty HTTP response body.');
    END IF;

    ------------------------------------------------------------------
    -- 3) Parse SOAP and get reportBytes as CLOB (no 32K limit)
    ------------------------------------------------------------------
    l_xml := XMLTYPE(l_response);

    BEGIN
        -- extract any <reportBytes> text node as CLOB
        l_b64 := l_xml.extract('//*[local-name()="reportBytes"]/text()').getClobVal();
    EXCEPTION
        WHEN OTHERS THEN
            l_b64 := NULL;
    END;

    ------------------------------------------------------------------
    -- 4) If no reportBytes, check for SOAP Fault and raise that
    ------------------------------------------------------------------
    IF l_b64 IS NULL THEN
        BEGIN
            -- Fault text can be under <faultstring> or <env:Text>
            l_fault :=
                l_xml.extract(
                    '//*[local-name()="Fault"]/*[local-name()="faultstring" or local-name()="Text"]/text()'
                ).getStringVal();
        EXCEPTION
            WHEN OTHERS THEN
                l_fault := NULL;
        END;

        IF l_fault IS NOT NULL THEN
            append_debug_log('EXTRACT_RUNREPORT_FAULT', l_fault);
            RAISE_APPLICATION_ERROR(-20001, 'BIP runReport fault: ' || l_fault);
        ELSIF l_report_file_id IS NOT NULL THEN
            append_debug_log(
                'EXTRACT_RUNREPORT_FILEID',
                'reportFileID=' || l_report_file_id
                || ', reportContentType=' || NVL(l_report_content_type, '<null>')
            );
            RETURN download_report_file(l_report_file_id);
        ELSE
            append_debug_log(
                'EXTRACT_NOREPORTBYTES',
                'deliveryOptionId=' || NVL(TO_CHAR(p_deliveryOptionId), '<null>')
                || ', payrollActionId=' || NVL(TO_CHAR(p_payrollActionId), '<null>')
                || ', flowInstanceName=' || NVL(p_flowInstanceName, '<null>')
                || ', sequence=' || NVL(TO_CHAR(p_sequence), '<null>')
                || ', isBursting=' || CASE WHEN p_isBursting THEN 'true' ELSE 'false' END
                || ', isChunking=' || CASE WHEN p_isChunking THEN 'true' ELSE 'false' END
                || ', reportFileID=' || NVL(l_report_file_id, '<null>')
                || ', reportContentType=' || NVL(l_report_content_type, '<null>')
            );
            RAISE_APPLICATION_ERROR(
                -20001,
                'runReport did not return reportBytes.'
                || CASE
                       WHEN l_report_content_type IS NOT NULL THEN
                           ' reportContentType=' || l_report_content_type || '.'
                       ELSE
                           ''
                   END
                || CASE
                       WHEN l_report_file_id IS NOT NULL THEN
                           ' reportFileID=' || l_report_file_id || '.'
                       ELSE
                           ''
                   END
                || ' First 1500 chars of SOAP response: '
                || SUBSTR(l_response, 1, 1500)
            );
        END IF;
    END IF;

    ------------------------------------------------------------------
    -- 5) Base64 decode CLOB into BLOB, in chunks
    ------------------------------------------------------------------
    DBMS_LOB.createtemporary(l_report_blob, TRUE);

    WHILE l_pos <= DBMS_LOB.getlength(l_b64) LOOP
        l_chunk := DBMS_LOB.SUBSTR(l_b64, 32000, l_pos);        -- CLOB -> VARCHAR2 chunk
        l_raw   := UTL_ENCODE.base64_decode(UTL_RAW.cast_to_raw(l_chunk));
        DBMS_LOB.writeappend(l_report_blob, UTL_RAW.LENGTH(l_raw), l_raw);
        l_pos   := l_pos + 32000;
    END LOOP;

    RETURN l_report_blob;

EXCEPTION
    WHEN OTHERS THEN
        BEGIN
            UTL_HTTP.end_response(l_resp);
        EXCEPTION
            WHEN OTHERS THEN NULL;
        END;
        RAISE;
END xxint_run_EXTRACT_report;
    FUNCTION split_line (
        p_str   IN VARCHAR2,
        p_delim IN VARCHAR2 DEFAULT '|'
    ) RETURN t_varchar_tab
    IS
        l_tab   t_varchar_tab := t_varchar_tab();
        l_pos2  PLS_INTEGER := 1;
        l_next2 PLS_INTEGER;
        l_sub   VARCHAR2(4000);
    BEGIN
        IF p_str IS NULL THEN
            RETURN l_tab;
        END IF;

        LOOP
            l_next2 := INSTR(p_str, p_delim, l_pos2);
            IF l_next2 = 0 THEN
                l_sub := SUBSTR(p_str, l_pos2);
            ELSE
                l_sub := SUBSTR(p_str, l_pos2, l_next2 - l_pos2);
            END IF;

            l_tab.EXTEND;
            l_tab(l_tab.COUNT) := TRIM(l_sub);

            EXIT WHEN l_next2 = 0;
            l_pos2 := l_next2 + LENGTH(p_delim);
        END LOOP;

        RETURN l_tab;
    END split_line;

    FUNCTION sanitize_col_name (p_raw IN VARCHAR2) RETURN VARCHAR2 IS
        l_name VARCHAR2(400);
    BEGIN
        l_name := TRIM(p_raw);

        IF l_name IS NULL THEN
            RETURN 'COL';
        END IF;

        l_name := UPPER(l_name);
        l_name := REGEXP_REPLACE(l_name, '[^A-Z0-9_]', '_');

        -- avoid some reserved/simple words
        IF l_name IN ('ACTION', 'DATE', 'NUMBER', 'SELECT', 'FROM', 'WHERE') THEN
            l_name := 'C_' || l_name;
        END IF;

        -- must contain at least one letter
        IF NOT REGEXP_LIKE(l_name, '[A-Z]') THEN
            l_name := 'COL_' || DBMS_RANDOM.STRING('X', 6);
        END IF;

        -- must start with a letter
        IF NOT REGEXP_LIKE(SUBSTR(l_name,1,1), '^[A-Z]') THEN
            l_name := 'C_' || l_name;
        END IF;

        l_name := SUBSTR(l_name, 1, 30);
        RETURN l_name;
    END sanitize_col_name;

    FUNCTION is_number (p_val VARCHAR2) RETURN BOOLEAN IS
    BEGIN
        RETURN REGEXP_LIKE(TRIM(p_val), '^-?\d+(\.\d+)?$');
    EXCEPTION
        WHEN OTHERS THEN
            RETURN FALSE;
    END is_number;

    FUNCTION is_date (p_val VARCHAR2) RETURN BOOLEAN IS
        v VARCHAR2(4000) := TRIM(p_val);
    BEGIN
        IF v IS NULL THEN
            RETURN TRUE; -- null doesn't break "all_date"
        END IF;

        RETURN REGEXP_LIKE(
                 v,
                   '^\d{4}-\d{2}-\d{2}$'           -- 2025-11-16
                 ||'|^\d{4}/\d{2}/\d{2}$'          -- 2025/11/16
                 ||'|^\d{2}-[A-Z]{3}-\d{2,4}$'     -- 16-NOV-2025
                 ||'|^\d{2}/\d{2}/\d{4}$'          -- 11/16/2025
               ,'i');
    EXCEPTION
        WHEN OTHERS THEN
            RETURN FALSE;
    END is_date;

    FUNCTION parse_date (p_val VARCHAR2) RETURN DATE IS
        v VARCHAR2(4000) := TRIM(p_val);
        d DATE;
    BEGIN
        IF v IS NULL THEN
            RETURN NULL;
        END IF;

        BEGIN
            IF REGEXP_LIKE(v, '^\d{4}-\d{2}-\d{2}$') THEN
                RETURN TO_DATE(v, 'YYYY-MM-DD');
            ELSIF REGEXP_LIKE(v, '^\d{4}/\d{2}/\d{2}$') THEN
                RETURN TO_DATE(v, 'YYYY/MM/DD');
            ELSIF REGEXP_LIKE(v, '^\d{2}-[A-Z]{3}-\d{2,4}$','i') THEN
                RETURN TO_DATE(v, 'DD-MON-YYYY');
            ELSIF REGEXP_LIKE(v, '^\d{2}/\d{2}/\d{4}$') THEN
                -- adjust if export is DD/MM/YYYY
                RETURN TO_DATE(v, 'MM/DD/YYYY');
            ELSE
                RETURN TO_DATE(v); -- fallback
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                RETURN NULL;
        END;
    END parse_date;

BEGIN
    p_rows_inserted_out := 0;

    ------------------------------------------------------------------
    -- 0) Insert initial log row
    ------------------------------------------------------------------
    create_bip_log(l_log_id);

    append_debug_log(
        'PROC_INPUTS',
        'report=' || p_report_name
        || ', path=' || p_report_path
        || ', template=' || NVL(p_template, '<null>')
        || ', format=' || NVL(p_format, '<null>')
        || ', locale=' || NVL(p_locale, '<null>')
        || ', deliveryOptionId=' || NVL(TO_CHAR(p_deliveryOptionId), '<null>')
        || ', payrollActionId=' || NVL(TO_CHAR(p_payrollActionId), '<null>')
        || ', flowInstanceName=' || NVL(p_flowInstanceName, '<null>')
        || ', sequence=' || NVL(TO_CHAR(p_sequence), '<null>')
        || ', isBursting=' || CASE WHEN p_isBursting THEN 'true' ELSE 'false' END
        || ', isChunking=' || CASE WHEN p_isChunking THEN 'true' ELSE 'false' END
    );

    ------------------------------------------------------------------
    -- 1) Call BIP and store raw BLOB
    ------------------------------------------------------------------
   /* l_blob := xxint_run_bip_report(
                p_report_path    => p_report_path,
                p_format         => p_format,
                p_template       => p_template,
                p_effective_date => p_effective_date,
                p_ldg            => p_ldg,
                p_limit          => p_limit,
                p_offset         => p_offset,
                p_locale         => p_locale
              );
              */
                  l_blob := xx_int.xxint_run_extract_report(
  p_report_path      => p_report_path,
  p_format           => p_format,
  p_template         => p_template,
  p_deliveryOptionId => p_deliveryOptionId,
  p_payrollActionId  => p_payrollActionId,
  p_flowInstanceName => p_flowInstanceName,
  p_sequence         => p_sequence,
  p_isBursting       => p_isBursting,
  p_isChunking       => p_isChunking,
  p_locale           => p_locale
);

    -- adjust param list if your xxint_run_bip_report signature differs

    INSERT INTO xx9638_report_raw (
        report_name,
        report_path,
        file_blob
    )
    VALUES (
        p_report_name,
        p_report_path,
        l_blob
    )
    RETURNING run_id INTO l_run_id;

    p_run_id_out := l_run_id;

    ------------------------------------------------------------------
    -- 2) Convert BLOB -> CLOB
    ------------------------------------------------------------------
    DBMS_LOB.createtemporary(l_clob, TRUE);
    DBMS_LOB.CONVERTTOCLOB(
      dest_lob     => l_clob,
      src_blob     => l_blob,
      amount       => DBMS_LOB.LOBMAXSIZE,
      dest_offset  => l_dest_off,
      src_offset   => l_src_off,
      blob_csid    => NLS_CHARSET_ID('AL32UTF8'),
      lang_context => l_lang_ctx,
      warning      => l_warning
    );

    ------------------------------------------------------------------
    -- 3) Find first header line (skip XML + blank, require '|')
    ------------------------------------------------------------------
    l_len := DBMS_LOB.getlength(l_clob);

    LOOP
        EXIT WHEN l_pos > l_len;

        l_next := DBMS_LOB.INSTR(l_clob, CHR(10), l_pos);

        IF l_next = 0 THEN
            l_header_line := DBMS_LOB.SUBSTR(l_clob, l_len - l_pos + 1, l_pos);
            l_pos         := l_len + 1;
        ELSE
            l_header_line := DBMS_LOB.SUBSTR(l_clob, l_next - l_pos, l_pos);
            l_pos         := l_next + 1;
        END IF;

        l_header_line := RTRIM(l_header_line, CHR(13));
        l_header_line := TRIM(l_header_line);

        IF l_header_line IS NULL THEN
            CONTINUE;
        END IF;

        IF REGEXP_LIKE(l_header_line, '^\<\?xml', 'i') THEN
            CONTINUE;
        END IF;

        IF INSTR(l_header_line, '|') = 0 THEN
            CONTINUE;
        END IF;

        EXIT;
    END LOOP;

    IF l_header_line IS NULL THEN
        RAISE_APPLICATION_ERROR(-20030, 'No valid header line found in report.');
    END IF;

    l_headers := split_line(l_header_line, '|');

    IF l_headers.COUNT = 0 THEN
        RAISE_APPLICATION_ERROR(-20031, 'Header found but contains zero columns.');
    END IF;

    ------------------------------------------------------------------
    -- 4) Init type info (assume numeric+date, relax by sampling)
    ------------------------------------------------------------------
    l_type_info := t_col_type_tab();

    FOR i IN 1 .. l_headers.COUNT LOOP
        l_type_info.EXTEND;
        l_type_info(i).all_numeric := TRUE;
        l_type_info(i).all_date    := TRUE;
    END LOOP;

    ------------------------------------------------------------------
    -- 5) Sample some data lines to infer numeric/date columns
    ------------------------------------------------------------------
    l_sample_pos   := l_pos;
    l_sample_count := 0;

    WHILE l_sample_count < l_sample_max AND l_sample_pos <= l_len LOOP
        l_next2 := DBMS_LOB.INSTR(l_clob, CHR(10), l_sample_pos);

        IF l_next2 = 0 THEN
            l_tmp_line := DBMS_LOB.SUBSTR(l_clob, l_len - l_sample_pos + 1, l_sample_pos);
            l_sample_pos := l_len + 1;
        ELSE
            l_tmp_line := DBMS_LOB.SUBSTR(l_clob, l_next2 - l_sample_pos, l_sample_pos);
            l_sample_pos := l_next2 + 1;
        END IF;

        l_tmp_line := RTRIM(l_tmp_line, CHR(13));
        l_tmp_line := TRIM(l_tmp_line);

        IF l_tmp_line IS NULL THEN
            CONTINUE;
        END IF;

        l_tmp_cols := split_line(l_tmp_line, '|');

        FOR i IN 1 .. l_headers.COUNT LOOP
            DECLARE
                v VARCHAR2(4000);
            BEGIN
                IF i <= l_tmp_cols.COUNT THEN
                    v := l_tmp_cols(i);
                END IF;

                IF v IS NULL OR TRIM(v) IS NULL THEN
                    NULL;
                ELSE
                    IF NOT is_number(v) THEN
                        l_type_info(i).all_numeric := FALSE;
                    END IF;

                    IF NOT is_date(v) THEN
                        l_type_info(i).all_date := FALSE;
                    END IF;
                END IF;
            END;
        END LOOP;

        l_sample_count := l_sample_count + 1;
    END LOOP;

    ------------------------------------------------------------------
    -- 6) Derive final type per column
    ------------------------------------------------------------------
    l_col_types := t_varchar_tab();

    FOR i IN 1 .. l_headers.COUNT LOOP
        l_col_types.EXTEND;
        IF l_type_info(i).all_numeric THEN
            l_col_types(i) := 'VARCHAR2(4000)'  ;---'NUMBER';
        ELSIF l_type_info(i).all_date THEN
            l_col_types(i) := 'VARCHAR2(4000)';
        ELSE
            l_col_types(i) := 'VARCHAR2(4000)';
        END IF;
    END LOOP;

    ------------------------------------------------------------------
    -- 7) Build sanitized, unique column names
    ------------------------------------------------------------------
    l_name_map.DELETE;
    l_col_names.DELETE;

    FOR i IN 1 .. l_headers.COUNT LOOP
        DECLARE
            l_base  VARCHAR2(400);
            l_final VARCHAR2(400);
            l_cnt   PLS_INTEGER;
        BEGIN
            l_base := sanitize_col_name(l_headers(i));

            IF l_name_map.EXISTS(l_base) THEN
                l_cnt := l_name_map(l_base) + 1;
            ELSE
                l_cnt := 1;
            END IF;

            l_name_map(l_base) := l_cnt;

            IF l_cnt = 1 THEN
                l_final := l_base;
            ELSE
                l_final := SUBSTR(l_base || '_' || l_cnt, 1, 30);
            END IF;

            l_col_names.EXTEND;
            l_col_names(l_col_names.COUNT) := l_final;
        END;
    END LOOP;

    ------------------------------------------------------------------
    -- 8) Derive table name and (re)create based on flag
    ------------------------------------------------------------------
    l_table_name := REGEXP_REPLACE(UPPER(TRIM(p_report_name)), '[^A-Z0-9_]', '_');
    IF REGEXP_LIKE(SUBSTR(l_table_name, 1, 1), '^[0-9]') THEN
        l_table_name := 'R_' || l_table_name;
    END IF;
    l_table_name := 'XXREP_' || SUBSTR(l_table_name, 1, 20);

    p_detail_table_out := l_table_name;

    -- update log with table name
    update_bip_log(p_table_name => l_table_name);

    -- check if table exists
    DECLARE
        l_exists NUMBER;
    BEGIN
        SELECT COUNT(*)
        INTO   l_exists
        FROM   user_tables
        WHERE  table_name = l_table_name;

        IF NVL(UPPER(p_recreate_table_flag), 'Y') = 'Y' THEN
            -- dev mode: drop and recreate
            IF l_exists > 0 THEN
                EXECUTE IMMEDIATE 'DROP TABLE ' || l_table_name || ' PURGE';
            END IF;

            l_create_sql := 'CREATE TABLE ' || l_table_name ||
                            ' (RUN_ID NUMBER, LINE_NO NUMBER';

            FOR i IN 1 .. l_col_names.COUNT LOOP
                l_create_sql := l_create_sql ||
                                ', ' || l_col_names(i) || ' ' || l_col_types(i);
            END LOOP;

            l_create_sql := l_create_sql || ')';

            EXECUTE IMMEDIATE l_create_sql;

        ELSE
            -- prod mode: create only if missing
            IF l_exists = 0 THEN
                l_create_sql := 'CREATE TABLE ' || l_table_name ||
                                ' (RUN_ID NUMBER, LINE_NO NUMBER';

                FOR i IN 1 .. l_col_names.COUNT LOOP
                    l_create_sql := l_create_sql ||
                                    ', ' || l_col_names(i) || ' ' || l_col_types(i);
                END LOOP;

                l_create_sql := l_create_sql || ')';

                EXECUTE IMMEDIATE l_create_sql;
            END IF;
        END IF;
    END;

    ------------------------------------------------------------------
    -- 9) Prepare dynamic INSERT using DBMS_SQL
    ------------------------------------------------------------------
    l_insert_sql := 'INSERT INTO ' || l_table_name || ' (RUN_ID, LINE_NO';

    FOR i IN 1 .. l_col_names.COUNT LOOP
        l_insert_sql := l_insert_sql || ', ' || l_col_names(i);
    END LOOP;

    l_insert_sql := l_insert_sql || ') VALUES (:b1, :b2';

    FOR i IN 1 .. l_col_names.COUNT LOOP
        l_insert_sql := l_insert_sql || ', :b' || (i + 2);
    END LOOP;

    l_insert_sql := l_insert_sql || ')';

    l_cur := DBMS_SQL.open_cursor;
    DBMS_SQL.parse(l_cur, l_insert_sql, DBMS_SQL.native);

    ------------------------------------------------------------------
    -- 10) Loop through remaining lines and insert rows
    ------------------------------------------------------------------
    l_line_no := 1;  -- header is logical line 1

    WHILE l_pos <= l_len LOOP
        l_next := DBMS_LOB.INSTR(l_clob, CHR(10), l_pos);

        IF l_next = 0 THEN
            l_line := DBMS_LOB.SUBSTR(l_clob, l_len - l_pos + 1, l_pos);
            l_pos  := l_len + 1;
        ELSE
            l_line := DBMS_LOB.SUBSTR(l_clob, l_next - l_pos, l_pos);
            l_pos  := l_next + 1;
        END IF;

        l_line := RTRIM(l_line, CHR(13));
        l_line := TRIM(l_line);

        IF l_line IS NOT NULL THEN
            l_line_no := l_line_no + 1;
            l_cols    := split_line(l_line, '|');

            DBMS_SQL.bind_variable(l_cur, ':b1', l_run_id);
            DBMS_SQL.bind_variable(l_cur, ':b2', l_line_no);

            FOR i IN 1 .. l_col_names.COUNT LOOP
                DECLARE
                    v_raw   VARCHAR2(4000);
                    v_num   NUMBER;
                    v_date  DATE;
                BEGIN
                    IF i <= l_cols.COUNT THEN
                        v_raw := l_cols(i);
                    ELSE
                        v_raw := NULL;
                    END IF;

                    IF l_col_types(i) = 'NUMBER' THEN
                        IF v_raw IS NULL OR TRIM(v_raw) IS NULL THEN
                            v_num := NULL;
                        ELSE
                         --   v_num := TO_NUMBER(v_raw);
                          v_num := v_raw;

                        END IF;
                        DBMS_SQL.bind_variable(l_cur, ':b' || (i + 2), v_num);

                    ELSIF l_col_types(i) = 'DATE' THEN
                        v_date := parse_date(v_raw);
                        DBMS_SQL.bind_variable(l_cur, ':b' || (i + 2), v_date);

                    ELSE
                        DBMS_SQL.bind_variable(l_cur, ':b' || (i + 2), v_raw);
                    END IF;
                END;
            END LOOP;

            l_rows := DBMS_SQL.execute(l_cur);
            l_total_rows := l_total_rows + NVL(l_rows,0);
        END IF;
    END LOOP;

    DBMS_SQL.close_cursor(l_cur);
    COMMIT;

    p_rows_inserted_out := l_total_rows;
    l_success_flag      := 'Y';

    ------------------------------------------------------------------
    -- 11) Final log update (success)
    ------------------------------------------------------------------
    update_bip_log(
        p_run_id        => l_run_id,
        p_rows_inserted => l_total_rows,
        p_success_flag  => l_success_flag
    );

 EXCEPTION
    WHEN OTHERS THEN
        DECLARE
            l_err_code NUMBER;
            l_err_msg  VARCHAR2(4000);
        BEGIN
l_err_code := sqlcode;

l_err_msg := substr(sqlerrm, 1, 4000);

BEGIN
    IF dbms_sql.is_open(l_cur) THEN
        dbms_sql.close_cursor(l_cur);
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        NULL;
END;

ROLLBACK;

        -- log error
         -- log error
BEGIN
    update_bip_log(
        p_run_id         => l_run_id,
        p_rows_inserted  => l_total_rows,
        p_success_flag   => 'E',
        p_error_code     => l_err_code,
        p_error_message  => '[FINAL_ERROR] ' || l_err_msg,
        p_append_message => TRUE
    );
EXCEPTION
    WHEN OTHERS THEN
        NULL;
        end;
        RAISE;
        end;
END xx_rods_load_asg_eit_extract_v3_prc;

/
