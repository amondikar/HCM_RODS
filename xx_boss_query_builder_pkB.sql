--------------------------------------------------------
--  File created - Saturday-February-28-2026   
--------------------------------------------------------
--------------------------------------------------------
--  DDL for Package Body XX_BOSS_QUERY_BUILDER_PKG
--------------------------------------------------------

  CREATE OR REPLACE EDITIONABLE PACKAGE BODY "XX_INT"."XX_BOSS_QUERY_BUILDER_PKG" AS

  -- ========================================
  -- Parse Query to Columns
  -- ========================================
  PROCEDURE parse_query_to_columns(p_config_name IN VARCHAR2) IS
    
    l_query           CLOB;
    l_limit           NUMBER;
    l_filter          VARCHAR2(4000);
    l_fields_json     CLOB;
    l_accessors_json  CLOB;
    l_is_valid        NUMBER;

  BEGIN

    DBMS_OUTPUT.PUT_LINE('Parsing: ' || p_config_name);

    -- Get existing query
    SELECT advanced_query_template
    INTO l_query
    FROM xx_int_saas_extract_config
    WHERE config_name = p_config_name;

    IF l_query IS NULL THEN
      DBMS_OUTPUT.PUT_LINE('  WARNING: Query is NULL');
      RETURN;
    END IF;

    -- Validate JSON using IS JSON syntax (Oracle 23ai)
    SELECT CASE WHEN l_query IS JSON THEN 1 ELSE 0 END
    INTO l_is_valid
    FROM DUAL;

    IF l_is_valid = 0 THEN
      DBMS_OUTPUT.PUT_LINE('  ERROR: Invalid JSON structure');
      RETURN;
    END IF;

    -- Extract limit
    BEGIN
      SELECT JSON_VALUE(l_query, '$.collection.limit' RETURNING NUMBER)
      INTO l_limit
      FROM DUAL;
    EXCEPTION
      WHEN OTHERS THEN
        l_limit := 1000000;
        DBMS_OUTPUT.PUT_LINE('  WARNING: Could not extract limit');
    END;

    -- Extract filter
    BEGIN
      SELECT JSON_VALUE(l_query, '$.collection.filter')
      INTO l_filter
      FROM DUAL;
    EXCEPTION
      WHEN OTHERS THEN
        l_filter := NULL;
        DBMS_OUTPUT.PUT_LINE('  WARNING: Could not extract filter');
    END;

    -- Extract fields
    BEGIN
      SELECT JSON_QUERY(l_query, '$.fields' RETURNING CLOB)
      INTO l_fields_json
      FROM DUAL;
    EXCEPTION
      WHEN OTHERS THEN
        l_fields_json := NULL;
        DBMS_OUTPUT.PUT_LINE('  WARNING: Could not extract fields');
    END;

    -- Extract accessors
    BEGIN
      SELECT JSON_QUERY(l_query, '$.accessors' RETURNING CLOB)
      INTO l_accessors_json
      FROM DUAL;
    EXCEPTION
      WHEN OTHERS THEN
        l_accessors_json := NULL;
        DBMS_OUTPUT.PUT_LINE('  WARNING: Could not extract accessors');
    END;

    -- Update table
    UPDATE xx_int_saas_extract_config
    SET query_limit = NVL(l_limit, 1000000),
        query_filter = l_filter,
        query_fields_json = l_fields_json,
        query_accessors_json = l_accessors_json,
        auto_build_query = 'Y',
        query_last_built = SYSDATE,
        query_built_by = USER
    WHERE config_name = p_config_name;

    COMMIT;

    DBMS_OUTPUT.PUT_LINE('  SUCCESS');
    DBMS_OUTPUT.PUT_LINE('    Limit: ' || l_limit);
    DBMS_OUTPUT.PUT_LINE('    Filter: ' || SUBSTR(NVL(l_filter, 'NULL'), 1, 50));
    DBMS_OUTPUT.PUT_LINE('    Fields: ' || CASE WHEN l_fields_json IS NOT NULL THEN 'YES (' || LENGTH(l_fields_json) || ')' ELSE 'NO' END);
    DBMS_OUTPUT.PUT_LINE('    Accessors: ' || CASE WHEN l_accessors_json IS NOT NULL THEN 'YES (' || LENGTH(l_accessors_json) || ')' ELSE 'NO' END);

  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('  ERROR: ' || SQLERRM);
      ROLLBACK;
  END parse_query_to_columns;

  -- ========================================
  -- Build Advanced Query
  -- ========================================
  FUNCTION build_advanced_query(p_config_name IN VARCHAR2) RETURN CLOB IS

    l_query           CLOB;
    l_limit           NUMBER;
    l_filter          VARCHAR2(4000);
    l_fields_json     CLOB;
    l_accessors_json  CLOB;
    l_auto_build      VARCHAR2(1);
    l_existing_query  CLOB;
    l_is_valid        NUMBER;
    l_json_obj        JSON_OBJECT_T;  -- used for validation
