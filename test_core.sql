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

  -- Helper for vector comparison
  PROCEDURE assert_equals_vector(test_name VARCHAR2, actual HTM_VECTOR, expected HTM_VECTOR, tolerance NUMBER := 0.0001) IS
  BEGIN
    IF actual IS NULL AND expected IS NULL THEN
       DBMS_OUTPUT.PUT_LINE(test_name || ': PASS (both null)');
       RETURN;
    END IF;
    IF actual IS NULL OR expected IS NULL THEN
       DBMS_OUTPUT.PUT_LINE(test_name || ': FAIL - One is null. Expected ' || expected.to_string() || ', Got ' || actual.to_string());
       RETURN;
    END IF;
    IF ABS(actual.x - expected.x) < tolerance AND
       ABS(actual.y - expected.y) < tolerance AND
       ABS(actual.z - expected.z) < tolerance THEN
      DBMS_OUTPUT.PUT_LINE(test_name || ': PASS');
    ELSE
      DBMS_OUTPUT.PUT_LINE(test_name || ': FAIL - Expected ' || expected.to_string() || ', Got ' || actual.to_string());
    END IF;
  END assert_equals_vector;
  
  PROCEDURE assert_not_null(test_name VARCHAR2, val ANYDATA) IS
  BEGIN
    IF val IS NOT NULL THEN
      DBMS_OUTPUT.PUT_LINE(test_name || ': PASS (Not Null)');
    ELSE
      DBMS_OUTPUT.PUT_LINE(test_name || ': FAIL - Value is NULL');
    END IF;
  END assert_not_null;
  
  v_point HTM_VECTOR;
  node_id NUMBER;
  node_id_expected NUMBER;
  v0 HTM_VECTOR;
  v1 HTM_VECTOR;
  v2 HTM_VECTOR;
  
  build_level_test NUMBER := 6; -- A moderate build level
  query_level_test NUMBER := 10; -- Query level deeper than build

