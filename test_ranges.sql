SET SERVEROUTPUT ON SIZE UNLIMITED;

DECLARE
  l_ranges HTM_ID_RANGE_LIST;
  expected_str VARCHAR2(200);
  bool_res BOOLEAN;

  -- Helper for string comparison (for range list string representation)
  PROCEDURE assert_equals_string(test_name VARCHAR2, actual VARCHAR2, expected VARCHAR2) IS
  BEGIN
    IF actual = expected THEN
      DBMS_OUTPUT.PUT_LINE(test_name || ': PASS');
    ELSE
      DBMS_OUTPUT.PUT_LINE(test_name || ': FAIL - Expected "' || expected || '", Got "' || actual || '"');
    END IF;
  END assert_equals_string;

  PROCEDURE assert_true(test_name VARCHAR2, condition BOOLEAN) IS
  BEGIN
    IF condition THEN
      DBMS_OUTPUT.PUT_LINE(test_name || ': PASS');
    ELSE
      DBMS_OUTPUT.PUT_LINE(test_name || ': FAIL - Condition was false');
    END IF;
  END assert_true;
  
  PROCEDURE assert_false(test_name VARCHAR2, condition BOOLEAN) IS
  BEGIN
    IF NOT condition THEN
      DBMS_OUTPUT.PUT_LINE(test_name || ': PASS');
    ELSE
      DBMS_OUTPUT.PUT_LINE(test_name || ': FAIL - Condition was true');
    END IF;
  END assert_false;
  
  PROCEDURE assert_equals_number(test_name VARCHAR2, actual NUMBER, expected NUMBER) IS
  BEGIN
     IF actual = expected THEN
      DBMS_OUTPUT.PUT_LINE(test_name || ': PASS');
    ELSE
      DBMS_OUTPUT.PUT_LINE(test_name || ': FAIL - Expected ' || expected || ', Got ' || actual);
    END IF;
  END assert_equals_number;

