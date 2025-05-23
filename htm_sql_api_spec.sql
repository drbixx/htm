CREATE OR REPLACE PACKAGE HTM_SQL_API AS

  -- Initialization Procedure
  PROCEDURE initialize_htm_system(
    p_build_level NUMBER,
    p_query_level NUMBER
  );

  -- Lookup Functions
  FUNCTION lookup_htm_id(
    p_ra NUMBER,
    p_dec NUMBER,
    p_target_level NUMBER
  ) RETURN NUMBER;

  FUNCTION get_htm_point_radec(
    p_htm_id NUMBER
  ) RETURN VARCHAR2;

  FUNCTION get_htm_point_cartesian(
    p_htm_id NUMBER
  ) RETURN HTM_VECTOR;

  -- Intersection Query Functions (Table Functions)
  FUNCTION htm_circle_intersect(
    p_ra NUMBER,
    p_dec NUMBER,
    p_radius_degrees NUMBER,
    p_query_level NUMBER
  ) RETURN HTM_ID_RANGE_LIST PIPELINED;

  FUNCTION htm_polygon_intersect(
    p_vertices_ra_dec_string VARCHAR2,
    p_query_level NUMBER,
    p_delimiter CHAR DEFAULT ';'
  ) RETURN HTM_ID_RANGE_LIST PIPELINED;

END HTM_SQL_API;
/