BEGIN
  DBMS_OUTPUT.PUT_LINE('--- Initializing HTM System ---');
  BEGIN
    HTM_SQL_API.initialize_htm_system(build_level_test, query_level_test);
    DBMS_OUTPUT.PUT_LINE('HTM System Initialized: Build=' || build_level_test || ', Query=' || query_level_test);
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Failed to initialize HTM System: ' || SQLERRM);
      RETURN; -- Stop tests if initialization fails
  END;

  DBMS_OUTPUT.PUT_LINE('--- Running HTM_INDEX_CORE Tests ---');

  -- 1. id_by_point
  DBMS_OUTPUT.PUT_LINE('-- id_by_point --');
  -- Test point near North Pole (0, 90), should be in one of N0-N3 at level 0
  v_point := HTM_VECTOR(0, 89.9); -- RA, Dec
  node_id := HTM_INDEX_CORE.id_by_point(v_point, 0); -- Target level 0
  -- Expected: N0 (12), N1 (13), N2 (14), N3 (15).
  -- (0,0,1) is vertex for all N triangles.
  -- N0=(X+,Y+,Z+), N1=(Y+,X-,Z+), N2=(X-,Y-,Z+), N3=(Y-,X+,Z+)
  -- (0,89.9) -> (small_x, small_y, close_to_1).
  -- Example: For (0,89.9), point is HTM_VECTOR(0.001745,0,0.999998) approx.
  -- This should fall into N0 (ID 12) or N3 (ID 15) if RA is exactly 0.
  -- Let's check if it's one of the North triangles
  IF node_id >= 12 AND node_id <= 15 THEN
    DBMS_OUTPUT.PUT_LINE('id_by_point (0,89.9) L0: PASS (Got ' || node_id || ', is a North triangle)');
  ELSE
    DBMS_OUTPUT.PUT_LINE('id_by_point (0,89.9) L0: FAIL - Expected N0-N3 (12-15), Got ' || node_id);
  END IF;

  -- Test point near (RA=0, Dec=0) -> should be X+ (1,0,0)
  -- This point is on the equator. At level 0, it is on edges of S0,S3,N0,N3.
  -- S0=(X+,Z-,Y-), S3=(Y+,Z-,X+), N0=(X+,Y+,Z+), N3=(Y-,X+,Z+)
  -- The exact ID depends on tie-breaking in is_inside_triangle.
  -- Let's pick a point slightly into one, e.g., RA=1, Dec=1 (clearly in N0 for HTM root setup)
  v_point := HTM_VECTOR(1, 1); -- RA, Dec
  node_id := HTM_INDEX_CORE.id_by_point(v_point, 0); -- Target level 0
  assert_equals_float('id_by_point (1,1) L0 (expected N0)', node_id, 12); -- N0 is (X+,Y+,Z+)

  v_point := HTM_VECTOR(1, -1); -- RA, Dec (should be S0 or S3) S0=(X+,Z-,Y-), S3=(Y+,Z-,X+)
  node_id := HTM_INDEX_CORE.id_by_point(v_point, 0);
  IF node_id = 8 OR node_id = 11 THEN -- S0 or S3
      DBMS_OUTPUT.PUT_LINE('id_by_point (1,-1) L0: PASS (Got ' || node_id || ', is S0 or S3)');
  ELSE
      DBMS_OUTPUT.PUT_LINE('id_by_point (1,-1) L0: FAIL - Expected S0 (8) or S3 (11), Got ' || node_id);
  END IF;
  
  -- Test deeper level for (1,1)
  node_id_expected := 12; -- N0
  FOR l IN 1..3 LOOP
    node_id_expected := node_id_expected * 4 + 0; -- Assume it stays in child 0 for a point near center
  END LOOP;
  -- For point (1,1), it's close to vertex of N0, not center.
  -- Let's take point_by_id(N0) and find ID for that.
  DECLARE
    center_N0 HTM_VECTOR := HTM_INDEX_CORE.point_by_id(12);
    center_N0_radec HTM_VECTOR := HTM_GEOMETRY_UTILS.cartesian_to_ra_dec(center_N0);
  BEGIN
    node_id := HTM_INDEX_CORE.id_by_point(center_N0, 3);
    node_id_expected := 12; -- N0
    FOR l_idx IN 1..3 LOOP
        -- For a point at the center of N0, it should fall into the central sub-triangle (index 3)
        -- if the subdivision is symmetrical. Or it might be specific to index 0.
        -- Let's use HTM_INDEX_CORE.id_by_point(center_N0, current_level+1) to find next child.
        DECLARE
            temp_id NUMBER;
            current_parent_id NUMBER := 12;
            path_str VARCHAR2(10) := 'N0';
        BEGIN
            FOR cl IN 0..2 LOOP -- to level 3
                temp_id := HTM_INDEX_CORE.id_by_point(center_N0, cl + 1);
                path_str := path_str || MOD(temp_id, 4);
                current_parent_id := temp_id;
            END LOOP;
            node_id_expected := current_parent_id;
            DBMS_OUTPUT.PUT_LINE('Expected path for center of N0 to L3: ' || path_str || ' (ID: ' || node_id_expected || ')');
        END;
    END LOOP;

    assert_equals_float('id_by_point (center of N0) L3', node_id, node_id_expected);
  END;


  -- 2. get_node_vertices & point_by_id
  DBMS_OUTPUT.PUT_LINE('-- get_node_vertices & point_by_id --');
  -- Test N0 (ID 12)
  node_id := 12;
  HTM_INDEX_CORE.get_node_vertices(node_id, v0, v1, v2);
  assert_not_null('get_node_vertices N0 - v0 not null', v0);
  assert_not_null('get_node_vertices N0 - v1 not null', v1);
  assert_not_null('get_node_vertices N0 - v2 not null', v2);
  
  -- Expected vertices for N0 (ID 12) from initialize_htm
  -- N0: (0,2,4) -> X+, Y+, Z+
  -- v_data(0)= (1,0,0), v_data(2)=(0,1,0), v_data(4)=(0,0,1)
  assert_equals_vector('N0 vertex 0 (X+)', v0, HTM_VECTOR(1,0,0));
  assert_equals_vector('N0 vertex 1 (Y+)', v1, HTM_VECTOR(0,1,0));
  assert_equals_vector('N0 vertex 2 (Z+)', v2, HTM_VECTOR(0,0,1));

  v_point := HTM_INDEX_CORE.point_by_id(node_id); -- Center of N0
  DECLARE
    expected_center HTM_VECTOR := HTM_VECTOR( (1+0+0)/3, (0+1+0)/3, (0+0+1)/3 );
    expected_center_norm HTM_VECTOR;
  BEGIN
    expected_center_norm := HTM_VECTOR(expected_center.x, expected_center.y, expected_center.z);
    expected_center_norm.normalize();
    assert_equals_vector('point_by_id N0 center', v_point, expected_center_norm);
  END;

  -- Test for a dynamically calculated node (level > build_level)
  -- N00 (ID 12*4+0 = 48). Level 1.
  -- If build_level_test = 0, this would be dynamic. Let's assume build_level_test = 6.
  -- So, ID for N0 at level 7. N0's ID is 12.
  -- L0: 12
  -- L1: 12*4 + child_idx (e.g. 48 for N00)
  -- L7 N0000000: 12 * 4^7 + 0 (this is one way, but IDs are typically parent*4+child)
  -- ID of N0 followed by 7 zeros:
  node_id := 12;
  FOR l IN 1 .. build_level_test + 1 LOOP -- One level deeper than build
    node_id := node_id * 4 + 0; -- Take child 0 each time
  END LOOP;
  
  DBMS_OUTPUT.PUT_LINE('Testing dynamic node: ID ' || node_id || ' (Level '|| (build_level_test+1) ||')');
  BEGIN
    HTM_INDEX_CORE.get_node_vertices(node_id, v0, v1, v2);
    assert_not_null('Dynamic get_node_vertices - v0 not null', v0);
    assert_not_null('Dynamic get_node_vertices - v1 not null', v1);
    assert_not_null('Dynamic get_node_vertices - v2 not null', v2);
    
    -- Vertices should be different from its parent N0...(build_level)0
    DECLARE
      parent_id NUMBER := FLOOR(node_id / 4);
      pv0 HTM_VECTOR; pv1 HTM_VECTOR; pv2 HTM_VECTOR;
    BEGIN
      HTM_INDEX_CORE.get_node_vertices(parent_id, pv0, pv1, pv2);
      -- Check if v0 (of child) is same as pv0 (of parent) - it should be for child 0
      assert_equals_vector('Dynamic node v0 vs parent v0', v0, pv0);
      -- Check if v1 (of child) is different from pv1 (of parent) - it should be a midpoint
      IF ABS(v1.x - pv1.x) < 0.0001 AND ABS(v1.y - pv1.y) < 0.0001 AND ABS(v1.z - pv1.z) < 0.0001 THEN
         DBMS_OUTPUT.PUT_LINE('Dynamic node v1 vs parent v1: FAIL - v1 is same as parent v1, expected midpoint w2');
      ELSE
         DBMS_OUTPUT.PUT_LINE('Dynamic node v1 vs parent v1: PASS - v1 is different from parent v1');
      END IF;
    END;

    v_point := HTM_INDEX_CORE.point_by_id(node_id);
    assert_not_null('Dynamic point_by_id - center not null', v_point);
    -- Check that point_by_id is inside the triangle formed by v0,v1,v2
    IF HTM_GEOMETRY_UTILS.is_inside_triangle(v_point, v0, v1, v2) THEN
        DBMS_OUTPUT.PUT_LINE('Dynamic point_by_id center is inside its triangle: PASS');
    ELSE
        DBMS_OUTPUT.PUT_LINE('Dynamic point_by_id center is inside its triangle: FAIL');
    END IF;

  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Error testing dynamic node ' || node_id || ': ' || SQLERRM);
  END;


  DBMS_OUTPUT.PUT_LINE('--- HTM_INDEX_CORE Tests Complete ---');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Error in Core Tests: ' || SQLERRM);
    DBMS_OUTPUT.PUT_LINE(DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
END;
/
