CREATE OR REPLACE PACKAGE BODY HTM_GEOMETRY_UTILS AS

  -- Geometric Functions
  FUNCTION cartesian_to_ra_dec(v HTM_VECTOR) RETURN HTM_VECTOR AS
    rad_to_deg CONSTANT NUMBER := 180.0 / c_pi;
    ra NUMBER;
    dec NUMBER;
    len NUMBER;
  BEGIN
    IF v.x IS NULL OR v.y IS NULL OR v.z IS NULL THEN
      RETURN HTM_VECTOR(NULL, NULL, NULL); -- Or raise an error
    END IF;

    len := v.magnitude();
    IF len = 0 THEN
      -- Or handle as an error, e.g., point at the origin has undefined RA/Dec
      RETURN HTM_VECTOR(0, 0, 0); 
    END IF;

    -- Normalize the vector for RA/Dec calculation if not already unit
    -- This function might receive non-unit vectors if used generally
    DECLARE
      unit_v HTM_VECTOR := HTM_VECTOR(v.x/len, v.y/len, v.z/len);
    BEGIN
      dec := ASIN(unit_v.z); -- Dec in radians
      
      IF ABS(unit_v.z) > 0.999999999999 THEN -- Close to poles
        ra := 0.0; -- RA is undefined at poles, conventionally set to 0
      ELSE
        ra := ATAN2(unit_v.y, unit_v.x); -- RA in radians, range (-PI, PI]
      END IF;

      -- Convert to degrees
      ra := ra * rad_to_deg;
      dec := dec * rad_to_deg;

      -- Adjust RA to be in [0, 360)
      IF ra < 0 THEN
        ra := ra + 360.0;
      END IF;
      
      RETURN HTM_VECTOR(ra, dec, len); -- Store RA in x, Dec in y, radius in z
    END;
  END cartesian_to_ra_dec;

  FUNCTION angle_between(v1 HTM_VECTOR, v2 HTM_VECTOR) RETURN NUMBER AS
    dot_prod NUMBER;
    angle_rad NUMBER;
  BEGIN
    -- Assuming v1 and v2 are unit vectors as per the note.
    -- If not, they should be normalized first:
    -- v1.normalize();
    -- v2.normalize();
    dot_prod := v1.dot_product(v2);

    -- Clamp dot_prod to [-1, 1] to avoid domain errors with ACOS
    IF dot_prod > 1.0 THEN
      dot_prod := 1.0;
    ELSIF dot_prod < -1.0 THEN
      dot_prod := -1.0;
    END IF;

    angle_rad := ACOS(dot_prod);
    RETURN angle_rad * (180.0 / c_pi); -- Convert to degrees
  END angle_between;

  FUNCTION is_inside_triangle(
    p HTM_VECTOR,
    v0 HTM_VECTOR,
    v1 HTM_VECTOR,
    v2 HTM_VECTOR,
    epsilon NUMBER DEFAULT 0.0000000001
  ) RETURN BOOLEAN AS
    -- Assuming p, v0, v1, v2 are unit vectors.
    -- The vertices v0, v1, v2 should be in counter-clockwise order.
    c0 HTM_VECTOR;
    c1 HTM_VECTOR;
    c2 HTM_VECTOR;
  BEGIN
    c0 := v0.cross_product(v1);
    c1 := v1.cross_product(v2);
    c2 := v2.cross_product(v0);

    RETURN (c0.dot_product(p) >= -epsilon) AND
           (c1.dot_product(p) >= -epsilon) AND
           (c2.dot_product(p) >= -epsilon);
  END is_inside_triangle;

  FUNCTION spherical_triangle_area(
    v0 HTM_VECTOR,
    v1 HTM_VECTOR,
    v2 HTM_VECTOR
  ) RETURN NUMBER AS
    -- Assumes v0, v1, v2 are unit vectors
    a_rad NUMBER;
    b_rad NUMBER;
    c_rad NUMBER;
    s NUMBER;
    tan_E_4_sq NUMBER;
    deg_to_rad CONSTANT NUMBER := c_pi / 180.0;
  BEGIN
    -- Get side lengths (angles between vertices) in radians
    a_rad := angle_between(v1, v2) * deg_to_rad;
    b_rad := angle_between(v0, v2) * deg_to_rad;
    c_rad := angle_between(v0, v1) * deg_to_rad;

    s := (a_rad + b_rad + c_rad) / 2.0;

    -- L'Huilier's Theorem for spherical excess E
    -- tan(E/4)^2 = tan(s/2) * tan((s-a)/2) * tan((s-b)/2) * tan((s-c)/2)
    -- Ensure arguments to TAN are not causing issues (e.g. s/2 = PI/2)
    -- However, for a valid spherical triangle, these should be fine.
    DECLARE
      tan_s_2 NUMBER;
      tan_s_a_2 NUMBER;
      tan_s_b_2 NUMBER;
      tan_s_c_2 NUMBER;
    BEGIN
      tan_s_2     := TAN(s / 2.0);
      tan_s_a_2   := TAN((s - a_rad) / 2.0);
      tan_s_b_2   := TAN((s - b_rad) / 2.0);
      tan_s_c_2   := TAN((s - c_rad) / 2.0);
      
      tan_E_4_sq := tan_s_2 * tan_s_a_2 * tan_s_b_2 * tan_s_c_2;
    EXCEPTION
      WHEN OTHERS THEN -- Catch potential math errors if arguments to TAN are problematic
        -- This might happen if the triangle is degenerate (e.g., vertices are collinear)
        -- or if floating point precision issues lead to invalid TAN arguments.
        -- A robust solution might check triangle validity beforehand.
        RETURN 0; -- Area of a degenerate triangle can be considered 0.
    END;


    IF tan_E_4_sq < 0 THEN
        -- This can happen due to floating point inaccuracies for very small triangles
        -- or if the triangle inequality is not strictly met. Area should be non-negative.
        RETURN 0;
    END IF;
    
    -- Area E (spherical excess) = 4 * atan(sqrt(tan_E_4_sq))
    RETURN 4.0 * ATAN(SQRT(tan_E_4_sq)); -- Result in steradians
  END spherical_triangle_area;

  -- HTM ID Manipulation Functions
  FUNCTION id_to_name(id NUMBER) RETURN VARCHAR2 AS
    name_buf VARCHAR2(c_max_htm_level + 2); -- N/S + level digits + null terminator (PL/SQL handles strings)
    level_val INTEGER := 0;
    num_id NUMBER := id;
    current_bit NUMBER;
    mask NUMBER;
  BEGIN
    IF id < 8 THEN
      RETURN 'ID_TOO_SMALL'; -- Or raise error
    END IF;

    -- Determine N or S and starting level
    IF (num_id >= POWER(2, (2 * c_max_htm_level) + 2)) THEN
        RETURN 'ID_OUT_OF_RANGE'; -- Exceeds max representable ID for c_max_htm_level
    END IF;

    -- Find the most significant bit to determine the level
    -- The ID structure is S0S1 L0L1 L2L3 ...
    -- S0S1 = 10 (South) or 11 (North)
    -- Level 0 IDs are 8-11 (N0-N3, S0-S3 are not used this way typically)
    -- ID 8 = 1000 (binary) -> S0
    -- ID 9 = 1001 (binary) -> S1
    -- ID 10 = 1010 (binary) -> S2
    -- ID 11 = 1011 (binary) -> S3
    -- ID 12 = 1100 (binary) -> N0
    -- ID 13 = 1101 (binary) -> N1
    -- ID 14 = 1110 (binary) -> N2
    -- ID 15 = 1111 (binary) -> N3

    -- A simpler way is to check ranges based on the ID encoding for HTM C++ library
    -- The first 2 bits determine N/S and establish the base ID (8 for S, 12 for N at level 0)
    -- Each subsequent level adds 2 bits.
    
    -- Determine initial character (N/S)
    mask := POWER(2, (2 * c_max_htm_level) + 1); -- Bit for 'N' vs 'S' (second MSB of full ID range)
                                              -- e.g. if c_max_htm_level = 3, total bits = 2+2*3=8. mask for bit 7 (0-indexed)
                                              -- id = S0 S1 d1 d2 d3 d4 d5 d6
                                              -- S0S1 = 10 for S, 11 for N.
                                              -- if num_id AND (1 << ((level*2)+1)) 
    
    -- Simplified logic based on typical HTM ID structure:
    -- 8-11 are S0-S3, 12-15 are N0-N3 for level 0.
    -- This means the first 2 bits are 10 (S) or 11 (N).
    -- Let's find the highest set bit to determine overall length, then derive level.
    
    DECLARE
        temp_id NUMBER := num_id;
        bit_pos INTEGER := 0;
    BEGIN
        WHILE temp_id > 0 LOOP
            temp_id := FLOOR(temp_id / 2);
            bit_pos := bit_pos + 1;
        END LOOP;
        -- bit_pos is now the number of bits in the id.
        -- For an ID like N0 (12 = 1100), bit_pos = 4. Level = (4-2)/2 = 1. This isn't quite right.
        -- Number of characters in name = (number of bits - 2) / 2.
        -- Example: N01. ID has 3 parts: N, 0, 1. Level = 2. (N=11, 0=00, 1=01 -> 110001, 49dec)
        -- Number of bits for 110001 is 6. (6-2)/2 = 2. This is correct for level.
        level_val := (bit_pos - 2) / 2;
    END;


    IF BITAND(num_id, POWER(2, (level_val * 2) + 1)) != 0 THEN -- Check the N/S bit (second MSB of the ID itself)
      name_buf := 'N';
    ELSE
      name_buf := 'S';
    END IF;
    
    -- Remove the N/S prefix bits from num_id for easier digit processing
    -- num_id := BITAND(num_id, POWER(2, level_val * 2) -1 ); -- this is wrong.
    -- The ID already contains the N/S part implicitly in its value.
    -- We need to extract pairs of bits from highest level to lowest.

    FOR i IN REVERSE 0 .. level_val - 1 LOOP
      current_bit := FLOOR(num_id / POWER(2, i * 2));
      name_buf := name_buf || TO_CHAR(BITAND(current_bit, 3));
    END LOOP;
    
    RETURN name_buf;

  END id_to_name;

  FUNCTION name_to_id(name VARCHAR2) RETURN NUMBER AS
    id_val NUMBER := 0;
    level_val INTEGER;
    ch CHAR(1);
    digit INTEGER;
  BEGIN
    IF name IS NULL OR LENGTH(name) < 2 THEN
      RETURN NULL; -- Or raise error "INVALID_NAME_FORMAT"
    END IF;

    level_val := LENGTH(name) - 1;
    IF level_val > c_max_htm_level THEN
        RETURN NULL; -- Or raise error "NAME_TOO_LONG"
    END IF;

    ch := SUBSTR(name, 1, 1);

    IF ch = 'N' THEN
      id_val := 3; -- Binary 11
    ELSIF ch = 'S' THEN
      id_val := 2; -- Binary 10
    ELSE
      RETURN NULL; -- Or raise error "INVALID_NAME_PREFIX"
    END IF;

    FOR i IN 1 .. level_val LOOP
      ch := SUBSTR(name, i + 1, 1);
      IF ch < '0' OR ch > '3' THEN
        RETURN NULL; -- Or raise error "INVALID_NAME_DIGIT"
      END IF;
      digit := TO_NUMBER(ch);
      id_val := id_val * 4 + digit; -- Equivalent to (id_val << 2) | digit
    END LOOP;

    RETURN id_val;
  END name_to_id;

  FUNCTION get_triangle_vertices_from_parent(
    parent_v0 HTM_VECTOR,
    parent_v1 HTM_VECTOR,
    parent_v2 HTM_VECTOR,
    child_index NUMBER
  ) RETURN HTM_VERTEX_LIST AS
    w0 HTM_VECTOR;
    w1 HTM_VECTOR;
    w2 HTM_VECTOR;
    result_vertices HTM_VERTEX_LIST := HTM_VERTEX_LIST();
  BEGIN
    -- Calculate midpoints (normalized)
    w0 := HTM_VECTOR(parent_v1.x + parent_v2.x, parent_v1.y + parent_v2.y, parent_v1.z + parent_v2.z);
    w0.normalize();
    w1 := HTM_VECTOR(parent_v0.x + parent_v2.x, parent_v0.y + parent_v2.y, parent_v0.z + parent_v2.z);
    w1.normalize();
    w2 := HTM_VECTOR(parent_v0.x + parent_v1.x, parent_v0.y + parent_v1.y, parent_v0.z + parent_v1.z);
    w2.normalize();

    result_vertices.EXTEND(3);

    IF child_index = 0 THEN
      result_vertices(1) := parent_v0;
      result_vertices(2) := w2;
      result_vertices(3) := w1;
    ELSIF child_index = 1 THEN
      result_vertices(1) := parent_v1;
      result_vertices(2) := w0;
      result_vertices(3) := w2;
    ELSIF child_index = 2 THEN
      result_vertices(1) := parent_v2;
      result_vertices(2) := w1;
      result_vertices(3) := w0;
    ELSIF child_index = 3 THEN
      result_vertices(1) := w0;
      result_vertices(2) := w1;
      result_vertices(3) := w2;
    ELSE
      -- Invalid child_index, return empty or raise error
      RETURN HTM_VERTEX_LIST(); -- Or RAISE_APPLICATION_ERROR(-20001, 'Invalid child index');
    END IF;

    RETURN result_vertices;
  END get_triangle_vertices_from_parent;

END HTM_GEOMETRY_UTILS;
/
