CREATE OR REPLACE PACKAGE gerfp_conc_gl_sae_auto_pkg
/*************************************************************************************************************************************
 *                           - Copy Right General Electric Company 2006 -
 *
 *************************************************************************************************************************************
 *************************************************************************************************************************************
 * Project      :  GEGBS Financial Implementation Project
 * Application      :  General Ledger
 * Title        :  N/A
 * Program Name     :  N/A
 * Description Purpose  :  To Load SAE Concur Expenses from staging into GL interface tables
 * $Revision        :
 * Utility      :
 * Created by       :  Ramesh Soorishetty
 * Creation Date    :  22-JAN-2009
 * Called By            :  Concurrent Program
 * Parameters           :  N.A
 * Dependency       :  N/A
 * Frequency        :  On Demand
 * Related documents    :
 * Tables/views accessed:
 * Table Name                       SELECT     INSERT     UPDATE     DELETE
 * ---------------------            ------     ------     ------     ------
 * ----------------------------------------------------------------------------
 * Change History   :
 *====================================================================================================================================
 * Date         |Name               |Case#      |Remarks
 *====================================================================================================================================
 *
  *************************************************************************************************************************************
*/

 IS

  PROCEDURE debug_message(p_message IN VARCHAR2);

  PROCEDURE process_gl_data(errbuff        OUT VARCHAR2,
                            retcode        OUT VARCHAR2,
                            p_process_flag IN VARCHAR2);

  PROCEDURE display_err_congl(errbuff OUT VARCHAR2,
                              retcode OUT VARCHAR2);

  PROCEDURE send_mail(p_action  IN VARCHAR2,
                      p_content IN VARCHAR2);

  g_group_id VARCHAR2(200);

