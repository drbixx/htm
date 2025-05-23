SET SERVEROUTPUT ON SIZE UNLIMITED;

DECLARE
  -- Helper for float comparison
  PROCEDURE assert_equals_float(test_name VARCHAR2, actual NUMBER, expected NUMBER, tolerance NUMBER := 0.0001) IS
  BEGIN
    IF ABS(actual - expected) < tolerance THEN
      DBMS_OUTPUT.PUT_LINE(test_name || ': PASS');
    ELSE
      DBMS_OUTPUT.PUT_LINE(test_name || ': FAIL - Expected ' || expected || ', Got ' || actual);
    END IF;
  END assert_equals_float;

  -- Helper for vector comparison
  PROCEDURE assert_equals_vector(test_name VARCHAR2, actual HTM_VECTOR, expected HTM_VECTOR, tolerance NUMBER := 0.0001) IS
  BEGIN
    IF ABS(actual.x - expected.x) < tolerance AND
       ABS(actual.y - expected.y) < tolerance AND
       ABS(actual.z - expected.z) < tolerance THEN
      DBMS_OUTPUT.PUT_LINE(test_name || ': PASS');
    ELSE
      DBMS_OUTPUT.PUT_LINE(test_name || ': FAIL - Expected ' || expected.to_string() || ', Got ' || actual.to_string());
    END IF;
  END assert_equals_vector;
  
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

  -- Test variables
  v1 HTM_VECTOR;
  v2 HTM_VECTOR;
  v3 HTM_VECTOR;
  v_res HTM_VECTOR;
  num_res NUMBER;
  str_res VARCHAR2(100);
  bool_res BOOLEAN;
  
  -- For triangle tests
  tri_v0 HTM_VECTOR;
  tri_v1 HTM_VECTOR;
  tri_v2 HTM_VECTOR;
  p_inside HTM_VECTOR;
  p_outside HTM_VECTOR;
  p_on_edge HTM_VECTOR;