BEGIN
  DBMS_OUTPUT.PUT_LINE('--- Running HTM_RANGE_UTILS Tests ---');

  -- 1. Initialization and basic add
  DBMS_OUTPUT.PUT_LINE('-- Initialization and Basic Add --');
  l_ranges := HTM_RANGE_UTILS.create_empty_range_list();
  assert_equals_string('Create empty list', HTM_RANGE_UTILS.range_list_to_string(l_ranges), '[]');
  assert_equals_number('Count empty list', HTM_RANGE_UTILS.get_range_count(l_ranges), 0);

  HTM_RANGE_UTILS.add_range(l_ranges, 10, 15);
  expected_str := '[(10,15)]';
  assert_equals_string('Add first range (10,15)', HTM_RANGE_UTILS.range_list_to_string(l_ranges), expected_str);
  assert_equals_number('Count after first add', HTM_RANGE_UTILS.get_range_count(l_ranges), 1);

  HTM_RANGE_UTILS.add_range(l_ranges, 1, 5);
  expected_str := '[(1,5), (10,15)]'; -- add_range calls merge, which sorts
  assert_equals_string('Add non-overlapping (1,5)', HTM_RANGE_UTILS.range_list_to_string(l_ranges), expected_str);
  assert_equals_number('Count after second add', HTM_RANGE_UTILS.get_range_count(l_ranges), 2);

  -- 2. Merging Overlapping Ranges
  DBMS_OUTPUT.PUT_LINE('-- Merging Overlapping Ranges --');
  HTM_RANGE_UTILS.add_range(l_ranges, 3, 7);
  expected_str := '[(1,7), (10,15)]';
  assert_equals_string('Add overlapping (3,7)', HTM_RANGE_UTILS.range_list_to_string(l_ranges), expected_str);
  assert_equals_number('Count after overlap merge', HTM_RANGE_UTILS.get_range_count(l_ranges), 2);

  -- 3. Merging Adjacent Ranges
  DBMS_OUTPUT.PUT_LINE('-- Merging Adjacent Ranges --');
  HTM_RANGE_UTILS.add_range(l_ranges, 8, 9); -- adjacent to (1,7) via (8,9) and (10,15) via (8,9)
                                          -- (1,7), (8,9), (10,15) -> (1,15)
  expected_str := '[(1,15)]';
  assert_equals_string('Add adjacent (8,9)', HTM_RANGE_UTILS.range_list_to_string(l_ranges), expected_str);
  assert_equals_number('Count after adjacent merge', HTM_RANGE_UTILS.get_range_count(l_ranges), 1);

  -- 4. Adding a Range that Engulfs Others
  DBMS_OUTPUT.PUT_LINE('-- Adding Engulfing Range --');
  HTM_RANGE_UTILS.add_range(l_ranges, 0, 20);
  expected_str := '[(0,20)]';
  assert_equals_string('Add engulfing (0,20)', HTM_RANGE_UTILS.range_list_to_string(l_ranges), expected_str);
  assert_equals_number('Count after engulfing merge', HTM_RANGE_UTILS.get_range_count(l_ranges), 1);

  -- 5. Adding a duplicate range
  DBMS_OUTPUT.PUT_LINE('-- Adding Duplicate Range --');
  HTM_RANGE_UTILS.add_range(l_ranges, 0, 20);
  expected_str := '[(0,20)]';
  assert_equals_string('Add duplicate (0,20)', HTM_RANGE_UTILS.range_list_to_string(l_ranges), expected_str);
  assert_equals_number('Count after duplicate merge', HTM_RANGE_UTILS.get_range_count(l_ranges), 1);

  -- 6. Adding range that is subset of existing
  DBMS_OUTPUT.PUT_LINE('-- Adding Subset Range --');
  HTM_RANGE_UTILS.add_range(l_ranges, 5, 10);
  expected_str := '[(0,20)]';
  assert_equals_string('Add subset (5,10) to (0,20)', HTM_RANGE_UTILS.range_list_to_string(l_ranges), expected_str);
  assert_equals_number('Count after subset merge', HTM_RANGE_UTILS.get_range_count(l_ranges), 1);

  -- 7. Complex sequence of adds
  DBMS_OUTPUT.PUT_LINE('-- Complex Sequence --');
  l_ranges := HTM_RANGE_UTILS.create_empty_range_list();
  HTM_RANGE_UTILS.add_range(l_ranges, 50, 60);  -- [(50,60)]
  HTM_RANGE_UTILS.add_range(l_ranges, 10, 20);  -- [(10,20), (50,60)]
  HTM_RANGE_UTILS.add_range(l_ranges, 15, 25);  -- [(10,25), (50,60)]
  HTM_RANGE_UTILS.add_range(l_ranges, 70, 80);  -- [(10,25), (50,60), (70,80)]
  HTM_RANGE_UTILS.add_range(l_ranges, 23, 55);  -- [(10,60), (70,80)]
  expected_str := '[(10,60), (70,80)]';
  assert_equals_string('Complex sequence merge', HTM_RANGE_UTILS.range_list_to_string(l_ranges), expected_str);
  assert_equals_number('Count after complex sequence', HTM_RANGE_UTILS.get_range_count(l_ranges), 2);
  
  -- 8. is_id_in_ranges
  DBMS_OUTPUT.PUT_LINE('-- is_id_in_ranges --');
  -- Current l_ranges: [(10,60), (70,80)]
  bool_res := HTM_RANGE_UTILS.is_id_in_ranges(l_ranges, 5);   -- false (before first range)
  assert_false('is_id_in_ranges(5)', bool_res);
  bool_res := HTM_RANGE_UTILS.is_id_in_ranges(l_ranges, 10);  -- true (low boundary of first range)
  assert_true('is_id_in_ranges(10)', bool_res);
  bool_res := HTM_RANGE_UTILS.is_id_in_ranges(l_ranges, 35);  -- true (middle of first range)
  assert_true('is_id_in_ranges(35)', bool_res);
  bool_res := HTM_RANGE_UTILS.is_id_in_ranges(l_ranges, 60);  -- true (high boundary of first range)
  assert_true('is_id_in_ranges(60)', bool_res);
  bool_res := HTM_RANGE_UTILS.is_id_in_ranges(l_ranges, 65);  -- false (between ranges)
  assert_false('is_id_in_ranges(65)', bool_res);
  bool_res := HTM_RANGE_UTILS.is_id_in_ranges(l_ranges, 70);  -- true (low boundary of second range)
  assert_true('is_id_in_ranges(70)', bool_res);
  bool_res := HTM_RANGE_UTILS.is_id_in_ranges(l_ranges, 75);  -- true (middle of second range)
  assert_true('is_id_in_ranges(75)', bool_res);
  bool_res := HTM_RANGE_UTILS.is_id_in_ranges(l_ranges, 80);  -- true (high boundary of second range)
  assert_true('is_id_in_ranges(80)', bool_res);
  bool_res := HTM_RANGE_UTILS.is_id_in_ranges(l_ranges, 85);  -- false (after second range)
  assert_false('is_id_in_ranges(85)', bool_res);
  
  bool_res := HTM_RANGE_UTILS.is_id_in_ranges(l_ranges, NULL); -- false (null id)
  assert_false('is_id_in_ranges(NULL)', bool_res);
  
  DECLARE
    empty_ranges HTM_ID_RANGE_LIST := HTM_RANGE_UTILS.create_empty_range_list();
  BEGIN
    bool_res := HTM_RANGE_UTILS.is_id_in_ranges(empty_ranges, 10); -- false (empty list)
    assert_false('is_id_in_ranges on empty list', bool_res);
  END;

  -- 9. Test add_range with low_id > high_id (should raise error)
  DBMS_OUTPUT.PUT_LINE('-- Add range with low_id > high_id --');
  BEGIN
    HTM_RANGE_UTILS.add_range(l_ranges, 100, 90);
    DBMS_OUTPUT.PUT_LINE('Add range (100,90): FAIL - Expected error, but none was raised.');
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE = -20100 THEN -- Custom error from add_range
        DBMS_OUTPUT.PUT_LINE('Add range (100,90): PASS (Correctly raised error: ' || SQLERRM || ')');
      ELSE
        DBMS_OUTPUT.PUT_LINE('Add range (100,90): FAIL - Incorrect error raised: ' || SQLERRM);
      END IF;
  END;

  DBMS_OUTPUT.PUT_LINE('--- HTM_RANGE_UTILS Tests Complete ---');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Error in Range Utils Tests: ' || SQLERRM);
    DBMS_OUTPUT.PUT_LINE(DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
END;
/
