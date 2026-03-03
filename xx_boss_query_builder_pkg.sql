--------------------------------------------------------
--  File created - Saturday-February-28-2026   
--------------------------------------------------------
--------------------------------------------------------
--  DDL for Package XX_BOSS_QUERY_BUILDER_PKG
--------------------------------------------------------

  CREATE OR REPLACE EDITIONABLE PACKAGE "XX_INT"."XX_BOSS_QUERY_BUILDER_PKG" AS
  
  FUNCTION build_advanced_query(p_config_name IN VARCHAR2) RETURN CLOB;
  PROCEDURE parse_query_to_columns(p_config_name IN VARCHAR2);
  PROCEDURE rebuild_all_queries(p_instance_code IN VARCHAR2 DEFAULT 'DEV1');

END xx_boss_query_builder_pkg;

/
