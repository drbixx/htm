SET SERVEROUTPUT ON SIZE UNLIMITED;

DECLARE
  -- Helper for float comparison
  PROCEDURE assert_equals_float(test_name VARCHAR2, actual NUMBER, expected NUMBER, tolerance NUMBER := 0.0001) IS
  BEGIN
    IF actual IS NULL AND expected IS NULL THEN
       DBMS_OUTPUT.PUT_LINE(test_name || ': PASS (both null)');
       RETURN;
    END IF;
    IF actual IS NULL OR expected IS NULL THEN
       DBMS_OUTPUT.PUT_LINE(test_name || ': FAIL - One is null. Expected ' || expected || ', Got ' || actual);
       RETURN;
    END IF;
    IF ABS(actual - expected) < tolerance THEN
      DBMS_OUTPUT.PUT_LINE(test_name || ': PASS');
    ELSE
      DBMS_OUTPUT.PUT_LINE(test_name || ': FAIL - Expected ' || expected || ', Got ' || actual);
    END IF;
  END assert_equals_float;
  
  PROCEDURE assert_equals_string(test_name VARCHAR2, actual VARCHAR2, expected VARCHAR2, case_sensitive BOOLEAN := TRUE) IS
    act_val VARCHAR2(32767) := actual;
    exp_val VARCHAR2(32767) := expected;
  BEGIN
    IF NOT case_sensitive THEN
      act_val := UPPER(actual);
      exp_val := UPPER(expected);
    END IF;
    IF act_val = exp_val THEN
      DBMS_OUTPUT.PUT_LINE(test_name || ': PASS');
    ELSE
      DBMS_OUTPUT.PUT_LINE(test_name || ': FAIL - Expected "' || expected || '", Got "' || actual || '"');
    END IF;
  END assert_equals_string;

  PROCEDURE assert_not_null(test_name VARCHAR2, val ANYDATA) IS
  BEGIN
    IF val IS NOT NULL THEN
      DBMS_OUTPUT.PUT_LINE(test_name || ': PASS (Not Null)');
    ELSE
      DBMS_OUTPUT.PUT_LINE(test_name || ': FAIL - Value is NULL');
    END IF;
  END assert_not_null;
  
  PROCEDURE assert_true(test_name VARCHAR2, condition BOOLEAN) IS
  BEGIN
    IF condition THEN
      DBMS_OUTPUT.PUT_LINE(test_name || ': PASS');
    ELSE
      DBMS_OUTPUT.PUT_LINE(test_name || ': FAIL - Condition was false');
    END IF;
  END assert_true;

  build_level_api NUMBER := 7; -- Build level for API tests
  query_level_api NUMBER := 10; -- Query level for API tests
  
  num_res NUMBER;
  str_res VARCHAR2(200);
  vec_res HTM_VECTOR;
  
  range_count NUMBER;
  first_range HTM_ID_RANGE;

