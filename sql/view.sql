SET HEA ON LIN 500 PAGES 100 TAB OFF FEED OFF ECHO OFF VER OFF TRIMS ON TRIM ON TI OFF TIMI OFF;
SET LONG 32000 LONGC 160
SELECT text
  FROM dba_views
 WHERE view_name = UPPER('&view_name.')
/
