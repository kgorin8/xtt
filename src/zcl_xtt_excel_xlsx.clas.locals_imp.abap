**********************************************************************
**********************************************************************
CLASS cl_ex_sheet IMPLEMENTATION.
*--------------------------------------------------------------------*
  METHOD constructor.
    DATA:
      l_sheet_ind     TYPE string,
      lo_row          TYPE REF TO if_ixml_element,
      lo_col          TYPE REF TO if_ixml_element,
      lo_cell         TYPE REF TO if_ixml_element,
      ls_cell         TYPE REF TO ts_ex_cell,
      lo_merge_cell   TYPE REF TO if_ixml_element,
      lo_data_valid   TYPE REF TO if_ixml_element,
      l_val           TYPE string,
      ls_area         TYPE REF TO ts_ex_area,
      ls_cell_beg     TYPE REF TO ts_ex_cell,
      ls_cell_end     TYPE REF TO ts_ex_cell,
      ls_defined_name TYPE REF TO ts_ex_defined_name,
      ls_list_object  TYPE REF TO ts_ex_list_object,
      l_prev_row      TYPE i,
      l_prev_col      TYPE i,
      lv_ind          TYPE i,
      lv_name         TYPE string,
      ls_blank        TYPE ts_ex_cell.

    " Path to the sheet
    int_2_text iv_ind l_sheet_ind.
    CONCATENATE `xl/worksheets/sheet` l_sheet_ind `.xml` INTO mv_full_path. "#EC NOTEXT

    " Content as an object
    zcl_xtt_util=>xml_from_zip(
     EXPORTING
       io_zip     = io_xlsx->mo_zip
       iv_name    = mv_full_path
     IMPORTING
       eo_xmldoc  = mo_dom ).

***************************************
    " Loop through excels rows
    lo_row ?= mo_dom->find_from_name( 'row' ).              "#EC NOTEXT
    WHILE lo_row IS BOUND.
      " Add new row
      zcl_xtt_excel_xlsx=>row_read_xml(
       EXPORTING
        io_node = lo_row
       CHANGING
        ct_rows = mt_rows ).

      " Loop through excels cells
      lo_cell = lo_row->find_from_name( 'c' ).              "#EC NOTEXT
      WHILE lo_cell IS BOUND.
        io_xlsx->cell_read_xml(
         EXPORTING
          io_node  = lo_cell
         CHANGING
          ct_cells = mt_cells ).

        " Add by key
        "INSERT ls_cell INTO TABLE lt_cells_hash.
        lo_cell ?= lo_cell->get_next( ).
      ENDWHILE.

      lo_row ?= lo_row->get_next( ).
    ENDWHILE.

    " No need already sorted
    "SORT mt_cells BY table_line->c_row table_line->c_col_ind.
***************************************

    " Loop through excels columns
    lo_col ?= mo_dom->find_from_name( 'col' ).              "#EC NOTEXT
    WHILE lo_col IS BOUND.
      " Add new col
      zcl_xtt_excel_xlsx=>column_read_xml(
       EXPORTING
        io_node = lo_col
       CHANGING
        ct_columns = mt_columns ).

      lo_col ?= lo_col->get_next( ).
    ENDWHILE.

***************************************
    lo_merge_cell ?= mo_dom->find_from_name( 'mergeCell' ). "#EC NOTEXT
    WHILE lo_merge_cell IS BOUND.
      " Create new area
      l_val = lo_merge_cell->get_attribute( 'ref' ).        "#EC NOTEXT
      CREATE DATA ls_area.
      zcl_xtt_excel_xlsx=>area_read_xml(
         iv_value = l_val
         is_area  = ls_area ).

      " Always 2 cells
      READ TABLE ls_area->a_cells REFERENCE INTO ls_cell_beg INDEX 1.
      READ TABLE ls_area->a_cells REFERENCE INTO ls_cell_end INDEX 2.

      " Get ref to existing or ls_cell_beg cell
      ls_cell = find_cell( ls_cell_beg->* ).

      " Fill dx
      ls_cell->c_merge_row_dx = ls_cell_end->c_row     - ls_cell_beg->c_row.
      ls_cell->c_merge_col_dx = ls_cell_end->c_col_ind - ls_cell_beg->c_col_ind.

      " Next
      lo_merge_cell ?= lo_merge_cell->get_next( ).
    ENDWHILE.
***************************************

    lo_data_valid ?= mo_dom->find_from_name( 'dataValidation' ). "#EC NOTEXT
    WHILE lo_data_valid IS BOUND.
      APPEND INITIAL LINE TO mt_data_valid REFERENCE INTO ls_area.

      " Create new area
      l_val = lo_data_valid->get_attribute( 'sqref' ).      "#EC NOTEXT
      zcl_xtt_excel_xlsx=>area_read_xml(
         iv_value = l_val
         is_area  = ls_area ).

      LOOP AT ls_area->a_cells REFERENCE INTO ls_cell.
        " Get existing cell Or insert new one
        find_cell( ls_cell->* ).
      ENDLOOP.

      " Next
      lo_data_valid ?= lo_data_valid->get_next( ).
    ENDWHILE.

