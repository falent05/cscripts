----------------------------------------------------------------------------------------
--
-- File name:   top_sql_chart_one.sql
--
--              *** Requires Oracle Diagnostics Pack License ***
--
-- Purpose:     Charts top SQL (as per a computed metric) for given time range
--
-- Author:      Carlos Sierra
--
-- Version:     2018/04/08
--
-- Usage:       Execute connected into the CDB or PDB of interest.
--
--              Enter range of AWR snapshot (optional), and metric of interest (optional)
--              Dafaults to last AWR snapshot and to elapsed_time_delta (DB time)
--
-- Example:     $ sqlplus / as sysdba
--              SQL> @top_sql_chart_one.sql
--
-- Notes:       Accesses AWR data thus you must have an Oracle Diagnostics Pack License.
--
--              Developed and tested on 12.1.0.2.
--
--              To further dive into SQL performance diagnostics use SQLd360.
--             
--              *** Requires Oracle Diagnostics Pack License ***
--
---------------------------------------------------------------------------------------
--
-- exit graciously if executed on standby
WHENEVER SQLERROR EXIT SUCCESS;
DECLARE
  l_open_mode VARCHAR2(20);
BEGIN
  SELECT open_mode INTO l_open_mode FROM v$database;
  IF l_open_mode <> 'READ WRITE' THEN
    raise_application_error(-20000, 'Must execute on PRIMARY');
  END IF;
END;
/
WHENEVER SQLERROR CONTINUE;
--
-- exit graciously if executed from CDB$ROOT
--WHENEVER SQLERROR EXIT SUCCESS;
BEGIN
  IF SYS_CONTEXT('USERENV', 'CON_NAME') = 'CDB$ROOT' THEN
    raise_application_error(-20000, 'Be aware! You are executing this script connected into CDB$ROOT.');
  END IF;
END;
/
WHENEVER SQLERROR CONTINUE;

DEF top_n = '12';
DEF default_window_hours = '24';
DEF default_awr_days = '30';
DEF date_format = 'YYYY-MM-DD"T"HH24:MI:SS';

SET HEA ON LIN 1000 PAGES 100 TAB OFF FEED OFF ECHO OFF VER OFF TRIMS ON TRIM ON TI OFF TIMI OFF;

COL dbid NEW_V dbid NOPRI;
COL db_name NEW_V db_name NOPRI;
SELECT dbid, LOWER(name) db_name FROM v$database
/

COL instance_number NEW_V instance_number NOPRI;
COL host_name NEW_V host_name NOPRI;
SELECT instance_number, LOWER(host_name) host_name FROM v$instance
/

COL con_name NEW_V con_name NOPRI;
SELECT SYS_CONTEXT('USERENV', 'CON_NAME') con_name FROM DUAL
/

COL con_id NEW_V con_id NOPRI;
SELECT SYS_CONTEXT('USERENV', 'CON_ID') con_id FROM DUAL
/

PRO
PRO How many days back in AWR history we want to display in chart.
PRO Due to performance impact, please be conservative.
PRO Default value is usually right.
PRO
PRO 1. Display AWR Days: [{&&default_awr_days.}|1-60]
DEF display_awr_days = '&1.';

COL display_awr_days NEW_V display_awr_days NOPRI;
SELECT NVL('&&display_awr_days.', '&&default_awr_days.') display_awr_days FROM DUAL
/

COL oldest_snap_id NEW_V oldest_snap_id NOPRI;
SELECT MAX(snap_id) oldest_snap_id 
  FROM dba_hist_snapshot
 WHERE dbid = &&dbid.
   AND instance_number = &&instance_number.
   AND end_interval_time < SYSDATE - &&display_awr_days.
/

SELECT snap_id, 
       TO_CHAR(begin_interval_time, '&&date_format.') begin_time, 
       TO_CHAR(end_interval_time, '&&date_format.') end_time
  FROM dba_hist_snapshot
 WHERE dbid = &&dbid.
   AND instance_number = &&instance_number.
   AND snap_id >= &&oldest_snap_id.
 ORDER BY
       snap_id
/

COL snap_id_max_default NEW_V snap_id_max_default NOPRI;
SELECT TO_CHAR(NVL(TO_NUMBER(''), MAX(snap_id))) snap_id_max_default 
  FROM dba_hist_snapshot
 WHERE dbid = &&dbid.
   AND instance_number = &&instance_number.
/

COL snap_id_min_default NEW_V snap_id_min_default NOPRI;
SELECT TO_CHAR(NVL(TO_NUMBER(''), MAX(snap_id))) snap_id_min_default 
  FROM dba_hist_snapshot
 WHERE dbid = &&dbid.
   AND instance_number = &&instance_number.
   AND ( CASE 
         WHEN '' IS NULL 
         THEN ( CASE 
                WHEN begin_interval_time < (SYSDATE - (TO_NUMBER(NVL('&&default_window_hours.', '0'))/24))
                THEN 1 
                ELSE 0 
                END
              ) 
         ELSE 1 
         END
       ) = 1
/

PRO
PRO Chart extends for &&display_awr_days. days. 
PRO Range of snaps below are to define lower and upper bounds to compute TOP SQL.
PRO
PRO Enter range of snaps to evaluate TOP SQL.
PRO
PRO 2. SNAP_ID FROM: [{&&snap_id_min_default.}|snap_id]
DEF snap_id_from = '&2.';
PRO
PRO 3. SNAP_ID TO: [{&&snap_id_max_default.}|snap_id]
DEF snap_id_to = '&3.';

COL snap_id_max NEW_V snap_id_max NOPRI;
SELECT TO_CHAR(NVL(TO_NUMBER('&&snap_id_to.'), MAX(snap_id))) snap_id_max 
  FROM dba_hist_snapshot
 WHERE dbid = &&dbid.
   AND instance_number = &&instance_number.
/

