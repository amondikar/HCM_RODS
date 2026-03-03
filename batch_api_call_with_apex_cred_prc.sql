--------------------------------------------------------
--  File created - Saturday-February-28-2026   
--------------------------------------------------------
--------------------------------------------------------
--  DDL for Procedure BATCH_API_CALL_WITH_APEX_CRED
--------------------------------------------------------
set define off;

  CREATE OR REPLACE EDITIONABLE PROCEDURE "XX_INT"."BATCH_API_CALL_WITH_APEX_CRED" 
AS
    c_app_id    CONSTANT NUMBER        := 100;
    c_page_id   CONSTANT NUMBER        := 1;
    c_username  CONSTANT VARCHAR2(50)  := 'AZ405';
    c_cred_id   CONSTANT VARCHAR2(100) := 'SPECTRA_BOSS_CRED'; -- from apex_workspace_credentials
    c_api_url   CONSTANT VARCHAR2(500) := 'https://external-api.example.com/api/resource';

    l_response  CLOB;

BEGIN
    -- 1. Set workspace context
    APEX_UTIL.SET_WORKSPACE(
        p_workspace => 'YOUR_WORKSPACE_NAME'
    );

    -- 2. Create APEX session
    APEX_SESSION.CREATE_SESSION(
        p_app_id   => c_app_id,
        p_page_id  => c_page_id,
        p_username => c_username
    );

    -- 3. Let APEX_WEB_SERVICE handle the credential + token automatically
    --    No need to extract the token manually at all
    l_response := APEX_WEB_SERVICE.MAKE_REST_REQUEST(
                      p_url                   => c_api_url,
                      p_http_method           => 'GET',
                      p_credential_static_id  => c_cred_id
                  );

    -- 4. Check HTTP status
    IF APEX_WEB_SERVICE.G_STATUS_CODE != 200 THEN
        RAISE_APPLICATION_ERROR(-20001,
            'API call failed. HTTP Status: ' || APEX_WEB_SERVICE.G_STATUS_CODE);
    END IF;

    DBMS_OUTPUT.PUT_LINE('Response: ' || SUBSTR(l_response, 1, 500));

    -- 5. Clean up session
    APEX_SESSION.DELETE_SESSION(
        p_session_id => APEX_APPLICATION.G_INSTANCE
    );

EXCEPTION
    WHEN OTHERS THEN
        BEGIN
            APEX_SESSION.DELETE_SESSION(
                p_session_id => APEX_APPLICATION.G_INSTANCE
            );
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
        RAISE;
END batch_api_call_with_apex_cred;

/