***************************************
    " Defined name contains areas
    mv_name = io_node->get_attribute( `name` ).             "#EC NOTEXT
    LOOP AT io_xlsx->mt_defined_names REFERENCE INTO ls_defined_name.
      LOOP AT ls_defined_name->d_areas REFERENCE INTO ls_area WHERE a_sheet_name = mv_name.
        " Reference to reference
        LOOP AT ls_area->a_cells REFERENCE INTO ls_cell.
          " Get existing cell Or insert new one
          find_cell( ls_cell->* ).
        ENDLOOP.
      ENDLOOP.
    ENDLOOP.

***************************************
    " Find related list objects
    CONCATENATE `xl/worksheets/_rels/sheet` l_sheet_ind `.xml.rels` INTO l_val. "#EC NOTEXT
    io_xlsx->list_object_read_xml(
     EXPORTING
      iv_path        = l_val
     CHANGING
      ct_list_objects = mt_list_objects ).

    LOOP AT mt_list_objects REFERENCE INTO ls_list_object.
      LOOP AT ls_list_object->area-a_cells REFERENCE INTO ls_cell.
        " Get existing cell Or insert new one
        find_cell( ls_cell->* ).
      ENDLOOP.
    ENDLOOP.

***************************************

    LOOP AT mt_cells REFERENCE INTO ls_cell WHERE c_value CS `;direction=column`. "#EC NOTEXT
      " Use columns
      lv_ind = sy-fdpos - 1.
      lv_name = ls_cell->c_value+1(lv_ind).
      INSERT lv_name INTO TABLE mt_column_dir.
      CLEAR ls_cell->c_value.

      " Add blank cell
      CHECK ls_cell->c_col_ind > 1.
      ls_blank-c_row     = ls_cell->c_row.
      ls_blank-c_col_ind = ls_cell->c_col_ind - 1.
      find_cell( ls_blank ).
    ENDLOOP.

***************************************
    " Write offest
    l_prev_row = 0.
    l_prev_col = 0.
    LOOP AT mt_cells REFERENCE INTO ls_cell.
      " If new row ls_cell->c_row_dx > 0
      ls_cell->c_row_dx = ls_cell->c_row     - l_prev_row.

      " If new row then column also from 0
      IF ls_cell->c_row_dx <> 0.
        l_prev_col = 0.
      ENDIF.
      ls_cell->c_col_dx = ls_cell->c_col_ind - l_prev_col.

      l_prev_row = ls_cell->c_row.
      l_prev_col = ls_cell->c_col_ind.
    ENDLOOP.

***************************************
  ENDMETHOD.                    "constructor
*--------------------------------------------------------------------*
  METHOD find_cell.
    DATA:
      ls_row TYPE ts_ex_row.

    READ TABLE mt_cells BINARY SEARCH REFERENCE INTO rr_ex_cell WITH KEY " with table key
      c_row = ir_cell-c_row c_col_ind = ir_cell-c_col_ind.
    IF sy-subrc <> 0.
      INSERT ir_cell INTO mt_cells INDEX sy-tabix REFERENCE INTO rr_ex_cell.

      READ TABLE mt_rows TRANSPORTING NO FIELDS
       WITH TABLE KEY r = ir_cell-c_row.
      IF sy-subrc <> 0.
        ls_row-r = sy-tabix.
        INSERT ls_row INTO TABLE mt_rows.
      ENDIF.
    ENDIF.
  ENDMETHOD.
*--------------------------------------------------------------------*
  METHOD fill_shared_strings.
    DATA:
     ls_cell TYPE REF TO ts_ex_cell.

    " Add one by one
    LOOP AT mt_cells REFERENCE INTO ls_cell. "WHERE c_value IS NOT INITIAL.
      CHECK zcl_xtt_excel_xlsx=>cell_is_string( ls_cell ) = abap_true.
      APPEND ls_cell->c_value TO ct_shared_strings.
    ENDLOOP.
  ENDMETHOD.                    "fill_shared_strings
*--------------------------------------------------------------------*
  METHOD save.
    DATA:
      l_sheet_data    TYPE string,
      l_merge_cells   TYPE string,
      l_merge_cnt     TYPE i,
      ls_cell         TYPE REF TO ts_ex_cell,
      ls_row          TYPE REF TO ts_ex_row,
      ls_blank_row    TYPE REF TO ts_ex_row,
      l_new_row_ind   TYPE i,
      l_new_col_ind   TYPE i,
      l_str           TYPE string,
      lo_data_valid   TYPE REF TO if_ixml_element,
      lo_mc           TYPE REF TO if_ixml_element,
      ls_list_object  TYPE REF TO ts_ex_list_object,
      lt_columns      LIKE mt_columns,
      ls_column       TYPE ts_ex_column,
      lv_columns_text TYPE string,
      lr_cell_ref     TYPE REF TO ts_cell_ref,
      ls_cell_ref     TYPE ts_cell_ref,
      ls_defined_name TYPE REF TO ts_ex_defined_name,
      ls_area         TYPE REF TO ts_ex_area,
      lv_address      TYPE string,
      lo_table        TYPE REF TO if_ixml_element.

    " Blank sheet
    CHECK mt_cells IS NOT INITIAL.