COL snap_id_min NEW_V snap_id_min NOPRI;
SELECT TO_CHAR(NVL(TO_NUMBER('&&snap_id_from.'), MAX(snap_id))) snap_id_min 
  FROM dba_hist_snapshot
 WHERE dbid = &&dbid.
   AND instance_number = &&instance_number.
   AND ( CASE 
         WHEN '&&snap_id_from.' IS NULL 
         THEN ( CASE 
                WHEN begin_interval_time < (SYSDATE - (TO_NUMBER(NVL('&&default_window_hours.', '0'))/24))
                THEN 1 
                ELSE 0 
                END
              ) 
         ELSE 1 
         END
       ) = 1
/

COL begin_interval_time NEW_V begin_interval_time NOPRI;
SELECT TO_CHAR(begin_interval_time, '&&date_format.') begin_interval_time
  FROM dba_hist_snapshot
 WHERE dbid = &&dbid.
   AND instance_number = &&instance_number.
   AND snap_id = &&snap_id_min.
/

COL end_interval_time NEW_V end_interval_time NOPRI;
SELECT TO_CHAR(end_interval_time, '&&date_format.') end_interval_time
  FROM dba_hist_snapshot
 WHERE dbid = &&dbid.
   AND instance_number = &&instance_number.
   AND snap_id = &&snap_id_max.
/

PRO
PRO Top SQL is computed for selected metric within range of snaphots.
PRO
PRO Computed Metric
PRO ~~~~~~~~~~~~~~~
PRO db_time_exec        : Latency   - Database Time per Exec - (MS)
PRO cpu_time_exec       : Latency   - CPU Time per Exec - (MS)
PRO io_time_exec        : Latency   - IO Wait Time per Exec - (MS)
PRO appl_time_exec      : Latency   - Application Wait Time per Exec - (MS)
PRO conc_time_exec      : Latency   - Concurrency Wait Time per Exec - (MS)
PRO db_time_aas         : DB Time   - Elapsed Time - (AAS)
PRO cpu_time_aas        : DB Time   - CPU Time - (AAS)
PRO io_time_aas         : DB Time   - IO Wait Time - (AAS)
PRO appl_time_aas       : DB Time   - Application Wait Time - (AAS)
PRO conc_time_aas       : DB Time   - Concurrency Wait Time - (AAS)
PRO parses_sec          : Calls     - Parses per Second - Calls
PRO executions_sec      : Calls     - Execs per Second - Calls
PRO fetches_sec         : Calls     - Fetches per Second - Calls
PRO rows_processed_sec  : Resources - Rows Processed per Second - Count
PRO buffer_gets_sec     : Resources - Buffer Gets    per Second - Count
PRO disk_reads_sec      : Resources - Disk Reads     per Second - Count
PRO rows_processed_exec : Resources - Rows Processed per Exec - Count
PRO buffer_gets_exec    : Resources - Buffer Gets    per Exec - Count
PRO disk_reads_exec     : Resources - Disk Reads     per Exec - Count
PRO loads               : Cursors   - Loads - Count
PRO invalidations       : Cursors   - Invalidations - Count
PRO version_count       : Cursors   - Versions - Count
PRO sharable_mem_mb     : Cursors   - Sharable Memory - (MBs)
PRO
PRO 4. Computed Metric: [{db_time_exec}|<computed_metric>]
DEF computed_metric = '&4.';

COL computed_metric NEW_V computed_metric NOPRI;
SELECT LOWER(NVL('&&computed_metric.', 'db_time_exec')) computed_metric FROM DUAL
/

COL metric_display NEW_V metric_display NOPRI;
SELECT CASE LOWER(TRIM('&&computed_metric.'))
       WHEN 'db_time_exec' THEN 'Database Time per Execution'
       WHEN 'db_time_aas' THEN 'Database Time'
       WHEN 'cpu_time_exec' THEN 'CPU Time per Execution'
       WHEN 'cpu_time_aas' THEN 'CPU Time'
       WHEN 'io_time_exec' THEN 'IO Wait Time per Execution'
       WHEN 'io_time_aas' THEN 'IO Wait Time'
       WHEN 'appl_time_exec' THEN 'Application Wait Time per Execution'
       WHEN 'appl_time_aas' THEN 'Application Wait Time'
       WHEN 'conc_time_exec' THEN 'Concurrency Wait Time per Execution'
       WHEN 'conc_time_aas' THEN 'Concurrency Wait Time'
       WHEN 'parses_sec' THEN 'Parses per Second'
       WHEN 'executions_sec' THEN 'Executions per Second'
       WHEN 'fetches_sec' THEN 'Fetches per Second'
       WHEN 'loads' THEN 'Loads'
       WHEN 'invalidations' THEN 'Invalidations'
       WHEN 'version_count' THEN 'Versions'
       WHEN 'sharable_mem_mb' THEN 'Sharable Memory'
       WHEN 'rows_processed_sec' THEN 'Rows Processed per Second'
       WHEN 'rows_processed_exec' THEN 'Rows Processed per Execution'
       WHEN 'buffer_gets_sec' THEN 'Buffer Gets per Second'
       WHEN 'buffer_gets_exec' THEN 'Buffer Gets per Execution'
       WHEN 'disk_reads_sec' THEN 'Disk Reads per Second'
       WHEN 'disk_reads_exec' THEN 'Disk Reads per Execution'
       ELSE 'Database Time per Execution'
       END metric_display
  FROM DUAL
/

PRO
PRO Filtering SQL to reduce search space.
PRO Ignore this parameter when executed on a non-KIEV database.
PRO
PRO 5. KIEV Transaction: [{CBSGU}|C|B|S|G|U|CB|SG] (C=CommitTx B=BeginTx S=Scan G=GC U=Unknown)
DEF kiev_tx = '&5.';

COL kiev_tx NEW_V kiev_tx NOPRI;
SELECT NVL('&&kiev_tx.', 'CBSGU') kiev_tx FROM DUAL
/

