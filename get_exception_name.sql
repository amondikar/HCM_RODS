--------------------------------------------------------
--  File created - Saturday-February-28-2026   
--------------------------------------------------------
--------------------------------------------------------
--  DDL for Function GET_EXCEPTION_NAME
--------------------------------------------------------

  CREATE OR REPLACE EDITIONABLE FUNCTION "XX_INT"."GET_EXCEPTION_NAME" (p_sqlcode IN NUMBER)
  RETURN VARCHAR2
IS
BEGIN
  CASE p_sqlcode
    -- ---------------------------------------------------------------
    -- All 22 Oracle PL/SQL Predefined Exceptions (STANDARD package)
    -- ---------------------------------------------------------------
    WHEN -6530  THEN RETURN 'ACCESS_INTO_NULL';
        -- Tried to assign a value to an attribute of an uninitialized object
    WHEN -6592  THEN RETURN 'CASE_NOT_FOUND';
        -- None of the WHEN clauses in a CASE matched and no ELSE exists
    WHEN -6531  THEN RETURN 'COLLECTION_IS_NULL';
        -- Tried to call a collection method on an uninitialized collection
    WHEN -6511  THEN RETURN 'CURSOR_ALREADY_OPEN';
        -- Tried to open a cursor that is already open
    WHEN -1     THEN RETURN 'DUP_VAL_ON_INDEX';
        -- Tried to insert a duplicate value into a unique index column
    WHEN -1001  THEN RETURN 'INVALID_CURSOR';
        -- Tried an illegal cursor operation (e.g. close an unopened cursor)
    WHEN -1722  THEN RETURN 'INVALID_NUMBER';
        -- Conversion of a string to a number failed
    WHEN -1017  THEN RETURN 'LOGIN_DENIED';
        -- Invalid username or password
    WHEN  100   THEN RETURN 'NO_DATA_FOUND';
        -- SELECT INTO returned no rows (note: positive 100, not negative)
    WHEN -6548  THEN RETURN 'NO_DATA_NEEDED';
        -- Pipelined function: caller no longer needs rows
    WHEN -1012  THEN RETURN 'NOT_LOGGED_ON';
        -- PL/SQL program issued a DB call without being connected
    WHEN -6501  THEN RETURN 'PROGRAM_ERROR';
        -- Internal PL/SQL error - usually means a bug in PL/SQL itself
    WHEN -6504  THEN RETURN 'ROWTYPE_MISMATCH';
        -- Host cursor variable and PL/SQL cursor variable have incompatible types
    WHEN -30625 THEN RETURN 'SELF_IS_NULL';
        -- Member method invoked but instance of object type is NULL
    WHEN -6500  THEN RETURN 'STORAGE_ERROR';
        -- PL/SQL ran out of memory or memory was corrupted
    WHEN -6533  THEN RETURN 'SUBSCRIPT_BEYOND_COUNT';
        -- Subscript references element beyond end of collection
    WHEN -6532  THEN RETURN 'SUBSCRIPT_OUTSIDE_LIMIT';
        -- Subscript is outside the allowed range (e.g. negative index on VARRAY)
    WHEN -1410  THEN RETURN 'SYS_INVALID_ROWID';
        -- Conversion of a string to ROWID failed - invalid ROWID string
    WHEN -51    THEN RETURN 'TIMEOUT_ON_RESOURCE';
        -- Timed out waiting for a resource in Oracle
    WHEN -1422  THEN RETURN 'TOO_MANY_ROWS';
        -- SELECT INTO returned more than one row
    WHEN -6502  THEN RETURN 'VALUE_ERROR';
        -- Arithmetic, conversion, truncation, or size constraint error
    WHEN -1476  THEN RETURN 'ZERO_DIVIDE';
        -- Attempted to divide a number by zero
    -- ---------------------------------------------------------------
    -- User-defined exceptions (declared without PRAGMA EXCEPTION_INIT)
    -- ---------------------------------------------------------------
    WHEN 1      THEN RETURN 'USER_DEFINED_EXCEPTION';
    -- ---------------------------------------------------------------
    -- Application errors via RAISE_APPLICATION_ERROR (-20000 to -20999)
    -- ---------------------------------------------------------------
    ELSE
      IF p_sqlcode BETWEEN -20999 AND -20000 THEN
        RETURN 'APPLICATION_ERROR (ORA' || TO_CHAR(p_sqlcode) || ')';
      END IF;
      -- All other internally defined ORA- errors with no predefined name
      RETURN 'ORA' || TO_CHAR(p_sqlcode);
  END CASE;
END get_exception_name;

/