*****************
    " Find old -> new match
    LOOP AT mt_cells REFERENCE INTO ls_cell.
      READ TABLE mt_cell_ref REFERENCE INTO lr_cell_ref
       WITH TABLE KEY r = ls_cell->c_row
                      c = ls_cell->c_col_ind.

      IF sy-subrc <> 0.
        ls_cell_ref-r   = ls_cell->c_row.
        ls_cell_ref-c   = ls_cell->c_col_ind.
        ls_cell_ref-beg = ls_cell.
        INSERT ls_cell_ref INTO TABLE mt_cell_ref REFERENCE INTO lr_cell_ref.
      ENDIF.

      lr_cell_ref->end = ls_cell.
    ENDLOOP.
*****************

    " Write cells data one by one
    CREATE DATA ls_blank_row.
    LOOP AT mt_cells REFERENCE INTO ls_cell.
      " New row index as a string
      l_new_row_ind = l_new_row_ind + ls_cell->c_row_dx.

      " New row
      IF ls_cell->c_row_dx > 0.
        l_new_col_ind = 0.
        " Closing tag
        IF l_sheet_data IS NOT INITIAL.
          CONCATENATE l_sheet_data `</row>` INTO l_sheet_data.
        ENDIF.

        " Read by previous key
        READ TABLE mt_rows WITH TABLE KEY r = ls_cell->c_row REFERENCE INTO ls_row.
        IF sy-subrc = 0.
          zcl_xtt_excel_xlsx=>row_write_xml(
           EXPORTING
            is_row           = ls_row
            iv_new_row       = l_new_row_ind
            iv_outline_level = ls_cell->c_row_outline
           CHANGING
            cv_sheet_data    = l_sheet_data ).
        ELSE.
          ls_blank_row->r = ls_cell->c_row.
          zcl_xtt_excel_xlsx=>row_write_xml(
           EXPORTING
            is_row           = ls_blank_row
            iv_new_row       = l_new_row_ind
            iv_outline_level = ls_cell->c_row_outline
           CHANGING
            cv_sheet_data    = l_sheet_data ).
        ENDIF.
      ENDIF.

***********
      " New column
      l_new_col_ind = l_new_col_ind + ls_cell->c_col_dx.

      DO 1 TIMES.
        " Existing old column
        READ TABLE mt_columns INTO ls_column
         WITH TABLE KEY min = ls_cell->c_col_ind.

        " Prog error
        CHECK sy-subrc = 0.

        IF ls_column-outline_skip = abap_true.
          CLEAR ls_column-outlinelevel.
        ENDIF.

        " New outline
        IF ls_cell->c_column_outline IS NOT INITIAL.
          int_2_text ls_cell->c_column_outline ls_column-outlinelevel.
        ENDIF.

        IF l_new_col_ind <> ls_cell->c_col_ind.
          ls_column-min = ls_column-max = l_new_col_ind.
        ENDIF.
        INSERT ls_column INTO TABLE lt_columns.
      ENDDO.
***********

      " Append cell info
      io_xlsx->cell_write_xml(
       EXPORTING
        is_cell         = ls_cell
        iv_new_row      = l_new_row_ind
        iv_new_col_ind  = l_new_col_ind
       CHANGING
        cv_sheet_data   = l_sheet_data
        cv_merge_cnt    = l_merge_cnt
        cv_merge_cells  = l_merge_cells ).
    ENDLOOP.

    " New columns
    lv_columns_text = zcl_xtt_excel_xlsx=>column_write_xml(
     it_columns = lt_columns ).

    " Closing tag
    CONCATENATE l_sheet_data `</row>` INTO l_sheet_data.

***************************************
    " Replace existing text
    xml_repleace_node(
     iv_tag_name  = 'sheetData'                             "#EC NOTEXT
     iv_repl_text = '_SHEET_DATA_' ).

    xml_repleace_node(
     iv_tag_name  = 'cols'                                  "#EC NOTEXT
     iv_repl_text = '_NEW_COLUMNS_' ).

    lo_mc = xml_repleace_node(
     iv_tag_name  = 'mergeCells'                            "#EC NOTEXT
     iv_repl_text = '_MERGE_CELLS_' ).

    " Change count
    IF lo_mc IS NOT INITIAL AND l_merge_cnt > 0.
      int_2_text l_merge_cnt l_str.
      lo_mc->set_attribute( name = 'count' value = l_str ). "#EC NOTEXT
    ENDIF.

    " Data validation
    IF mt_data_valid IS NOT INITIAL.
      lo_data_valid ?= mo_dom->find_from_name( 'dataValidation' ). "#EC NOTEXT
      LOOP AT mt_data_valid REFERENCE INTO ls_area.
        CHECK lo_data_valid IS NOT INITIAL.

        " Change
        replace_with_new( ls_area ).

        lv_address = zcl_xtt_excel_xlsx=>area_get_address(
          is_area     = ls_area
          iv_no_bucks = abap_true ).

        lo_data_valid->set_attribute( name = 'sqref' value = lv_address ). "#EC NOTEXT

        " Next
        lo_data_valid ?= lo_data_valid->get_next( ).
      ENDLOOP.
    ENDIF.

    " Transform to string
    zcl_xtt_util=>xml_to_str(
     EXPORTING
       io_doc    = mo_dom
     IMPORTING
       ev_str    = l_str ).

    " Do replcement
    REPLACE FIRST OCCURRENCE OF '_SHEET_DATA_'  IN l_str WITH l_sheet_data. "#EC NOTEXT
    REPLACE FIRST OCCURRENCE OF '_NEW_COLUMNS_' IN l_str WITH lv_columns_text. "#EC NOTEXT
    IF lo_mc IS NOT INITIAL AND l_merge_cnt > 0.
      REPLACE FIRST OCCURRENCE OF '_MERGE_CELLS_' IN l_str WITH l_merge_cells. "#EC NOTEXT
    ENDIF.

    " Replace XML file
    zcl_xtt_util=>xml_to_zip(
     io_zip  = io_xlsx->mo_zip
     iv_name = mv_full_path
     iv_sdoc = l_str ).