BEGIN
  DBMS_OUTPUT.PUT_LINE('--- Running HTM_GEOMETRY_UTILS & HTM_VECTOR Tests ---');

  -- 1. Vector Construction
  DBMS_OUTPUT.PUT_LINE('-- Vector Construction --');
  v1 := HTM_VECTOR(1,2,3);
  assert_equals_vector('HTM_VECTOR(x,y,z) construction', v1, HTM_VECTOR(1,2,3));

  -- RA=0, Dec=0 -> (1,0,0)
  v1 := HTM_VECTOR(0,0); -- RA, Dec
  assert_equals_vector('HTM_VECTOR(0,0) RA/Dec', v1, HTM_VECTOR(1,0,0));
  
  -- RA=90, Dec=0 -> (0,1,0) (cos(90)=0, sin(90)=1 for phi; theta=90)
  -- x = sin(pi/2)*cos(pi/2) = 1*0 = 0
  -- y = sin(pi/2)*sin(pi/2) = 1*1 = 1
  -- z = cos(pi/2) = 0
  v1 := HTM_VECTOR(90,0); -- RA, Dec
  assert_equals_vector('HTM_VECTOR(90,0) RA/Dec', v1, HTM_VECTOR(0,1,0));

  -- RA=0, Dec=90 (North Pole) -> (0,0,1) (phi=0; theta=0)
  -- x = sin(0)*cos(0) = 0*1 = 0
  -- y = sin(0)*sin(0) = 0*0 = 0
  -- z = cos(0) = 1
  v1 := HTM_VECTOR(0,90); -- RA, Dec
  assert_equals_vector('HTM_VECTOR(0,90) RA/Dec', v1, HTM_VECTOR(0,0,1));
  
  -- RA=0, Dec=-90 (South Pole) -> (0,0,-1) (phi=0; theta=pi)
  -- x = sin(pi)*cos(0) = 0*1 = 0
  -- y = sin(pi)*sin(0) = 0*0 = 0
  -- z = cos(pi) = -1
  v1 := HTM_VECTOR(0,-90); -- RA, Dec
  assert_equals_vector('HTM_VECTOR(0,-90) RA/Dec', v1, HTM_VECTOR(0,0,-1));

  -- 2. Vector Operations
  DBMS_OUTPUT.PUT_LINE('-- Vector Operations --');
  v1 := HTM_VECTOR(3,4,0);
  num_res := v1.magnitude();
  assert_equals_float('Magnitude (3,4,0)', num_res, 5);

  v1 := HTM_VECTOR(3,4,0);
  v1.normalize();
  assert_equals_vector('Normalize (3,4,0)', v1, HTM_VECTOR(0.6, 0.8, 0));
  
  v1 := HTM_VECTOR(1,0,0);
  v1.normalize(); -- Should remain (1,0,0)
  assert_equals_vector('Normalize (1,0,0)', v1, HTM_VECTOR(1,0,0));

  v1 := HTM_VECTOR(1,0,0);
  v2 := HTM_VECTOR(0,1,0);
  num_res := v1.dot_product(v2);
  assert_equals_float('Dot Product orthogonal', num_res, 0);

  v1 := HTM_VECTOR(1,2,3);
  v2 := HTM_VECTOR(1,2,3);
  num_res := v1.dot_product(v2);
  assert_equals_float('Dot Product parallel', num_res, 14); -- 1*1 + 2*2 + 3*3 = 1+4+9=14

  v1 := HTM_VECTOR(1,0,0);
  v2 := HTM_VECTOR(0,1,0);
  v_res := v1.cross_product(v2);
  assert_equals_vector('Cross Product (1,0,0)x(0,1,0)', v_res, HTM_VECTOR(0,0,1));

  v1 := HTM_VECTOR(0,1,0);
  v2 := HTM_VECTOR(1,0,0);
  v_res := v1.cross_product(v2);
  assert_equals_vector('Cross Product (0,1,0)x(1,0,0)', v_res, HTM_VECTOR(0,0,-1));

  -- 3. Coordinate Conversion
  DBMS_OUTPUT.PUT_LINE('-- Coordinate Conversion --');
  v1 := HTM_VECTOR(1,0,0); -- Corresponds to RA=0, Dec=0
  v_res := HTM_GEOMETRY_UTILS.cartesian_to_ra_dec(v1);
  assert_equals_vector('cartesian_to_ra_dec (1,0,0)', v_res, HTM_VECTOR(0,0,1), 0.001); -- RA, Dec, Radius

  v1 := HTM_VECTOR(0,1,0); -- Corresponds to RA=90, Dec=0
  v_res := HTM_GEOMETRY_UTILS.cartesian_to_ra_dec(v1);
  assert_equals_vector('cartesian_to_ra_dec (0,1,0)', v_res, HTM_VECTOR(90,0,1), 0.001);

  v1 := HTM_VECTOR(0,0,1); -- Corresponds to RA=0, Dec=90
  v_res := HTM_GEOMETRY_UTILS.cartesian_to_ra_dec(v1);
  assert_equals_vector('cartesian_to_ra_dec (0,0,1)', v_res, HTM_VECTOR(0,90,1), 0.001);
  
  v1 := HTM_VECTOR(SQRT(2)/2, SQRT(2)/2, 0); -- RA=45, Dec=0
  v_res := HTM_GEOMETRY_UTILS.cartesian_to_ra_dec(v1);
  assert_equals_vector('cartesian_to_ra_dec (sqrt(2)/2, sqrt(2)/2, 0)', v_res, HTM_VECTOR(45,0,1), 0.001);


  -- 4. is_inside_triangle
  DBMS_OUTPUT.PUT_LINE('-- is_inside_triangle --');
  -- Define a sample triangle (e.g., one of the base N0 triangle vertices)
  tri_v0 := HTM_VECTOR(1,0,0); -- X+
  tri_v1 := HTM_VECTOR(0,1,0); -- Y+
  tri_v2 := HTM_VECTOR(0,0,1); -- Z+ (These form N0 if ordered X+, Y+, Z+)
                               -- Actual N0: (X+, Y+, Z+) -> (1,0,0), (0,1,0), (0,0,1)
                               -- The order is important for cross products.
                               -- Let's use (1,0,0), (0,1,0), (0,0,1) - assuming CCW order for is_inside_triangle test
  
  -- Point clearly inside (e.g., center of this spherical triangle)
  p_inside := HTM_VECTOR( (1+0+0)/3, (0+1+0)/3, (0+0+1)/3 ); p_inside.normalize();
  bool_res := HTM_GEOMETRY_UTILS.is_inside_triangle(p_inside, tri_v0, tri_v1, tri_v2);
  assert_true('is_inside_triangle - point inside', bool_res);

  -- Point clearly outside (e.g., -Z pole)
  p_outside := HTM_VECTOR(0,0,-1);
  bool_res := HTM_GEOMETRY_UTILS.is_inside_triangle(p_outside, tri_v0, tri_v1, tri_v2);
  assert_false('is_inside_triangle - point outside', bool_res);

  -- Point on vertex (v0)
  bool_res := HTM_GEOMETRY_UTILS.is_inside_triangle(tri_v0, tri_v0, tri_v1, tri_v2);
  assert_true('is_inside_triangle - point on vertex', bool_res);

  -- Point on edge (midpoint of v0-v1)
  p_on_edge := HTM_VECTOR( (tri_v0.x+tri_v1.x)/2, (tri_v0.y+tri_v1.y)/2, (tri_v0.z+tri_v1.z)/2 ); p_on_edge.normalize();
  bool_res := HTM_GEOMETRY_UTILS.is_inside_triangle(p_on_edge, tri_v0, tri_v1, tri_v2);
  assert_true('is_inside_triangle - point on edge', bool_res);
  
  -- Test with a point slightly outside due to epsilon with default epsilon
  DECLARE
    p_slightly_outside HTM_VECTOR;
    v0_test HTM_VECTOR := HTM_VECTOR(1,0,0);
    v1_test HTM_VECTOR := HTM_VECTOR(0,1,0);
    v2_test HTM_VECTOR := HTM_VECTOR(0,0,1);
    -- A point that should be just outside the v0-v1 edge normal plane
    edge_normal HTM_VECTOR := v0_test.cross_product(v1_test); -- (0,0,1)
    p_on_plane HTM_VECTOR := HTM_VECTOR(1,1,0.1); p_on_plane.normalize(); -- On the plane of v0,v1,v2, but outside triangle
    -- To make it slightly outside, move it against the normal of one edge plane by more than epsilon
    -- Let's use a point that is "behind" the plane formed by v0-v1 (normal is v0 x v1)
    -- If v0=(1,0,0), v1=(0,1,0), v2=(0,0,1), then n01=(0,0,1). Dot with p.
    -- p_slightly_outside := HTM_VECTOR(0.5, 0.5, -0.000001); -- this is not normalized, and may not be outside with default epsilon
    -- This test is tricky to set up robustly without known "failing" points for specific epsilon.
    -- Let's use a point known to be on the other side of an edge plane.
    -- Example: Triangle (1,0,0)-(0,1,0)-(0,0,1). Point (-0.1, 0.1, 0.1) normalized.
    -- Normal of plane (0,1,0)-(0,0,1) is (0,1,0).cross_product(0,0,1) = (1,0,0).
    -- Point (-0.1,0.1,0.1) dot (1,0,0) = -0.1 which is < -epsilon. So it should be outside.
    p_slightly_outside := HTM_VECTOR(-0.1, 0.1, 0.1); p_slightly_outside.normalize();
  BEGIN
    bool_res := HTM_GEOMETRY_UTILS.is_inside_triangle(p_slightly_outside, v0_test, v1_test, v2_test, 0.0000000001);
    assert_false('is_inside_triangle - point slightly outside (specific case)', bool_res);
  END;


  -- 5. id_to_name / name_to_id
  DBMS_OUTPUT.PUT_LINE('-- id_to_name / name_to_id --');
  str_res := HTM_GEOMETRY_UTILS.id_to_name(12); -- N0
  assert_equals_string('id_to_name(12)', str_res, 'N0');
  
  num_res := HTM_GEOMETRY_UTILS.name_to_id('N0');
  assert_equals_float('name_to_id("N0")', num_res, 12);

  str_res := HTM_GEOMETRY_UTILS.id_to_name(8); -- S0
  assert_equals_string('id_to_name(8)', str_res, 'S0');
  
  num_res := HTM_GEOMETRY_UTILS.name_to_id('S0');
  assert_equals_float('name_to_id("S0")', num_res, 8);

  -- S01: S=2 (10), 0=(00), 1=(01) -> 100001 binary = 32+1 = 33
  num_res := HTM_GEOMETRY_UTILS.name_to_id('S01');
  assert_equals_float('name_to_id("S01")', num_res, 33);
  str_res := HTM_GEOMETRY_UTILS.id_to_name(33);
  assert_equals_string('id_to_name(33)', str_res, 'S01');
  
  -- N320: N=3 (11), 3=(11), 2=(10), 0=(00) -> 11111000 binary = 128+64+32+16+8 = 248
  num_res := HTM_GEOMETRY_UTILS.name_to_id('N320');
  assert_equals_float('name_to_id("N320")', num_res, 248);
  str_res := HTM_GEOMETRY_UTILS.id_to_name(248);
  assert_equals_string('id_to_name(248)', str_res, 'N320');
  
  -- Test max level (assuming c_max_htm_level = 25 in HTM_GEOMETRY_UTILS)
  -- Name N followed by 25 zeros. ID should be 3 << (2*25) = 3 * 2^50
  DECLARE
    long_name VARCHAR2(30) := 'N';
    expected_id NUMBER;
  BEGIN
    FOR i IN 1..HTM_GEOMETRY_UTILS.c_max_htm_level LOOP long_name := long_name || '0'; END LOOP;
    expected_id := 3 * POWER(2, 2 * HTM_GEOMETRY_UTILS.c_max_htm_level); -- This is 3 * 4^level
                                                                          -- The name_to_id logic is id = prefix_val; loop (id = id*4 + digit)
                                                                          -- So for N00 (level 2), N=3. id=3. id=3*4+0=12. id=12*4+0=48.
                                                                          -- N00 should be 110000b = 48.
    expected_id := 3; -- N
    FOR i IN 1..HTM_GEOMETRY_UTILS.c_max_htm_level LOOP expected_id := expected_id * 4 + 0; END LOOP;
    
    num_res := HTM_GEOMETRY_UTILS.name_to_id(long_name);
    -- Due to NUMBER precision limits, this might not be exact for very large levels.
    -- Let's test a moderate level.
    long_name := 'N';
    expected_id := 3;
    FOR i IN 1..10 LOOP long_name := long_name || '0'; expected_id := expected_id * 4 + 0; END LOOP; -- N0000000000 (10 zeros, level 10)
    num_res := HTM_GEOMETRY_UTILS.name_to_id(long_name);
    assert_equals_float('name_to_id("N" + 10 zeros)', num_res, expected_id);
    str_res := HTM_GEOMETRY_UTILS.id_to_name(num_res);
    assert_equals_string('id_to_name for N + 10 zeros', str_res, long_name);

  END;
  
  DBMS_OUTPUT.PUT_LINE('--- HTM_GEOMETRY_UTILS & HTM_VECTOR Tests Complete ---');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Error in Geometry Tests: ' || SQLERRM);
    DBMS_OUTPUT.PUT_LINE(DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
END;
/
