--------------------------------------------------------
--  File created - Saturday-February-28-2026   
--------------------------------------------------------
--------------------------------------------------------
--  DDL for Procedure LOG_ERROR
--------------------------------------------------------
set define off;

  CREATE OR REPLACE EDITIONABLE PROCEDURE "XX_INT"."LOG_ERROR" (
  p_program_unit  IN VARCHAR2,
  p_line_number   IN NUMBER     DEFAULT NULL,
  p_sqlcode       IN NUMBER     DEFAULT SQLCODE,
  p_sqlerrm       IN VARCHAR2   DEFAULT SQLERRM,
  p_backtrace     IN VARCHAR2   DEFAULT NULL
)
IS
  -- AUTONOMOUS_TRANSACTION: this procedure's COMMIT is independent of caller
  PRAGMA AUTONOMOUS_TRANSACTION;

  -- Session variables
  v_username      VARCHAR2(100);
  v_os_user       VARCHAR2(100);
  v_machine       VARCHAR2(100);
  v_program       VARCHAR2(100);
  v_sid           NUMBER;

  -- Failed SQL variables
  v_failed_sql    CLOB;
  v_obj_name      VARCHAR2(200);
  v_error_line    NUMBER;

BEGIN

  -- ---------------------------------------------------------------
  -- Get session information from V$SESSION
  -- SYS_CONTEXT('USERENV','SESSIONID') = AUDSID, uniquely identifies
  -- the current session without needing to know your own SID first
  -- ---------------------------------------------------------------
  BEGIN
    SELECT s.username,
           s.osuser,
           s.machine,
           s.program,
           s.sid
    INTO   v_username,
           v_os_user,
           v_machine,
           v_program,
           v_sid
    FROM   v$session s
    WHERE  s.audsid = SYS_CONTEXT('USERENV', 'SESSIONID');
  EXCEPTION
    WHEN OTHERS THEN
      -- Fallback if V$SESSION grant is missing
      v_username := SYS_CONTEXT('USERENV', 'SESSION_USER');
      v_os_user  := SYS_CONTEXT('USERENV', 'OS_USER');
      v_machine  := SYS_CONTEXT('USERENV', 'HOST');
      v_program  := NULL;
      v_sid      := NULL;
  END;

  -- ---------------------------------------------------------------
  -- Parse backtrace to extract failing object name and line number
  --
  -- Backtrace example string:
  --   ORA-06512: at "MY_SCHEMA.EXAMPLE_PKG", line 42
  --   ORA-06512: at "MY_SCHEMA.EXAMPLE_PKG", line 18
  --
  -- We take the FIRST occurrence (innermost = actual failing line)
  -- REGEXP_SUBSTR group 1 extracts content inside first double quotes
  -- REGEXP_SUBSTR group 1 on 'line\s+(\d+)' extracts the line number
  -- ---------------------------------------------------------------
  BEGIN

    -- Extract full object name e.g. MY_SCHEMA.EXAMPLE_PKG
    v_obj_name := REGEXP_SUBSTR(
                    p_backtrace,
                    '"([^"]+)"',  -- match content inside first "..."
                    1,            -- start position
                    1,            -- first occurrence
                    NULL,         -- no flags
                    1             -- return capture group 1
                  );

    -- Extract the line number after first "line " keyword
    v_error_line := TO_NUMBER(
                      REGEXP_SUBSTR(
                        p_backtrace,
                        'line\s+(\d+)',  -- match digits after "line "
                        1,
                        1,
                        'i',            -- case insensitive
                        1               -- return capture group 1
                      )
                    );

    -- Strip schema prefix if present (USER_SOURCE uses object name only)
    -- e.g. MY_SCHEMA.EXAMPLE_PKG -> EXAMPLE_PKG
    IF INSTR(v_obj_name, '.') > 0 THEN
      v_obj_name := SUBSTR(v_obj_name, INSTR(v_obj_name, '.') + 1);
    END IF;

    -- ---------------------------------------------------------------
    -- Look up source lines from USER_SOURCE
    -- Retrieves 2 lines before + failing line + 2 lines after
    -- This gives full context of the failing SQL/PL/SQL statement
    --
    -- Example output stored in failed_sql:
    --   40:     BEGIN
    --   41:       SELECT first_name || ' ' || last_name
    --   42:       INTO   v_name
    --  *43:       FROM   employees         <-- error on this line
    --   44:       WHERE  employee_id = p_emp_id;
    --   45:     EXCEPTION
    -- ---------------------------------------------------------------
    SELECT LISTAGG(
             CASE
               WHEN line = v_error_line
               THEN '*' || TO_CHAR(line,'FM99999') || ': ' || RTRIM(text, CHR(10))
               ELSE ' ' || TO_CHAR(line,'FM99999') || ': ' || RTRIM(text, CHR(10))
             END,
             CHR(10)
           ) WITHIN GROUP (ORDER BY line)
    INTO   v_failed_sql
    FROM   user_source
    WHERE  name = v_obj_name
    AND    line BETWEEN (v_error_line - 2) AND (v_error_line + 2);

  EXCEPTION
    WHEN OTHERS THEN
      -- Backtrace may be null or unparseable (e.g. anonymous block)
      -- In that case just store a note - the backtrace column has full details
      v_failed_sql := '[Unable to extract source - see error_backtrace column. '
                   || 'Object: ' || NVL(v_obj_name, 'UNKNOWN')
                   || ', Line: ' || NVL(TO_CHAR(v_error_line), 'UNKNOWN') || ']';
  END;

  -- ---------------------------------------------------------------
  -- INSERT the error log record
  -- ---------------------------------------------------------------
  INSERT INTO error_log (
    log_id,
    log_timestamp,
    username,
    os_user,
    machine,
    program,
    session_id,
    program_unit,
    line_number,
    exception_name,
    error_code,
    error_message,
    failed_sql,
    call_stack,
    error_backtrace
  ) VALUES (
    error_log_seq.NEXTVAL,
    SYSTIMESTAMP,
    v_username,
    v_os_user,
    v_machine,
    v_program,
    v_sid,
    p_program_unit,
    p_line_number,
    get_exception_name(p_sqlcode),
    p_sqlcode,
    SUBSTR(p_sqlerrm, 1, 4000),
    v_failed_sql,
    DBMS_UTILITY.FORMAT_CALL_STACK,    -- call stack at moment of logging
    p_backtrace                        -- backtrace passed in from caller
  );

  -- COMMIT is mandatory for AUTONOMOUS_TRANSACTION to persist the row
  COMMIT;

EXCEPTION
  WHEN OTHERS THEN
    -- If the logger itself fails, rollback and do not re-raise
    -- so the original exception propagation is never disrupted
    ROLLBACK;
END log_error;

/