***************************************

    LOOP AT io_xlsx->mt_defined_names REFERENCE INTO ls_defined_name.
      LOOP AT ls_defined_name->d_areas REFERENCE INTO ls_area WHERE a_sheet_name = mv_name.
        replace_with_new( ls_area ).
      ENDLOOP.
    ENDLOOP.

    " List object
    LOOP AT mt_list_objects REFERENCE INTO ls_list_object.
      " Get address
      GET REFERENCE OF ls_list_object->area INTO ls_area.

      " Change cells
      replace_with_new( ls_area ).

      lv_address = zcl_xtt_excel_xlsx=>area_get_address(
       is_area     = ls_area
       iv_no_bucks = abap_true ).
      CHECK lv_address IS NOT INITIAL.

      " Change area
      lo_table = ls_list_object->dom->get_root_element( ).
      lo_table->set_attribute( name = 'ref' value = lv_address ). "#EC NOTEXT

      " Replace in zip
      zcl_xtt_util=>xml_to_zip(
       io_zip     = io_xlsx->mo_zip
       iv_name    = ls_list_object->arc_path
       io_xmldoc  = ls_list_object->dom ).
    ENDLOOP.
  ENDMETHOD.                    "save
*--------------------------------------------------------------------*
  METHOD replace_with_new.
    DATA:
      lr_cell     TYPE REF TO ts_ex_cell,
      lr_cell_ref TYPE REF TO ts_cell_ref,
      lv_tabix    TYPE sytabix.

    LOOP AT ir_area->a_cells REFERENCE INTO lr_cell.
      lv_tabix = sy-tabix.

      " OLD -> NEW
      READ TABLE mt_cell_ref REFERENCE INTO lr_cell_ref
       WITH TABLE KEY r = lr_cell->c_row
                      c = lr_cell->c_col_ind.
      CHECK sy-subrc = 0.

      CASE lv_tabix.
          " First occurrence
        WHEN 1.
          lr_cell->* = lr_cell_ref->beg->*.

          " Last occurrence
        WHEN 2.
          lr_cell->* = lr_cell_ref->end->*.
      ENDCASE.
    ENDLOOP.

    " Add additional cell to the eand
    IF lv_tabix = 1 AND lr_cell_ref IS NOT INITIAL.
      APPEND lr_cell_ref->end->* TO ir_area->a_cells.
    ENDIF.
  ENDMETHOD.
*--------------------------------------------------------------------*
  METHOD merge.
    DATA:
      lo_new_replace_block TYPE REF TO zcl_xtt_replace_block,
      lr_field             TYPE REF TO zcl_xtt_replace_block=>ts_field,
      lr_field2            TYPE REF TO zcl_xtt_replace_block=>ts_field,
      lt_cells_end         LIKE ct_cells,
      lt_cells_mid         LIKE ct_cells,
      lt_copy              LIKE ct_cells,
      lt_cell_match        TYPE tt_cell_match,
      lo_tree_handler      TYPE REF TO lcl_tree_handler,
      lr_tree              TYPE REF TO zcl_xtt_replace_block=>ts_tree,
      lv_by_column         TYPE abap_bool.
    FIELD-SYMBOLS:
      <lt_items> TYPE ANY TABLE.
*      <ls_item>  TYPE any.
***************************************
    " merge-1 @see ME->MATCH_FOUND
    SET HANDLER match_found FOR io_replace_block ACTIVATION abap_true.

    " Current cell
    LOOP AT ct_cells REFERENCE INTO ms_cell WHERE c_formula IS INITIAL.
      " @see match_found
      io_replace_block->find_match(
       CHANGING
        cv_content = ms_cell->c_value ).
    ENDLOOP.

    " Turn off event handler
    SET HANDLER match_found FOR io_replace_block ACTIVATION abap_false.

***************************************
    " merge-2 Structures and objects
    LOOP AT io_replace_block->mt_fields REFERENCE INTO lr_field WHERE
     typ = zcl_xtt_replace_block=>mc_type_struct OR typ = zcl_xtt_replace_block=>mc_type_object.

      " Based on nested structure
      CREATE OBJECT lo_new_replace_block
        EXPORTING
          is_field = lr_field.

      " Recursion if type is the same
      CHECK lr_field->typ = zcl_xtt_replace_block=>mc_type_struct OR
            lr_field->typ = zcl_xtt_replace_block=>mc_type_object.

      " Recursion
      me->merge(
       EXPORTING
        io_replace_block = lo_new_replace_block
       CHANGING
          ct_cells       = ct_cells ).
    ENDLOOP.