END gerfp_conc_gl_sae_auto_pkg;
/
CREATE OR REPLACE PACKAGE BODY gerfp_conc_gl_sae_auto_pkg AS
  /*************************************************************************************************************************************
   *                           - Copy Right General Electric Company 2006 -
   *
   *************************************************************************************************************************************
   *************************************************************************************************************************************
   * Project      :  GEGBS Financial Implementation Project
   * Application      :  General Ledger
   * Title        :  N/A
   * Program Name     :  N/A
   * Description Purpose  :  To Load SAE Concur Expenses from staging into GL interface tables
   * $Revision        :
   * Utility      :
   * Created by       :  Ramesh Soorishetty
   * Creation Date    :  22-JAN-2009
   * Called By            :  Concurrent Program
   * Parameters           :  N.A
   * Dependency       :  N/A
   * Frequency        :  On Demand
   * Related documents    :
   * Tables/views accessed:
   * Table Name                       SELECT     INSERT     UPDATE     DELETE
   * ---------------------            ------     ------     ------     ------
   *  GL_CODE_COMBINATIONS              X          -          -          -
   *  GL_JE_HEADERS             X          -          -          -
   *  GL_JE_SOURCES                 X          -          -          -
   *  GL_JE_CATEGORIES              X          -          -          -
   *  GL_INTERFACE_CONTROL              -          X          -          -
   *  GL_SETS_OF_BOOKS              X          -          -          -
   *  GL_CODE_COMBINATIONS              X          -          -          -
   *  GL_INTERFACE              -          X          -          X
   *  XXRFP_CONCUR_BUS_MAP              X          -          -          -
   *  XXRFP_CONCUR_KEYAC_MAP        X          -          -          -
   *  XXRFP_CONCUR_CC_MAP           X          -          -          -
   *  GERFP_CONGL_STG               X          -          X          -
   * ----------------------------------------------------------------------------
   * Change History   :
   *====================================================================================================================================
   * Date         |Name               |Case#      |Remarks
   *====================================================================================================================================
   * 11-MAY-2009  |Ramesh Soorishetty             | N.A           | Modified for Sob Id to show error records for specific sob in
   *                                                                SAE Error Correction Form
   * 02-FEB-2010  |Ramesh Soorishetty             | Japan (T4)    | Modified for Japan Requirement.
   * 13-FEB-2010  |Ramesh Soorishetty             | N.A           | Automation to process Muliple SAE Files
   * 10-MAY-2010  | Kishore Variganji             | Extend of Account Mapping to Project Code|
                                                    Key Account mapping and cost center mapping segments are retreived
                                                    as per the Natural account validations(Extend Of Project Code). *
   *************************************************************************************************************************************
  */

  v_conc_request NUMBER := fnd_global.conc_request_id;
  p_flag         VARCHAR(2); --added by Kishore Variganji for Project code Extn
  p_flag_1       VARCHAR(2); --added by satya chittella

  g_conn        utl_smtp.connection;
  g_sender      VARCHAR2(100) := 'oracle_user@ge.com';
  g_recipients  VARCHAR2(300);
  g_mail_domain VARCHAR2(30) DEFAULT '@mail.ad.ge.com';

  /******************************************************************************/
  /*               PROCEDURE TO DISPLAY LOG MESSAGES                            */
  /******************************************************************************/

  PROCEDURE debug_message(p_message IN VARCHAR2) IS
  BEGIN
    fnd_file.put_line(fnd_file.log,
                      p_message);
  EXCEPTION
    WHEN OTHERS THEN
      debug_message('-> Error occured in DEBUG_MESSAGE Procedure : ' ||
                    SQLERRM);
  END debug_message;

  /******************************************************************************/
  /*   Procedure to Check Duplicate file processing with batch number           */
  /******************************************************************************/

  PROCEDURE check_dup_file_process(p_sob_id       IN NUMBER,
                                   p_batch_number IN VARCHAR2,
                                   p_group_id     IN NUMBER,
                                   x_status       OUT VARCHAR2)
  
   IS
    v_batch_number VARCHAR2(50);
    v_je_cnt       NUMBER := 0;
    v_status       VARCHAR2(1);
  BEGIN
  
    IF (p_batch_number IS NOT NULL) THEN
      /*Checking Batch number in Oracle Base Table (GL_JE_HEADERS) */
      BEGIN
        SELECT SUM(rc)
          INTO v_je_cnt
          FROM (SELECT COUNT(gjh.je_header_id) rc
                   FROM gl_je_headers    gjh,
                        gl_je_sources    gjs,
                        gl_je_categories gjc
                  WHERE
                 --gjh.external_reference like p_batch_number
                  (substr(gjh.external_reference,
                          2,
                          length(gjh.external_reference) - 2) =
                  p_batch_number OR
                  substr(gjh.external_reference,
                          2,
                          instr(gjh.external_reference,
                                '_') - 1) = p_batch_number)
               AND gjh.set_of_books_id = p_sob_id
               AND gjc.je_category_name = gjh.je_category
               AND gjs.je_source_name = gjh.je_source
               AND upper(gjc.user_je_category_name) = 'CONCUR SAE'
               AND upper(gjs.user_je_source_name) = 'CONCUR'
               AND rownum = 1
                 UNION ALL
                 SELECT COUNT(1) rc
                   FROM gl_interface gi
                  WHERE upper(gi.user_je_category_name) = 'CONCUR SAE'
                    AND upper(gi.user_je_source_name) = 'CONCUR'
                    AND gi.reference6 = p_batch_number
                    AND gi.group_id <> p_group_id
                    AND rownum = 1
                 /*
                 union all
                 select COUNT(1) rc  from 
                 gerfp_congl_stg
                 where CONCUR_BATCH_ID=p_batch_number
                 and FILE_SEQ<>p_group_id
                 and SOB_ID=p_sob_id
                 */
                 );
      
        IF (nvl(v_je_cnt,
                0) > 0) THEN
          x_status := 'Y';
        ELSE
          x_status := 'N';
        END IF;
      END;
    END IF;
  
    x_status := 'N';
    x_status := nvl(x_status,
                    'N');
  
  EXCEPTION
    WHEN OTHERS THEN
      fnd_file.put_line(fnd_file.log,
                        'Error occured in CHECK_DUP_FILE_PROCESS Procedure : ' ||
                        SQLERRM);
  END check_dup_file_process;

  /******************************************************************************/
  /*   PROCEDURE to Submit JOURNAL IMPORT Program                               */
  /******************************************************************************/

  PROCEDURE submit_journal_import(p_user_id  IN NUMBER,
                                  p_resp_id  IN NUMBER,
                                  p_sob_id   IN NUMBER,
                                  p_group_id IN NUMBER,
                                  p_source   IN VARCHAR2,
                                  x_status   OUT VARCHAR2,
                                  x_req_id   OUT NUMBER) IS
  
    v_req_id            NUMBER;
    v_appl_id           NUMBER;
    v_suspense_flag     VARCHAR2(2) := 'Y';
    v_interface_run_id  NUMBER;
    v_req_return_status BOOLEAN;
    v_summary_flag      VARCHAR2(1) := 'N';
    v_source_name       VARCHAR2(30);
    v_user_source_name  VARCHAR2(80);
    v_req_phase         VARCHAR2(30);
    v_req_status        VARCHAR2(30);
    v_req_dev_phase     VARCHAR2(30);
    v_req_dev_status    VARCHAR2(30);
    v_req_message       VARCHAR2(50);
    v_je_source         VARCHAR2(50);
  
  BEGIN
  
    SELECT DISTINCT application_id
      INTO v_appl_id
      FROM fnd_application
     WHERE application_short_name = 'SQLGL';
  
    /*Deriving the Source Name*/
    BEGIN
    
      SELECT je_source_name
        INTO v_je_source
        FROM gl_je_sources
       WHERE user_je_source_name = p_source;
    
    EXCEPTION
      WHEN no_data_found THEN
        fnd_file.put_line(fnd_file.log,
                          'No Data Found Exception : JE_SOURCE_NAME does not exist for ' ||
                          p_source);
      WHEN too_many_rows THEN
        fnd_file.put_line(fnd_file.log,
                          'Exact Fetch Returned Too many Rows while extracting JE_SOURCE_NAME Value');
      WHEN OTHERS THEN
        fnd_file.put_line(fnd_file.log,
                          'SQL ERROR MESSAGE while extracting JE_SOURCE_NAME Value:' ||
                          SQLERRM);
    END;
  
    /* Sequence to create RUN_ID -- -- GERFP_IMPORT_RUN_ID_S.NEXTVAL */
    SELECT gl_journal_import_s.nextval INTO v_interface_run_id FROM dual;
  
    --     debug_message('Before insert to Interface control table  ');
    /* Insert record to interface control table */
    INSERT INTO gl_interface_control
      (je_source_name,
       status,
       interface_run_id,
       group_id,
       set_of_books_id,
       packet_id,
       request_id)
    VALUES
      (v_je_source --p_source
      ,
       'S',
       v_interface_run_id,
       p_group_id,
       p_sob_id,
       NULL,
       v_req_id);
    COMMIT;
  
    --     debug_message('After insert to Interface control table  ');
  
    --   Calling FND_REQUEST for Journal Import
    v_req_id := fnd_request.submit_request(application => 'SQLGL',
                                           program     => 'GLLEZL',
                                           description => NULL,
                                           start_time  => SYSDATE,
                                           sub_request => FALSE,
                                           argument1   => to_char(v_interface_run_id),
                                           argument2   => to_char(p_sob_id),
                                           argument3   => 'N' --Suspense Flag
                                          ,
                                           argument4   => NULL,
                                           argument5   => NULL,
                                           argument6   => 'N' -- Summary Flag
                                          ,
                                           argument7   => 'O' --Import DFF w/out validation
                                           );
  
    debug_message('Import Request id :' || v_req_id);
  
    x_req_id := v_req_id;
    IF v_req_id = 0 THEN
      raise_application_error(-20160,
                              fnd_message.get);
      x_status := 'Failed';
    ELSE
      x_status := 'Done';
    END IF;
  
  EXCEPTION
    WHEN OTHERS THEN
      fnd_file.put_line(fnd_file.log,
                        'JOB FAILED' || SQLERRM);
  END submit_journal_import;

  /**************************************************************/
  /*    MAIN PROCEDURE TO PROCESS DATA FROM STAGING TABLE TO INTERFACE TABLES   */
  /**************************************************************/

  PROCEDURE process_gl_data(errbuff        OUT VARCHAR2,
                            retcode        OUT VARCHAR2,
                            p_process_flag IN VARCHAR2) IS
  
    /*Added by Soori on 13-FEB-2010 for Automation*/
    CURSOR cur_file_seq IS
      SELECT DISTINCT file_seq
        FROM gerfp_congl_stg
       WHERE process_flag = p_process_flag
         AND concur_req_id = v_conc_request
         AND file_seq IS NOT NULL
         AND err_msg IS NULL;
  
    /*Cursor to fetch records from staging table*/
    CURSOR cur_concur_data(p_conc_req_id IN VARCHAR2,
                           p_file_seq    IN NUMBER /*Added by Soori on 13-FEB-2010 for Automation*/) IS
      SELECT ROWID,
             concur_req_id,
             concur_batch_id,
             detail_format_ind,
             account_detail_type,
             concur_export_date,
             stdacctngexport_id,
             last_name,
             first_name,
             capuser_number,
             category_name,
             submission_id,
             submission_name,
             transaction_date,
             home_iso_currency_code,
             capuser_ap_number,
             category_segment_1,
             department,
             expense_description, /*Added by george for MY JE description on 08-SEP-2010*/
             sae_char_1, /*Added by Soori for Japan Requirement, on 02-FEB-2010*/
             int_dom_flag, /*Added by Soori for Japan Requirement, on 02-FEB-2010*/
             amount, /*Added by Soori for Japan Requirement, on 02-FEB-2010*/
             authorised_tax_amount, /*Added by Soori for Japan Requirement, on 02-FEB-2010*/
             authorised_reclaim_amount, /*Added by Soori for Japan Requirement, on 02-FEB-2010*/
             tax_rate_type, /*Added by Soori for Japan Requirement, on 05-FEB-2010*/
             home_net_amount,
             gross_reclaim_amount,
             sae_float_1, /*Added by george for VN WTH */
             debit_credit_indicator,
             hh_description,
             sob_id /*Added by Soori on 11-MAY-2009*/,
             file_seq /*Added by Soori on 13-FEB-2010 for Automation*/
        FROM gerfp_congl_stg
       WHERE concur_req_id = p_conc_req_id
         AND detail_format_ind IN ('HH',
                                   'AD')
         AND file_seq = p_file_seq /*Added by Soori on 13-FEB-2010 for Automation*/
         AND process_flag = p_process_flag
         AND err_msg IS NULL
       ORDER BY 3 DESC;
  
    CURSOR notifier_list IS
      SELECT DISTINCT future2
        FROM apps.xxrfp_concur_bus_map glid
       WHERE future2 IS NOT NULL
      /* and CONCUR_LEDGER_CODE like 'TH%' */
       ORDER BY future2;
  
    CURSOR cur_file_status(p_req_id NUMBER,
                           notifier VARCHAR2) IS
      SELECT DISTINCT file_seq,
                      file_name,
                      concur_batch_id,
                      concur_req_id,
                      sob_id,
                      sob_name,
                      capuser_ap_number,
                      future2
        FROM gerfp_congl_stg           stg,
             apps.xxrfp_concur_bus_map glid
       WHERE glid.concur_ledger_code = stg.capuser_ap_number
         AND concur_req_id = p_req_id
         AND glid.future2 = notifier
       ORDER BY capuser_ap_number,
                sob_id;
  
    CURSOR cur_err_cgl(p_req_id     NUMBER,
                       p_file_name  VARCHAR2,
                       p_batch_name VARCHAR2) IS
      SELECT *
        FROM gerfp_congl_stg
       WHERE process_flag IN ('CR',
                              'KR',
                              'R') /*CC,Key and Other Rejected*/
         AND err_msg IS NOT NULL
         AND file_name = p_file_name
         AND concur_batch_id = p_batch_name
         AND detail_format_ind = 'AD' /*Added by Soori on 13-FEB-2010 for Automation*/
         AND concur_req_id = p_req_id;
  
    CURSOR cur_iface_data(p_source     VARCHAR2,
                          p_category   VARCHAR2,
                          p_batch_name VARCHAR2,
                          p_group_id   NUMBER /*Commented by Soori on 13-FEB-2010 for Automation*/) IS
      SELECT gi.set_of_books_id sob_id,
             sob.name sob_name,
             gi.reference6 batch_name,
             gi.group_id, /*Added by Soori on 13-FEB-2010 for Automation*/
             COUNT(1) rec_cnt
        FROM gl_interface     gi,
             gl_sets_of_books sob
       WHERE gi.set_of_books_id = sob.set_of_books_id
         AND user_je_source_name = p_source
         AND user_je_category_name = p_category
         AND substr(gi.reference6,
                    2,
                    length(gi.reference6) - 2) = p_batch_name
         AND group_id = p_group_id /*Commented by Soori on 13-FEB-2010 for Automation*/
         AND status = 'NEW'
       GROUP BY gi.set_of_books_id,
                sob.name,
                gi.reference6,
                gi.group_id;
  
    /*Variables Declaration*/
    v_batch_id           VARCHAR2(200);
    v_export_date        DATE;
    v_concur_export_date DATE;
    v_err_msg            VARCHAR2(4000) := NULL;
    v_cc_err_msg         VARCHAR2(4000) := NULL;
    v_keyacc_err_msg     VARCHAR2(4000) := NULL;
    v_sob_id             NUMBER;
    v_je_cnt             NUMBER;
    v_intr_rec_cnt       NUMBER;
    v_userid             NUMBER;
    v_resp_id            NUMBER;
    v_import_status      VARCHAR2(500);
    v_chk_status         VARCHAR2(2000);
    v_final_chk_status   VARCHAR2(2000);
  
    v_last_name              VARCHAR2(200);
    v_first_name             VARCHAR2(200);
    v_capuser_number         NUMBER;
    v_category_name          VARCHAR2(200);
    v_submission_name        VARCHAR2(200);
    v_transaction_date       DATE;
    v_home_iso_currency_code VARCHAR2(200);
    v_capuser_ap_number      VARCHAR2(200);
    v_category_segment_1     VARCHAR2(200);
    v_department             VARCHAR2(200);
    v_expense_description    VARCHAR2(200); /*Added by george for MY JE description on 08-SEP-2010*/
  
    v_sae_char_1                VARCHAR2(200); /*Added by Soori for Japan Requirement, on 02-FEB-2010*/
    v_int_dom_flag              VARCHAR2(200); /*Added by Soori for Japan Requirement, on 02-FEB-2010*/
    v_amount                    NUMBER; /*Added by Soori for Japan Requirement, on 02-FEB-2010*/
    v_authorised_tax_amount     NUMBER; /*Added by Soori for Japan Requirement, on 02-FEB-2010*/
    v_authorised_reclaim_amount NUMBER; /*Added by Soori for Japan Requirement, on 02-FEB-2010*/
    v_tax_rate_type             VARCHAR2(200); /*Added by Soori for Japan Requirement, on 05-FEB-2010*/
    v_home_net_amount           NUMBER;
    v_gross_reclaim_amount      NUMBER;
    v_sae_float_1               NUMBER; /* Added by george for TH WHT sae_float_1*/
  
    v_debit_credit_indicator VARCHAR2(200);
    v_hh_description         VARCHAR2(4000);
    v_reference10            VARCHAR2(250);
    v_attribute10            VARCHAR2(250);
    v_tot_cr_amt             NUMBER;
    v_tot_dr_amt             NUMBER;
  
    v_me_code               apps.xxrfp_concur_bus_map.me_code%TYPE;
    v_le_code               apps.xxrfp_concur_bus_map.le_code%TYPE;
    v_book_type             apps.xxrfp_concur_bus_map.book_type%TYPE;
    v_sae_offset_account    apps.xxrfp_concur_bus_map.sae_offset_account%TYPE;
    v_tax_account           apps.xxrfp_concur_bus_map.tax_account%TYPE;
    v_accr_offset_account   apps.xxrfp_concur_bus_map.accrual_offset_account%TYPE;
    v_conc_suspense_account apps.xxrfp_concur_bus_map.concur_suspense_account%TYPE;
  
    /* Added by george for TH
    --xbus.CC_SAE_OFFSET_ACCOUNT,xbus.CASH_ADV_ACCOUNT,xbus.WHT_ACCOUNT,xbus.ALLOC_CEARING_ACCOUNT
    */
    TYPE t_acc IS VARRAY(9) OF VARCHAR2(200);
    TYPE t_item_acc IS VARRAY(4) OF t_acc;
    v_item_acc t_item_acc := t_item_acc();
  
    v_cc_sae_offset_account apps.xxrfp_concur_bus_map.cc_sae_offset_account%TYPE;
    v_cash_adv_account      apps.xxrfp_concur_bus_map.cash_adv_account%TYPE;
    v_wht_account           apps.xxrfp_concur_bus_map.wht_account%TYPE;
    v_alloc_cearing_account apps.xxrfp_concur_bus_map.alloc_cearing_account%TYPE;
  
    v_na             apps.xxrfp_concur_keyac_map.natrual_account%TYPE;
    v_ime_code       apps.xxrfp_concur_keyac_map.ime_code%TYPE;
    v_ile_code       apps.xxrfp_concur_keyac_map.ile_code%TYPE;
    v_no_keyacc_flag VARCHAR2(20);
    v_file_cnt       NUMBER; /*Added by Soori on 13-FEB-2010 for Automation*/
  
    v_shltn_code     apps.xxrfp_shelton_cc_map.shelton_ledger%TYPE;
    v_oracle_cc      apps.xxrfp_shelton_cc_map.oracle_cc%TYPE;
    v_project        apps.xxrfp_shelton_cc_map.project%TYPE;
    v_project_1      VARCHAR2(300); -- added by Kishore Variganji for Project Code Extn purpose
    v_keyacproj_code VARCHAR2(300); -- added by Satya chittella for Project Code Extn purpose
    v_reference      apps.xxrfp_shelton_cc_map.ref%TYPE;
    v_no_cc_flag     VARCHAR2(20);
    v_key_flag       VARCHAR2(20);
    v_acctype        VARCHAR2(20);
  
    v_html             VARCHAR2(3000);
    v_err_cnt          NUMBER;
    v_err_buffer       VARCHAR2(3000);
    v_req_id           NUMBER;
    v_rc               NUMBER;
    x_status           VARCHAR2(25);
    v_phase            VARCHAR2(25);
    v_status           VARCHAR2(25);
    v_dev_phase        VARCHAR2(25);
    v_dev_status       VARCHAR2(25);
    v_message          VARCHAR2(200);
    v_request_complete BOOLEAN;
    v_file_count       NUMBER;
  
    /* Exception Declaration */
    end_of_program     EXCEPTION;
    e_skip_to_next_rec EXCEPTION;
    e_end_program      EXCEPTION;
    e_cc_proj          EXCEPTION;
    e_flag             EXCEPTION;
    e_flag_proj_d      EXCEPTION;
    e_flag_proj_nd     EXCEPTION;
    e_flag_proj_nd_c   EXCEPTION;
    e_shelton_bus      EXCEPTION;
  
    v_default_cc VARCHAR2(100);
  
    v_offset_account VARCHAR2(100);
    v_cash_account   VARCHAR2(100);
    v_currency       VARCHAR2(100);
    l_mor            NUMBER;
    v_offset_ime     VARCHAR2(100);
  
  BEGIN
    /*Procedure BEGIN*/
  
    v_userid  := to_number(fnd_profile.value('USER_ID'));
    v_resp_id := to_number(fnd_profile.value('RESP_ID'));
  
    /*Commented by Soori on 13-FEB-2010 for Automation*/
    /*For Updating the staging table for the current submission of upload*/
    BEGIN
      /*SELECT TO_CHAR(SYSDATE,'DDMMRRRRHH24MISS')
      INTO g_group_id
      FROM DUAL;
      
      debug_message('Group Id Derived - '||g_group_id);
        */
    
      /* Modified by george for pick data for TH
      UPDATE gerfp_congl_stg
      SET concur_req_id = v_conc_request
      WHERE concur_req_id = '-1'
      AND process_flag ='U'
      AND err_msg IS NULL;
      */
      UPDATE gerfp_congl_stg
         SET concur_req_id = v_conc_request,
             err_msg       = NULL
       WHERE process_flag = p_process_flag;
      /*
      AND FILE_SEQ in 
      (select distinct FILE_SEQ 
      from gerfp_congl_stg 
      where CAPUSER_AP_NUMBER like 'TH%' and concur_req_id = '-1'
      AND process_flag ='U'
      AND err_msg IS NULL);   
      */
      COMMIT;
      debug_message(' ');
      debug_message('Process: Updated the Staging table with Program Request Id Derived ');
    
    EXCEPTION
      WHEN no_data_found THEN
        v_err_msg := v_err_msg || ' /' ||
                     'No Data Exist for Updating the staging table with Current request Id';
        RAISE end_of_program;
      WHEN OTHERS THEN
        v_err_msg := v_err_msg || ' /' ||
                     'Exception in Updating the staging table with Current request Id';
        RAISE end_of_program;
    END;
  
    /*Added by Soori on 13-FEB-2010 for Automation*/
    v_file_cnt := 0;
  
    /*Loop for file added by george on 12-JUL-2010 for comment  */
    FOR rec_file_seq IN cur_file_seq
    LOOP
    
      debug_message(' ');
      /*START : Added by Soori on 13-FEB-2010 for Automation*/
      v_file_cnt := v_file_cnt + 1;
      IF (v_file_cnt = 1) THEN
      
        SELECT to_char(SYSDATE,
                       'DDMMRRHH24SS')
          INTO g_group_id
          FROM dual;
      
        debug_message('Group Id Derived - ' || g_group_id);
      ELSE
        --           g_group_id := g_group_id||v_file_cnt;
        IF (length(g_group_id) > 9) THEN
          v_file_cnt := 0; /*Added by Soori on 19-FEB-2010*/
          v_file_cnt := v_file_cnt + 1; /*Added by Soori on 19-FEB-2010*/
          g_group_id := substr(g_group_id,
                               1,
                               5) || v_file_cnt;
        ELSE
          g_group_id := substr(g_group_id,
                               1,
                               6) || v_file_cnt;
        END IF;
      
        debug_message('Group Id Derived - ' || g_group_id);
      END IF;
      /*END : Added by Soori on 13-FEB-2010 for Automation*/
    
      SELECT substr(to_char(systimestamp,
                            'yymmddhh24missff'),
                    1,
                    15)
        INTO g_group_id
        FROM dual;
      g_group_id := rec_file_seq.file_seq;
    
      /*Main Loop for each concur line*/
      --       FOR rec_concur_data IN cur_concur_data(v_conc_request) /*Commented by Soori on 13-FEB-2010 for Automation*/
      FOR rec_concur_data IN cur_concur_data(v_conc_request,
                                             rec_file_seq.file_seq) /*Added by Soori on 13-FEB-2010 for Automation*/
      LOOP
      
        v_no_keyacc_flag := 'N';
        v_no_cc_flag     := 'N';
      
        v_last_name              := rec_concur_data.last_name;
        v_first_name             := rec_concur_data.first_name;
        v_capuser_number         := rec_concur_data.capuser_number;
        v_category_name          := rec_concur_data.category_name;
        v_submission_name        := rec_concur_data.submission_name;
        v_transaction_date       := rec_concur_data.transaction_date;
        v_home_iso_currency_code := rec_concur_data.home_iso_currency_code;
        v_capuser_ap_number      := rec_concur_data.capuser_ap_number;
        v_category_segment_1     := rec_concur_data.category_segment_1;
        v_expense_description    := rec_concur_data.expense_description;
        --v_department:=rec_concur_data.department;
      
        /*Commented by Soori for Japan Requirement, on 02-FEB-2010*/
        v_debit_credit_indicator := rec_concur_data.debit_credit_indicator;
        v_hh_description         := rec_concur_data.hh_description;
      
        /*START : Added by Soori for Japan Requirement, on 02-FEB-2010*/
        v_sae_char_1                := rec_concur_data.sae_char_1;
        v_int_dom_flag              := rec_concur_data.int_dom_flag;
        v_amount                    := rec_concur_data.amount;
        v_authorised_tax_amount     := rec_concur_data.authorised_tax_amount;
        v_authorised_reclaim_amount := rec_concur_data.authorised_reclaim_amount;
        v_sae_float_1               := nvl(rec_concur_data.sae_float_1,
                                           0);
      
        v_tax_rate_type := rec_concur_data.tax_rate_type; /*Added by Soori for Japan Requirement, on 05-FEB-2010*/
        --FND_FILE.PUT_LINE (FND_FILE.OUTPUT,'5111'||v_department);
        IF (v_capuser_ap_number LIKE 'JP%') THEN
          IF (v_sae_char_1 IS NOT NULL AND v_sae_char_1 <> 'NA') THEN
            v_department := v_sae_char_1;
          ELSE
            v_department := rec_concur_data.department;
            --  FND_FILE.PUT_LINE (FND_FILE.OUTPUT,'5114'||v_department);
          END IF;
        
          -- 1 = International
          -- 0 = Domestic
        
          IF (v_int_dom_flag = '1' AND
             upper(v_category_name) = 'AIRFARE INTERNATIONAL') THEN
            v_gross_reclaim_amount := nvl(v_authorised_tax_amount,
                                          0);
            v_home_net_amount      := nvl(v_amount,
                                          0) - nvl(v_authorised_tax_amount,
                                                   0);
          ELSE
            v_gross_reclaim_amount := nvl(rec_concur_data.gross_reclaim_amount,
                                          0);
            v_home_net_amount      := nvl(v_amount,
                                          0) - nvl(v_authorised_reclaim_amount,
                                                   0);
          END IF;
        ELSE
          --FND_FILE.PUT_LINE (FND_FILE.OUTPUT,'5117'||v_department);
          v_department           := rec_concur_data.department;
          v_gross_reclaim_amount := rec_concur_data.gross_reclaim_amount;
        
          /* Modified by george for unifying the calculation logic
          v_home_net_amount        :=  rec_concur_data.home_net_amount;
          */
          v_home_net_amount := nvl(v_amount,
                                   0) - nvl(v_gross_reclaim_amount,
                                            0);
        
        END IF;
        /*END : Added by Soori for Japan Requirement, on 02-FEB-2010*/
        --FND_FILE.PUT_LINE (FND_FILE.OUTPUT,'5119'||v_department);
      
        v_reference10 := NULL;
        v_attribute10 := NULL;
      
        --howlet 12/OCT/2012
        IF (v_capuser_ap_number LIKE 'MY%' OR
           v_capuser_ap_number = 'PHCF01') THEN
          v_reference10 := v_first_name || '#' || v_last_name || '#' ||
                           v_capuser_number || '#' || v_category_name || '#' ||
                           v_transaction_date || '#' ||
                           v_expense_description;
        ELSE
          v_reference10 := v_first_name || '#' || v_last_name || '#' ||
                           v_capuser_number || '#' || v_category_name || '#' ||
                           v_transaction_date || '#' ||
                           rec_concur_data.submission_id;
        END IF;
      
        /* For test */
        --v_reference10         :=rec_concur_data.stdacctngexport_id ||'#'|| v_first_name||'#'||v_last_name||'#'||v_capuser_number||'#'||v_category_name||'#'||v_transaction_date;
      
        /*START : Added by Soori for Japan Requirement, on 05-FEB-2010*/
        IF (v_capuser_ap_number LIKE 'JP%') THEN
          -- Modified by Soori on 18-MAR-2010, to add Submission Name (Report id) to Extended Desc
          --v_attribute10         := v_tax_rate_type;
          v_attribute10 := v_tax_rate_type || '#' || v_submission_name;
        ELSE
          v_attribute10 := v_submission_name;
        END IF;
        /*END : Added by Soori for Japan Requirement, on 05-FEB-2010*/
      
        BEGIN
          /*LOOP BEGIN*/
          IF (rec_concur_data.detail_format_ind = 'HH') THEN
            /*For Header Section*/
            v_batch_id := NULL;
          
            BEGIN
              --howlet
              SELECT substr(v_hh_description,
                            instr(v_hh_description,
                                  'EXPORTID:') + 9),
                     
                     to_date(substr(substr(v_hh_description,
                                           instr(v_hh_description,
                                                 'EXPORTID:') + 9),
                                    -14,
                                    8),
                             'RRRRMMDD')
                INTO v_batch_id,
                     v_export_date
                FROM dual;
            
              debug_message('Batch Number :' || v_batch_id);
              debug_message('Concur Export Date :' || v_export_date);
            
            EXCEPTION
              WHEN no_data_found THEN
                v_err_msg := v_err_msg || ' /' ||
                             'No Export ID Data Exist for Header in the Flat File';
                RAISE e_skip_to_next_rec;
            END;
          
            debug_message('Updating the Batch Number in the Staging table for Lines ');
            BEGIN
            
              UPDATE gerfp_congl_stg
                 SET concur_batch_id    = v_batch_id,
                     concur_export_date = v_export_date
               WHERE concur_req_id = v_conc_request
                 AND concur_batch_id = '-1'
                 AND file_seq = rec_concur_data.file_seq /*Added by Soori on 13-FEB-2010 for Automation*/
                 AND process_flag = 'U'
                 AND err_msg IS NULL;
            
              COMMIT;
            
            EXCEPTION
              WHEN OTHERS THEN
                v_err_msg := v_err_msg || ' /' ||
                             'Exception in Updating the Batch Id in Staging Table : ' ||
                             SQLERRM;
                RAISE e_skip_to_next_rec;
            END;
          
          ELSE
            /*For Detail Section*/
          
            /*Deriving ME+LE+BT+SOB from Concur Mapping form */
            BEGIN
              v_me_code               := NULL;
              v_le_code               := NULL;
              v_book_type             := NULL;
              v_sob_id                := NULL;
              v_sae_offset_account    := NULL;
              v_tax_account           := NULL;
              v_accr_offset_account   := NULL;
              v_conc_suspense_account := NULL;
            
              SELECT DISTINCT xbus.me_code,
                              xbus.le_code,
                              xbus.book_type,
                              xbus.sae_offset_account,
                              xbus.tax_account,
                              xbus.accrual_offset_account,
                              xbus.concur_suspense_account,
                              gsob.set_of_books_id,
                              xbus.cc_sae_offset_account,
                              xbus.cash_adv_account,
                              xbus.wht_account,
                              xbus.alloc_cearing_account,
                              xbus.cash_account
              
                INTO v_me_code,
                     v_le_code,
                     v_book_type,
                     v_sae_offset_account,
                     v_tax_account,
                     v_accr_offset_account,
                     v_conc_suspense_account,
                     v_sob_id,
                     v_cc_sae_offset_account,
                     v_cash_adv_account,
                     v_wht_account,
                     v_alloc_cearing_account,
                     v_cash_account
                FROM apps.xxrfp_concur_bus_map xbus,
                     apps.gl_sets_of_books     gsob
               WHERE xbus.sob_name = gsob.name
                 AND xbus.concur_ledger_code = v_capuser_ap_number
                 AND xbus.enabled_flag = 'Y';
            
            EXCEPTION
              WHEN no_data_found THEN
                debug_message('-> ME+LE+BT+SOB does not exist for given Capuser AP Number - ' ||
                              v_capuser_ap_number);
                v_err_msg := v_err_msg || ' /' ||
                             'ME+LE+BT+SOB does not exist for given Capuser AP Number - ' ||
                             v_capuser_ap_number;
                RAISE e_skip_to_next_rec;
              WHEN too_many_rows THEN
                debug_message('-> More than one ME+LE+BT+SOB exist for given Capuser AP Number - ' ||
                              v_capuser_ap_number);
                v_err_msg := v_err_msg || ' /' ||
                             'More than one ME+LE+BT+SOB exist for given Capuser AP Number - ' ||
                             v_capuser_ap_number;
                RAISE e_skip_to_next_rec;
              WHEN OTHERS THEN
                debug_message('-> Exception in deriving ME+LE+BT+SOB for given Capuser AP Number - ' ||
                              v_capuser_ap_number || ' ->' || SQLERRM);
                v_err_msg := v_err_msg || ' /' ||
                             'Exception in deriving ME+LE+BT+SOB for given Capuser AP Number - ' ||
                             v_capuser_ap_number || ' ->' || SQLERRM;
                RAISE e_skip_to_next_rec;
            END;
          
            /* START : Added by Soori on 11-MAY-2009*/
            -- To Update SOB Id In Staging Table, in order to show in specific error in respective SOB
            BEGIN
            
              UPDATE gerfp_congl_stg
                 SET sob_id = v_sob_id
               WHERE ROWID = rec_concur_data.rowid;
            
              COMMIT;
            EXCEPTION
              WHEN OTHERS THEN
                NULL;
            END;
            /* END : Added by Soori on 11-MAY-2009*/
          
            debug_message(rec_concur_data.stdacctngexport_id || ';' ||
                          rec_concur_data.account_detail_type);
            --howlet 12/OCT/2012
            v_na             := NULL;
            v_ime_code       := NULL;
            v_ile_code       := NULL;
            v_oracle_cc      := NULL;
            v_project        := NULL;
            v_reference      := NULL;
            v_default_cc     := NULL;
            v_offset_account := NULL;
            v_default_cc     := '000000';
            v_offset_ime     := '000000';
            /* Only validate expense account */
            IF rec_concur_data.account_detail_type IN
               ('1',
                '2') THEN
            
              v_offset_account := v_sae_offset_account;
            
              IF instr(v_department,
                       '/') <> 0
                 OR length(v_department) = 12 THEN
                /* CCL value system, no shelton dependence */
                BEGIN
                  SELECT natrual_account,
                         ime_code,
                         ile_code,
                         project
                    INTO v_na,
                         v_ime_code,
                         v_ile_code,
                         v_project_1
                    FROM xxrfp_concur_keyac_map --XXRFP_SHELTON_KEYAC_MAP
                   WHERE concur_category = rtrim(v_category_segment_1)
                     AND concur_ledger_code = rtrim(v_capuser_ap_number)
                     AND enabled_flag = 'Y';
                
                  SELECT gerfp_cc_proj_extend.chk_key_proj_flag(v_na)
                    INTO v_key_flag
                    FROM dual;
                
                  IF v_key_flag = 1
                     AND v_project_1 = '0000000000' THEN
                    RAISE e_flag_proj_nd;
                  END IF;
                
                EXCEPTION
                  WHEN e_flag_proj_nd THEN
                    debug_message('-> The non-default project is required on the NA, IME, ILE with' ||
                                  v_capuser_ap_number ||
                                  ' and Category Seg1 : ' ||
                                  v_category_segment_1);
                    v_err_msg := v_err_msg || ' /' ||
                                 'The non-default project is required on the NA, IME, ILE with' ||
                                 v_capuser_ap_number ||
                                 ' and Category Seg1 : ' ||
                                 v_category_segment_1;
                    RAISE e_skip_to_next_rec;
                  WHEN no_data_found THEN
                  
                    debug_message('-> NA+IME+ILE does not exists for given GLID : ' ||
                                  v_capuser_ap_number ||
                                  ' and Category Seg1 : ' ||
                                  v_category_segment_1);
                    /*Assigning it to Suspense Account when Keyacc fails */
                    debug_message('-> Hence JE is Accounted to Suspense Account : ' ||
                                  v_conc_suspense_account);
                  
                    v_na             := v_conc_suspense_account;
                    v_ime_code       := '000000';
                    v_ile_code       := '000000';
                    v_oracle_cc      := '000000';
                    v_project_1      := '0000000000';
                    v_reference      := '000000';
                    v_keyacc_err_msg := 'NA+IME+ILE does not exists for given GLID : ' ||
                                        v_capuser_ap_number ||
                                        ' and Category Seg1 : ' ||
                                        v_category_segment_1 ||
                                        ' ; Hence JE is Accounted to Suspense Account : ' ||
                                        v_conc_suspense_account;
                    v_no_keyacc_flag := 'Y';
                  
                  WHEN too_many_rows THEN
                    debug_message('-> More than one NA+IME+ILE exist for given GLID : ' ||
                                  v_capuser_ap_number ||
                                  ' and Category Seg1 : ' ||
                                  v_category_segment_1);
                    v_err_msg := v_err_msg || ' /' ||
                                 'More than one NA+IME+ILE exist for given GLID : ' ||
                                 v_capuser_ap_number ||
                                 ' and Category Seg1 : ' ||
                                 v_category_segment_1;
                    RAISE e_skip_to_next_rec;
                  
                  WHEN OTHERS THEN
                    debug_message('-> Exception in deriving NA+IME+ILE for given GLID : ' ||
                                  v_capuser_ap_number ||
                                  ' and Category Seg1 : ' ||
                                  v_category_segment_1 || ' ->' || SQLERRM);
                    v_err_msg := v_err_msg || ' /' ||
                                 'Exception in deriving NA+IME+ILE for given GLID : ' ||
                                 v_capuser_ap_number ||
                                 ' and Category Seg1 : ' ||
                                 v_category_segment_1 || ' ->' || SQLERRM;
                    RAISE e_skip_to_next_rec;
                END;
              
                BEGIN
                  --Ignore the cc while the account is BS account
                  SELECT substr(compiled_value_attributes,
                                5,
                                1)
                    INTO v_acctype
                    FROM fnd_flex_value_sets ffvs,
                         fnd_flex_values     ffv
                   WHERE ffvs.flex_value_set_id = ffv.flex_value_set_id
                     AND ffvs.flex_value_set_name = 'RFP_KEYACCOUNT'
                     AND ffv.flex_value = v_na
                     AND ffv.enabled_flag = 'Y'
                     AND ffv.summary_flag = 'N';
                EXCEPTION
                  WHEN OTHERS THEN
                    debug_message('-> Exception in deriving accout type of NA : ' || v_na ||
                                  ' ->' || SQLERRM);
                    v_err_msg := v_err_msg || ' /' ||
                                 'Exception in deriving accout type of NA : ' || v_na ||
                                 ' ->' || SQLERRM;
                    RAISE e_skip_to_next_rec;
                END;
              
                IF v_no_keyacc_flag = 'Y' THEN
                  v_project := nvl(v_project_1,
                                   '0000000000');
                
                ELSE
                  --If keyac is ok, go ahead for cc block
                
                  IF v_acctype NOT IN ('R',
                                       'E') THEN
                    v_oracle_cc := '000000';
                    v_reference := '000000';
                    v_project   := nvl(v_project_1,
                                       '0000000000');
                  ELSE
                    BEGIN
                      IF instr(v_department,
                               '/') <> 0 THEN
                      
                        v_oracle_cc := substr(v_department,
                                              1,
                                              instr(v_department,
                                                    '/') - 1);
                        v_reference := substr(v_department,
                                              instr(v_department,
                                                    '/') + 1);
                      
                        IF instr(v_reference,
                                 '/') <> 0 THEN
                          v_project   := substr(v_reference,
                                                instr(v_reference,
                                                      '/') + 1);
                          v_reference := substr(v_reference,
                                                1,
                                                instr(v_reference,
                                                      '/') - 1);
                        END IF;
                      END IF;
                    
                      IF (length(v_department) = 12) THEN
                        v_oracle_cc := substr(v_department,
                                              1,
                                              6);
                        v_reference := substr(v_department,
                                              7,
                                              6);
                      END IF;
                    
                      v_oracle_cc := nvl(v_oracle_cc,
                                         '000000');
                      v_reference := nvl(v_reference,
                                         '000000');
                      v_project   := nvl(v_project,
                                         '0000000000');
                    
                    EXCEPTION
                      WHEN OTHERS THEN
                        debug_message('-> Exception on extracting cost center information from ' ||
                                      v_department);
                        v_err_msg := v_err_msg || ' /' ||
                                     'Exception on extracting cost center information from ' ||
                                     v_department;
                        RAISE e_skip_to_next_rec;
                    END;
                  
                    BEGIN
                      SELECT flex_value
                        INTO v_oracle_cc
                        FROM fnd_flex_value_sets ffvs,
                             fnd_flex_values     ffv
                       WHERE ffvs.flex_value_set_id = ffv.flex_value_set_id
                         AND ffvs.flex_value_set_name = 'RFP_COSTCENTER'
                         AND ffv.flex_value = v_oracle_cc
                         AND ffv.enabled_flag = 'Y'
                         AND ffv.summary_flag = 'N';
                    EXCEPTION
                      WHEN no_data_found THEN
                        /*
                        debug_message('-> The CC value:' || v_oracle_cc || ' of department:'|| v_department ||' does not exist in Cost center valueset.');
                        v_err_msg := v_err_msg||' /'||'The CC value:' || v_oracle_cc || ' from '|| v_department ||' does not exist in Cost center valueset.';
                        RAISE e_skip_to_next_rec;
                        */
                      
                        debug_message('-> The CC value:' || v_oracle_cc ||
                                      ' of department:' || v_department ||
                                      ' does not exist in Cost center valueset.'); /*Assigning it to Suspense Account*/
                        debug_message('-> Hence JE is Accounted to Suspense Account : ' ||
                                      v_conc_suspense_account);
                        v_cc_err_msg := 'The CC value:' || v_oracle_cc ||
                                        ' of department:' || v_department ||
                                        ' does not exist in Cost center valueset; Hence JE is Accounted to Suspense Account : ' ||
                                        v_conc_suspense_account;
                      
                        v_na        := v_conc_suspense_account;
                        v_ime_code  := '000000';
                        v_ile_code  := '000000';
                        v_oracle_cc := '000000';
                        v_project   := '0000000000';
                        v_reference := '000000';
                      
                        v_no_cc_flag := 'Y';
                      
                      WHEN OTHERS THEN
                        debug_message('-> Exception in validating CC value:' ||
                                      v_oracle_cc || ' for ' ||
                                      v_department || ' ->' || SQLERRM);
                        v_err_msg := v_err_msg || ' /' ||
                                     'Exception in validating CC value:' ||
                                     v_oracle_cc || ' for ' || v_department ||
                                     ' ->' || SQLERRM;
                        RAISE e_skip_to_next_rec;
                    END;
                  
                    BEGIN
                      SELECT flex_value
                        INTO v_project
                        FROM fnd_flex_value_sets ffvs,
                             fnd_flex_values     ffv
                       WHERE ffvs.flex_value_set_id = ffv.flex_value_set_id
                         AND ffvs.flex_value_set_name = 'RFP_PROJECT'
                         AND ffv.flex_value = v_project
                         AND ffv.enabled_flag = 'Y'
                         AND ffv.summary_flag = 'N';
                    
                    EXCEPTION
                      WHEN no_data_found THEN
                        /*
                        debug_message('-> The project value:' || v_project || ' of department:'|| v_department ||' does not exist in project valueset.');
                        v_err_msg := v_err_msg||' /'||'The project value:' || v_project || ' from '|| v_department ||' does not exist in project valueset.';
                        RAISE e_skip_to_next_rec;
                        */
                      
                        debug_message('-> The project value:' || v_project ||
                                      ' of department:' || v_department ||
                                      ' does not exist in project valueset.');
                        /*Assigning it to Suspense Account*/
                        debug_message('-> Hence JE is Accounted to Suspense Account : ' ||
                                      v_conc_suspense_account);
                      
                        v_cc_err_msg := 'The project value:' || v_project ||
                                        ' from ' || v_department ||
                                        ' does not exist in project valueset; Hence JE is Accounted to Suspense Account : ' ||
                                        v_conc_suspense_account;
                      
                        v_na         := v_conc_suspense_account;
                        v_ime_code   := '000000';
                        v_ile_code   := '000000';
                        v_oracle_cc  := '000000';
                        v_project    := '0000000000';
                        v_reference  := '000000';
                        v_no_cc_flag := 'Y';
                      
                      WHEN OTHERS THEN
                        debug_message('-> Exception in validating project value:' ||
                                      v_project || ' for ' || v_department ||
                                      ' ->' || SQLERRM);
                        v_err_msg := v_err_msg || ' /' ||
                                     'Exception in validating project value:' ||
                                     v_project || ' for ' || v_department ||
                                     ' ->' || SQLERRM;
                        RAISE e_skip_to_next_rec;
                    END;
                  
                    BEGIN
                      SELECT flex_value
                        INTO v_reference
                        FROM fnd_flex_value_sets ffvs,
                             fnd_flex_values     ffv
                       WHERE ffvs.flex_value_set_id = ffv.flex_value_set_id
                         AND ffvs.flex_value_set_name = 'RFP_REF'
                         AND ffv.flex_value = v_reference
                         AND ffv.enabled_flag = 'Y'
                         AND ffv.summary_flag = 'N';
                    
                    EXCEPTION
                      WHEN no_data_found THEN
                        /*
                        debug_message('-> The reference value:' || v_reference || ' of department:'|| v_department ||' does not exist in reference valueset.');
                        v_err_msg := v_err_msg||' /'||'The reference value:' || v_reference || ' of department: '|| v_department ||' does not exist in reference valueset.';
                        RAISE e_skip_to_next_rec;
                        */
                      
                        debug_message('-> The reference value:' ||
                                      v_reference || ' of department:' ||
                                      v_department ||
                                      ' does not exist in reference valueset.'); /*Assigning it to Suspense Account*/
                        debug_message('-> Hence JE is Accounted to Suspense Account : ' ||
                                      v_conc_suspense_account);
                      
                        v_cc_err_msg := 'The reference value:' ||
                                        v_reference || ' of department:' ||
                                        v_department ||
                                        ' does not exist in reference valueset; Hence JE is Accounted to Suspense Account : ' ||
                                        v_conc_suspense_account;
                      
                        v_na        := v_conc_suspense_account;
                        v_ime_code  := '000000';
                        v_ile_code  := '000000';
                        v_oracle_cc := '000000';
                        v_project   := '0000000000';
                        v_reference := '000000';
                      
                        v_no_cc_flag := 'Y';
                      
                      WHEN OTHERS THEN
                        debug_message('-> Exception in validating reference value:' ||
                                      v_reference || ' of department:' ||
                                      v_department || ' ->' || SQLERRM);
                        v_err_msg := v_err_msg || ' /' ||
                                     'Exception in validating reference value:' ||
                                     v_reference || ' of department:' ||
                                     v_department || ' ->' || SQLERRM;
                        RAISE e_skip_to_next_rec;
                    END;
                  
                    IF v_no_cc_flag = 'N' THEN
                      BEGIN
                        SELECT gerfp_cc_proj_extend.chk_cc_proj_flag(v_oracle_cc)
                          INTO p_flag
                          FROM dual;
                      
                        IF p_flag = -1
                           AND v_project <> '0000000000' THEN
                          IF v_key_flag = -1 THEN
                            RAISE e_flag;
                          ELSIF v_key_flag = 0
                                AND v_project_1 <> '0000000000' THEN
                            RAISE e_flag_proj_d;
                          END IF;
                        ELSIF p_flag = -1
                              AND v_project = '0000000000' THEN
                          RAISE e_flag_proj_nd_c;
                        END IF;
                      
                        SELECT decode(p_flag,
                                      '-1',
                                      v_project,
                                      '0',
                                      v_project_1)
                          INTO v_project
                          FROM dual;
                      
                      EXCEPTION
                        WHEN e_flag THEN
                          debug_message('-> Invalid entry as Proj Req flag is Yes at Cost Center and Account Level' ||
                                        v_capuser_ap_number ||
                                        ' and Category Seg1 : ' ||
                                        v_category_segment_1);
                          v_err_msg := v_err_msg || ' /' ||
                                       'Invalid entry as Proj Req flag is Yes at Cost Center and Account Level' ||
                                       v_capuser_ap_number ||
                                       ' and Category Seg1 : ' ||
                                       v_category_segment_1;
                          RAISE e_skip_to_next_rec;
                        WHEN e_flag_proj_d THEN
                          debug_message('-> The non-default project is not allowed on the NA, IME, ILE with' ||
                                        v_capuser_ap_number ||
                                        ' and Category Seg1 : ' ||
                                        v_category_segment_1);
                          v_err_msg := v_err_msg || ' /' ||
                                       'The non-default project is not allowed on the NA, IME, ILE with' ||
                                       v_capuser_ap_number ||
                                       ' and Category Seg1 : ' ||
                                       v_category_segment_1;
                          RAISE e_skip_to_next_rec;
                        WHEN e_flag_proj_nd_c THEN
                          debug_message('-> The non-default project is required on cost center:' ||
                                        v_oracle_cc);
                          v_err_msg := v_err_msg || ' /' ||
                                       'The non-default project is required on cost center:' ||
                                       v_oracle_cc;
                          RAISE e_skip_to_next_rec;
                      END;
                    END IF;
                  END IF;
                END IF;
                --If keyac is ok, end for go ahead for cc block
              ELSE
                /* CCL value system converted from shelton map */
              
                /*Derive Shelton Ledger fron Shelton BUS Mapping Form*/
                BEGIN
                  SELECT shelton_company_code
                    INTO v_shltn_code
                    FROM xxrfp_shelton_bus_map
                   WHERE me_code = v_me_code
                     AND le_code = v_le_code
                     AND book_type = v_book_type;
                
                  IF v_shltn_code IS NULL THEN
                    RAISE e_shelton_bus;
                  END IF;
                
                EXCEPTION
                  WHEN e_shelton_bus THEN
                    debug_message('-> Shelton Ledger Code is blank for given ME+LE+BT Combination, ME : ' ||
                                  v_me_code || ' LE : ' || v_le_code ||
                                  'and Book Type : ' || v_book_type);
                    v_err_msg := v_err_msg || ' /' ||
                                 'Shelton Ledger Code is blank for given ME+LE+BT Combination, ME : ' ||
                                 v_me_code || ' LE : ' || v_le_code ||
                                 'and Book Type : ' || v_book_type;
                    RAISE e_skip_to_next_rec;
                  
                  WHEN no_data_found THEN
                    debug_message('-> Shelton Ledger Code does not exists for given ME+LE+BT Combination, ME : ' ||
                                  v_me_code || ' LE : ' || v_le_code ||
                                  'and Book Type : ' || v_book_type);
                    v_err_msg := v_err_msg || ' /' ||
                                 'Shelton Ledger Code does not exists for given ME+LE+BT Combination, ME : ' ||
                                 v_me_code || ' LE : ' || v_le_code ||
                                 'and Book Type : ' || v_book_type;
                    RAISE e_skip_to_next_rec;
                  WHEN too_many_rows THEN
                    debug_message('-> More than one Shelton Ledger Code exist for given ME+LE+BT Combination, ME : ' ||
                                  v_me_code || ' LE : ' || v_le_code ||
                                  'and Book Type : ' || v_book_type);
                    v_err_msg := v_err_msg || ' /' ||
                                 'More than one Shelton Ledger Code exist for given ME+LE+BT Combination, ME : ' ||
                                 v_me_code || ' LE : ' || v_le_code ||
                                 'and Book Type : ' || v_book_type;
                    RAISE e_skip_to_next_rec;
                  WHEN OTHERS THEN
                    debug_message('-> Exception in deriving Shelton Ledger Code for given ME+LE+BT Combination, ME : ' ||
                                  v_me_code || ' LE : ' || v_le_code ||
                                  'and Book Type : ' || v_book_type ||
                                  ' ->' || SQLERRM);
                    v_err_msg := v_err_msg || ' /' ||
                                 'Exception in deriving Shelton Ledger Code for given ME+LE+BT Combination, ME : ' ||
                                 v_me_code || ' LE : ' || v_le_code ||
                                 'and Book Type : ' || v_book_type || ' ->' ||
                                 SQLERRM;
                    RAISE e_skip_to_next_rec;
                END;
              
                /*Deriving NA+IME+ILE from Mapping form */
                BEGIN
                  v_na       := NULL;
                  v_ime_code := NULL;
                  v_ile_code := NULL;
                
                  --added by Kishore Variganji on 10-MAY-2010 as the Extend of Concur Key Mapping to Project Code
                  gerfp_cc_proj_extend.conc_keyac_proj_inbound(v_capuser_ap_number,
                                                               TRIM(v_department),
                                                               TRIM(v_category_segment_1),
                                                               v_na,
                                                               v_ime_code,
                                                               v_ile_code,
                                                               v_project_1,
                                                               p_flag,
                                                               v_keyacproj_code);
                
                  SELECT gerfp_cc_proj_extend.chk_key_proj_flag(v_na)
                    INTO v_key_flag
                    FROM dual;
                  IF p_flag = -1 THEN
                    IF v_key_flag = -1 THEN
                      RAISE e_flag;
                      ---FND_FILE.PUT_LINE (FND_FILE.OUTPUT,'Invalid entry as Proj Req flag is Yes at Cost Center and Account Level');
                    ELSIF v_key_flag = 0
                          AND v_keyacproj_code <> '0000000000' THEN
                      RAISE e_flag_proj_d;
                    END IF;
                  END IF;
                
                EXCEPTION
                  WHEN e_flag THEN
                    debug_message('-> Invalid entry as Proj Req flag is Yes at Cost Center and Account Level' ||
                                  v_capuser_ap_number ||
                                  ' and Category Seg1 : ' ||
                                  v_category_segment_1);
                    v_err_msg := v_err_msg || ' /' ||
                                 'Invalid entry as Proj Req flag is Yes at Cost Center and Account Level' ||
                                 v_capuser_ap_number ||
                                 ' and Category Seg1 : ' ||
                                 v_category_segment_1;
                    RAISE e_skip_to_next_rec;
                  WHEN e_flag_proj_d THEN
                    debug_message('-> The non-default project is not allowed on the NA, IME, ILE with' ||
                                  v_capuser_ap_number ||
                                  ' and Category Seg1 : ' ||
                                  v_category_segment_1);
                    v_err_msg := v_err_msg || ' /' ||
                                 'The non-default project is not allowed on the NA, IME, ILE with' ||
                                 v_capuser_ap_number ||
                                 ' and Category Seg1 : ' ||
                                 v_category_segment_1;
                    RAISE e_skip_to_next_rec;
                  WHEN no_data_found THEN
                  
                    debug_message('-> NA+IME+ILE does not exists for given GLID : ' ||
                                  v_capuser_ap_number ||
                                  ' and Category Seg1 : ' ||
                                  v_category_segment_1);
                    /*Assigning it to Suspense Account when Keyacc fails */
                    debug_message('-> Hence JE is Accounted to Suspense Account : ' ||
                                  v_conc_suspense_account);
                  
                    v_na             := v_conc_suspense_account;
                    v_ime_code       := '000000';
                    v_ile_code       := '000000';
                    v_oracle_cc      := '000000';
                    v_project        := '0000000000';
                    v_reference      := '000000';
                    v_keyacc_err_msg := 'NA+IME+ILE does not exists for given GLID : ' ||
                                        v_capuser_ap_number ||
                                        ' and Category Seg1 : ' ||
                                        v_category_segment_1 ||
                                        ' ; Hence JE is Accounted to Suspense Account : ' ||
                                        v_conc_suspense_account;
                    v_no_keyacc_flag := 'Y';
                  
                  WHEN too_many_rows THEN
                    debug_message('-> More than one NA+IME+ILE exist for given GLID : ' ||
                                  v_capuser_ap_number ||
                                  ' and Category Seg1 : ' ||
                                  v_category_segment_1);
                    v_err_msg := v_err_msg || ' /' ||
                                 'More than one NA+IME+ILE exist for given GLID : ' ||
                                 v_capuser_ap_number ||
                                 ' and Category Seg1 : ' ||
                                 v_category_segment_1;
                    RAISE e_skip_to_next_rec;
                  
                  WHEN OTHERS THEN
                    debug_message('-> Exception in deriving NA+IME+ILE for given GLID : ' ||
                                  v_capuser_ap_number ||
                                  ' and Category Seg1 : ' ||
                                  v_category_segment_1 || ' ->' || SQLERRM);
                    v_err_msg := v_err_msg || ' /' ||
                                 'Exception in deriving NA+IME+ILE for given GLID : ' ||
                                 v_capuser_ap_number ||
                                 ' and Category Seg1 : ' ||
                                 v_category_segment_1 || ' ->' || SQLERRM;
                    RAISE e_skip_to_next_rec;
                END;
              
                BEGIN
                  --Ignore the cc while the account is BS account
                  SELECT substr(compiled_value_attributes,
                                5,
                                1)
                    INTO v_acctype
                    FROM fnd_flex_value_sets ffvs,
                         fnd_flex_values     ffv
                   WHERE ffvs.flex_value_set_id = ffv.flex_value_set_id
                     AND ffvs.flex_value_set_name = 'RFP_KEYACCOUNT'
                     AND ffv.flex_value = v_na
                     AND ffv.enabled_flag = 'Y'
                     AND ffv.summary_flag = 'N';
                EXCEPTION
                  WHEN OTHERS THEN
                    debug_message('-> Exception in deriving accout type of NA : ' || v_na ||
                                  ' ->' || SQLERRM);
                    v_err_msg := v_err_msg || ' /' ||
                                 'Exception in deriving accout type of NA : ' || v_na ||
                                 ' ->' || SQLERRM;
                    RAISE e_skip_to_next_rec;
                END;
              
                IF v_no_keyacc_flag = 'Y' THEN
                  v_project := nvl(v_project_1,
                                   '0000000000');
                ELSE
                  IF v_acctype NOT IN ('R',
                                       'E') THEN
                    v_oracle_cc := '000000';
                    v_reference := '000000';
                    v_project   := nvl(nvl(v_project_1,
                                           v_keyacproj_code),
                                       '0000000000');
                  ELSE
                    /*Deriving CC+PROJ+REF from Shelton CC Mapping form */
                    BEGIN
                      v_no_cc_flag := 'N';
                      v_oracle_cc  := NULL;
                      v_project    := NULL;
                      v_reference  := NULL;
                    
                      --Added by Kishore Variganji on 10-MAY-2010 as the Extend of CC Mapping to Project Code
                      gerfp_cc_proj_extend.shlt_cc_proj_inbound(v_shltn_code,
                                                                TRIM(v_department),
                                                                v_oracle_cc,
                                                                v_reference,
                                                                v_project,
                                                                p_flag);
                    
                      IF p_flag = -1
                         AND v_project = '0000000000' THEN
                        RAISE e_cc_proj;
                      END IF;
                    
                      SELECT decode(p_flag,
                                    '-1',
                                    v_project,
                                    '0',
                                    v_project_1)
                        INTO v_project
                        FROM dual;
                    
                    EXCEPTION
                      WHEN e_cc_proj THEN
                        debug_message('-> Invalid Project for Shelton ledger:' ||
                                      v_shltn_code || ' and Shelton CC : ' ||
                                      v_department);
                        /*Assigning it to Suspense Account*/
                        v_err_msg := v_err_msg || ' /' ||
                                     'Invalid Project for Shelton ledger:' ||
                                     v_shltn_code || ' and Shelton CC : ' ||
                                     v_department;
                        RAISE e_skip_to_next_rec;
                      
                      WHEN no_data_found THEN
                        debug_message('-> CC+PROJ+REF does not exists for given Shelton Code : ' ||
                                      v_shltn_code || ' and Shelton CC : ' ||
                                      v_department);
                        /*Assigning it to Suspense Account*/
                        debug_message('-> Hence JE is Accounted to Suspense Account : ' ||
                                      v_conc_suspense_account);
                      
                        v_na         := v_conc_suspense_account;
                        v_ime_code   := '000000';
                        v_ile_code   := '000000';
                        v_oracle_cc  := '000000';
                        v_project    := '0000000000';
                        v_reference  := '000000';
                        v_cc_err_msg := 'CC+PROJ+REF does not exists for given Shelton Code : ' ||
                                        v_shltn_code ||
                                        ' and Shelton CC : ' ||
                                        v_department ||
                                        ' ; Hence JE is Accounted to Suspense Account : ' ||
                                        v_conc_suspense_account;
                        v_no_cc_flag := 'Y';
                      
                      --FND_FILE.PUT_LINE (FND_FILE.OUTPUT,'5124'||v_department);
                      WHEN too_many_rows THEN
                        debug_message('-> More than one CC+PROJ+REF exist for given Shelton Code : ' ||
                                      v_shltn_code || ' and Shelton CC : ' ||
                                      v_department);
                        v_err_msg := v_err_msg || ' /' ||
                                     'More than one CC+PROJ+REF exist for given Shelton Code : ' ||
                                     v_shltn_code || ' and Shelton CC : ' ||
                                     v_department;
                        RAISE e_skip_to_next_rec;
                      WHEN OTHERS THEN
                        debug_message('-> Exception in deriving CC+PROJ+REF for given Shelton Code : ' ||
                                      v_shltn_code || ' and Shelton CC : ' ||
                                      v_department || ' ->' || SQLERRM);
                        v_err_msg := v_err_msg || ' /' ||
                                     'Exception in deriving CC+PROJ+REF for given Shelton Code : ' ||
                                     v_shltn_code || ' and Shelton CC : ' ||
                                     v_department || ' ->' || SQLERRM;
                        RAISE e_skip_to_next_rec;
                    END;
                  END IF;
                END IF;
              END IF;
            
              --howlet 12/OCT/2012
            ELSIF rec_concur_data.account_detail_type = 26 THEN
            
              v_na             := v_cash_account;
              v_ime_code       := '000000';
              v_ile_code       := '000000';
              v_oracle_cc      := '000000';
              v_project        := '0000000000';
              v_reference      := '000000';
              v_default_cc     := '000000';
              v_offset_account := v_sae_offset_account;
            
              BEGIN
                --Ignore the cc while the account is BS account
                SELECT substr(compiled_value_attributes,
                              5,
                              1)
                  INTO v_acctype
                  FROM fnd_flex_value_sets ffvs,
                       fnd_flex_values     ffv
                 WHERE ffvs.flex_value_set_id = ffv.flex_value_set_id
                   AND ffvs.flex_value_set_name = 'RFP_KEYACCOUNT'
                   AND ffv.flex_value = v_na
                   AND ffv.enabled_flag = 'Y'
                   AND ffv.summary_flag = 'N';
              EXCEPTION
                WHEN OTHERS THEN
                  debug_message('-> Exception in deriving accout type of NA : ' || v_na ||
                                ' ->' || SQLERRM);
                  v_err_msg := v_err_msg || ' /' ||
                               'Exception in deriving accout type of NA : ' || v_na ||
                               ' ->' || SQLERRM;
                  RAISE e_skip_to_next_rec;
              END;
            
              --howlet 12/OCT/2012
            ELSIF rec_concur_data.account_detail_type = 27 THEN
            
              v_na             := v_cash_account;
              v_ime_code       := '000000';
              v_ile_code       := '000000';
              v_oracle_cc      := '000000';
              v_project        := '0000000000';
              v_reference      := '000000';
              v_offset_account := v_cc_sae_offset_account;
            
              IF (v_capuser_ap_number IN ('MNTR01',
                                          'MNCO01')) THEN
                v_offset_ime := 'GGMN01';
              END IF;
            
              BEGIN
                --Ignore the cc while the account is BS account
                SELECT substr(compiled_value_attributes,
                              5,
                              1)
                  INTO v_acctype
                  FROM fnd_flex_value_sets ffvs,
                       fnd_flex_values     ffv
                 WHERE ffvs.flex_value_set_id = ffv.flex_value_set_id
                   AND ffvs.flex_value_set_name = 'RFP_KEYACCOUNT'
                   AND ffv.flex_value = v_na
                   AND ffv.enabled_flag = 'Y'
                   AND ffv.summary_flag = 'N';
              EXCEPTION
                WHEN OTHERS THEN
                  debug_message('-> Exception in deriving accout type of NA : ' || v_na ||
                                ' ->' || SQLERRM);
                  v_err_msg := v_err_msg || ' /' ||
                               'Exception in deriving accout type of NA : ' || v_na ||
                               ' ->' || SQLERRM;
                  RAISE e_skip_to_next_rec;
              END;
            
            ELSE
              debug_message('-> Invalid AD Type:' ||
                            rec_concur_data.account_detail_type);
              v_err_msg := v_err_msg || ' /' || '-> Invalid AD Type:' ||
                           rec_concur_data.account_detail_type;
              RAISE e_skip_to_next_rec;
            END IF;
          
            /* Added by george for ACCOUNT_DETAIL_TYPE 
            v_sae_offset_account,
            v_tax_account,
            v_accr_offset_account,
            v_conc_suspense_account,
            v_sob_id,
            v_CC_SAE_OFFSET_ACCOUNT,
            v_CASH_ADV_ACCOUNT,
            v_WHT_ACCOUNT,
            v_ALLOC_CEARING_ACCOUNT
            */
          
            --HOWLET 2-JUN-2012
            IF v_na = v_conc_suspense_account
               AND v_capuser_ap_number = 'PHCF01' THEN
              v_oracle_cc := 'NCDZM2';
            END IF;
          
            IF (v_capuser_ap_number = 'PHCF01') THEN
              v_default_cc := 'NCDZM2';
            END IF;
          
            v_item_acc := t_item_acc();
          
            CASE
              WHEN rec_concur_data.account_detail_type IN
                   ('1',
                    '26',
                    '27') THEN
                v_item_acc.extend(4);
              
                v_item_acc(1) := t_acc(v_me_code,
                                       v_le_code,
                                       v_book_type,
                                       v_na,
                                       v_oracle_cc,
                                       v_project,
                                       v_ime_code,
                                       v_ile_code,
                                       v_reference);
                --debug_message(v_Item_ACC(1)(1) || '.' || v_Item_ACC(1)(2)|| '.' || v_Item_ACC(1)(3)|| '.' || v_Item_ACC(1)(4)|| '.' || v_Item_ACC(1)(5)|| '.' || v_Item_ACC(1)(6)|| '.' || v_Item_ACC(1)(7)|| '.' || v_Item_ACC(1)(8)|| '.' || v_Item_ACC(1)(9));                         
                v_item_acc(2) := t_acc(v_me_code,
                                       v_le_code,
                                       v_book_type,
                                       v_tax_account,
                                       v_default_cc,
                                       '0000000000',
                                       '000000',
                                       '000000',
                                       '000000');
                v_item_acc(3) := t_acc(v_me_code,
                                       v_le_code,
                                       v_book_type,
                                       v_wht_account,
                                       v_default_cc,
                                       '0000000000',
                                       '000000',
                                       '000000',
                                       '000000');
              
                v_item_acc(4) := t_acc(v_me_code,
                                       v_le_code,
                                       v_book_type,
                                       v_offset_account,
                                       v_default_cc,
                                       '0000000000',
                                       v_offset_ime,
                                       '000000',
                                       '000000');
              
            --debug_message(v_Item_ACC(4)(1) || '.' || v_Item_ACC(4)(2)|| '.' || v_Item_ACC(4)(3)|| '.' || v_Item_ACC(4)(4)|| '.' || v_Item_ACC(4)(5)|| '.' || v_Item_ACC(4)(6)|| '.' || v_Item_ACC(4)(7)|| '.' || v_Item_ACC(4)(8)|| '.' || v_Item_ACC(4)(9));                         
            
              WHEN rec_concur_data.account_detail_type = '2' THEN
                v_item_acc.extend(4);
              
                v_item_acc(1) := t_acc(v_me_code,
                                       v_le_code,
                                       v_book_type,
                                       v_na,
                                       v_oracle_cc,
                                       v_project,
                                       v_ime_code,
                                       v_ile_code,
                                       v_reference);
                --debug_message(v_Item_ACC(1)(1) || '.' || v_Item_ACC(1)(2)|| '.' || v_Item_ACC(1)(3)|| '.' || v_Item_ACC(1)(4)|| '.' || v_Item_ACC(1)(5)|| '.' || v_Item_ACC(1)(6)|| '.' || v_Item_ACC(1)(7)|| '.' || v_Item_ACC(1)(8)|| '.' || v_Item_ACC(1)(9)); 
                v_item_acc(2) := t_acc(v_me_code,
                                       v_le_code,
                                       v_book_type,
                                       v_tax_account,
                                       v_default_cc,
                                       '0000000000',
                                       '000000',
                                       '000000',
                                       '000000');
                v_item_acc(3) := t_acc(v_me_code,
                                       v_le_code,
                                       v_book_type,
                                       v_wht_account,
                                       v_default_cc,
                                       '0000000000',
                                       '000000',
                                       '000000',
                                       '000000');
              
                v_item_acc(4) := t_acc(v_me_code,
                                       v_le_code,
                                       v_book_type,
                                       nvl(v_cc_sae_offset_account,
                                           v_sae_offset_account),
                                       v_default_cc,
                                       '0000000000',
                                       '000000',
                                       '000000',
                                       '000000');
              
            --debug_message(v_Item_ACC(4)(1) || '.' || v_Item_ACC(4)(2)|| '.' || v_Item_ACC(4)(3)|| '.' || v_Item_ACC(4)(4)|| '.' || v_Item_ACC(4)(5)|| '.' || v_Item_ACC(4)(6)|| '.' || v_Item_ACC(4)(7)|| '.' || v_Item_ACC(4)(8)|| '.' || v_Item_ACC(4)(9));                         
              ELSE
                debug_message('-> Invalid AD Type:' ||
                              rec_concur_data.account_detail_type);
                v_err_msg := v_err_msg || ' /' || '-> Invalid AD Type:' ||
                             rec_concur_data.account_detail_type;
                RAISE e_skip_to_next_rec;
            END CASE;
          
            v_concur_export_date := v_export_date;
          
            --howlet 12/OCT/2012 currency
          
            IF (v_capuser_ap_number = 'MNTR01') THEN
              v_currency := 'MNT';
              BEGIN
              
                SELECT gdr.conversion_rate
                  INTO l_mor
                  FROM apps.gl_daily_rates            gdr,
                       apps.gl_daily_conversion_types gdct
                 WHERE gdr.conversion_type = gdct.conversion_type
                   AND gdct.user_conversion_type = 'MOR'
                   AND gdr.from_currency = 'USD'
                   AND gdr.to_currency = 'MNT'
                   AND gdr.conversion_date = v_concur_export_date;
              EXCEPTION
                WHEN OTHERS THEN
                  debug_message('-> Exception in getting rate from USD to MNT on : ' ||
                                v_concur_export_date || ' ->' || SQLERRM);
                  v_err_msg := v_err_msg || ' /' ||
                               'Exception in getting rate from USD to MNT on : ' ||
                               v_concur_export_date || ' ->' || SQLERRM;
                  RAISE e_skip_to_next_rec;
              END;
            
              v_home_net_amount      := round(v_home_net_amount * l_mor,
                                              2);
              v_gross_reclaim_amount := round(v_gross_reclaim_amount *
                                              l_mor,
                                              2);
              v_sae_float_1          := round(v_sae_float_1 * l_mor,
                                              2);
            
            ELSE
              v_currency := v_home_iso_currency_code;
            END IF;
          
            --debug_message(v_home_net_amount || ';' || v_gross_reclaim_amount || ',' || v_SAE_FLOAT_1);
          
            /*Check the Data and populate interface for Credit or Debit amount*/
            --IF (v_debit_credit_indicator = 'DR') then
            --Items, home_net_amount, home_reclaim_amount= WTH, SAE off 
            /*DR: Item1, home_net_amount */
            INSERT INTO gl_interface
              (status,
               accounting_date,
               currency_code,
               actual_flag,
               user_je_category_name,
               user_je_source_name,
               segment1,
               segment2,
               segment3,
               segment4,
               segment5,
               segment6,
               segment7,
               segment8,
               segment9,
               segment10,
               segment11,
               entered_dr,
               entered_cr,
               accounted_dr,
               accounted_cr,
               reference6,
               reference10,
               attribute10,
               currency_conversion_date,
               user_currency_conversion_type,
               currency_conversion_rate,
               created_by,
               date_created,
               group_id,
               set_of_books_id)
            VALUES
              ('NEW',
               v_concur_export_date,
               v_currency,
               'A',
               'Concur SAE',
               'Concur',
               v_item_acc(1) (1),
               v_item_acc(1) (2),
               v_item_acc(1) (3),
               v_item_acc(1) (4),
               v_item_acc(1) (5),
               v_item_acc(1) (6),
               v_item_acc(1) (7),
               v_item_acc(1) (8),
               v_item_acc(1) (9),
               '0',
               '0',
               decode(v_debit_credit_indicator,
                      'DR',
                      v_home_net_amount,
                      NULL), /*entered dr */
               decode(v_debit_credit_indicator,
                      'DR',
                      NULL,
                      v_home_net_amount), /*entered cr */
               NULL, /*accounted dr */
               NULL, /*accounted_cr*/
               '"' || v_batch_id || '"',
               v_reference10,
               v_attribute10,
               v_concur_export_date,
               'MOR',
               NULL,
               fnd_global.user_id,
               SYSDATE,
               g_group_id,
               v_sob_id);
          
            /*DR : If Tax Amt Exists*/
            IF (nvl(v_gross_reclaim_amount,
                    0) <> 0) THEN
              INSERT INTO gl_interface
                (status,
                 accounting_date,
                 currency_code,
                 actual_flag,
                 user_je_category_name,
                 user_je_source_name,
                 segment1,
                 segment2,
                 segment3,
                 segment4,
                 segment5,
                 segment6,
                 segment7,
                 segment8,
                 segment9,
                 segment10,
                 segment11,
                 entered_dr,
                 entered_cr,
                 accounted_dr,
                 accounted_cr,
                 reference6,
                 reference10,
                 attribute10,
                 currency_conversion_date,
                 user_currency_conversion_type,
                 currency_conversion_rate,
                 created_by,
                 date_created,
                 group_id,
                 set_of_books_id)
              VALUES
                ('NEW',
                 v_concur_export_date,
                 v_currency,
                 'A',
                 'Concur SAE',
                 'Concur',
                 v_item_acc(2) (1),
                 v_item_acc(2) (2),
                 v_item_acc(2) (3),
                 v_item_acc(2) (4),
                 v_item_acc(2) (5),
                 v_item_acc(2) (6),
                 v_item_acc(2) (7),
                 v_item_acc(2) (8),
                 v_item_acc(2) (9),
                 '0',
                 '0',
                 decode(v_debit_credit_indicator,
                        'DR',
                        v_gross_reclaim_amount,
                        NULL), /*entered dr */
                 decode(v_debit_credit_indicator,
                        'DR',
                        NULL,
                        v_gross_reclaim_amount), /*entered cr */
                 NULL, /*accounted dr */
                 NULL, /*accounted_cr*/
                 --                         'CONC2GL Batch Number '||'"'||v_batch_id||'"',
                 '"' || v_batch_id || '"',
                 v_reference10,
                 v_attribute10,
                 v_concur_export_date,
                 'MOR',
                 NULL,
                 fnd_global.user_id,
                 SYSDATE,
                 g_group_id,
                 v_sob_id);
            END IF;
          
            /*DR : If WHT Exists*/
            IF (nvl(v_sae_float_1,
                    0) <> 0) THEN
            
              INSERT INTO gl_interface
                (status,
                 accounting_date,
                 currency_code,
                 actual_flag,
                 user_je_category_name,
                 user_je_source_name,
                 segment1,
                 segment2,
                 segment3,
                 segment4,
                 segment5,
                 segment6,
                 segment7,
                 segment8,
                 segment9,
                 segment10,
                 segment11,
                 entered_dr,
                 entered_cr,
                 accounted_dr,
                 accounted_cr,
                 reference6,
                 reference10,
                 attribute10,
                 currency_conversion_date,
                 user_currency_conversion_type,
                 currency_conversion_rate,
                 created_by,
                 date_created,
                 group_id,
                 set_of_books_id)
              VALUES
                ('NEW',
                 v_concur_export_date,
                 v_currency,
                 'A',
                 'Concur SAE',
                 'Concur',
                 v_item_acc(3) (1),
                 v_item_acc(3) (2),
                 v_item_acc(3) (3),
                 v_item_acc(3) (4),
                 v_item_acc(3) (5),
                 v_item_acc(3) (6),
                 v_item_acc(3) (7),
                 v_item_acc(3) (8),
                 v_item_acc(3) (9),
                 '0',
                 '0',
                 decode(v_debit_credit_indicator,
                        'DR',
                        NULL,
                        v_sae_float_1), /*entered dr */
                 decode(v_debit_credit_indicator,
                        'DR',
                        v_sae_float_1,
                        NULL), /*entered cr */
                 NULL, /*accounted dr */
                 NULL, /*accounted_cr*/
                 --                         'CONC2GL Batch Number '||'"'||v_batch_id||'"',
                 '"' || v_batch_id || '"',
                 v_reference10,
                 v_attribute10,
                 v_concur_export_date,
                 'MOR',
                 NULL,
                 fnd_global.user_id,
                 SYSDATE,
                 g_group_id,
                 v_sob_id);
            
            END IF;
          
            /*DR : Create a Credit line for total amt*/
            v_tot_cr_amt := v_home_net_amount + v_gross_reclaim_amount -
                            v_sae_float_1;
          
            INSERT INTO gl_interface
              (status,
               accounting_date,
               currency_code,
               actual_flag,
               user_je_category_name,
               user_je_source_name,
               segment1,
               segment2,
               segment3,
               segment4,
               segment5,
               segment6,
               segment7,
               segment8,
               segment9,
               segment10,
               segment11,
               entered_dr,
               entered_cr,
               accounted_dr,
               accounted_cr,
               reference6,
               reference10,
               attribute10,
               currency_conversion_date,
               user_currency_conversion_type,
               currency_conversion_rate,
               created_by,
               date_created,
               group_id,
               set_of_books_id)
            VALUES
              ('NEW',
               v_concur_export_date,
               v_currency,
               'A',
               'Concur SAE',
               'Concur',
               v_item_acc(4) (1),
               v_item_acc(4) (2),
               v_item_acc(4) (3),
               v_item_acc(4) (4),
               v_item_acc(4) (5),
               v_item_acc(4) (6),
               v_item_acc(4) (7),
               v_item_acc(4) (8),
               v_item_acc(4) (9),
               '0',
               '0',
               decode(v_debit_credit_indicator,
                      'DR',
                      NULL,
                      v_tot_cr_amt), /*entered dr */
               decode(v_debit_credit_indicator,
                      'DR',
                      v_tot_cr_amt,
                      NULL), /*entered cr */
               NULL, /*accounted dr */
               NULL, /*accounted_cr*/
               --                         'CONC2GL Batch Number '||'"'||v_batch_id||'"',
               '"' || v_batch_id || '"',
               v_reference10,
               v_attribute10,
               v_concur_export_date,
               'MOR',
               NULL,
               fnd_global.user_id,
               SYSDATE,
               g_group_id,
               v_sob_id);
          END IF;
        
          IF (v_no_cc_flag = 'Y') THEN
          
            UPDATE gerfp_congl_stg
               SET process_flag = 'CR' /*Cost Center Rejected*/,
                   err_msg      = v_cc_err_msg
             WHERE ROWID = rec_concur_data.rowid;
          
          ELSIF (v_no_keyacc_flag = 'Y') THEN
          
            UPDATE gerfp_congl_stg
               SET process_flag = 'KR' /*Key Account Rejected*/,
                   err_msg      = v_keyacc_err_msg
             WHERE ROWID = rec_concur_data.rowid;
          ELSE
          
            UPDATE gerfp_congl_stg
               SET process_flag = 'P',
                   err_msg      = NULL
             WHERE ROWID = rec_concur_data.rowid;
          END IF;
        
        EXCEPTION
          /*LOOP EXCEPTION*/
          WHEN e_skip_to_next_rec THEN
            debug_message('--> Updating staging table with Error Message..');
          
            UPDATE gerfp_congl_stg
               SET process_flag = 'R',
                   err_msg      = v_err_msg
             WHERE ROWID = rec_concur_data.rowid;
          
            retcode := '1';
          
            COMMIT;
          
          WHEN OTHERS THEN
            debug_message('--> Updating staging table with OTHER exception message..');
          
            v_err_msg := v_err_msg ||
                         'Exception in Processing Information - ' ||
                         SQLERRM;
          
            UPDATE gerfp_congl_stg
               SET process_flag = 'R',
                   err_msg      = v_err_msg
             WHERE ROWID = rec_concur_data.rowid;
          
            retcode := '1';
            COMMIT;
          
        END;
        /*INSIDE FOR-LOOP BEGIN..END*/
        v_err_msg        := NULL;
        v_no_cc_flag     := NULL;
        v_no_keyacc_flag := NULL;
        v_cc_err_msg     := NULL;
        v_keyacc_err_msg := NULL;
      
        v_last_name                 := NULL;
        v_first_name                := NULL;
        v_capuser_number            := NULL;
        v_category_name             := NULL;
        v_submission_name           := NULL;
        v_transaction_date          := NULL;
        v_home_iso_currency_code    := NULL;
        v_capuser_ap_number         := NULL;
        v_category_segment_1        := NULL;
        v_department                := NULL;
        v_home_net_amount           := NULL;
        v_gross_reclaim_amount      := NULL;
        v_sae_float_1               := NULL; /* Added by george for TH WHT */
        v_debit_credit_indicator    := NULL;
        v_hh_description            := NULL;
        v_concur_export_date        := NULL;
        v_sae_char_1                := NULL; /*Added by Soori for Japan Requirement, on 02-FEB-2010*/
        v_int_dom_flag              := NULL; /*Added by Soori for Japan Requirement, on 02-FEB-2010*/
        v_amount                    := NULL; /*Added by Soori for Japan Requirement, on 02-FEB-2010*/
        v_authorised_tax_amount     := NULL; /*Added by Soori for Japan Requirement, on 02-FEB-2010*/
        v_authorised_reclaim_amount := NULL; /*Added by Soori for Japan Requirement, on 02-FEB-2010*/
        v_tax_rate_type             := NULL; /*Added by Soori for Japan Requirement, on 05-FEB-2010*/
      
      END LOOP;
      /*Main Loop End*/
    
    /*Added by Soori on 13-FEB-2010 for Automation*/
    END LOOP; -- For Each File
  
    debug_message(' ');
    debug_message('Process: Import and Status collection');
    FOR notifier IN notifier_list
    LOOP
    
      debug_message(' ');
      g_recipients := notifier.future2 || g_mail_domain;
    
      debug_message('-->>Begin:Send mail to:' || g_recipients);
    
      v_html := 'Concur SAE inbound notification';
      send_mail('O',
                v_html);
    
      v_html := '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">' ||
                '<html xmlns="http://www.w3.org/1999/xhtml" lang="en" xml:lang="en">' ||
                '<head>' ||
                '<meta http-equiv="Content-Type" content="text/html; charset=utf-8"></meta>' ||
                '<title>Concur SAE inbound notification</title>' ||
                '<style type="text/css"> ' ||
                '  table {border:1; cellspacing:0;bordercolor:black;frame:box;}' ||
                '  td {white-space: nowrap;}' || '</style>' || '</head>' ||
                '<body>' ||
                '<h1 align="left">Concur inbound notification</h1></BR>';
      send_mail('S',
                v_html);
    
      BEGIN
        SELECT COUNT(1)
          INTO v_file_count
          FROM gerfp_congl_stg           stg,
               apps.xxrfp_concur_bus_map glid
         WHERE glid.concur_ledger_code = stg.capuser_ap_number
           AND concur_req_id = v_conc_request
           AND glid.future2 = notifier.future2;
      
        IF v_file_count > 0 THEN
          v_html := '<table border="1" cellspacing="0" frame="box">' ||
                    '<tr><td>File name</td>' ||
                    '<td colspan="3">Batch id</td>' ||
                    '<td colspan="2">Request id</td>' ||
                    '<td colspan="6">Result</td></TR>';
        
        ELSE
          v_html := 'No data for your GLID.';
        END IF;
        send_mail('S',
                  v_html);
      END;
    
      FOR file_status IN cur_file_status(v_conc_request,
                                         notifier.future2)
      LOOP
        /* FILE_SEQ,FILE_NAME,CONCUR_BATCH_ID,CONCUR_REQ_ID,SOB_ID,CAPUSER_AP_NUMBER,FUTURE2,gi_group_id */
      
        --check if duplicate load
        /*1, Check for Duplicate file processing */
        debug_message(' ');
        debug_message('Step: Checking Duplicate File Process:' ||
                      file_status.concur_req_id || ' under SOB Name : ' ||
                      file_status.sob_name);
      
        v_chk_status := NULL;
        check_dup_file_process(p_sob_id       => file_status.sob_id,
                               p_batch_number => file_status.concur_batch_id,
                               p_group_id     => file_status.file_seq,
                               x_status       => v_chk_status);
      
        debug_message(file_status.sob_id || '.' ||
                      file_status.concur_batch_id || '.' ||
                      file_status.file_seq);
      
        IF (v_chk_status = 'Y') THEN
        
          debug_message(' Already processed and Journal exist for this batch : ' ||
                        file_status.concur_req_id || ' under SOB Name : ' ||
                        file_status.sob_name);
          debug_message('*** Purging records from Interface table for this batch ..');
        
          fnd_file.put_line(fnd_file.output,
                            ' Already processed and Journal exist for this batch : ' ||
                            file_status.concur_req_id ||
                            ' under SOB Name : ' || file_status.sob_name);
          fnd_file.put_line(fnd_file.output,
                            '*** Purging records from Interface table for this batch ..');
        
          DELETE FROM gl_interface
          ----BEGIN:MODIFIED BY GEORGE FOR FIXING BUG ON 08-JUL-2010         
          --WHERE GROUP_ID=G_GROUP_ID /*COMMENTED BY SOORI ON 13-FEB-2010 FOR AUTOMATION*/
          --WHERE GROUP_ID=SUBSTR(REC_IFACE_DATA.BATCH_NAME,2,LENGTH(REC_IFACE_DATA.BATCH_NAME)-2)
           WHERE group_id = file_status.file_seq
                ----End:modified by george for fixing bug on 08-JUL-2010
             AND set_of_books_id = file_status.sob_id
             AND substr(reference6,
                        2,
                        length(reference6) - 2) =
                 file_status.concur_batch_id;
        
          DELETE FROM gerfp_congl_stg
           WHERE concur_batch_id = file_status.concur_batch_id
             AND file_seq = file_status.file_seq
             AND concur_req_id = file_status.concur_req_id;
        
          debug_message('test end: ' || file_status.concur_batch_id ||
                        ' under SOB Name : ' || file_status.sob_name);
          COMMIT;
        
          v_html := '<TR><TD>' || file_status.file_name || '</TD>' ||
                    '<TD colspan="3">' || file_status.concur_batch_id ||
                    '</TD>' || '<TD colspan="2">' || v_conc_request ||
                    '</TD>' ||
                    '<TD colspan="6">Duplicate file has been cleaned.</TD></TR>';
          apps.fnd_file.put_line(apps.fnd_file.output,
                                 v_html);
        
          send_mail('S',
                    v_html);
        ELSE
          /*2, GL_interface process */
          FOR rec_iface_data IN cur_iface_data(p_source     => 'Concur',
                                               p_category   => 'Concur SAE',
                                               p_batch_name => file_status.concur_batch_id,
                                               p_group_id   => file_status.file_seq /*Commented by Soori on 13-FEB-2010 for Automation*/)
          LOOP
          
            debug_message('Step: Journal Import Program Submission Process');
            BEGIN
              debug_message(' Number of Records for SOB# ' ||
                            rec_iface_data.sob_name || ' , Batch # ' ||
                            rec_iface_data.batch_name || ' is :' ||
                            rec_iface_data.rec_cnt);
            
              submit_journal_import(p_user_id => v_userid,
                                    p_resp_id => v_resp_id,
                                    p_sob_id  => rec_iface_data.sob_id
                                    -- ,p_group_id=> g_group_id            /*Commented by Soori on 13-FEB-2010 for Automation*/
                                   ,
                                    p_group_id => rec_iface_data.group_id /*Added by Soori on 13-FEB-2010 for Automation*/,
                                    p_source   => 'Concur',
                                    x_status   => v_import_status,
                                    x_req_id   => v_req_id);
            
              debug_message('--> Journal Import Program Submitted ..');
              debug_message('    JOURNAL IMPORT Program Status for SOB# ' ||
                            rec_iface_data.sob_name || ' is ' ||
                            v_import_status);
            
              COMMIT;
            
              IF v_req_id = 0 THEN
                v_html := '<TR><TD>' || file_status.file_name || '</TD>' ||
                          '<TD colspan="3">' || file_status.concur_batch_id ||
                          '</TD>' || '<TD colspan="2">' || v_req_id ||
                          '</TD>' ||
                          '<TD colspan="6">Import journal error.</TD></TR>';
                apps.fnd_file.put_line(apps.fnd_file.output,
                                       v_html);
              
                send_mail('S',
                          v_html);
              
                raise_application_error(-20160,
                                        fnd_message.get);
                x_status := 'FAILED';
              ELSE
                x_status := 'DONE';
                LOOP
                  v_phase      := NULL;
                  v_status     := NULL;
                  v_dev_phase  := NULL;
                  v_dev_status := NULL;
                  v_message    := NULL;
                
                  v_request_complete := apps.fnd_concurrent.wait_for_request(v_req_id,
                                                                             10,
                                                                             9999,
                                                                             v_phase,
                                                                             v_status,
                                                                             v_dev_phase,
                                                                             v_dev_status,
                                                                             v_message);
                
                  IF upper(v_phase) = 'COMPLETED' THEN
                    fnd_file.put_line(fnd_file.log,
                                      'Import journal completed.');
                    EXIT;
                  END IF;
                END LOOP;
              
                BEGIN
                  SELECT COUNT(gjh.je_header_id)
                    INTO v_rc
                    FROM gl_je_headers    gjh,
                         gl_je_sources    gjs,
                         gl_je_categories gjc
                   WHERE gjh.external_reference = rec_iface_data.batch_name
                     AND gjh.set_of_books_id = rec_iface_data.sob_id
                     AND gjc.je_category_name = gjh.je_category
                     AND gjs.je_source_name = gjh.je_source
                     AND upper(gjc.user_je_category_name) = 'CONCUR SAE'
                     AND upper(gjs.user_je_source_name) = 'CONCUR';
                
                  IF nvl(v_rc,
                         0) > 0 THEN
                    v_html := '<TR><TD>' || file_status.file_name ||
                              '</TD>' || '<TD colspan="3">' ||
                              file_status.concur_batch_id || '</TD>' ||
                              '<TD colspan="2">' || v_req_id || '</TD>' ||
                              '<TD colspan="6">Import journal succeeded.</TD></TR>';
                  ELSE
                    v_html := '<TR><TD>' || file_status.file_name ||
                              '</TD>' || '<TD colspan="3">' ||
                              file_status.concur_batch_id || '</TD>' ||
                              '<TD colspan="2">' || v_req_id || '</TD>' ||
                              '<TD colspan="6">Import journal failed with group_id:' ||
                              rec_iface_data.group_id || '</TD></TR>';
                  END IF;
                
                  apps.fnd_file.put_line(apps.fnd_file.output,
                                         v_html);
                
                  send_mail('S',
                            v_html);
                END;
              END IF;
            END;
          END LOOP;
        
          /*1, Stage process */
          BEGIN
            SELECT COUNT(1)
              INTO v_err_cnt
              FROM gerfp_congl_stg
             WHERE process_flag IN ('CR',
                                    'KR',
                                    'R') /*CC,Key and Other Rejected*/
               AND err_msg IS NOT NULL
               AND file_name = file_status.file_name
               AND concur_batch_id = file_status.concur_batch_id
               AND detail_format_ind = 'AD' /*Added by Soori on 13-FEB-2010 for Automation*/
               AND concur_req_id = v_conc_request;
          
          EXCEPTION
            WHEN no_data_found THEN
              v_err_cnt := 0;
          END;
        
          IF v_err_cnt = 0 THEN
            v_html := '<TR><TD>' || file_status.file_name || '</TD>' ||
                      '<TD colspan="3">' || file_status.concur_batch_id ||
                      '</TD>' || '<TD colspan="2">' || v_conc_request ||
                      '</TD>' ||
                      '<TD colspan="6">Inbound succeeded.</TD></TR>';
            apps.fnd_file.put_line(apps.fnd_file.output,
                                   v_html);
            send_mail('S',
                      v_html);
          
          ELSE
            v_html := '<TR><TD>' || file_status.file_name || '</TD>' ||
                      '<TD colspan="3">' || file_status.concur_batch_id ||
                      '</TD>' || '<TD colspan="2">' || v_conc_request ||
                      '</TD>' ||
                      '<TD colspan="6">Inbound failed with exceptions as below.</TD></TR>';
            apps.fnd_file.put_line(apps.fnd_file.output,
                                   v_html);
            send_mail('S',
                      v_html);
          
            SELECT rpad('Detail Format Ind',
                        20) || '</TD><TD>' ||
                   rpad('Stnd Acc Export ID',
                        20) || '</TD><TD>' ||
                   rpad('Last Name',
                        15) || '</TD><TD>' ||
                   rpad('First Name',
                        15) || '</TD><TD>' ||
                   rpad('GLID',
                        10) || '</TD><TD>' ||
                   rpad('Category Segment 1',
                        25) || '</TD><TD>' ||
                   rpad('Department',
                        20) || '</TD><TD>' ||
                   rpad('Home ISO Currency Code',
                        25) || '</TD><TD>' ||
                   rpad('Home Net Amt',
                        15) || '</TD><TD>' ||
                   rpad('Process Flag',
                        20) || '</TD><TD>' ||
                   rpad('Error Message',
                        150)
              INTO v_err_buffer
              FROM dual;
          
            v_html := '<TR><TD></TD>' || '<TD>' || v_err_buffer ||
                      '</TD></TR>';
            send_mail('S',
                      v_html);
          
            FOR rec_err_cgl IN cur_err_cgl(v_conc_request,
                                           file_status.file_name,
                                           file_status.concur_batch_id)
            LOOP
            
              SELECT rpad(rec_err_cgl.detail_format_ind,
                          20) || '</TD><TD>' ||
                     rpad(rec_err_cgl.stdacctngexport_id,
                          20) || '</TD><TD>' ||
                     rpad(rec_err_cgl.last_name,
                          15) || '</TD><TD>' ||
                     rpad(rec_err_cgl.first_name,
                          15) || '</TD><TD>' ||
                     rpad(rec_err_cgl.capuser_ap_number,
                          10) || '</TD><TD>' ||
                     rpad(rec_err_cgl.category_segment_1,
                          25) || '</TD><TD>' ||
                     rpad(rec_err_cgl.department,
                          20) || '</TD><TD>' ||
                     rpad(rec_err_cgl.home_iso_currency_code,
                          25) || '</TD><TD>' ||
                     rpad(nvl(rec_err_cgl.home_net_amount,
                              0),
                          15) || '</TD><TD>' ||
                     rpad(rec_err_cgl.process_flag,
                          20) || '</TD><TD>' ||
                     rpad(rec_err_cgl.err_msg,
                          150)
                INTO v_err_buffer
                FROM dual;
              v_html := '<TR><TD></TD>' || '<TD>' || v_err_buffer ||
                        '</TD></TR>';
              apps.fnd_file.put_line(apps.fnd_file.output,
                                     v_html);
              send_mail('S',
                        v_html);
            END LOOP;
          END IF;
        END IF;
      END LOOP; --Loop for file status
    
      IF v_file_count > 0 THEN
        v_html := '</table></html>';
        send_mail('S',
                  v_html);
      END IF;
    
      send_mail('C',
                v_html);
      debug_message('-->>End:Send mail to:' || g_recipients);
    END LOOP;
  EXCEPTION
    /*Procedure EXCEPTION*/
  
    WHEN end_of_program THEN
      debug_message('ERROR in Processing : ' || v_err_msg);
      retcode := '1';
    
    WHEN e_end_program THEN
      debug_message(' No Records to Process ..');
      retcode := '1';
    
    WHEN OTHERS THEN
      debug_message('Exception in processing the program :' || v_err_msg || ' :' ||
                    SQLERRM);
      retcode := '2';
    
  END process_gl_data;

  /***************************************************/
  /*               PROCEDURE FOR ERROR REPORT        */
  /***************************************************/

  PROCEDURE display_err_congl(errbuff OUT VARCHAR2,
                              retcode OUT VARCHAR2) IS
  
    CURSOR cur_err_cgl IS
      SELECT *
        FROM gerfp_congl_stg
       WHERE process_flag IN ('CR',
                              'KR',
                              'R') /*CC,Key and Other Rejected*/
         AND err_msg IS NOT NULL
         AND detail_format_ind = 'AD' /*Added by Soori on 13-FEB-2010 for Automation*/
         AND concur_req_id =
             (SELECT MAX(fcq.request_id)
                FROM fnd_concurrent_requests fcq,
                     fnd_concurrent_programs fcp
               WHERE fcq.concurrent_program_id = fcp.concurrent_program_id
                 AND upper(concurrent_program_name) =
                     'GERFP_CONCUR_GL_INBOUND');
  
    v_err_buffer VARCHAR2(4000);
    v_err_cnt    NUMBER;
  
  BEGIN
  
    fnd_file.put_line(fnd_file.output,
                      '************************************  Concur TO GL Error Record Details  *******************************************');
    fnd_file.put_line(fnd_file.output,
                      '  ');
    fnd_file.put_line(fnd_file.output,
                      '********************************************************************************************************************');
  
    fnd_file.put_line(fnd_file.output,
                      '  ');
    fnd_file.put_line(fnd_file.output,
                      rpad('-',
                           250,
                           '-'));
    fnd_file.put_line(fnd_file.output,
                      rpad('Detail Format Ind',
                           20) || chr(9) || rpad('Stnd Acc Export ID',
                                                 20) || chr(9) ||
                      rpad('Last Name',
                           15) || chr(9) || rpad('First Name',
                                                 15) || chr(9) ||
                      rpad('GLID',
                           10) || chr(9) || rpad('Category Segment 1',
                                                 25) || chr(9) ||
                      rpad('Department',
                           20) || chr(9) || rpad('Home ISO Currency Code',
                                                 25) || chr(9) ||
                      rpad('Home Net Amt',
                           15) || chr(9) || rpad('Process Flag',
                                                 20) || chr(9) ||
                      rpad('Error Message',
                           150));
    fnd_file.put_line(fnd_file.output,
                      rpad('-',
                           250,
                           '-'));
  
    /*Fetching the count of error records*/
    BEGIN
    
      SELECT COUNT(1)
        INTO v_err_cnt
        FROM gerfp_congl_stg
       WHERE process_flag IN ('CR',
                              'KR',
                              'R') /*CC,Key and Other Rejected*/
         AND err_msg IS NOT NULL
         AND concur_req_id =
             (SELECT MAX(fcq.request_id)
                FROM fnd_concurrent_requests fcq,
                     fnd_concurrent_programs fcp
               WHERE fcq.concurrent_program_id = fcp.concurrent_program_id
                 AND upper(concurrent_program_name) =
                     'GERFP_CONCUR_GL_INBOUND');
    EXCEPTION
      WHEN no_data_found THEN
        v_err_cnt := 0;
      WHEN OTHERS THEN
        fnd_file.put_line(fnd_file.output,
                          'EXCEPTION IN FETCHING COUNT  ' || SQLERRM);
    END;
  
    IF (v_err_cnt > 0) THEN
    
      retcode := '1';
    
      FOR rec_err_cgl IN cur_err_cgl
      LOOP
      
        SELECT rpad(rec_err_cgl.detail_format_ind,
                    20) || chr(9) || rpad(rec_err_cgl.stdacctngexport_id,
                                          20) || chr(9) ||
               rpad(rec_err_cgl.last_name,
                    15) || chr(9) || rpad(rec_err_cgl.first_name,
                                          15) || chr(9) ||
               rpad(rec_err_cgl.capuser_ap_number,
                    10) || chr(9) || rpad(rec_err_cgl.category_segment_1,
                                          25) || chr(9) ||
               rpad(rec_err_cgl.department,
                    20) || chr(9) || rpad(rec_err_cgl.home_iso_currency_code,
                                          25) || chr(9) ||
               rpad(nvl(rec_err_cgl.home_net_amount,
                        0),
                    15) || chr(9) || rpad(rec_err_cgl.process_flag,
                                          20) || chr(9) ||
               rpad(rec_err_cgl.err_msg,
                    150)
          INTO v_err_buffer
          FROM dual;
      
        fnd_file.put_line(fnd_file.output,
                          v_err_buffer);
      END LOOP;
    ELSE
      fnd_file.put_line(fnd_file.output,
                        ' ');
      fnd_file.put_line(fnd_file.output,
                        '                           *** No Errored Concur Entries ***');
    END IF;
  
    fnd_file.put_line(fnd_file.output,
                      '      ');
    fnd_file.put_line(fnd_file.output,
                      rpad('-',
                           250,
                           '-'));
  
  EXCEPTION
    WHEN no_data_found THEN
      fnd_file.put_line(fnd_file.output,
                        'NO DATA FOUND ' || SQLERRM);
      retcode := '1';
    WHEN OTHERS THEN
      fnd_file.put_line(fnd_file.output,
                        'EXCEPTION :  ' || SQLERRM);
      retcode := '2';
    
  END display_err_congl;

  /*  PROCEDURE send_mail(p_action  IN VARCHAR2,
                      p_content IN VARCHAR2) IS
  BEGIN
    CASE p_action
      WHEN 'O' THEN
        g_conn := gerfp_ccl_mail.begin_mail(sender     => g_sender,
                                            recipients => g_recipients,
                                            subject    => p_content,
                                            mime_type  => 'text/html');
      WHEN 'S' THEN
        gerfp_ccl_mail.write_text(conn    => g_conn,
                                  message => p_content || utl_tcp.crlf);
      WHEN 'C' THEN
        gerfp_ccl_mail.end_mail(conn => g_conn);
    END CASE;
  
  END send_mail;*/

  PROCEDURE send_mail(p_action  IN VARCHAR2,
                      p_content IN VARCHAR2) IS
  BEGIN
  
    NULL;
  
  END send_mail;

END gerfp_conc_gl_sae_auto_pkg;
/
