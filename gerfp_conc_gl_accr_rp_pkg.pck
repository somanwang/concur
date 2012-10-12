CREATE OR REPLACE PACKAGE gerfp_conc_gl_accr_rp_pkg
/*************************************************************************************************************************************
 *                           - Copy Right General Electric Company 2006 -
 *
 *************************************************************************************************************************************
 *************************************************************************************************************************************
 * Project      :  GEGBS Financial Implementation Project
 * Application      :  General Ledger
 * Title        :  N/A
 * Program Name     :  N/A
  * Description Purpose  :  To Re-Process Rejected ACCURAL Concur Expenses from staging into GL interface tables
 * $Revision        :
 * Utility      :
 * Created by       :  Ramesh Soorishetty
 * Creation Date    :  17-MAR-2009
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

  PROCEDURE reprocess_gl_accr_data(errbuff OUT VARCHAR2,
                                   retcode OUT VARCHAR2);

  PROCEDURE display_err_rp_congl(p_request_id IN NUMBER);

  g_group_id        VARCHAR2(200);
  g_entries         VARCHAR2(200);
  tot_group_id      VARCHAR2(200);
  tot_category_name VARCHAR2(200);

END gerfp_conc_gl_accr_rp_pkg;
/
CREATE OR REPLACE PACKAGE BODY gerfp_conc_gl_accr_rp_pkg AS
  /*************************************************************************************************************************************
   *                           - Copy Right General Electric Company 2006 -
   *
   *************************************************************************************************************************************
   *************************************************************************************************************************************
   * Project      :  GEGBS Financial Implementation Project
   * Application      :  General Ledger
   * Title        :  N/A
   * Program Name     :  N/A
   * Description Purpose  :  To Re-Process Rejected ACCURAL Concur Expenses from staging into GL interface tables
   * $Revision        :
   * Utility      :
   * Created by       :  Ramesh Soorishetty
   * Creation Date    :  17-MAR-2009
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
   *  GL_INTERFACE              -          X          -          -
   *  XXRFP_CONCUR_BUS_MAP              X          -          -          -
   *  XXRFP_CONCUR_KEYAC_MAP        X          -          -          -
   *  XXRFP_CONCUR_CC_MAP           X          -          -          -
   *  GERFP_CONGL_ACCR_STG                  X          -          X          -
   * ----------------------------------------------------------------------------
   * Change History   :
   *====================================================================================================================================
   * Date         |Name               |Case#      |Remarks
   *====================================================================================================================================
   * 12-may-2010  Satya Chittella      Modified the pacakage as a apetr of Project Code extn
    *====================================================================================================================================
   * 11-Aug-2010  George Ye            Modified the pacakage as a apetr of SG automotion enhancement
  
    *************************************************************************************************************************************
  */

  v_conc_request NUMBER := fnd_global.conc_request_id;
  p_flag         VARCHAR(2); --added by Satya Chittella for project code Extn

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
                                   p_category     IN VARCHAR2,
                                   x_status       OUT VARCHAR2)
  
   IS
    v_batch_number VARCHAR2(50);
    v_je_cnt       NUMBER := 0;
    v_status       VARCHAR2(1);
  BEGIN
  
    IF (p_batch_number IS NOT NULL) THEN
      /*Checking Batch number in Oracle Base Table (GL_JE_HEADERS) */
      BEGIN
        SELECT COUNT(gjh.je_header_id)
          INTO v_je_cnt
          FROM gl_je_headers    gjh,
               gl_je_sources    gjs,
               gl_je_categories gjc
         WHERE gjh.external_reference LIKE p_batch_number
           AND gjh.set_of_books_id = p_sob_id
           AND gjc.je_category_name = gjh.je_category
           AND gjs.je_source_name = gjh.je_source
           AND upper(gjc.user_je_category_name) = upper(p_category)
           AND upper(gjs.user_je_source_name) = 'CONCUR'
           AND rownum = 1;
      
        IF (nvl(v_je_cnt,
                0) > 0) THEN
          x_status := 'Y';
        ELSE
          x_status := 'N';
        END IF;
      END;
    END IF;
  
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
                                  x_status   OUT VARCHAR2) IS
  
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

  PROCEDURE reprocess_gl_accr_data(errbuff OUT VARCHAR2,
                                   retcode OUT VARCHAR2) IS
  
    /*Added by george on 23-Jul-2010 Cursor to fetch batch list */
    CURSOR cur_file_seq(p_conc_req_id IN VARCHAR2,
                        p_sob_id      IN NUMBER) IS
      SELECT DISTINCT concur_batch_id
        FROM gerfp_congl_accr_stg
       WHERE concur_req_id = p_conc_req_id
         AND (sob_id = p_sob_id OR p_sob_id IS NULL)
         AND detail_format_ind = 'AD'
         AND process_flag IN ('R',
                              'CR');
  
    /*Cursor to fetch records from staging table*/
    --CURSOR cur_concur_accr_rp_data(p_conc_req_id IN VARCHAR2)
    CURSOR cur_concur_accr_rp_data(p_conc_req_id IN VARCHAR2,
                                   p_batch_id    IN VARCHAR2) IS
      SELECT ROWID,
             concur_req_id,
             concur_batch_id,
             detail_format_ind,
             concur_export_date,
             cc_trans_key,
             last_name,
             first_name,
             middle_name,
             ohr_emp_id,
             glid,
             department,
             paymt_type_seg_1,
             paymt_type_ap_num,
             custom1_segment_1,
             custom2_segment_1,
             custom3_segment_1,
             transaction_type,
             transaction_number,
             vendor_name,
             vendor_mcc_code,
             paymt_method,
             paymt_type_acc_num,
             paymt_acc_num,
             int_dom_flag,
             e_tran_iso_contry_code,
             entity_iso_country_code,
             entity_iso_curr_code,
             submission_name,
             submit_date,
             transaction_date,
             home_amount,
             debit_credit_indicator,
             hh_description,
             process_flag,
             err_msg
        FROM gerfp_congl_accr_stg
       WHERE concur_req_id = p_conc_req_id
         AND detail_format_ind = 'AD'
         AND process_flag IN ('R',
                              'CR')
         AND concur_batch_id = p_batch_id
       ORDER BY 3 DESC;
  
    CURSOR cur_iface_data(p_source   VARCHAR2,
                          p_category VARCHAR2
                          -- , p_group_id   NUMBER
                          ) IS
      SELECT gi.set_of_books_id sob_id,
             sob.name sob_name,
             gi.reference6 batch_name,
             gi.group_id,
             gi.user_je_category_name category_name,
             COUNT(1) rec_cnt
        FROM gl_interface     gi,
             gl_sets_of_books sob
       WHERE gi.set_of_books_id = sob.set_of_books_id
         AND user_je_source_name = p_source
         AND user_je_category_name = p_category
            --AND   group_id=p_group_id
         AND status = 'NEW'
       GROUP BY gi.set_of_books_id,
                sob.name,
                gi.reference6,
                gi.group_id,
                gi.user_je_category_name;
  
    /*Variables Declaration*/
    r_sob_id NUMBER;
  
    v_batch_id           VARCHAR2(200);
    v_concur_export_date DATE;
    v_err_msg            VARCHAR2(2000) := NULL;
    v_cc_err_msg         VARCHAR2(4000) := NULL;
    v_sob_id             NUMBER;
    v_je_cnt             NUMBER;
    v_intr_rec_cnt       NUMBER;
    v_userid             NUMBER;
    v_resp_id            NUMBER;
    v_import_status      VARCHAR2(500);
    v_chk_status         VARCHAR2(2000);
    v_final_chk_status   VARCHAR2(2000);
    v_start_date         DATE;
    v_period_name        VARCHAR2(200);
  
    v_last_name              VARCHAR2(200);
    v_first_name             VARCHAR2(200);
    v_glid                   VARCHAR2(200);
    v_submission_name        VARCHAR2(200);
    v_transaction_date       DATE;
    v_entity_iso_curr_code   VARCHAR2(200);
    v_department             VARCHAR2(200);
    v_home_amount            NUMBER;
    v_debit_credit_indicator VARCHAR2(200);
    v_hh_description         VARCHAR2(4000);
    v_reference10            VARCHAR2(250);
    v_attribute10            VARCHAR2(250);
    v_tot_cr_amt             NUMBER;
    v_tot_dr_amt             NUMBER;
    v_upd_accr_rp_cnt        NUMBER;
    v_process_flag           VARCHAR2(20);
    v_upd_process_flag       VARCHAR2(20);
  
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
    v_cc_sae_offset_account apps.xxrfp_concur_bus_map.cc_sae_offset_account%TYPE;
    v_cash_adv_account      apps.xxrfp_concur_bus_map.cash_adv_account%TYPE;
    v_wht_account           apps.xxrfp_concur_bus_map.wht_account%TYPE;
    v_alloc_cearing_account apps.xxrfp_concur_bus_map.alloc_cearing_account%TYPE;
    v_acctype               VARCHAR2(20);
    v_key_flag              VARCHAR(2);
  
    v_na       apps.xxrfp_concur_keyac_map.natrual_account%TYPE;
    v_ime_code apps.xxrfp_concur_keyac_map.ime_code%TYPE;
    v_ile_code apps.xxrfp_concur_keyac_map.ile_code%TYPE;
  
    v_shltn_code apps.xxrfp_shelton_cc_map.shelton_ledger%TYPE;
    v_oracle_cc  apps.xxrfp_shelton_cc_map.oracle_cc%TYPE;
    v_project    apps.xxrfp_shelton_cc_map.project%TYPE;
    v_project_1  apps.xxrfp_concur_keyac_map.project%TYPE DEFAULT '0000000000';
    v_reference  apps.xxrfp_shelton_cc_map.ref%TYPE;
    v_no_cc_flag VARCHAR2(20);
  
    v_accr_batch_seq VARCHAR2(4000);
  
    v_file_cnt NUMBER;
  
    /* Exception Declaration */
    end_of_program EXCEPTION;
    e_skip_to_next_rec EXCEPTION;
    e_end_program EXCEPTION;
    e_acc_type EXCEPTION;
    e_flag EXCEPTION;
    e_flag_proj_nd EXCEPTION;
    e_flag_proj_nd_c EXCEPTION;
    e_shelton_bus EXCEPTION;
  
    v_default_cc VARCHAR2(100);
  
  BEGIN
    /*Procedure BEGIN*/
  
    v_userid  := to_number(fnd_profile.value('USER_ID'));
    v_resp_id := to_number(fnd_profile.value('RESP_ID'));
    SELECT fnd_profile.value('GL_SET_OF_BKS_ID') INTO r_sob_id FROM dual;
  
    /*Fetch the Next Value from Sequence for Batch Identifier*/
    BEGIN
    
      SELECT '_RP' || gerfp_congl_accr_seq.nextval
        INTO v_accr_batch_seq
        FROM dual;
    
      debug_message('ACCRUAL Batch Sequence Value  - ' || v_accr_batch_seq);
    
    EXCEPTION
      WHEN OTHERS THEN
        SELECT '_RP' || to_char(SYSDATE,
                                'HH24MISS')
          INTO v_accr_batch_seq
          FROM dual;
      
        debug_message('ACCRUAL Batch Sequence Value  - ' ||
                      v_accr_batch_seq);
      
    END;
  
    /*For Updating the staging table for the current submission of upload*/
    BEGIN
    
      /*   SELECT TO_CHAR(SYSDATE,'DDMMRRRRHH24MISS')
      INTO g_group_id
      FROM DUAL;
      
      debug_message('Group Id Derived - '||g_group_id);
      debug_message('For Reversal, Group Id Derived - '||g_group_id||'9');*/
    
      UPDATE gerfp_congl_accr_stg
         SET concur_req_id = v_conc_request,
             err_msg       = NULL
       WHERE process_flag IN ('R',
                              'CR')
         AND (sob_id = r_sob_id OR r_sob_id IS NULL)
         AND err_msg IS NOT NULL;
    
      v_upd_accr_rp_cnt := SQL%ROWCOUNT;
    
      COMMIT;
    
      debug_message('Updated the Staging table with Program Request Id Derived ');
      debug_message('No Of Records Updated  for Re-processing.. : ' ||
                    v_upd_accr_rp_cnt);
    
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
  
    v_file_cnt := 0;
    FOR rec_file_seq IN cur_file_seq(v_conc_request,
                                     r_sob_id)
    LOOP
    
      /*START : Added by Soori on 13-FEB-2010 for Automation*/
      v_file_cnt := v_file_cnt + 1;
      IF (v_file_cnt = 1) THEN
      
        SELECT to_char(SYSDATE,
                       'DDMMRRHH24MISS')
          INTO g_group_id
          FROM dual;
      
        debug_message('Group Id Derived - ' || g_group_id);
      ELSE
        --g_group_id := g_group_id||v_file_cnt;
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
      debug_message('File cnt:' || v_file_cnt || ';Group Id Derived - ' ||
                    g_group_id);
    
      /*Main Loop for each concur line*/
      FOR rec_concur_accr_rp_data IN cur_concur_accr_rp_data(v_conc_request,
                                                             rec_file_seq.concur_batch_id)
      LOOP
        BEGIN
          /*LOOP BEGIN*/
        
          v_last_name              := rec_concur_accr_rp_data.last_name;
          v_first_name             := rec_concur_accr_rp_data.first_name;
          v_glid                   := ltrim(rtrim(rec_concur_accr_rp_data.glid));
          v_department             := rec_concur_accr_rp_data.department;
          v_submission_name        := rec_concur_accr_rp_data.submission_name;
          v_transaction_date       := rec_concur_accr_rp_data.transaction_date;
          v_entity_iso_curr_code   := rec_concur_accr_rp_data.entity_iso_curr_code;
          v_home_amount            := rec_concur_accr_rp_data.home_amount;
          v_debit_credit_indicator := rec_concur_accr_rp_data.debit_credit_indicator;
          v_hh_description         := rec_concur_accr_rp_data.hh_description;
          v_process_flag           := rec_concur_accr_rp_data.process_flag;
          v_batch_id               := rec_concur_accr_rp_data.concur_batch_id;
          v_concur_export_date     := rec_concur_accr_rp_data.concur_export_date;
        
          /*Deriving ME+LE+BT+SOB from Mapping form */
          BEGIN
          
            v_me_code               := NULL;
            v_le_code               := NULL;
            v_book_type             := NULL;
            v_sob_id                := NULL;
            v_sae_offset_account    := NULL;
            v_tax_account           := NULL;
            v_accr_offset_account   := NULL;
            v_conc_suspense_account := NULL;
          
            v_upd_process_flag := NULL;
            v_upd_process_flag := 'P';
          
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
                            xbus.alloc_cearing_account
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
                   v_alloc_cearing_account
              FROM apps.xxrfp_concur_bus_map xbus,
                   apps.gl_sets_of_books     gsob
             WHERE xbus.sob_name = gsob.name
               AND xbus.concur_ledger_code = v_glid
               AND xbus.enabled_flag = 'Y';
          
            IF v_glid LIKE '%TH%' THEN
              v_sae_offset_account := nvl(v_cc_sae_offset_account,
                                          v_sae_offset_account);
            END IF;
          
          EXCEPTION
            WHEN no_data_found THEN
              debug_message('-> ME+LE+BT+SOB does not exist for given GLID - ' ||
                            v_glid);
              v_err_msg          := v_err_msg || ' /' ||
                                    'ME+LE+BT+SOB does not exist for given GLID - ' ||
                                    v_glid;
              v_upd_process_flag := v_process_flag;
              RAISE e_skip_to_next_rec;
            WHEN too_many_rows THEN
              debug_message('-> More than one ME+LE+BT+SOB exist for given GLID - ' ||
                            v_glid);
              v_err_msg          := v_err_msg || ' /' ||
                                    'More than one ME+LE+BT+SOB exist for given GLID - ' ||
                                    v_glid;
              v_upd_process_flag := v_process_flag;
              RAISE e_skip_to_next_rec;
            WHEN OTHERS THEN
              debug_message('-> Exception in deriving ME+LE+BT+SOB for given GLID - ' ||
                            v_glid || ' ->' || SQLERRM);
              v_err_msg          := v_err_msg || ' /' ||
                                    'Exception in deriving ME+LE+BT+SOB for given GLID - ' ||
                                    v_glid || ' ->' || SQLERRM;
              v_upd_process_flag := v_process_flag;
              RAISE e_skip_to_next_rec;
          END;
        
          /* Validation on accrual offset account setup*/
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
               AND ffv.flex_value = v_accr_offset_account
               AND ffv.enabled_flag = 'Y'
               AND ffv.summary_flag = 'N';
          
            SELECT gerfp_cc_proj_extend.chk_key_proj_flag(v_accr_offset_account)
              INTO v_key_flag
              FROM dual;
          
            IF v_acctype NOT IN ('A',
                                 'E') THEN
              RAISE e_acc_type;
            END IF;
          
            IF v_key_flag = -1 THEN
              RAISE e_flag_proj_nd;
            END IF;
          
          EXCEPTION
            WHEN e_acc_type THEN
              debug_message('-> The accrual offset account:' ||
                            v_accr_offset_account || 'must be PL account.');
              v_err_msg          := v_err_msg || ' /' ||
                                    'The accrual offset account:' ||
                                    v_accr_offset_account ||
                                    'must be PL account.';
              v_upd_process_flag := v_process_flag;
              RAISE e_skip_to_next_rec;
            
            WHEN e_flag_proj_nd THEN
              debug_message('-> The accrual offset account:' ||
                            v_accr_offset_account ||
                            'can not require project.');
              v_err_msg          := v_err_msg || ' /' ||
                                    'The accrual offset account:' ||
                                    v_accr_offset_account ||
                                    'can not require project.';
              v_upd_process_flag := v_process_flag;
              RAISE e_skip_to_next_rec;
            
            WHEN OTHERS THEN
              debug_message('-> Exception in deriving accout type of accrual offset account : ' || v_na ||
                            ' ->' || SQLERRM);
              v_err_msg          := v_err_msg || ' /' ||
                                    'Exception in deriving accout type of accrual offset account : ' || v_na ||
                                    ' ->' || SQLERRM;
              v_upd_process_flag := v_process_flag;
              RAISE e_skip_to_next_rec;
          END;
        
          IF instr(v_department,
                   '/') <> 0
             OR length(v_department) = 12 THEN
            /* CCL value system, no shelton dependence */
          
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
                                 '0000000000');
              v_reference := nvl(v_reference,
                                 '0000000000');
              v_project   := nvl(v_project,
                                 '0000000000');
            
            EXCEPTION
              WHEN OTHERS THEN
                debug_message('-> Exception on extracting cost center information from ' ||
                              v_department);
                v_err_msg          := v_err_msg || ' /' ||
                                      'Exception on extracting cost center information from ' ||
                                      v_department;
                v_upd_process_flag := v_process_flag;
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
                v_upd_process_flag := 'R';
                RAISE e_skip_to_next_rec;
                */
              
                debug_message('-> The CC value:' || v_oracle_cc ||
                              ' of department:' || v_department ||
                              ' does not exist in Cost center valueset.');
                IF (v_process_flag = 'R') THEN
                  /*Assigning it to Suspense Account*/
                  debug_message('-> Hence JE is Accounted to Suspense Account : ' ||
                                v_conc_suspense_account);
                
                  v_accr_offset_account := v_conc_suspense_account;
                  v_ime_code            := '000000';
                  v_ile_code            := '000000';
                  v_oracle_cc           := '000000';
                  v_project             := '0000000000';
                  v_reference           := '000000';
                
                  v_cc_err_msg       := 'The CC value:' || v_oracle_cc ||
                                        ' from ' || v_department ||
                                        ' does not exist in Cost center valueset ; Hence JE is Accounted to Suspense Account : ' ||
                                        v_conc_suspense_account;
                  v_no_cc_flag       := 'Y';
                  v_err_msg          := v_cc_err_msg;
                  v_no_cc_flag       := 'Y';
                  v_upd_process_flag := 'CR';
                ELSE
                  v_err_msg          := v_err_msg || ' /' ||
                                        'The CC value:' || v_oracle_cc ||
                                        ' from ' || v_department ||
                                        ' does not exist in Cost center valueset.';
                  v_upd_process_flag := 'CR';
                  RAISE e_skip_to_next_rec;
                END IF;
              
              WHEN OTHERS THEN
                debug_message('-> Exception in validating CC value:' ||
                              v_oracle_cc || ' for ' || v_department ||
                              ' ->' || SQLERRM);
                v_err_msg          := v_err_msg || ' /' ||
                                      'Exception in validating CC value:' ||
                                      v_oracle_cc || ' for ' ||
                                      v_department || ' ->' || SQLERRM;
                v_upd_process_flag := v_process_flag;
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
                v_upd_process_flag := 'R';
                RAISE e_skip_to_next_rec;
                */
              
                debug_message('-> The project value:' || v_project ||
                              ' of department:' || v_department ||
                              ' does not exist in project valueset.');
                IF (v_process_flag = 'R') THEN
                  /*Assigning it to Suspense Account*/
                  debug_message('-> Hence JE is Accounted to Suspense Account : ' ||
                                v_conc_suspense_account);
                
                  v_accr_offset_account := v_conc_suspense_account;
                  v_ime_code            := '000000';
                  v_ile_code            := '000000';
                  v_oracle_cc           := '000000';
                  v_project             := '0000000000';
                  v_reference           := '000000';
                
                  v_cc_err_msg       := 'The project value:' || v_project ||
                                        ' from ' || v_department ||
                                        ' does not exist in project valueset; Hence JE is Accounted to Suspense Account : ' ||
                                        v_conc_suspense_account;
                  v_no_cc_flag       := 'Y';
                  v_err_msg          := v_cc_err_msg;
                  v_no_cc_flag       := 'Y';
                  v_upd_process_flag := 'CR';
                ELSE
                  v_err_msg          := v_err_msg || ' /' ||
                                        'The project value:' || v_project ||
                                        ' from ' || v_department ||
                                        ' does not exist in project valueset.';
                  v_upd_process_flag := 'CR';
                  RAISE e_skip_to_next_rec;
                END IF;
              
              WHEN OTHERS THEN
                debug_message('-> Exception in validating project value:' ||
                              v_project || ' for ' || v_department ||
                              ' ->' || SQLERRM);
                v_err_msg          := v_err_msg || ' /' ||
                                      'Exception in validating project value:' ||
                                      v_project || ' for ' || v_department ||
                                      ' ->' || SQLERRM;
                v_upd_process_flag := v_process_flag;
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
                v_upd_process_flag := 'R';
                RAISE e_skip_to_next_rec;
                */
              
                debug_message('-> The reference value:' || v_reference ||
                              ' of department:' || v_department ||
                              ' does not exist in reference valueset.');
                IF (v_process_flag = 'R') THEN
                  /*Assigning it to Suspense Account*/
                  debug_message('-> Hence JE is Accounted to Suspense Account : ' ||
                                v_conc_suspense_account);
                
                  v_accr_offset_account := v_conc_suspense_account;
                  v_ime_code            := '000000';
                  v_ile_code            := '000000';
                  v_oracle_cc           := '000000';
                  v_project             := '0000000000';
                  v_reference           := '000000';
                
                  v_cc_err_msg       := 'The reference value:' ||
                                        v_reference || ' of department:' ||
                                        v_department ||
                                        ' does not exist in reference valueset; Hence JE is Accounted to Suspense Account : ' ||
                                        v_conc_suspense_account;
                  v_no_cc_flag       := 'Y';
                  v_err_msg          := v_cc_err_msg;
                  v_no_cc_flag       := 'Y';
                  v_upd_process_flag := 'CR';
                ELSE
                  v_err_msg          := v_err_msg || ' /' ||
                                        'The reference value:' ||
                                        v_reference || ' of department:' ||
                                        v_department ||
                                        ' does not exist in reference valueset.';
                  v_upd_process_flag := 'CR';
                  RAISE e_skip_to_next_rec;
                END IF;
              
              WHEN OTHERS THEN
                debug_message('-> Exception in validating reference value:' ||
                              v_reference || ' of department:' ||
                              v_department || ' ->' || SQLERRM);
                v_err_msg          := v_err_msg || ' /' ||
                                      'Exception in validating reference value:' ||
                                      v_reference || ' of department:' ||
                                      v_department || ' ->' || SQLERRM;
                v_upd_process_flag := v_process_flag;
                RAISE e_skip_to_next_rec;
            END;
          
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
            
              --debug_message('Shelton Ledger Code Derived : '||v_shltn_code);
            
              IF v_shltn_code IS NULL THEN
                RAISE e_shelton_bus;
              END IF;
            
            EXCEPTION
              WHEN e_shelton_bus THEN
                debug_message('-> Shelton Ledger Code is blank for given ME+LE+BT Combination, ME : ' ||
                              v_me_code || ' LE : ' || v_le_code ||
                              'and Book Type : ' || v_book_type);
                v_err_msg          := v_err_msg || ' /' ||
                                      'Shelton Ledger Code is blank for given ME+LE+BT Combination, ME : ' ||
                                      v_me_code || ' LE : ' || v_le_code ||
                                      'and Book Type : ' || v_book_type;
                v_upd_process_flag := v_process_flag;
                RAISE e_skip_to_next_rec;
              WHEN no_data_found THEN
                debug_message('-> Shelton Ledger Code does not exists for given ME+LE+BT Combination, ME : ' ||
                              v_me_code || ' LE : ' || v_le_code ||
                              'and Book Type : ' || v_book_type);
                v_err_msg          := v_err_msg || ' /' ||
                                      'Shelton Ledger Code does not exists for given ME+LE+BT Combination, ME : ' ||
                                      v_me_code || ' LE : ' || v_le_code ||
                                      'and Book Type : ' || v_book_type;
                v_upd_process_flag := v_process_flag;
                RAISE e_skip_to_next_rec;
              WHEN too_many_rows THEN
                debug_message('-> More than one Shelton Ledger Code exist for given ME+LE+BT Combination, ME : ' ||
                              v_me_code || ' LE : ' || v_le_code ||
                              'and Book Type : ' || v_book_type);
                v_err_msg          := v_err_msg || ' /' ||
                                      'More than one Shelton Ledger Code exist for given ME+LE+BT Combination, ME : ' ||
                                      v_me_code || ' LE : ' || v_le_code ||
                                      'and Book Type : ' || v_book_type;
                v_upd_process_flag := v_process_flag;
                RAISE e_skip_to_next_rec;
              WHEN OTHERS THEN
                debug_message('-> Exception in deriving Shelton Ledger Code for given ME+LE+BT Combination, ME : ' ||
                              v_me_code || ' LE : ' || v_le_code ||
                              'and Book Type : ' || v_book_type || ' ->' ||
                              SQLERRM);
                v_err_msg          := v_err_msg || ' /' ||
                                      'Exception in deriving Shelton Ledger Code for given ME+LE+BT Combination, ME : ' ||
                                      v_me_code || ' LE : ' || v_le_code ||
                                      'and Book Type : ' || v_book_type ||
                                      ' ->' || SQLERRM;
                v_upd_process_flag := v_process_flag;
                RAISE e_skip_to_next_rec;
            END;
          
            /*Deriving CC+PROJ+REF from Shelton CC Mapping form */
            BEGIN
            
              v_oracle_cc := NULL;
              v_project   := NULL;
              v_reference := NULL;
            
              v_no_cc_flag       := 'N';
              v_upd_process_flag := 'P';
            
              --added by Satya Chittella for project code extn on 11-may-10
              gerfp_cc_proj_extend.shlt_cc_proj_inbound(v_shltn_code,
                                                        --trim(nvl(v_department,'00000000')),
                                                        TRIM(v_department),
                                                        v_oracle_cc,
                                                        v_reference,
                                                        v_project,
                                                        p_flag);
            
              IF v_project IS NULL THEN
                v_project := '0000000000';
              END IF;
            
            EXCEPTION
              WHEN no_data_found THEN
                debug_message('-> CC+PROJ+REF does not exists for given Shelton Code : ' ||
                              v_shltn_code || ' and Shelton CC : ' ||
                              v_department);
              
                IF (v_process_flag = 'R') THEN
                  /*Assigning it to Suspense Account*/
                  debug_message('-> Hence JE is Accounted to Suspense Account : ' ||
                                v_conc_suspense_account);
                
                  v_accr_offset_account := v_conc_suspense_account;
                  v_ime_code            := '000000';
                  v_ile_code            := '000000';
                  v_oracle_cc           := '000000';
                  v_project             := '0000000000';
                  v_reference           := '000000';
                
                  v_cc_err_msg       := 'CC+PROJ+REF does not exists for given Shelton Code : ' ||
                                        v_shltn_code ||
                                        ' and Shelton CC : ' ||
                                        v_department ||
                                        ' ; Hence JE is Accounted to Suspense Account : ' ||
                                        v_conc_suspense_account;
                  v_no_cc_flag       := 'Y';
                  v_err_msg          := v_cc_err_msg;
                  v_no_cc_flag       := 'Y';
                  v_upd_process_flag := 'CR';
                ELSE
                  v_err_msg          := v_err_msg || ' /' ||
                                        'CC+PROJ+REF does not exists for given Shelton Code : ' ||
                                        v_shltn_code ||
                                        ' and Shelton CC : ' ||
                                        v_department;
                  v_upd_process_flag := 'CR';
                  RAISE e_skip_to_next_rec;
                END IF;
              
              WHEN too_many_rows THEN
                debug_message('-> More than one CC+PROJ+REF exist for given Shelton Code : ' ||
                              v_shltn_code || ' and Shelton CC : ' ||
                              v_department);
                v_err_msg          := v_err_msg || ' /' ||
                                      'More than one CC+PROJ+REF exist for given Shelton Code : ' ||
                                      v_shltn_code || ' and Shelton CC : ' ||
                                      v_department;
                v_upd_process_flag := v_process_flag;
              WHEN OTHERS THEN
                debug_message('-> Exception in deriving CC+PROJ+REF for given Shelton Code : ' ||
                              v_shltn_code || ' and Shelton CC : ' ||
                              v_department || ' ->' || SQLERRM);
                v_err_msg          := v_err_msg || ' /' ||
                                      'Exception in deriving CC+PROJ+REF for given Shelton Code : ' ||
                                      v_shltn_code || ' and Shelton CC : ' ||
                                      v_department || ' ->' || SQLERRM;
                v_upd_process_flag := v_process_flag;
                RAISE e_skip_to_next_rec;
            END;
          END IF;
        
          BEGIN
            /*
            P_flag
            */
            SELECT gerfp_cc_proj_extend.chk_cc_proj_flag(v_oracle_cc)
              INTO p_flag
              FROM dual;
          
            IF p_flag = '-1'
               AND v_project <> '0000000000' THEN
              IF v_key_flag = -1 THEN
                RAISE e_flag;
              END IF;
            ELSIF (p_flag = '-1' AND v_project = '0000000000') THEN
              RAISE e_flag_proj_nd_c;
            END IF;
          
          EXCEPTION
            WHEN e_flag THEN
              debug_message('-> Invalid entry as Proj Req flag is Yes at Cost Center and Account Level');
              v_err_msg          := v_err_msg || ' /' ||
                                    'Invalid entry as Proj Req flag is Yes at Cost Center and Account Level';
              v_upd_process_flag := v_process_flag;
              RAISE e_skip_to_next_rec;
            WHEN e_flag_proj_nd_c THEN
              debug_message('-> The non-default project is required on cost center:' ||
                            v_oracle_cc);
              v_err_msg          := v_err_msg || ' /' ||
                                    'The non-default project is required on cost center:' ||
                                    v_oracle_cc;
              v_upd_process_flag := v_process_flag;
              RAISE e_skip_to_next_rec;
            WHEN OTHERS THEN
              debug_message('-> Exception in validating project for ' ||
                            v_department || ' ->' || SQLERRM);
              v_err_msg          := v_err_msg || ' /' ||
                                    'Exception in validating project for ' ||
                                    v_department || ' ->' || SQLERRM;
              v_upd_process_flag := v_process_flag;
              RAISE e_skip_to_next_rec;
          END;
        
          /*Details for Reversal for Next Non-Adjustment Period*/
          BEGIN
            v_start_date  := NULL;
            v_period_name := NULL;
          
            SELECT start_date,
                   period_name
              INTO v_start_date,
                   v_period_name
              FROM gl_periods
             WHERE start_date =
                   (SELECT end_date + 1
                      FROM gl_periods
                     WHERE period_set_name = 'RFP_CALENDAR'
                       AND v_concur_export_date BETWEEN start_date AND
                           end_date)
               AND period_set_name = 'RFP_CALENDAR'
               AND adjustment_period_flag = 'N';
          
          EXCEPTION
            WHEN no_data_found THEN
              debug_message('-> Next Period is NOT Found for Reversal');
              v_err_msg          := v_err_msg || ' /' ||
                                    'Next Period is NOT Found for Reversal';
              v_upd_process_flag := v_process_flag;
              RAISE e_skip_to_next_rec;
            WHEN too_many_rows THEN
              debug_message('-> More than one Period is Found for Reversal');
              v_err_msg          := v_err_msg || ' /' ||
                                    'More than one Period is Found for Reversal';
              v_upd_process_flag := v_process_flag;
              RAISE e_skip_to_next_rec;
            WHEN OTHERS THEN
              debug_message('-> Exception in deriving Next Period : ->' ||
                            SQLERRM);
              v_err_msg          := v_err_msg || ' /' ||
                                    'Exception in deriving Next Period : ->' ||
                                    SQLERRM;
              v_upd_process_flag := v_process_flag;
              RAISE e_skip_to_next_rec;
          END;
        
          v_reference10 := NULL;
          v_attribute10 := NULL;
        
          v_reference10 := v_first_name || '#' || v_last_name || '#' ||
                           v_glid || '#' || v_transaction_date||'#'||rec_concur_accr_rp_data.Ohr_Emp_Id;
          v_attribute10 := v_submission_name;
        
          --HOWLET 2-JUN-2012
          IF v_accr_offset_account = v_conc_suspense_account
             AND v_glid = 'PHCF01' THEN
            v_oracle_cc := 'NCDZM2';
          END IF;
        
          IF (v_glid = 'PHCF01') THEN
            v_default_cc := 'NCDZM2';
          ELSE
            v_default_cc := '000000';
          END IF;
        
          /*Check the Data and populate interface for Credit or Debit amount*/
          IF (v_process_flag = 'R') THEN
          
            BEGIN
              IF (v_debit_credit_indicator = 'DR') THEN
              
                /* CREATING FOR ORIGINAL JOURNAL IN CURRRENT PERIOD*/
                /*DR : If Net Amt Exists*/
                FOR j IN 1 .. 2
                LOOP
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
                     v_entity_iso_curr_code,
                     'A',
                     'Concur Accrual',
                     'Concur',
                     v_me_code,
                     v_le_code,
                     v_book_type,
                     decode(j,
                            1,
                            v_accr_offset_account,
                            v_sae_offset_account),
                     decode(j,
                            1,
                            v_oracle_cc,
                            v_default_cc),
                     decode(j,
                            1,
                            decode(p_flag,
                                   -1,
                                   v_project,
                                   0,
                                   v_project_1),
                            '0000000000'),
                     '000000',
                     '000000',
                     decode(j,
                            1,
                            v_reference,
                            '000000'),
                     '0',
                     '0',
                     decode(j,
                            1,
                            v_home_amount,
                            NULL), /*entered dr */
                     decode(j,
                            1,
                            NULL,
                            v_home_amount), /*entered cr */
                     NULL, /*accounted dr */
                     NULL, /*accounted_cr*/
                     --                     'CONC2GL ACCR Batch Number '||'"'||v_batch_id||v_accr_batch_seq||'"',
                     '"' || v_batch_id || v_accr_batch_seq || '"',
                     v_reference10,
                     v_attribute10,
                     v_concur_export_date,
                     'MOR',
                     NULL,
                     fnd_global.user_id,
                     SYSDATE,
                     g_group_id,
                     v_sob_id);
                END LOOP;
              
                /* CREATING FOR REVERSAL JOURNAL IN NEXT PERIOD*/
                /*DR : If Net Amt Exists*/
              
                FOR k IN 1 .. 2
                LOOP
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
                     reference4,
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
                     v_start_date,
                     v_entity_iso_curr_code,
                     'A',
                     'Concur Accrual Reversal',
                     'Concur',
                     v_me_code,
                     v_le_code,
                     v_book_type,
                     decode(k,
                            1,
                            v_sae_offset_account,
                            v_accr_offset_account),
                     decode(k,
                            1,
                            v_default_cc,
                            v_oracle_cc),
                     decode(k,
                            1,
                            '0000000000',
                            decode(p_flag,
                                   -1,
                                   v_project,
                                   0,
                                   v_project_1)),
                     '000000',
                     '000000',
                     decode(k,
                            1,
                            '000000',
                            v_reference),
                     '0',
                     '0',
                     decode(k,
                            1,
                            v_home_amount,
                            NULL), /*entered dr */
                     decode(k,
                            1,
                            NULL,
                            v_home_amount), /*entered cr */
                     NULL, /*accounted dr */
                     NULL, /*accounted_cr*/
                     'Reversal',
                     --                     'CONC2GL ACCR Batch Number '||'"'||v_batch_id||v_accr_batch_seq||'_REVERSAL"',
                     '"' || v_batch_id || v_accr_batch_seq || '_REVERSAL"',
                     v_reference10,
                     v_attribute10,
                     v_start_date,
                     'MOR',
                     NULL,
                     fnd_global.user_id,
                     SYSDATE,
                     g_group_id || '9',
                     v_sob_id);
                END LOOP;
              
              ELSIF (v_debit_credit_indicator = 'CR') THEN
              
                /* CREATING FOR ORIGINAL JOURNAL IN CURRRENT PERIOD*/
                /*CR : If Net Amt Exists*/
              
                FOR j IN 1 .. 2
                LOOP
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
                     v_entity_iso_curr_code,
                     'A',
                     'Concur Accrual',
                     'Concur',
                     v_me_code,
                     v_le_code,
                     v_book_type,
                     decode(j,
                            1,
                            v_accr_offset_account,
                            v_sae_offset_account),
                     decode(j,
                            1,
                            v_oracle_cc,
                            v_default_cc),
                     decode(j,
                            1,
                            decode(p_flag,
                                   -1,
                                   v_project,
                                   0,
                                   v_project_1),
                            '0000000000'),
                     '000000',
                     '000000',
                     decode(j,
                            1,
                            v_reference,
                            '000000'),
                     '0',
                     '0',
                     decode(j,
                            1,
                            NULL,
                            v_home_amount), /*entered dr */
                     decode(j,
                            1,
                            v_home_amount,
                            NULL), /*entered cr */
                     NULL, /*accounted dr */
                     NULL, /*accounted_cr*/
                     --                     'CONC2GL ACCR Batch Number '||'"'||v_batch_id||v_accr_batch_seq||'"',
                     '"' || v_batch_id || v_accr_batch_seq || '"',
                     v_reference10,
                     v_attribute10,
                     v_concur_export_date,
                     'MOR',
                     NULL,
                     fnd_global.user_id,
                     SYSDATE,
                     g_group_id,
                     v_sob_id);
                
                END LOOP;
              
                /* CREATING FOR REVERSAL JOURNAL IN NEXT PERIOD*/
                /*CR : If Net Amt Exists*/
              
                FOR k IN 1 .. 2
                LOOP
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
                     reference4,
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
                     v_start_date,
                     v_entity_iso_curr_code,
                     'A',
                     'Concur Accrual Reversal',
                     'Concur',
                     v_me_code,
                     v_le_code,
                     v_book_type,
                     decode(k,
                            1,
                            v_sae_offset_account,
                            v_accr_offset_account),
                     decode(k,
                            1,
                            v_default_cc,
                            v_oracle_cc),
                     decode(k,
                            1,
                            '0000000000',
                            decode(p_flag,
                                   -1,
                                   v_project,
                                   0,
                                   v_project_1)),
                     '000000',
                     '000000',
                     decode(k,
                            1,
                            '000000',
                            v_reference),
                     '0',
                     '0',
                     decode(k,
                            1,
                            NULL,
                            v_home_amount), /*entered dr */
                     decode(k,
                            1,
                            v_home_amount,
                            NULL), /*entered cr */
                     NULL, /*accounted dr */
                     NULL, /*accounted_cr*/
                     'Reversal',
                     --                     'CONC2GL ACCR Batch Number '||'"'||v_batch_id||v_accr_batch_seq||'_REVERSAL"',
                     '"' || v_batch_id || v_accr_batch_seq || '_REVERSAL"',
                     v_reference10,
                     v_attribute10,
                     v_start_date,
                     'MOR',
                     NULL,
                     fnd_global.user_id,
                     SYSDATE,
                     g_group_id || '9',
                     v_sob_id);
                END LOOP;
              END IF;
              /*End if for CR-DR Indicator*/
            EXCEPTION
              WHEN OTHERS THEN
                debug_message('-> Exception in Inserting data for R in GL Interface : -> ' ||
                              SQLERRM);
                v_err_msg          := v_err_msg || ' /' ||
                                      'Exception in Inserting data for R in GL Interface : -> ' ||
                                      SQLERRM;
                v_upd_process_flag := v_process_flag;
                RAISE e_skip_to_next_rec;
            END;
            /*else if CR then */
          ELSE
          
            BEGIN
              IF (v_debit_credit_indicator = 'DR') THEN
              
                /* CREATING FOR ORIGINAL JOURNAL IN CURRRENT PERIOD*/
                /*DR : If Net Amt Exists*/
                FOR j IN 1 .. 2
                LOOP
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
                     v_entity_iso_curr_code,
                     'A',
                     'Concur Accrual',
                     'Concur',
                     v_me_code,
                     v_le_code,
                     v_book_type,
                     decode(j,
                            1,
                            v_accr_offset_account,
                            v_conc_suspense_account),
                     decode(j,
                            1,
                            v_oracle_cc,
                            v_default_cc),
                     decode(j,
                            1,
                            decode(p_flag,
                                   -1,
                                   v_project,
                                   0,
                                   v_project_1),
                            '0000000000'),
                     '000000',
                     '000000',
                     decode(j,
                            1,
                            v_reference,
                            '000000'),
                     '0',
                     '0',
                     decode(j,
                            1,
                            v_home_amount,
                            NULL), /*entered dr */
                     decode(j,
                            1,
                            NULL,
                            v_home_amount), /*entered cr */
                     NULL, /*accounted dr */
                     NULL, /*accounted_cr*/
                     --                     'CONC2GL ACCR Batch Number '||'"'||v_batch_id||v_accr_batch_seq||'"',
                     '"' || v_batch_id || v_accr_batch_seq || '"',
                     v_reference10,
                     v_attribute10,
                     v_concur_export_date,
                     'MOR',
                     NULL,
                     fnd_global.user_id,
                     SYSDATE,
                     g_group_id,
                     v_sob_id);
                END LOOP;
              
                /* CREATING FOR REVERSAL JOURNAL IN NEXT PERIOD*/
                /*DR : If Net Amt Exists*/
              
                FOR k IN 1 .. 2
                LOOP
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
                     reference4,
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
                     v_start_date,
                     v_entity_iso_curr_code,
                     'A',
                     'Concur Accrual Reversal',
                     'Concur',
                     v_me_code,
                     v_le_code,
                     v_book_type,
                     decode(k,
                            1,
                            v_conc_suspense_account,
                            v_accr_offset_account),
                     decode(k,
                            1,
                            v_default_cc,
                            v_oracle_cc),
                     decode(k,
                            1,
                            '0000000000',
                            decode(p_flag,
                                   -1,
                                   v_project,
                                   0,
                                   v_project_1)),
                     '000000',
                     '000000',
                     decode(k,
                            1,
                            '000000',
                            v_reference),
                     '0',
                     '0',
                     decode(k,
                            1,
                            v_home_amount,
                            NULL), /*entered dr */
                     decode(k,
                            1,
                            NULL,
                            v_home_amount), /*entered cr */
                     NULL, /*accounted dr */
                     NULL, /*accounted_cr*/
                     'Reversal',
                     --                     'CONC2GL ACCR Batch Number '||'"'||v_batch_id||v_accr_batch_seq||'_REVERSAL"',
                     '"' || v_batch_id || v_accr_batch_seq || '_REVERSAL"',
                     v_reference10,
                     v_attribute10,
                     v_start_date,
                     'MOR',
                     NULL,
                     fnd_global.user_id,
                     SYSDATE,
                     g_group_id || '9',
                     v_sob_id);
                END LOOP;
              
              ELSIF (v_debit_credit_indicator = 'CR') THEN
              
                /* CREATING FOR ORIGINAL JOURNAL IN CURRRENT PERIOD*/
                /*CR : If Net Amt Exists*/
              
                FOR j IN 1 .. 2
                LOOP
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
                     v_entity_iso_curr_code,
                     'A',
                     'Concur Accrual',
                     'Concur',
                     v_me_code,
                     v_le_code,
                     v_book_type,
                     decode(j,
                            1,
                            v_accr_offset_account,
                            v_conc_suspense_account),
                     decode(j,
                            1,
                            v_oracle_cc,
                            v_default_cc),
                     decode(j,
                            1,
                            decode(p_flag,
                                   -1,
                                   v_project,
                                   0,
                                   v_project_1),
                            '0000000000'),
                     '000000',
                     '000000',
                     decode(j,
                            1,
                            v_reference,
                            '000000'),
                     '0',
                     '0',
                     decode(j,
                            1,
                            NULL,
                            v_home_amount), /*entered dr */
                     decode(j,
                            1,
                            v_home_amount,
                            NULL), /*entered cr */
                     NULL, /*accounted dr */
                     NULL, /*accounted_cr*/
                     --                     'CONC2GL ACCR Batch Number '||'"'||v_batch_id||v_accr_batch_seq||'"',
                     '"' || v_batch_id || v_accr_batch_seq || '"',
                     v_reference10,
                     v_attribute10,
                     v_concur_export_date,
                     'MOR',
                     NULL,
                     fnd_global.user_id,
                     SYSDATE,
                     g_group_id,
                     v_sob_id);
                
                END LOOP;
              
                /* CREATING FOR REVERSAL JOURNAL IN NEXT PERIOD*/
                /*CR : If Net Amt Exists*/
              
                FOR k IN 1 .. 2
                LOOP
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
                     reference4,
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
                     v_start_date,
                     v_entity_iso_curr_code,
                     'A',
                     'Concur Accrual Reversal',
                     'Concur',
                     v_me_code,
                     v_le_code,
                     v_book_type,
                     decode(k,
                            1,
                            v_conc_suspense_account,
                            v_accr_offset_account),
                     decode(k,
                            1,
                            v_default_cc,
                            v_oracle_cc),
                     decode(k,
                            1,
                            '0000000000',
                            decode(p_flag,
                                   -1,
                                   v_project,
                                   0,
                                   v_project_1)),
                     '000000',
                     '000000',
                     decode(k,
                            1,
                            '000000',
                            v_reference),
                     '0',
                     '0',
                     decode(k,
                            1,
                            NULL,
                            v_home_amount), /*entered dr */
                     decode(k,
                            1,
                            v_home_amount,
                            NULL), /*entered cr */
                     NULL, /*accounted dr */
                     NULL, /*accounted_cr*/
                     'Reversal',
                     --                     'CONC2GL ACCR Batch Number '||'"'||v_batch_id||v_accr_batch_seq||'_REVERSAL"',
                     '"' || v_batch_id || v_accr_batch_seq || '_REVERSAL"',
                     v_reference10,
                     v_attribute10,
                     v_start_date,
                     'MOR',
                     NULL,
                     fnd_global.user_id,
                     SYSDATE,
                     g_group_id || '9',
                     v_sob_id);
                END LOOP;
              END IF;
              /*End if for CR-DR Indicator*/
            EXCEPTION
              WHEN OTHERS THEN
                debug_message('-> Exception in Inserting data for CR in GL Interface : -> ' ||
                              SQLERRM);
                v_err_msg          := v_err_msg || ' /' ||
                                      'Exception in Inserting data for CR in GL Interface : -> ' ||
                                      SQLERRM;
                v_upd_process_flag := v_process_flag;
                RAISE e_skip_to_next_rec;
            END;
          END IF;
          /*End if for R and CR*/
        
          UPDATE gerfp_congl_accr_stg
             SET process_flag = v_upd_process_flag,
                 err_msg      = decode(v_upd_process_flag,
                                       'P',
                                       NULL,
                                       v_err_msg)
           WHERE ROWID = rec_concur_accr_rp_data.rowid;
        
        EXCEPTION
          /*LOOP EXCEPTION*/
          WHEN e_skip_to_next_rec THEN
            debug_message('--> Updating staging table with error message..');
          
            UPDATE gerfp_congl_accr_stg
               SET process_flag = v_upd_process_flag,
                   err_msg      = v_err_msg
             WHERE ROWID = rec_concur_accr_rp_data.rowid;
            retcode := '1';
            COMMIT;
          
          WHEN OTHERS THEN
            debug_message('--> Updating staging table with OTHER exception message..');
          
            v_err_msg := v_err_msg ||
                         'Exception in Processing Information - ' ||
                         SQLERRM;
          
            UPDATE gerfp_congl_accr_stg
               SET process_flag = v_process_flag,
                   err_msg      = v_err_msg
             WHERE ROWID = rec_concur_accr_rp_data.rowid;
            retcode := '2';
            COMMIT;
          
        END;
      
        /*INSIDE FOR-LOOP BEGIN..END*/
        v_err_msg                := NULL;
        v_last_name              := NULL;
        v_upd_process_flag       := NULL;
        v_first_name             := NULL;
        v_glid                   := NULL;
        v_department             := NULL;
        v_submission_name        := NULL;
        v_transaction_date       := NULL;
        v_entity_iso_curr_code   := NULL;
        v_home_amount            := NULL;
        v_debit_credit_indicator := NULL;
        v_hh_description         := NULL;
        v_concur_export_date     := NULL;
      
      END LOOP;
      /*Main Loop End*/
    
    END LOOP;
  
    /*Check for Duplicate file processing */
    FOR t IN 1 .. 2
    LOOP
    
      SELECT decode(t,
                    1,
                    'Original Entries',
                    'Reversal Entries')
        INTO g_entries
        FROM dual;
    
      SELECT decode(t,
                    1,
                    g_group_id,
                    g_group_id || '9')
        INTO tot_group_id
        FROM dual;
    
      SELECT decode(t,
                    1,
                    'Concur Accrual',
                    'Concur Accrual Reversal')
        INTO tot_category_name
        FROM dual;
    
      debug_message('Checking Duplicate File Process for : ' || g_entries ||
                    ' under JE Category : ' || tot_category_name);
    
      FOR rec_iface_data IN cur_iface_data(p_source   => 'Concur',
                                           p_category => tot_category_name
                                           -- , p_group_id => tot_group_id
                                           )
      LOOP
        v_chk_status := NULL;
      
        check_dup_file_process(p_sob_id       => rec_iface_data.sob_id,
                               p_batch_number => rec_iface_data.batch_name,
                               p_category     => rec_iface_data.category_name,
                               x_status       => v_chk_status);
      
        --            v_final_chk_status := v_final_chk_status||v_chk_status;
      
        IF (v_chk_status = 'Y') THEN
        
          debug_message(' Already processed and Journal exist for this batch for ' ||
                        g_entries || ': ' || rec_iface_data.batch_name ||
                        ' under SOB Name : ' || rec_iface_data.sob_name);
          debug_message('*** Purging records from Interface table for this batch ..');
        
          fnd_file.put_line(fnd_file.output,
                            ' Already processed and Journal exist for this batch : ' ||
                            rec_iface_data.batch_name ||
                            ' under SOB Name : ' || rec_iface_data.sob_name);
          fnd_file.put_line(fnd_file.output,
                            '*** Purging records from Interface table for this batch ..');
        
          DELETE FROM gl_interface
           WHERE
          --group_id=tot_group_id
           group_id = rec_iface_data.group_id
           AND set_of_books_id = rec_iface_data.sob_id
           AND reference6 = rec_iface_data.batch_name
           AND user_je_category_name = rec_iface_data.category_name;
        
          COMMIT;
        END IF;
      
      END LOOP;
    
      /*To Submit Journal Import Program*/
      debug_message(' Journal Import Program Submission Process for : ' ||
                    g_entries);
      debug_message(' ------------------------------------------------------------------ ');
      BEGIN
      
        debug_message(' Checking Records in Interface Table ');
      
        BEGIN
          SELECT COUNT(1)
            INTO v_intr_rec_cnt
            FROM gl_interface
           WHERE user_je_source_name = 'Concur'
             AND user_je_category_name = tot_category_name;
          --AND group_id=cur_iface_data.group_id;
        
          IF nvl(v_intr_rec_cnt,
                 0) = 0 THEN
            debug_message(' No Records in Interface Table for Source Concur');
            --          RAISE e_end_program;
          ELSE
          
            debug_message(' No. of Records in Interface Table for Source Concur is ' ||
                          nvl(v_intr_rec_cnt,
                              0));
            debug_message(' Submit JOURNAL IMPORT Program   ');
          
            FOR rec_iface_data IN cur_iface_data(p_source   => 'Concur',
                                                 p_category => tot_category_name
                                                 --, p_group_id => tot_group_id
                                                 )
            LOOP
              debug_message(' Number of Records for SOB# ' ||
                            rec_iface_data.sob_name || ' , Batch # ' ||
                            rec_iface_data.batch_name || ' is :' ||
                            rec_iface_data.rec_cnt);
              debug_message('Group Id Derived - ' ||
                            rec_iface_data.group_id);
              submit_journal_import(p_user_id  => v_userid,
                                    p_resp_id  => v_resp_id,
                                    p_sob_id   => rec_iface_data.sob_id,
                                    p_group_id => rec_iface_data.group_id,
                                    p_source   => 'Concur',
                                    x_status   => v_import_status);
            
              debug_message('--> Journal Import Program Submitted ..');
              debug_message(' JOURNAL IMPORT Program Status for SOB# ' ||
                            rec_iface_data.sob_name || ' is ' ||
                            v_import_status);
            
            END LOOP;
          
          END IF;
        END;
      
        debug_message(' ------------------------------------------------------------------ ');
      
      END;
    END LOOP;
  
    display_err_rp_congl(v_conc_request);
  
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
    
  END reprocess_gl_accr_data;

  /***************************************************/
  /*               PROCEDURE FOR ERROR REPORT        */
  /***************************************************/

  PROCEDURE display_err_rp_congl(p_request_id IN NUMBER) IS
  
    CURSOR cur_err_rp_cgl IS
      SELECT *
        FROM gerfp_congl_accr_stg
       WHERE process_flag IN ('R',
                              'CR')
         AND err_msg IS NOT NULL
         AND concur_req_id = p_request_id;
  
    v_err_buffer VARCHAR2(4000);
    v_err_cnt    NUMBER;
  
  BEGIN
  
    fnd_file.put_line(fnd_file.output,
                      '************************************  Concur TO GL ACCURAL Re-Processed Error Record Details  *******************************************');
    fnd_file.put_line(fnd_file.output,
                      '  ');
    fnd_file.put_line(fnd_file.output,
                      '********************************************************************************************************************');
  
    fnd_file.put_line(fnd_file.output,
                      '  ');
    fnd_file.put_line(fnd_file.output,
                      rpad('-',
                           350,
                           '-'));
    fnd_file.put_line(fnd_file.output,
                      rpad('Detail Format Ind',
                           20) || chr(9) || rpad('CC Trans Key',
                                                 20) || chr(9) ||
                      rpad('Last Name',
                           15) || chr(9) || rpad('First Name',
                                                 15) || chr(9) ||
                      rpad('GLID',
                           10) || chr(9) || rpad('Department',
                                                 15) || chr(9) ||
                      rpad('Transaction#',
                           20) || chr(9) || rpad('Transaction Date',
                                                 20) || chr(9) ||
                      rpad('Entity ISO Currency Code',
                           25) || chr(9) || rpad('CR/DR Indicator',
                                                 18) || chr(9) ||
                      rpad('Home Amount',
                           15) || chr(9) || rpad('Process Flag',
                                                 20) || chr(9) ||
                      rpad('Error Message',
                           150));
    fnd_file.put_line(fnd_file.output,
                      rpad('-',
                           350,
                           '-'));
  
    /*Fetching the count of error records*/
    BEGIN
    
      SELECT COUNT(1)
        INTO v_err_cnt
        FROM gerfp_congl_accr_stg
       WHERE process_flag IN ('R',
                              'CR')
         AND err_msg IS NOT NULL
         AND concur_req_id = p_request_id;
    
    EXCEPTION
      WHEN no_data_found THEN
        v_err_cnt := 0;
      WHEN OTHERS THEN
        fnd_file.put_line(fnd_file.output,
                          'EXCEPTION IN FETCHING COUNT  ' || SQLERRM);
    END;
  
    IF (v_err_cnt > 0) THEN
    
      FOR rec_err_rp_cgl IN cur_err_rp_cgl
      LOOP
      
        SELECT rpad(rec_err_rp_cgl.detail_format_ind,
                    20) || chr(9) || rpad(rec_err_rp_cgl.cc_trans_key,
                                          20) || chr(9) ||
               rpad(rec_err_rp_cgl.last_name,
                    15) || chr(9) || rpad(rec_err_rp_cgl.first_name,
                                          15) || chr(9) ||
               rpad(rec_err_rp_cgl.glid,
                    10) || chr(9) || rpad(rec_err_rp_cgl.department,
                                          15) || chr(9) ||
               rpad(rec_err_rp_cgl.transaction_number,
                    20) || chr(9) || rpad(rec_err_rp_cgl.transaction_date,
                                          20) || chr(9) ||
               rpad(rec_err_rp_cgl.entity_iso_curr_code,
                    25) || chr(9) || rpad(rec_err_rp_cgl.debit_credit_indicator,
                                          18) || chr(9) ||
               rpad(nvl(rec_err_rp_cgl.home_amount,
                        0),
                    15) || chr(9) || rpad(rec_err_rp_cgl.process_flag,
                                          15) || chr(9) ||
               rpad(rec_err_rp_cgl.err_msg,
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
                        '                           *** No Errored Re-Processed Accural Concur Entries ***');
    END IF;
  
    fnd_file.put_line(fnd_file.output,
                      '      ');
    fnd_file.put_line(fnd_file.output,
                      rpad('-',
                           350,
                           '-'));
  
  EXCEPTION
    WHEN no_data_found THEN
      fnd_file.put_line(fnd_file.output,
                        'NO DATA FOUND ' || SQLERRM);
    WHEN OTHERS THEN
      fnd_file.put_line(fnd_file.output,
                        'EXCEPTION :  ' || SQLERRM);
    
  END display_err_rp_congl;

END gerfp_conc_gl_accr_rp_pkg;
/