PRO
PRO Filtering SQL to reduce search space.
PRO Ignore this parameter when executed on a non-KIEV database.
PRO
PRO 6. KIEV Bucket (optional):
DEF kiev_bucket = '&6.';

COL locale NEW_V locale NOPRI;
SELECT LOWER(REPLACE(SUBSTR('&&host_name.', 1 + INSTR('&&host_name.', '.', 1, 2), 30), '.', '_')) locale FROM DUAL
/

COL output_file_name NEW_V output_file_name NOPRI;
SELECT 'top_sql_&&locale._&&db_name._'||REPLACE('&&con_name.','$')||'_&&snap_id_min._&&snap_id_max._&&computed_metric.' output_file_name FROM DUAL
/

DEF report_abstract_1 = "LOCALE: &&locale.";
DEF report_abstract_2 = "<br>DATABASE: &&db_name.";
DEF report_abstract_3 = "<br>PDB: &&con_name.";
DEF report_abstract_4 = "<br>HOST: &&host_name.";
DEF report_abstract_5 = "<br>KIEV Transaction: &&kiev_tx.";
DEF report_abstract_6 = "<br>KIEV Bucket: &&kiev_bucket.";
DEF chart_title = "Top SQL according to &&metric_display. between &&begin_interval_time.(&&snap_id_min.) and &&end_interval_time.(&&snap_id_max.) UTC";
DEF xaxis_title = "&&metric_display. (&&computed_metric.)";
DEF vaxis_title = "vaxis_title";
COL vaxis_title NEW_V vaxis_title NOPRI;
SELECT CASE LOWER(TRIM('&&computed_metric.'))
       WHEN 'db_time_exec' THEN 'Milliseconds (MS)'
       WHEN 'db_time_aas' THEN 'Average Active Sessions (AAS)'
       WHEN 'cpu_time_exec' THEN 'Milliseconds (MS)'
       WHEN 'cpu_time_aas' THEN 'Average Active Sessions (AAS)'
       WHEN 'io_time_exec' THEN 'Milliseconds (MS)'
       WHEN 'io_time_aas' THEN 'Average Active Sessions (AAS)'
       WHEN 'appl_time_exec' THEN 'Milliseconds (MS)'
       WHEN 'appl_time_aas' THEN 'Average Active Sessions (AAS)'
       WHEN 'conc_time_exec' THEN 'Milliseconds (MS)'
       WHEN 'conc_time_aas' THEN 'Average Active Sessions (AAS)'
       WHEN 'parses_sec' THEN 'Parse Calls'
       WHEN 'executions_sec' THEN 'Execution Calls'
       WHEN 'fetches_sec' THEN 'Fetch Calls'
       WHEN 'loads' THEN 'Loads'
       WHEN 'invalidations' THEN 'Invalidations'
       WHEN 'version_count' THEN 'Version Count'
       WHEN 'sharable_mem_mb' THEN 'Sharable Memory (MBs)'
       WHEN 'rows_processed_sec' THEN 'Rows Processed'
       WHEN 'rows_processed_exec' THEN 'Rows Processed'
       WHEN 'buffer_gets_sec' THEN 'Buffer Gets'
       WHEN 'buffer_gets_exec' THEN 'Buffer Gets'
       WHEN 'disk_reads_sec' THEN 'Disk Reads'
       WHEN 'disk_reads_exec' THEN 'Disk Reads'
       ELSE 'Milliseconds (MS)'
       END vaxis_title
  FROM DUAL
/
DEF vaxis_baseline = "";;
DEF report_title = "Top SQL according to &&metric_display.<br>between &&begin_interval_time.(&&snap_id_min.) and &&end_interval_time.(&&snap_id_max.) UTC";
DEF chart_foot_note_1 = "<br>1) Drag to Zoom, and right click to reset Chart.";
DEF chart_foot_note_2 = "<br>2) Expect lower values than OEM Top Activity since only a subset of SQL is captured into dba_hist_sqlstat.";
DEF chart_foot_note_3 = "<br>3) PL/SQL executions are excluded since they distort charts.";
DEF chart_foot_note_4 = "";
DEF report_foot_note = "&&output_file_name..html based on dba_hist_sqlstat";
PRO
ALTER SESSION SET STATISTICS_LEVEL = 'ALL';