***************************************
    " merge-3 Array types
    LOOP AT io_replace_block->mt_fields REFERENCE INTO lr_field WHERE typ = zcl_xtt_replace_block=>mc_type_table
                                                                   OR typ = zcl_xtt_replace_block=>mc_type_tree.
      " For columns
      READ TABLE mt_column_dir TRANSPORTING NO FIELDS
       WITH TABLE KEY table_line = lr_field->name.
      IF sy-subrc <> 0.
        lv_by_column = abap_false.
      ELSE.
        lv_by_column = abap_true.

        SORT ct_cells STABLE BY c_col_ind c_row.
      ENDIF.

      " Find for replication
      cl_ex_sheet=>split_2_content(
       EXPORTING
        is_field      = lr_field
        iv_by_column  = lv_by_column
       CHANGING
        ct_cells      = ct_cells        " Begin!
        ct_cells_mid  = lt_cells_mid
        ct_cells_end  = lt_cells_end
        ct_cell_match = lt_cell_match ).

      CASE lr_field->typ.
**********************************************************************
        WHEN zcl_xtt_replace_block=>mc_type_tree.
          lr_tree ?= lr_field->dref.

          CREATE OBJECT lo_tree_handler
            EXPORTING
              io_owner      = me
              ir_tree       = lr_tree
              iv_block_name = lr_field->name
              it_row_match  = lt_cell_match.

          lo_tree_handler->add_tree_data(
           EXPORTING
             ir_tree       = lr_tree
           CHANGING
             ct_cells      = ct_cells ).

**********************************************************************
        WHEN zcl_xtt_replace_block=>mc_type_table.
          CHECK lt_cells_mid IS NOT INITIAL.

          " Replicate middle
          ASSIGN lr_field->dref->* TO <lt_items>.

          " Use copy
          CREATE DATA lr_field2.
          lr_field2->* = lr_field->*.

          LOOP AT <lt_items> REFERENCE INTO lr_field2->dref. "ASSIGNING <ls_item>.
            lt_copy[] = lt_cells_mid[].

*            " Create descriptor
*            CREATE OBJECT lo_new_replace_block
*              EXPORTING
*                is_block      = <ls_item>
*                iv_block_name = lr_field->name.

*            " Create merge description
* Create copy first
*            GET REFERENCE OF <ls_item> INTO lr_field->dref.
            CREATE OBJECT lo_new_replace_block
              EXPORTING
                is_field = lr_field2.

            " Recursion
            me->merge(
             EXPORTING
              io_replace_block = lo_new_replace_block
             CHANGING
                ct_cells       = lt_copy ).
            APPEND LINES OF lt_copy TO ct_cells.
          ENDLOOP.
      ENDCASE.

      " Rest of the cells
      APPEND LINES OF lt_cells_end TO ct_cells.

      " Set the order back
      IF lv_by_column = abap_true.
        SORT ct_cells STABLE BY c_row.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.                    "merge
*--------------------------------------------------------------------*
  METHOD match_found.
    CONSTANTS:
      c_date_start TYPE d VALUE '18991230',
      c_time_start TYPE t VALUE '000000'.
    DATA:
      l_len   TYPE i,
      l_value TYPE string,
      l_date  TYPE float.
    FIELD-SYMBOLS:
      <l_string> TYPE csequence,
      <l_date>   TYPE d,
      <l_time>   TYPE t.

    " Just skip
    CHECK is_field->typ <> zcl_xtt_replace_block=>mc_type_tree.

    " If the exactly in one cell and number (ms_cell->c_typ can be 's' string)
    l_len      = strlen( ms_cell->c_value ).
    iv_pos_end = iv_pos_end + 1.
    IF iv_pos_beg = 0 AND l_len = iv_pos_end.
      CASE is_field->typ.
          " integer and double(float)
        WHEN zcl_xtt_replace_block=>mc_type_integer OR zcl_xtt_replace_block=>mc_type_double.
          CLEAR ms_cell->c_type.

          " Datetime Whole as a string like  d + t
        WHEN zcl_xtt_replace_block=>mc_type_datetime.
          ASSIGN is_field->dref->* TO <l_string>.

          " Both parts
          ASSIGN <l_string>(8)     TO <l_date> CASTING.
          ASSIGN <l_string>+8(6)   TO <l_time> CASTING.
          CLEAR ms_cell->c_type.

          " Date
        WHEN zcl_xtt_replace_block=>mc_type_date.
          ASSIGN is_field->dref->* TO <l_date>.
          CLEAR ms_cell->c_type.

          " Time
        WHEN zcl_xtt_replace_block=>mc_type_time.
          ASSIGN is_field->dref->* TO <l_time>.
          CLEAR ms_cell->c_type.

        WHEN zcl_xtt_replace_block=>mc_type_boolean.
          ms_cell->c_type = 'b'.
      ENDCASE.

      DO 1 TIMES.
        " Transform date to excel format as float
        CHECK <l_date> IS ASSIGNED OR <l_time> IS ASSIGNED.

        " Date
        IF <l_date> IS ASSIGNED AND <l_date> IS NOT INITIAL.
          " Number of days since
          l_date = <l_date> - c_date_start.
        ENDIF.

        " Time
        IF <l_time> IS ASSIGNED AND <l_time> IS NOT INITIAL.
          " 0.5 half of a day
          l_date = l_date + ( <l_time> - c_time_start ) / ( 60 * 60 * 24 ).
        ENDIF.

        " Empty string
        IF     l_date IS INITIAL.
          " Empty string
          CREATE DATA is_field->dref TYPE string.
          is_field->typ = zcl_xtt_replace_block=>mc_type_string.
        ELSEIF l_date < 0.
          " Use WRITE ... TO
        ELSE.
          GET REFERENCE OF l_date INTO is_field->dref.
          is_field->typ = zcl_xtt_replace_block=>mc_type_double.
        ENDIF.
      ENDDO.
    ENDIF.

    " Try to get value as a string
    IF l_value IS INITIAL.
      l_value = zcl_xtt_replace_block=>get_as_string( is_field = is_field ).

      " Use WRITE ... TO
      IF l_date < 0.
        ms_cell->c_style = ''.
        ms_cell->c_type  = 's'.
        is_field->typ        = zcl_xtt_replace_block=>mc_type_string.
      ENDIF.
    ENDIF.

    " Create new value
    CONCATENATE
     ms_cell->c_value(iv_pos_beg)
     l_value
     ms_cell->c_value+iv_pos_end INTO ms_cell->c_value RESPECTING BLANKS.
  ENDMETHOD.                    "match_found