BEGIN
  DBMS_OUTPUT.PUT_LINE('--- Initializing HTM System for API Tests ---');
  BEGIN
    HTM_SQL_API.initialize_htm_system(build_level_api, query_level_api);
    DBMS_OUTPUT.PUT_LINE('HTM System Initialized: Build=' || build_level_api || ', Query=' || query_level_api);
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Failed to initialize HTM System for API Tests: ' || SQLERRM);
      RETURN; -- Stop tests if initialization fails
  END;

  DBMS_OUTPUT.PUT_LINE('--- Running HTM_SQL_API Tests ---');

  -- 1. lookup_htm_id
  DBMS_OUTPUT.PUT_LINE('-- lookup_htm_id --');
  -- Point (1,1) at query_level_api. N0 is 12.
  -- Expected ID depends on how HTM_INDEX_CORE.id_by_point subdivides.
  DECLARE
    expected_id NUMBER;
    pt_vec HTM_VECTOR := HTM_VECTOR(1,1); -- RA, Dec
  BEGIN
    expected_id := HTM_INDEX_CORE.id_by_point(pt_vec, query_level_api);
    num_res := HTM_SQL_API.lookup_htm_id(1, 1, query_level_api);
    assert_equals_float('lookup_htm_id (1,1) L' || query_level_api, num_res, expected_id);
  EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('lookup_htm_id (1,1) L' || query_level_api || ': FAIL - Error: ' || SQLERRM);
  END;
  
  -- Test lookup_htm_id for a point at the North Pole (RA=0, Dec=90)
  BEGIN
    num_res := HTM_SQL_API.lookup_htm_id(0, 90, query_level_api);
    assert_not_null('lookup_htm_id (0,90) L' || query_level_api || ' not null', num_res);
    DBMS_OUTPUT.PUT_LINE('  Value for (0,90) L' || query_level_api || ': ' || num_res);
  EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('lookup_htm_id (0,90) L' || query_level_api || ': FAIL - Error: ' || SQLERRM);
  END;


  -- 2. get_htm_point_radec
  DBMS_OUTPUT.PUT_LINE('-- get_htm_point_radec --');
  -- N0 ID is 12
  str_res := HTM_SQL_API.get_htm_point_radec(12);
  assert_not_null('get_htm_point_radec(12) not null', str_res);
  DBMS_OUTPUT.PUT_LINE('  RA/Dec for N0 (ID 12): ' || str_res);
  -- Expected for N0 (center of (1,0,0),(0,1,0),(0,0,1)) is approx (RA=45, Dec=35.26)
  -- (1/sqrt(3), 1/sqrt(3), 1/sqrt(3)) -> atan2(1,1)=45 deg. asin(1/sqrt(3)) = 35.26 deg.
  IF INSTR(str_res, ',') > 0 THEN
    DECLARE
      ra_str VARCHAR2(50) := SUBSTR(str_res, 1, INSTR(str_res, ',')-1);
      dec_str VARCHAR2(50) := SUBSTR(str_res, INSTR(str_res, ',')+1);
      ra_val NUMBER := TO_NUMBER(ra_str);
      dec_val NUMBER := TO_NUMBER(dec_str);
    BEGIN
      assert_equals_float('  RA for N0 center', ra_val, 45, 1); -- Tolerance 1 degree
      assert_equals_float('  Dec for N0 center', dec_val, 35.26, 1); -- Tolerance 1 degree
    END;
  ELSE
    DBMS_OUTPUT.PUT_LINE('get_htm_point_radec(12): FAIL - Output format not "RA,DEC"');
  END IF;

  -- 3. get_htm_point_cartesian
  DBMS_OUTPUT.PUT_LINE('-- get_htm_point_cartesian --');
  vec_res := HTM_SQL_API.get_htm_point_cartesian(12);
  assert_not_null('get_htm_point_cartesian(12) not null', vec_res);
  DBMS_OUTPUT.PUT_LINE('  Cartesian for N0 (ID 12): ' || vec_res.to_string());
  DECLARE
    expected_vec HTM_VECTOR := HTM_VECTOR(1/SQRT(3), 1/SQRT(3), 1/SQRT(3));
  BEGIN
    assert_equals_float('  X for N0 center', vec_res.x, expected_vec.x, 0.01);
    assert_equals_float('  Y for N0 center', vec_res.y, expected_vec.y, 0.01);
    assert_equals_float('  Z for N0 center', vec_res.z, expected_vec.z, 0.01);
  END;

  -- 4. htm_circle_intersect
  DBMS_OUTPUT.PUT_LINE('-- htm_circle_intersect --');
  -- Circle around North Pole (RA=0, Dec=90), radius 1 degree, query_level 5 (coarser for fewer results)
  range_count := 0;
  first_range := NULL;
  BEGIN
    FOR r IN (SELECT low_id, high_id FROM TABLE(HTM_SQL_API.htm_circle_intersect(0, 89.99, 1, 5))) LOOP
      range_count := range_count + 1;
      IF range_count = 1 THEN
        first_range := HTM_ID_RANGE(r.low_id, r.high_id);
      END IF;
    END LOOP;
    assert_true('htm_circle_intersect NPole R=1deg L5 - range_count > 0', range_count > 0);
    DBMS_OUTPUT.PUT_LINE('  Ranges found for NPole R=1deg L5: ' || range_count);
    IF first_range IS NOT NULL THEN
      DBMS_OUTPUT.PUT_LINE('  First range: (' || first_range.low_id || ',' || first_range.high_id || ')');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
       DBMS_OUTPUT.PUT_LINE('htm_circle_intersect NPole R=1deg L5: FAIL - Error: ' || SQLERRM);
  END;
  
  -- Circle that should return empty or very few results (small circle far from dense areas at high level)
  range_count := 0;
  BEGIN
    FOR r IN (SELECT low_id, high_id FROM TABLE(HTM_SQL_API.htm_circle_intersect(0, 0, 0.0001, query_level_api))) LOOP
      range_count := range_count + 1;
    END LOOP;
    assert_true('htm_circle_intersect (0,0) R=0.0001deg L' || query_level_api || ' - range_count reasonable', range_count >= 0 AND range_count < 100); -- Expect few ranges
    DBMS_OUTPUT.PUT_LINE('  Ranges found for (0,0) R=0.0001deg L' || query_level_api || ': ' || range_count);
  EXCEPTION
    WHEN OTHERS THEN
       DBMS_OUTPUT.PUT_LINE('htm_circle_intersect (0,0) R=0.0001deg L' || query_level_api || ': FAIL - Error: ' || SQLERRM);
  END;


  -- 5. htm_polygon_intersect
  DBMS_OUTPUT.PUT_LINE('-- htm_polygon_intersect --');
  -- Small square-like polygon around (RA=10, Dec=10)
  DECLARE
    poly_str VARCHAR2(200) := '9,9; 11,9; 11,11; 9,11'; -- RA,Dec pairs
  BEGIN
    range_count := 0;
    first_range := NULL;
    FOR r IN (SELECT low_id, high_id FROM TABLE(HTM_SQL_API.htm_polygon_intersect(poly_str, 7))) LOOP
      range_count := range_count + 1;
      IF range_count = 1 THEN
        first_range := HTM_ID_RANGE(r.low_id, r.high_id);
      END IF;
    END LOOP;
    assert_true('htm_polygon_intersect small square L7 - range_count > 0', range_count > 0);
    DBMS_OUTPUT.PUT_LINE('  Ranges found for small square L7: ' || range_count);
    IF first_range IS NOT NULL THEN
      DBMS_OUTPUT.PUT_LINE('  First range: (' || first_range.low_id || ',' || first_range.high_id || ')');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
       DBMS_OUTPUT.PUT_LINE('htm_polygon_intersect small square L7: FAIL - Error: ' || SQLERRM);
  END;

  -- Test malformed polygon string
  DBMS_OUTPUT.PUT_LINE('-- htm_polygon_intersect (malformed string) --');
  DECLARE
    malformed_poly_str VARCHAR2(200) := '10,10; 20,20; 30'; -- Missing Dec for last point
  BEGIN
    range_count := 0;
    FOR r IN (SELECT low_id, high_id FROM TABLE(HTM_SQL_API.htm_polygon_intersect(malformed_poly_str, 5))) LOOP
      range_count := range_count + 1;
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('htm_polygon_intersect malformed string: FAIL - Expected error, but ' || range_count || ' ranges returned.');
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE = -20353 OR SQLCODE = -20354 OR SQLCODE = -20355 THEN -- Custom errors from htm_polygon_intersect parsing
        DBMS_OUTPUT.PUT_LINE('htm_polygon_intersect malformed string: PASS (Correctly raised error: ' || SQLERRM || ')');
      ELSE
        DBMS_OUTPUT.PUT_LINE('htm_polygon_intersect malformed string: FAIL - Incorrect error raised: ' || SQLERRM);
      END IF;
  END;
  
  -- Test polygon string with insufficient vertices
  DBMS_OUTPUT.PUT_LINE('-- htm_polygon_intersect (insufficient vertices) --');
  DECLARE
    short_poly_str VARCHAR2(200) := '10,10; 20,20'; -- Only 2 points
  BEGIN
    range_count := 0;
    FOR r IN (SELECT low_id, high_id FROM TABLE(HTM_SQL_API.htm_polygon_intersect(short_poly_str, 5))) LOOP
      range_count := range_count + 1;
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('htm_polygon_intersect insufficient vertices: FAIL - Expected error, but ' || range_count || ' ranges returned.');
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE = -20355 THEN -- Custom error for insufficient vertices
        DBMS_OUTPUT.PUT_LINE('htm_polygon_intersect insufficient vertices: PASS (Correctly raised error: ' || SQLERRM || ')');
      ELSE
        DBMS_OUTPUT.PUT_LINE('htm_polygon_intersect insufficient vertices: FAIL - Incorrect error raised: ' || SQLERRM);
      END IF;
  END;


  DBMS_OUTPUT.PUT_LINE('--- HTM_SQL_API Tests Complete ---');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Error in API Tests: ' || SQLERRM);
    DBMS_OUTPUT.PUT_LINE(DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
END;
/

-- Instructions to run:
-- 1. Ensure all HTM packages (HTM_TYPES, HTM_GEOMETRY_UTILS, HTM_INDEX_CORE, HTM_RANGE_UTILS, HTM_QUERY_INTERFACE, HTM_SQL_API)
--    and their bodies are compiled successfully in the Oracle schema.
-- 2. Connect to the Oracle schema using SQL*Plus, SQL Developer, or another Oracle client.
-- 3. Enable server output: SET SERVEROUTPUT ON SIZE UNLIMITED
-- 4. Execute this script file (e.g., @test_api.sql).
-- 5. Review the output for PASS/FAIL messages.
--
-- Note: The specific IDs and range counts for intersection queries can vary based on minor differences in floating point
-- arithmetic and the exact tie-breaking rules in geometric predicates (like is_inside_triangle).
-- The tests for these primarily check for:
--   - No unexpected errors.
--   - A non-zero number of ranges for reasonable queries.
--   - A very small/zero number of ranges for queries expected to cover little area.
-- Exact range matching would require prior calibration with a known good version of the algorithm.