SPO &&output_file_name..html;
PRO <html>
PRO <!-- $Header: line_chart.sql 2018-04-08 carlos.sierra $ -->
PRO <head>
PRO <title>&&output_file_name..html</title>
PRO
PRO <style type="text/css">
PRO body             {font:10pt Arial,Helvetica,Geneva,sans-serif; color:black; background:white;}
PRO h1               {font-size:16pt; font-weight:bold; color:#336699; border-bottom:1px solid #336699; margin-top:0pt; margin-bottom:0pt; padding:0px 0px 0px 0px;}
PRO h2               {font-size:14pt; font-weight:bold; color:#336699; margin-top:4pt; margin-bottom:0pt;}
PRO h3               {font-size:12pt; font-weight:bold; color:#336699; margin-top:4pt; margin-bottom:0pt;}
PRO pre              {font:8pt monospace,Monaco,"Courier New",Courier;}
PRO a                {color:#663300;}
PRO table            {font-size:8pt; border-collapse:collapse; empty-cells:show; white-space:nowrap; border:1px solid #336699;}
PRO li               {font-size:8pt; color:black; padding-left:4px; padding-right:4px; padding-bottom:2px;}
PRO th               {font-weight:bold; color:white; background:#0066CC; padding-left:4px; padding-right:4px; padding-bottom:2px;}
PRO tr               {color:black; background:white;}
PRO tr:hover         {color:white; background:#0066CC;}
PRO tr.main          {color:black; background:white;}
PRO tr.main:hover    {color:black; background:white;}
PRO td               {vertical-align:top; border:1px solid #336699;}
PRO td.c             {text-align:center;}
PRO font.n           {font-size:8pt; font-style:italic; color:#336699;}
PRO font.f           {font-size:8pt; color:#999999; border-top:1px solid #336699; margin-top:30pt;}
PRO div.google-chart {width:809px; height:500px;}
PRO </style>
PRO
PRO <script type="text/javascript" src="https://www.google.com/jsapi"></script>
PRO <script type="text/javascript">
PRO google.load("visualization", "1", {packages:["corechart"]})
PRO google.setOnLoadCallback(drawChart)
PRO
PRO function drawChart() {
PRO var data = google.visualization.arrayToDataTable([
PRO [
PRO 'Date Column'
PRO ,'all others'
PRO // please wait... getting &&metric_display....

SET HEA OFF PAGES 0;
/****************************************************************************************/
WITH 
  FUNCTION application_category (p_sql_text IN VARCHAR2)
  RETURN VARCHAR2
  IS
    gk_appl_cat_1                  CONSTANT VARCHAR2(10) := 'BeginTx'; -- 1st application category
    gk_appl_cat_2                  CONSTANT VARCHAR2(10) := 'CommitTx'; -- 2nd application category
    gk_appl_cat_3                  CONSTANT VARCHAR2(10) := 'Scan'; -- 3rd application category
    gk_appl_cat_4                  CONSTANT VARCHAR2(10) := 'GC'; -- 4th application category
    k_appl_handle_prefix           CONSTANT VARCHAR2(30) := '/*'||CHR(37);
    k_appl_handle_suffix           CONSTANT VARCHAR2(30) := CHR(37)||'*/'||CHR(37);
  BEGIN
    IF   p_sql_text LIKE k_appl_handle_prefix||'addTransactionRow'||k_appl_handle_suffix 
      OR p_sql_text LIKE k_appl_handle_prefix||'checkStartRowValid'||k_appl_handle_suffix 
    THEN RETURN gk_appl_cat_1;
    ELSIF p_sql_text LIKE k_appl_handle_prefix||'SPM:CP'||k_appl_handle_suffix 
      OR  p_sql_text LIKE k_appl_handle_prefix||'findMatchingRow'||k_appl_handle_suffix 
      OR  p_sql_text LIKE k_appl_handle_prefix||'readTransactionsSince'||k_appl_handle_suffix 
      OR  p_sql_text LIKE k_appl_handle_prefix||'writeTransactionKeys'||k_appl_handle_suffix 
      OR  p_sql_text LIKE k_appl_handle_prefix||'setValueByUpdate'||k_appl_handle_suffix 
      OR  p_sql_text LIKE k_appl_handle_prefix||'setValue'||k_appl_handle_suffix 
      OR  p_sql_text LIKE k_appl_handle_prefix||'deleteValue'||k_appl_handle_suffix 
      OR  p_sql_text LIKE k_appl_handle_prefix||'exists'||k_appl_handle_suffix 
      OR  p_sql_text LIKE k_appl_handle_prefix||'existsUnique'||k_appl_handle_suffix 
      OR  p_sql_text LIKE k_appl_handle_prefix||'updateIdentityValue'||k_appl_handle_suffix 
      OR  p_sql_text LIKE 'LOCK TABLE'||CHR(37) 
      OR  p_sql_text LIKE '/* null */ LOCK TABLE'||CHR(37)
      OR  p_sql_text LIKE k_appl_handle_prefix||'getTransactionProgress'||k_appl_handle_suffix 
      OR  p_sql_text LIKE k_appl_handle_prefix||'recordTransactionState'||k_appl_handle_suffix 
      OR  p_sql_text LIKE k_appl_handle_prefix||'checkEndRowValid'||k_appl_handle_suffix
      OR  p_sql_text LIKE k_appl_handle_prefix||'getMaxTransactionCommitID'||k_appl_handle_suffix 
    THEN RETURN gk_appl_cat_2;
    ELSIF p_sql_text LIKE k_appl_handle_prefix||'getValues'||k_appl_handle_suffix 
      OR  p_sql_text LIKE k_appl_handle_prefix||'getNextIdentityValue'||k_appl_handle_suffix 
      OR  p_sql_text LIKE k_appl_handle_prefix||'performScanQuery'||k_appl_handle_suffix
      OR  p_sql_text LIKE k_appl_handle_prefix||'performSnapshotScanQuery'||k_appl_handle_suffix 
      OR  p_sql_text LIKE k_appl_handle_prefix||'performFirstRowsScanQuery'||k_appl_handle_suffix 
      OR  p_sql_text LIKE k_appl_handle_prefix||'performStartScanValues'||k_appl_handle_suffix 
      OR  p_sql_text LIKE k_appl_handle_prefix||'performContinuedScanValues'||k_appl_handle_suffix 
      OR  p_sql_text LIKE k_appl_handle_prefix||'bucketIndexSelect'||k_appl_handle_suffix 
      OR  p_sql_text LIKE k_appl_handle_prefix||'bucketKeySelect'||k_appl_handle_suffix 
      OR  p_sql_text LIKE k_appl_handle_prefix||'selectBuckets'||k_appl_handle_suffix 
      OR  p_sql_text LIKE k_appl_handle_prefix||'getAutoSequences'||k_appl_handle_suffix 
      OR  p_sql_text LIKE k_appl_handle_prefix||'bucketValueSelect'||k_appl_handle_suffix 
      OR  p_sql_text LIKE k_appl_handle_prefix||'countTransactions'||k_appl_handle_suffix 
      OR  p_sql_text LIKE k_appl_handle_prefix||'Fetch snapshots'||k_appl_handle_suffix 
    THEN RETURN gk_appl_cat_3;
    ELSIF p_sql_text LIKE k_appl_handle_prefix||'populateBucketGCWorkspace'||k_appl_handle_suffix 
      OR  p_sql_text LIKE k_appl_handle_prefix||'deleteBucketGarbage'||k_appl_handle_suffix 
      OR  p_sql_text LIKE k_appl_handle_prefix||'Populate workspace'||k_appl_handle_suffix 
      OR  p_sql_text LIKE k_appl_handle_prefix||'Delete garbage fOR  transaction GC'||k_appl_handle_suffix 
      OR  p_sql_text LIKE k_appl_handle_prefix||'Delete garbage in KTK GC'||k_appl_handle_suffix 
      OR  p_sql_text LIKE k_appl_handle_prefix||'hashBucket'||k_appl_handle_suffix 
      OR  p_sql_text LIKE k_appl_handle_prefix||'validateIfWorkspaceEmpty'||k_appl_handle_suffix 
      OR  p_sql_text LIKE k_appl_handle_prefix||'getGCLogEntries'||k_appl_handle_suffix 
      OR  p_sql_text LIKE k_appl_handle_prefix||'gcEventTryInsert'||k_appl_handle_suffix 
      OR  p_sql_text LIKE k_appl_handle_prefix||'countAllRows'||k_appl_handle_suffix 
      OR  p_sql_text LIKE k_appl_handle_prefix||'Delete rows from'||k_appl_handle_suffix 
      OR  p_sql_text LIKE k_appl_handle_prefix||'hashSnapshot'||k_appl_handle_suffix 
      OR  p_sql_text LIKE k_appl_handle_prefix||'countKtkRows'||k_appl_handle_suffix 
      OR  p_sql_text LIKE k_appl_handle_prefix||'gcEventMaxId'||k_appl_handle_suffix 
      OR  p_sql_text LIKE k_appl_handle_prefix||'secondsSinceLastGcEvent'||k_appl_handle_suffix 
      OR  p_sql_text LIKE k_appl_handle_prefix||'getMaxTransactionOlderThan'||k_appl_handle_suffix 
    THEN RETURN gk_appl_cat_4;
    ELSE RETURN 'Unknown';
    END IF;
  END application_category;
all_sql AS (
--SELECT /*+ MATERIALIZE NO_MERGE */
--      DISTINCT sql_id, command_type, sql_text FROM v$sql
--UNION
SELECT /*+ MATERIALIZE NO_MERGE */ 
       DISTINCT sql_id, command_type, DBMS_LOB.SUBSTR(sql_text, 1000) sql_text FROM dba_hist_sqltext
),
all_sql_with_type AS (
SELECT /*+ MATERIALIZE NO_MERGE */
       sql_id, command_type, sql_text, 
       SUBSTR(CASE WHEN sql_text LIKE '/*'||CHR(37) THEN SUBSTR(sql_text, 1, INSTR(sql_text, '*/') + 1) ELSE sql_text END, 1, 100) sql_text_100,
       application_category(sql_text) application_module
  FROM all_sql
),
my_tx_sql AS (
SELECT /*+ MATERIALIZE NO_MERGE */
       sql_id, MAX(sql_text) sql_text, MAX(sql_text_100) sql_text_100, MAX(application_module) application_module
  FROM all_sql_with_type
 WHERE application_module IS NOT NULL
   AND (  
         (NVL('&&kiev_tx.', 'CBSGU') LIKE CHR(37)||'C'||CHR(37) AND application_module = 'CommitTx') OR
         (NVL('&&kiev_tx.', 'CBSGU') LIKE CHR(37)||'B'||CHR(37) AND application_module = 'BeginTx') OR
         (NVL('&&kiev_tx.', 'CBSGU') LIKE CHR(37)||'S'||CHR(37) AND application_module = 'Scan') OR
         (NVL('&&kiev_tx.', 'CBSGU') LIKE CHR(37)||'G'||CHR(37) AND application_module = 'GC') OR
         (NVL('&&kiev_tx.', 'CBSGU') LIKE CHR(37)||'U'||CHR(37) AND application_module = 'Unknown')
       )
   AND ('&&kiev_bucket.' IS NULL OR UPPER(sql_text) LIKE CHR(37)||UPPER('&&kiev_bucket.')||CHR(37))
   AND command_type NOT IN (SELECT action FROM audit_actions WHERE name IN ('PL/SQL EXECUTE', 'EXECUTE PROCEDURE'))
 GROUP BY
       sql_id
),
/****************************************************************************************/
snapshots AS (
SELECT /*+ MATERIALIZE NO_MERGE */
       s.snap_id,
       CAST(s.end_interval_time AS DATE) end_date_time,
       (CAST(s.end_interval_time AS DATE) - CAST(s.begin_interval_time AS DATE)) * 24 * 60 * 60 interval_seconds
  FROM dba_hist_snapshot s /* sys.wrm$_snapshot */
 WHERE s.dbid = &&dbid.
   AND s.instance_number = &&instance_number.
   AND s.snap_id >= &&oldest_snap_id.
),
sqlstat_group_by_snap_sql_con AS (
SELECT /*+ MATERIALIZE NO_MERGE */
       h.snap_id,
       h.sql_id,
       h.con_id,
       --
       SUM(h.executions_delta) executions_delta,
       SUM(h.elapsed_time_delta) elapsed_time_delta,
       SUM(h.cpu_time_delta) cpu_time_delta,
       SUM(h.iowait_delta) iowait_delta,
       SUM(h.apwait_delta) apwait_delta,
       SUM(h.ccwait_delta) ccwait_delta,
       SUM(h.parse_calls_delta) parse_calls_delta,
       SUM(h.fetches_delta) fetches_delta,
       SUM(h.loads_delta) loads_delta,
       SUM(h.invalidations_delta) invalidations_delta,
       MAX(h.version_count) version_count,
       SUM(h.sharable_mem) sharable_mem,
       SUM(h.rows_processed_delta) rows_processed_delta,
       SUM(h.buffer_gets_delta) buffer_gets_delta,
       SUM(h.disk_reads_delta) disk_reads_delta
  FROM dba_hist_sqlstat h /* sys.wrh$_sqlstat */
 WHERE h.dbid = &&dbid.
   AND h.instance_number = &&instance_number.
   AND h.snap_id >= &&oldest_snap_id.
   AND h.snap_id BETWEEN &&snap_id_min. AND &&snap_id_max.
   AND h.con_dbid > 0
   AND h.sql_id IN (SELECT t.sql_id FROM my_tx_sql t)
 GROUP BY
       h.snap_id,
       h.sql_id,
       h.con_id
),
sqlstat_snap_range AS (
SELECT /*+ MATERIALIZE NO_MERGE */
       h.sql_id,
       h.con_id,
       --
       ROUND(SUM(h.elapsed_time_delta)/1e3/GREATEST(SUM(h.executions_delta),1),3) db_time_exec,
       ROUND(SUM(h.elapsed_time_delta)/SUM(s.interval_seconds)/1e6,3) db_time_aas,
       ROUND(SUM(h.cpu_time_delta)/1e3/GREATEST(SUM(h.executions_delta),1),3) cpu_time_exec,
       ROUND(SUM(h.cpu_time_delta)/SUM(s.interval_seconds)/1e6,3) cpu_time_aas,
       ROUND(SUM(h.iowait_delta)/1e3/GREATEST(SUM(h.executions_delta),1),3) io_time_exec,
       ROUND(SUM(h.iowait_delta)/SUM(s.interval_seconds)/1e6,3) io_time_aas,
       ROUND(SUM(h.apwait_delta)/1e3/GREATEST(SUM(h.executions_delta),1),3) appl_time_exec,
       ROUND(SUM(h.apwait_delta)/SUM(s.interval_seconds)/1e6,3) appl_time_aas,
       ROUND(SUM(h.ccwait_delta)/1e3/GREATEST(SUM(h.executions_delta),1),3) conc_time_exec,
       ROUND(SUM(h.ccwait_delta)/SUM(s.interval_seconds)/1e6,3) conc_time_aas,
       SUM(h.parse_calls_delta) parses,
       ROUND(SUM(h.parse_calls_delta)/SUM(s.interval_seconds),3) parses_sec,
       SUM(h.executions_delta) executions,
       ROUND(SUM(h.executions_delta)/SUM(s.interval_seconds),3) executions_sec,
       SUM(h.fetches_delta) fetches,
       ROUND(SUM(h.fetches_delta)/SUM(s.interval_seconds),3) fetches_sec,
       SUM(h.loads_delta) loads,
       SUM(h.invalidations_delta) invalidations,
       MAX(h.version_count) version_count,
       ROUND(SUM(h.sharable_mem)/POWER(2,20),3) sharable_mem_mb,
       ROUND(SUM(h.rows_processed_delta)/SUM(s.interval_seconds),3) rows_processed_sec,
       ROUND(SUM(h.rows_processed_delta)/GREATEST(SUM(h.executions_delta),1),3) rows_processed_exec,
       ROUND(SUM(h.buffer_gets_delta)/SUM(s.interval_seconds),3) buffer_gets_sec,
       ROUND(SUM(h.buffer_gets_delta)/GREATEST(SUM(h.executions_delta),1),3) buffer_gets_exec,
       ROUND(SUM(h.disk_reads_delta)/SUM(s.interval_seconds),3) disk_reads_sec,
       ROUND(SUM(h.disk_reads_delta)/GREATEST(SUM(h.executions_delta),1),3) disk_reads_exec
       --
  FROM sqlstat_group_by_snap_sql_con h, 
       snapshots s /* dba_hist_snapshot */
 WHERE s.snap_id = h.snap_id
 GROUP BY
       h.sql_id,
       h.con_id
),
ranked_sql AS (
SELECT /*+ MATERIALIZE NO_MERGE */
       sr.sql_id,
       sr.con_id,
       ROW_NUMBER() OVER (ORDER BY sr.&&computed_metric. DESC NULLS LAST, sr.db_time_exec DESC NULLS LAST, sr.db_time_aas DESC NULLS LAST) rank
  FROM sqlstat_snap_range sr
),
sqlstat_ranked_and_grouped AS (
SELECT /*+ MATERIALIZE NO_MERGE */
       CASE WHEN rs.rank <= &&top_n. THEN h.sql_id END sql_id,
       CASE WHEN rs.rank <= &&top_n. THEN rs.rank END rank,
       h.con_id,
       h.snap_id,
       --
       SUM(h.executions_delta) executions_delta,
       SUM(h.elapsed_time_delta) elapsed_time_delta,
       SUM(h.cpu_time_delta) cpu_time_delta,
       SUM(h.iowait_delta) iowait_delta,
       SUM(h.apwait_delta) apwait_delta,
       SUM(h.ccwait_delta) ccwait_delta,
       SUM(h.parse_calls_delta) parse_calls_delta,
       SUM(h.fetches_delta) fetches_delta,
       SUM(h.loads_delta) loads_delta,
       SUM(h.invalidations_delta) invalidations_delta,
       MAX(h.version_count) version_count,
       SUM(h.sharable_mem) sharable_mem,
       SUM(h.rows_processed_delta) rows_processed_delta,
       SUM(h.buffer_gets_delta) buffer_gets_delta,
       SUM(h.disk_reads_delta) disk_reads_delta
  FROM dba_hist_sqlstat h, /* sys.wrh$_sqlstat */
       ranked_sql rs
 WHERE h.dbid = &&dbid.
   AND h.instance_number = &&instance_number.
   AND h.snap_id >= &&oldest_snap_id.
   AND h.con_dbid > 0
   AND h.sql_id IN (SELECT t.sql_id FROM my_tx_sql t)
   AND rs.sql_id(+) = h.sql_id
   AND rs.con_id(+) = h.con_id
 GROUP BY
       CASE WHEN rs.rank <= &&top_n. THEN h.sql_id END,
       CASE WHEN rs.rank <= &&top_n. THEN rs.rank END,
       h.con_id,
       h.snap_id
),
sqlstat_time_series AS (
SELECT /*+ MATERIALIZE NO_MERGE */
       h.sql_id,
       h.rank,
       h.con_id,
       h.snap_id,
       --
       ROUND(SUM(h.elapsed_time_delta)/1e3/GREATEST(SUM(h.executions_delta),1),3) db_time_exec,
       ROUND(SUM(h.elapsed_time_delta)/SUM(s.interval_seconds)/1e6,3) db_time_aas,
       ROUND(SUM(h.cpu_time_delta)/1e3/GREATEST(SUM(h.executions_delta),1),3) cpu_time_exec,
       ROUND(SUM(h.cpu_time_delta)/SUM(s.interval_seconds)/1e6,3) cpu_time_aas,
       ROUND(SUM(h.iowait_delta)/1e3/GREATEST(SUM(h.executions_delta),1),3) io_time_exec,
       ROUND(SUM(h.iowait_delta)/SUM(s.interval_seconds)/1e6,3) io_time_aas,
       ROUND(SUM(h.apwait_delta)/1e3/GREATEST(SUM(h.executions_delta),1),3) appl_time_exec,
       ROUND(SUM(h.apwait_delta)/SUM(s.interval_seconds)/1e6,3) appl_time_aas,
       ROUND(SUM(h.ccwait_delta)/1e3/GREATEST(SUM(h.executions_delta),1),3) conc_time_exec,
       ROUND(SUM(h.ccwait_delta)/SUM(s.interval_seconds)/1e6,3) conc_time_aas,
       SUM(h.parse_calls_delta) parses,
       ROUND(SUM(h.parse_calls_delta)/SUM(s.interval_seconds),3) parses_sec,
       SUM(h.executions_delta) executions,
       ROUND(SUM(h.executions_delta)/SUM(s.interval_seconds),3) executions_sec,
       SUM(h.fetches_delta) fetches,
       ROUND(SUM(h.fetches_delta)/SUM(s.interval_seconds),3) fetches_sec,
       SUM(h.loads_delta) loads,
       SUM(h.invalidations_delta) invalidations,
       MAX(h.version_count) version_count,
       ROUND(SUM(h.sharable_mem)/POWER(2,20),3) sharable_mem_mb,
       ROUND(SUM(h.rows_processed_delta)/SUM(s.interval_seconds),3) rows_processed_sec,
       ROUND(SUM(h.rows_processed_delta)/GREATEST(SUM(h.executions_delta),1),3) rows_processed_exec,
       ROUND(SUM(h.buffer_gets_delta)/SUM(s.interval_seconds),3) buffer_gets_sec,
       ROUND(SUM(h.buffer_gets_delta)/GREATEST(SUM(h.executions_delta),1),3) buffer_gets_exec,
       ROUND(SUM(h.disk_reads_delta)/SUM(s.interval_seconds),3) disk_reads_sec,
       ROUND(SUM(h.disk_reads_delta)/GREATEST(SUM(h.executions_delta),1),3) disk_reads_exec
       --
  FROM sqlstat_ranked_and_grouped h,
       snapshots s /* dba_hist_snapshot */
 WHERE s.snap_id = h.snap_id
 GROUP BY
       h.sql_id,
       h.rank,
       h.con_id,
       h.snap_id
),
sqlstat_top_and_null AS (
SELECT /*+ MATERIALIZE NO_MERGE */
       ts.sql_id,
       ts.con_id,
       ts.rank,
       ts.snap_id,
       ts.&&computed_metric. value
  FROM sqlstat_time_series ts
),
sqlstat_top AS (
SELECT /*+ MATERIALIZE NO_MERGE */
       tn.snap_id,
       SUM(CASE WHEN tn.rank IS NULL THEN tn.value ELSE 0 END) sql_00, -- all but top
       SUM(CASE tn.rank WHEN 01 THEN tn.value ELSE 0 END) sql_01,
       SUM(CASE tn.rank WHEN 02 THEN tn.value ELSE 0 END) sql_02,
       SUM(CASE tn.rank WHEN 03 THEN tn.value ELSE 0 END) sql_03,
       SUM(CASE tn.rank WHEN 04 THEN tn.value ELSE 0 END) sql_04,
       SUM(CASE tn.rank WHEN 05 THEN tn.value ELSE 0 END) sql_05,
       SUM(CASE tn.rank WHEN 06 THEN tn.value ELSE 0 END) sql_06,
       SUM(CASE tn.rank WHEN 07 THEN tn.value ELSE 0 END) sql_07,
       SUM(CASE tn.rank WHEN 08 THEN tn.value ELSE 0 END) sql_08,
       SUM(CASE tn.rank WHEN 09 THEN tn.value ELSE 0 END) sql_09,
       SUM(CASE tn.rank WHEN 10 THEN tn.value ELSE 0 END) sql_10,
       SUM(CASE tn.rank WHEN 11 THEN tn.value ELSE 0 END) sql_11,
       SUM(CASE tn.rank WHEN 12 THEN tn.value ELSE 0 END) sql_12 -- consistent with tn.value on top_n
       /*
       SUM(CASE tn.rank WHEN 13 THEN tn.value ELSE 0 END) sql_13,
       SUM(CASE tn.rank WHEN 14 THEN tn.value ELSE 0 END) sql_14,
       SUM(CASE tn.rank WHEN 15 THEN tn.value ELSE 0 END) sql_15,
       SUM(CASE tn.rank WHEN 16 THEN tn.value ELSE 0 END) sql_16,
       SUM(CASE tn.rank WHEN 17 THEN tn.value ELSE 0 END) sql_17,
       SUM(CASE tn.rank WHEN 18 THEN tn.value ELSE 0 END) sql_18,
       SUM(CASE tn.rank WHEN 19 THEN tn.value ELSE 0 END) sql_19,
       SUM(CASE tn.rank WHEN 20 THEN tn.value ELSE 0 END) sql_20 -- consistent with tn.value on top_n
       */
  FROM sqlstat_top_and_null tn
 GROUP BY
       tn.snap_id
),
sql_list AS (
SELECT /*+ MATERIALIZE NO_MERGE FULL(rs) */
       rs.rank,
       ','''||rs.sql_id||(CASE '&&con_name.' WHEN 'CDB$ROOT' THEN ' '||c.name END)||'''' line
  FROM ranked_sql rs,
       v$containers c
 WHERE rs.rank <= &&top_n.
   AND c.con_id = rs.con_id
 ORDER BY
       rs.rank
),
sql_list_part_2 AS (
SELECT /*+ MATERIALIZE NO_MERGE */
       LEVEL rank,
       ',''top sql #'||LPAD(LEVEL,2,'0')||'''' line
  FROM DUAL
 WHERE LEVEL > (SELECT MAX(rank) FROM sql_list)
CONNECT BY LEVEL <= &&top_n.
 ORDER BY
       LEVEL
),
data_list AS (
SELECT /*+ MATERIALIZE NO_MERGE FULL(s) FULL(t) USE_HASH(s t) LEADING(s t) */
       ', [new Date('||
       TO_CHAR(s.end_date_time, 'YYYY')|| /* year */
       ','||(TO_NUMBER(TO_CHAR(s.end_date_time, 'MM')) - 1)|| /* month - 1 */
       ','||TO_CHAR(s.end_date_time, 'DD')|| /* day */
       ','||TO_CHAR(s.end_date_time, 'HH24')|| /* hour */
       ','||TO_CHAR(s.end_date_time, 'MI')|| /* minute */
       ','||TO_CHAR(s.end_date_time, 'SS')|| /* second */
       ')'||
       ','||ROUND(t.sql_00,3)||
       ','||ROUND(t.sql_01,3)||
       ','||ROUND(t.sql_02,3)||
       ','||ROUND(t.sql_03,3)||
       ','||ROUND(t.sql_04,3)||
       ','||ROUND(t.sql_05,3)||
       ','||ROUND(t.sql_06,3)||
       ','||ROUND(t.sql_07,3)||
       ','||ROUND(t.sql_08,3)||
       ','||ROUND(t.sql_09,3)||
       ','||ROUND(t.sql_10,3)||
       ','||ROUND(t.sql_11,3)||
       ','||ROUND(t.sql_12,3)||
       /*
       ','||ROUND(t.sql_13,3)||
       ','||ROUND(t.sql_14,3)||
       ','||ROUND(t.sql_15,3)||
       ','||ROUND(t.sql_16,3)||
       ','||ROUND(t.sql_17,3)||
       ','||ROUND(t.sql_18,3)||
       ','||ROUND(t.sql_19,3)||
       ','||ROUND(t.sql_20,3)||
       */
       ']' line
  FROM sqlstat_top t,
       snapshots s /* dba_hist_snapshot */
 WHERE s.snap_id = t.snap_id
 ORDER BY
       t.snap_id
)
/****************************************************************************************/
SELECT line FROM sql_list
 UNION ALL
SELECT line FROM sql_list_part_2
 UNION ALL
SELECT ']' line FROM DUAL
 UNION ALL
SELECT line FROM data_list
/
/****************************************************************************************/
SET HEA ON PAGES 100;

PRO ]);
PRO
PRO var options = {isStacked: true,
PRO chartArea:{left:90, top:75, width:'65%', height:'70%'},
PRO backgroundColor: {fill: 'white', stroke: '#336699', strokeWidth: 1},
PRO explorer: {actions: ['dragToZoom', 'rightClickToReset'], maxZoomIn: 0.01},
PRO title: '&&chart_title.',
PRO titleTextStyle: {fontSize: 18, bold: false},
PRO focusTarget: 'category',
PRO legend: {position: 'right', textStyle: {fontSize: 14}},
PRO tooltip: {textStyle: {fontSize: 14}},
PRO hAxis: {title: '&&xaxis_title.', gridlines: {count: -1}, titleTextStyle: {fontSize: 16, bold: false}},
PRO series: { 0: { color :'#34CF27'}, 1: { color :'#0252D7'},  2: { color :'#1E96DD'},  3: { color :'#CEC3B5'},  4: { color :'#EA6A05'},  5: { color :'#871C12'},  6: { color :'#C42A05'}, 7: {color :'#75763E'},
PRO 8: { color :'#594611'}, 9: { color :'#989779'}, 10: { color :'#C6BAA5'}, 11: { color :'#9FFA9D'}, 12: { color :'#F571A0'}, 13: { color :'#000000'}, 14: { color :'#ff0000'}},
PRO vAxis: {title: '&&vaxis_title.' &&vaxis_baseline., gridlines: {count: -1}, titleTextStyle: {fontSize: 16, bold: false}}
PRO }
PRO
PRO var chart = new google.visualization.AreaChart(document.getElementById('chart_div'))
PRO chart.draw(data, options)
PRO }
PRO </script>
PRO </head>
PRO <body>
PRO <h1>&&report_title.</h1>
PRO &&report_abstract_1.
PRO &&report_abstract_2.
PRO &&report_abstract_3.
PRO &&report_abstract_4.
PRO &&report_abstract_5.
PRO &&report_abstract_6.
PRO <div id="chart_div" class="google-chart"></div>
PRO <font class="n">Notes:</font>
PRO <font class="n">&&chart_foot_note_1.</font>
PRO <font class="n">&&chart_foot_note_2.</font>
PRO <font class="n">&&chart_foot_note_3.</font>
PRO <font class="n">&&chart_foot_note_4.</font>
--PRO <pre>
--L
--PRO </pre>
PRO <br>
PRO <font class="f">&&report_foot_note.</font>
PRO </body>
PRO </html>
SPO OFF;
PRO
PRO &&output_file_name..html
PRO
CL COL;
UNDEF 1 2 3 4 5 6;
SET HEA ON PAGES 100;
