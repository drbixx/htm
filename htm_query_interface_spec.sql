CREATE OR REPLACE PACKAGE HTM_QUERY_INTERFACE AS

  -- Public Functions
  FUNCTION circle_region_intersect(
    center_ra NUMBER,
    center_dec NUMBER,
    radius_degrees NUMBER,
    query_level NUMBER
  ) RETURN HTM_ID_RANGE_LIST;

  FUNCTION circle_region_intersect_cartesian(
    center_vec HTM_VECTOR,
    radius_degrees NUMBER,
    query_level NUMBER
  ) RETURN HTM_ID_RANGE_LIST;

  FUNCTION convex_hull_intersect(
    vertices_ra_dec HTM_VERTEX_LIST, -- List of RA/Dec points
    query_level NUMBER
  ) RETURN HTM_ID_RANGE_LIST;

  FUNCTION convex_hull_intersect_cartesian(
    vertices_cartesian HTM_VERTEX_LIST, -- List of Cartesian vectors
    query_level NUMBER
  ) RETURN HTM_ID_RANGE_LIST;

END HTM_QUERY_INTERFACE;
/