*--------------------------------------------------------------------*
  METHOD xml_repleace_node.
    DATA:
      lo_elem       TYPE REF TO if_ixml_element.

    ro_elem = mo_dom->find_from_name( iv_tag_name ).
    CHECK ro_elem IS BOUND.

    " Delete child elements
    DO.
      lo_elem ?= ro_elem->get_last_child( ).  " replace_child( ) instead ? IF_IXML_NODE
      IF lo_elem IS NOT BOUND.
        EXIT.
      ENDIF.

      ro_elem->remove_child( lo_elem ).
    ENDDO.

    " Replace with text
    ro_elem->set_value( iv_repl_text ).
  ENDMETHOD.                    "xml_repleace_node
*--------------------------------------------------------------------*
  METHOD split_2_content.
    TYPES:
      BEGIN OF ts_pair,
        position  TYPE i,       " Excel row Or column
        array_ind TYPE sytabix, " Index in ct_cells[]
      END OF ts_pair,
      tt_pair TYPE SORTED TABLE OF ts_pair WITH UNIQUE KEY position.

    DATA:
      lv_ind_beg   TYPE i,
      lv_ind_end   TYPE i,
      lv_ind_end_1 TYPE i,
      lv_find_str  TYPE string,
      ls_cell      TYPE REF TO ts_ex_cell,
      lt_row_begs  TYPE tt_pair,
      lt_row_ends  TYPE tt_pair,
      lv_row_first TYPE i,
      lv_row_last  TYPE i,
      ls_cur_pair  TYPE ts_pair,
      ls_pair_ref  TYPE REF TO ts_pair,
      lv_offset    TYPE i,
      lv_length    TYPE i,
      lv_text      TYPE string,
      lt_row_off   TYPE zcl_xtt_replace_block=>tt_row_offset,
      ls_row_off   TYPE zcl_xtt_replace_block=>ts_row_offset,
      lv_from      TYPE sytabix,
      ls_row_match TYPE ts_cell_match.
    FIELD-SYMBOLS:
      <ls_row_off>  TYPE zcl_xtt_replace_block=>ts_row_offset,
      <ls_row_off2> TYPE zcl_xtt_replace_block=>ts_row_offset.

    " All positions
    CLEAR:
     ct_cell_match,
     ct_cells_end,
     ct_cells_mid.

    " CONCATENATE zcl_xtt_replace_block=>mc_char_block_begin iv_fld_name INTO lv_find_str.
    CONCATENATE `\{` is_field->name `\b[^}]*\}` INTO lv_find_str.

    " Find matches
    LOOP AT ct_cells REFERENCE INTO ls_cell.
      " Current values
      ls_cur_pair-array_ind  = sy-tabix.

      " What field to use
      IF iv_by_column = abap_true.
        ls_cur_pair-position  = ls_cell->c_col_ind. " ls_cur_pair-position + ls_cell->c_col_dx.
      ELSE.
        ls_cur_pair-position  = ls_cell->c_row.  " ls_cur_pair-position + ls_cell->c_row_dx.
      ENDIF.

      " Find row range
      READ TABLE lt_row_begs WITH TABLE KEY
       position = ls_cur_pair-position TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
        INSERT ls_cur_pair INTO TABLE lt_row_begs.
      ENDIF.

      " Make range bigger
      READ TABLE lt_row_ends REFERENCE INTO ls_pair_ref WITH TABLE KEY
       position = ls_cur_pair-position.
      IF sy-subrc = 0.
        ls_pair_ref->array_ind = ls_cur_pair-array_ind.
      ELSE.
        INSERT ls_cur_pair INTO TABLE lt_row_ends.
      ENDIF.

      " Rows range
      FIND FIRST OCCURRENCE OF REGEX lv_find_str IN ls_cell->c_value
       MATCH OFFSET lv_offset
       MATCH LENGTH lv_length.
      CHECK sy-subrc = 0.

      lv_row_last = ls_cur_pair-position.
      " Set 1 time only
      IF lv_row_first IS INITIAL.
        lv_row_first = lv_row_last.
      ENDIF.

