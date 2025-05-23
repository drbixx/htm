CREATE OR REPLACE PACKAGE HTM_GEOMETRY_UTILS AS

  -- PI constant
  c_pi CONSTANT NUMBER := ACOS(-1);
  -- Maximum level for HTM ID conversion (adjust as needed)
  c_max_htm_level CONSTANT INTEGER := 25; -- Corresponds to 25 pairs of bits after the initial 2 bits for N/S. Max ID would be 2 + 2*25 = 52 bits.

  -- Geometric Functions
  FUNCTION cartesian_to_ra_dec(v HTM_VECTOR) RETURN HTM_VECTOR;

  FUNCTION angle_between(v1 HTM_VECTOR, v2 HTM_VECTOR) RETURN NUMBER;

  FUNCTION is_inside_triangle(
    p HTM_VECTOR,
    v0 HTM_VECTOR,
    v1 HTM_VECTOR,
    v2 HTM_VECTOR,
    epsilon NUMBER DEFAULT 0.0000000001
  ) RETURN BOOLEAN;

  FUNCTION spherical_triangle_area(
    v0 HTM_VECTOR,
    v1 HTM_VECTOR,
    v2 HTM_VECTOR
  ) RETURN NUMBER;

  -- HTM ID Manipulation Functions
  FUNCTION id_to_name(id NUMBER) RETURN VARCHAR2;

  FUNCTION name_to_id(name VARCHAR2) RETURN NUMBER;

  FUNCTION get_triangle_vertices_from_parent(
    parent_v0 HTM_VECTOR,
    parent_v1 HTM_VECTOR,
    parent_v2 HTM_VECTOR,
    child_index NUMBER
  ) RETURN HTM_VERTEX_LIST;

END HTM_GEOMETRY_UTILS;
/