l_json_test CLOB;
v_backtrace  VARCHAR2(4000);
  BEGIN

    -- Get configuration
    SELECT 
      query_limit,
      query_filter,
      query_fields_json,
      query_accessors_json,
      auto_build_query,
      advanced_query_template
    INTO
      l_limit,
      l_filter,
      l_fields_json,
      l_accessors_json,
      l_auto_build,
      l_existing_query
    FROM xx_int_saas_extract_config
    WHERE config_name = p_config_name;

    -- If auto_build is N, return existing
    IF l_auto_build = 'N' THEN
      RETURN l_existing_query;
    END IF;

    -- Build JSON
    l_query := '{';
    l_query := l_query || '"collection":{';
    l_query := l_query || '"limit":' || l_limit;

    IF l_filter IS NOT NULL THEN
      l_query := l_query || ',"filter":"' || l_filter || '"';
    END IF;

    l_query := l_query || '}';

    IF l_fields_json IS NOT NULL THEN
      l_query := l_query || ',"fields":' || l_fields_json;
    END IF;

    IF l_accessors_json IS NOT NULL THEN
      l_query := l_query || ',"accessors":' || l_accessors_json;
    END IF;

    l_query := l_query || '}';
l_json_test := REPLACE(l_query, '''{{EFFECTIVE_DATE}}''', '''2024-01-01''');
 BEGIN
    l_json_obj := JSON_OBJECT_T.PARSE(l_json_test);
    l_is_valid := 1;
     v_backtrace := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE;

      log_error(
        p_program_unit => UTL_CALL_STACK.CONCATENATE_SUBPROGRAM(
                            UTL_CALL_STACK.SUBPROGRAM(1)),
        p_line_number  => $$PLSQL_LINE,
        p_sqlcode      => SQLCODE,
        p_sqlerrm      => SQLERRM,
        p_backtrace    => v_backtrace
      );
  DBMS_OUTPUT.PUT_LINE('=== VALID ==='||p_config_name);
EXCEPTION
    WHEN OTHERS THEN
        l_is_valid := 0;
        
      v_backtrace := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE;

      log_error(
        p_program_unit => UTL_CALL_STACK.CONCATENATE_SUBPROGRAM(
                            UTL_CALL_STACK.SUBPROGRAM(1)),
        p_line_number  => $$PLSQL_LINE,
        p_sqlcode      => SQLCODE,
        p_sqlerrm      => SQLERRM,
        p_backtrace    => v_backtrace
      );
   
        DBMS_OUTPUT.PUT_LINE('=== INVALID ==='||p_config_name);
     --   DBMS_OUTPUT.PUT_LINE('SQLCODE  : ' || SQLCODE);
     --   DBMS_OUTPUT.PUT_LINE('SQLERRM  : ' || SQLERRM);
END;

    -- Update table
    UPDATE xx_int_saas_extract_config
    SET advanced_query_template = l_query,
        query_last_built = SYSDATE,
        query_built_by = USER
    WHERE config_name = p_config_name;
    v_backtrace := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE;

      log_error(
        p_program_unit => UTL_CALL_STACK.CONCATENATE_SUBPROGRAM(
                            UTL_CALL_STACK.SUBPROGRAM(1)),
        p_line_number  => $$PLSQL_LINE,
        p_sqlcode      => SQLCODE,
        p_sqlerrm      => SQLERRM,
        p_backtrace    => v_backtrace
      );
    COMMIT;

    RETURN l_query;

  END build_advanced_query;

  -- ========================================
  -- Rebuild All
  -- ========================================
  PROCEDURE rebuild_all_queries(p_instance_code IN VARCHAR2 DEFAULT 'DEV1') IS
    l_count NUMBER := 0;
    l_success NUMBER := 0;
    l_error NUMBER := 0;
  BEGIN

    DBMS_OUTPUT.PUT_LINE('Rebuilding all queries...');

    FOR rec IN (
      SELECT config_name
      FROM xx_int_saas_extract_config
      WHERE instance_code = p_instance_code
      AND auto_build_query = 'Y'
      ORDER BY config_name
    ) LOOP

      l_count := l_count + 1;

      BEGIN
        DECLARE
          l_result CLOB;
        BEGIN
          l_result := build_advanced_query(rec.config_name);
          l_success := l_success + 1;
        END;
      EXCEPTION
        WHEN OTHERS THEN
          l_error := l_error + 1;
          DBMS_OUTPUT.PUT_LINE('ERROR ' || rec.config_name || ': ' || SQLERRM);
      END;

    END LOOP;

    DBMS_OUTPUT.PUT_LINE('Total: ' || l_count || ' | Success: ' || l_success || ' | Errors: ' || l_error);

  END rebuild_all_queries;

END xx_boss_query_builder_pkg;

/