***************************
      " TREE begin
      CHECK is_field->typ = zcl_xtt_replace_block=>mc_type_tree.

      " Delete surrounding {}
      lv_offset = lv_offset + 1.
      lv_length = lv_length - 2.

      lv_text = ls_cell->c_value+lv_offset(lv_length).

      " Read from texts
      zcl_xtt_replace_block=>tree_detect_options(
       EXPORTING
         iv_text       = lv_text
         iv_pos        = ls_cur_pair-position
       CHANGING
         cs_row_offset = ls_row_off
         ct_row_offset = lt_row_off ).
***************************
      " TREE end
    ENDLOOP.

    " Skip
    IF lv_row_first IS INITIAL AND lv_row_last IS INITIAL.
      RETURN.
    ENDIF.

    " Oops not found
    IF lv_row_first IS INITIAL OR lv_row_last IS INITIAL.
      MESSAGE x001(zsy_xtt).
    ENDIF.

***************************
    " TREE begin Check overlaps
    LOOP AT lt_row_off ASSIGNING <ls_row_off>.
      lv_from = sy-tabix + 1.
      LOOP AT lt_row_off ASSIGNING <ls_row_off2> FROM lv_from WHERE
         ( first <= <ls_row_off>-last AND first >= <ls_row_off>-first ) OR
         ( last  <= <ls_row_off>-last AND last  >= <ls_row_off>-first ).
        MESSAGE x001(zsy_xtt).
      ENDLOOP.
    ENDLOOP.

    " And add
    LOOP AT lt_row_off ASSIGNING <ls_row_off>.
      CLEAR ls_row_match.

      READ TABLE lt_row_begs REFERENCE INTO ls_pair_ref
       WITH TABLE KEY position = <ls_row_off>-first.
      lv_ind_beg = ls_pair_ref->array_ind.

      READ TABLE lt_row_ends REFERENCE INTO ls_pair_ref
       WITH TABLE KEY position = <ls_row_off>-last.
      lv_ind_end = ls_pair_ref->array_ind.

      " And add
      MOVE-CORRESPONDING <ls_row_off> TO ls_row_match.
      APPEND LINES OF ct_cells FROM lv_ind_beg TO lv_ind_end TO ls_row_match-cells.
      INSERT ls_row_match INTO TABLE ct_cell_match.
    ENDLOOP.
***************************
    " TREE end

    " Detect middle
    READ TABLE lt_row_begs REFERENCE INTO ls_pair_ref
     WITH TABLE KEY position = lv_row_first.
    lv_ind_beg = ls_pair_ref->array_ind.

    READ TABLE lt_row_ends REFERENCE INTO ls_pair_ref
     WITH TABLE KEY position = lv_row_last.
    lv_ind_end = ls_pair_ref->array_ind.

    " End
    lv_ind_end_1 = lv_ind_end + 1.
    APPEND LINES OF ct_cells FROM lv_ind_end_1 TO ct_cells_end.
    " Middle
    APPEND LINES OF ct_cells FROM lv_ind_beg TO lv_ind_end TO ct_cells_mid.
    " Begin!
    DELETE ct_cells FROM lv_ind_beg.
  ENDMETHOD.                    "split_2_content
*--------------------------------------------------------------------*
  METHOD convert_column2int.
    DATA: lv_uccpi   TYPE i,
          lv_factor  TYPE i,
          lv_offset  TYPE i,
          lv_char    TYPE c,
          lr_col_ind TYPE REF TO ts_col_ind,
          ls_col_ind TYPE ts_col_ind.

*   Upper case
    TRANSLATE iv_column TO UPPER CASE.
    CONDENSE iv_column NO-GAPS.

    " For speed
    READ TABLE mt_col_ind REFERENCE INTO lr_col_ind
     WITH TABLE KEY col = iv_column.
    IF sy-subrc = 0.
      rv_column = lr_col_ind->ind.
      RETURN.
    ENDIF.

*   Get string lenght and align to right
    lv_offset = 3 - strlen( iv_column ).

    SHIFT iv_column RIGHT BY lv_offset PLACES.

*   Claculate column position
    DO 3 TIMES.
      lv_offset = sy-index - 1.
      lv_char = iv_column+lv_offset(1).
      IF lv_char IS INITIAL.
        CONTINUE.
      ENDIF.
      lv_uccpi   = cl_abap_conv_out_ce=>uccpi( lv_char ).
      lv_factor  = 26 ** ( 3 - sy-index ).
      rv_column  = rv_column + ( lv_uccpi MOD 64 ) * lv_factor.
    ENDDO.

    " Add to both tables
    CONDENSE iv_column.
    ls_col_ind-col = iv_column.
    ls_col_ind-ind = rv_column.
    INSERT ls_col_ind INTO TABLE mt_col_ind.
    INSERT ls_col_ind INTO TABLE mt_ind_col.
  ENDMETHOD.                    "convert_column2int

  METHOD convert_column2alpha.
    DATA:
      lr_col_ind TYPE REF TO ts_col_ind,
      ls_col_ind TYPE ts_col_ind,
      lv_module  TYPE i,
      lv_uccpi   TYPE i,
      lv_text    TYPE sychar02.
    IF iv_column > 16384 OR iv_column < 1.
      MESSAGE x005(zsy_xtt) WITH iv_column.
    ENDIF.

    " For speed
    READ TABLE mt_ind_col REFERENCE INTO lr_col_ind
     WITH TABLE KEY ind = iv_column.
    IF sy-subrc = 0.
      rv_column = lr_col_ind->col.
      RETURN.
    ENDIF.

    ls_col_ind-ind = iv_column.
    WHILE iv_column GT 0.
      lv_module = ( iv_column - 1 ) MOD 26.
      lv_uccpi  = 65 + lv_module.

      iv_column = ( iv_column - lv_module ) / 26.

      lv_text   = cl_abap_conv_in_ce=>uccpi( lv_uccpi ).
      CONCATENATE lv_text rv_column INTO rv_column.
    ENDWHILE.

    " Add to both tables
    ls_col_ind-col = rv_column.
    INSERT ls_col_ind INTO TABLE mt_col_ind.
    INSERT ls_col_ind INTO TABLE mt_ind_col.
  ENDMETHOD.
*--------------------------------------------------------------------*
ENDCLASS.                    "cl_ex_sheet IMPLEMENTATION

**********************************************************************
**********************************************************************

CLASS lcl_tree_handler IMPLEMENTATION.
  METHOD constructor.
    mo_owner      = io_owner.
    mv_block_name = iv_block_name.
    mt_row_match  = it_row_match.

    " If there are dynamic levels
    zcl_xtt_replace_block=>tree_initialize(
     EXPORTING
       ir_tree      = ir_tree
     IMPORTING
       ev_program   = mv_check_prog
     CHANGING
       ct_row_match = mt_row_match ).
  ENDMETHOD.

  METHOD add_tree_data.
    DATA:
      lo_replace_block TYPE REF TO zcl_xtt_replace_block,
      lr_found_match   TYPE REF TO ts_cell_match,
      lv_top           TYPE abap_bool,
      lt_row_top       TYPE tt_ex_cell,
      lt_row_bottom    TYPE tt_ex_cell,
      lr_tree_attr     TYPE REF TO zcl_xtt_replace_block=>ts_tree_attr,
      lr_tree          TYPE REF TO zcl_xtt_replace_block=>ts_tree,
      ls_cell          TYPE REF TO ts_ex_cell,
      ls_row           TYPE REF TO ts_ex_row,
      ls_column        TYPE REF TO ts_ex_column,
      lv_templ_lev_cnt TYPE i.
    FIELD-SYMBOLS:
      <ls_data>  TYPE any,
      <lt_cells> TYPE tt_ex_cell.
    ASSIGN ir_tree->data->* TO <ls_data>.

    " Create merge description
    CREATE OBJECT lo_replace_block
      EXPORTING
        is_block      = <ls_data>
        iv_block_name = mv_block_name.

    " Check amount of level's templates
    lv_templ_lev_cnt = lines( mt_row_match ).
    DO 3 TIMES.
      CASE sy-index.
        WHEN 1.
          ASSIGN lt_row_top TO <lt_cells>.
          lv_top = abap_true.
        WHEN 2.
          ASSIGN lt_row_bottom TO <lt_cells>.
          lv_top = abap_false.
        WHEN 3.
          " 3-d try
          CHECK lt_row_top IS INITIAL AND lt_row_bottom IS INITIAL.

          ASSIGN lt_row_top TO <lt_cells>.
          lv_top = abap_undefined.
      ENDCASE.

      " Find match
      lr_found_match ?= zcl_xtt_replace_block=>tree_find_match(
         ir_tree        = ir_tree
         iv_block_name  = mv_block_name
         iv_top         = lv_top
         iv_check_prog  = mv_check_prog
         it_row_match   = mt_row_match ).
      CHECK lr_found_match IS NOT INITIAL.

      " Merge with data
      <lt_cells>[] = lr_found_match->cells[].

      " For new rows only
      IF lv_templ_lev_cnt = 1.
        LOOP AT <lt_cells> REFERENCE INTO ls_cell.
          " Rows
          DO 1 TIMES. " WHERE c_row_dx IS NOT INITIAL. ?
            " Have outline ot not
            READ TABLE mo_owner->mt_rows WITH TABLE KEY r = ls_cell->c_row REFERENCE INTO ls_row.
            CHECK sy-subrc = 0 AND ls_row->outlinelevel IS NOT INITIAL.

            ls_cell->c_row_outline = ir_tree->level.
            ls_row->outline_skip   = abap_true.
          ENDDO.

          " Columns
          DO 1 TIMES.
            " Have outline ot not
            READ TABLE mo_owner->mt_columns WITH TABLE KEY min = ls_cell->c_col_ind REFERENCE INTO ls_column.
            CHECK sy-subrc = 0 AND ls_column->outlinelevel IS NOT INITIAL.

            ls_cell->c_column_outline = ir_tree->level.
            ls_column->outline_skip   = abap_true.
          ENDDO.
        ENDLOOP.
      ENDIF.

      mo_owner->merge(
       EXPORTING
        io_replace_block = lo_replace_block
       CHANGING
        ct_cells         = <lt_cells> ).
    ENDDO.

    " row before
    APPEND LINES OF lt_row_top TO ct_cells.

    " children rows
    LOOP AT ir_tree->sub_nodes REFERENCE INTO lr_tree_attr.
      lr_tree ?= lr_tree_attr->attr.
      add_tree_data(
       EXPORTING
        ir_tree  = lr_tree
       CHANGING
        ct_cells = ct_cells ).
    ENDLOOP.

    " row after
    APPEND LINES OF lt_row_bottom TO ct_cells.
  ENDMETHOD.
ENDCLASS.

**********************************************************************
**********************************************************************
